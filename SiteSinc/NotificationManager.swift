import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var notificationPreferences: [String: Any] = [:]
    @Published var sessionManager: SessionManager?
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await MainActor.run {
                self.isAuthorized = granted
            }
            
            if granted {
                await registerForRemoteNotifications()
            }
            
            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    // MARK: - Device Token Management
    func setDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("📱 Device token: \(token)")
        
        // Store token in UserDefaults for API calls
        UserDefaults.standard.set(token, forKey: "deviceToken")
        
        // Send token to backend
        sendDeviceTokenToBackend(token)
    }
    
    private func sendDeviceTokenToBackend(_ token: String) {
        guard let userToken = self.sessionManager?.token else {
            print("❌ No session available for device token registration")
            return
        }
        
        Task {
            do {
                try await APIClient.registerDeviceToken(token: userToken, deviceToken: token)
                print("✅ Device token registered successfully")
            } catch {
                print("❌ Failed to register device token: \(error)")
            }
        }
    }
    
    // MARK: - Notification Preferences
    func fetchNotificationPreferences(projectId: Int) async {
        guard let userToken = self.sessionManager?.token else {
            print("❌ No session available for fetching notification preferences")
            return
        }
        
        let url = URL(string: "\(APIClient.baseURL)/notifications/preferences?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run {
                        self.notificationPreferences = preferences
                    }
                    print("✅ Notification preferences fetched successfully")
                }
            } else {
                print("❌ Failed to fetch notification preferences")
            }
        } catch {
            print("❌ Error fetching notification preferences: \(error)")
        }
    }
    
    func updateNotificationPreferences(projectId: Int, preferences: [String: Any]) async {
        guard let userToken = self.sessionManager?.token else {
            print("❌ No session available for updating notification preferences")
            return
        }
        
        let url = URL(string: "\(APIClient.baseURL)/notifications/preferences")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body = preferences
        body["projectId"] = projectId
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Notification preferences updated successfully")
                await fetchNotificationPreferences(projectId: projectId)
            } else {
                print("❌ Failed to update notification preferences")
            }
        } catch {
            print("❌ Error updating notification preferences: \(error)")
        }
    }
    
    // MARK: - Local Notifications
    func scheduleLocalNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling local notification: \(error)")
            } else {
                print("✅ Local notification scheduled successfully")
            }
        }
    }
    
    // MARK: - Drawing Upload Notifications
    func handleDrawingUploadNotification(drawingTitle: String, projectName: String, drawingNumber: String) {
        let title = "New Drawing Uploaded"
        let body = "Drawing \(drawingNumber): \(drawingTitle) has been uploaded to \(projectName)"
        
        let userInfo: [String: Any] = [
            "type": "drawing_upload",
            "drawingTitle": drawingTitle,
            "projectName": projectName,
            "drawingNumber": drawingNumber
        ]
        
        scheduleLocalNotification(title: title, body: body, userInfo: userInfo)
    }
    
    // MARK: - Notification Actions
    func addNotificationActions() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_DRAWING",
            title: "View Drawing",
            options: [.foreground]
        )
        
        let projectAction = UNNotificationAction(
            identifier: "VIEW_PROJECT",
            title: "View Project",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "DRAWING_UPLOAD",
            actions: [viewAction, projectAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification actions
        switch response.actionIdentifier {
        case "VIEW_DRAWING":
            handleViewDrawingAction(userInfo: userInfo)
        case "VIEW_PROJECT":
            handleViewProjectAction(userInfo: userInfo)
        default:
            // Default tap action
            handleDefaultNotificationTap(userInfo: userInfo)
        }
        
        completionHandler()
    }
    
    private func handleViewDrawingAction(userInfo: [AnyHashable: Any]) {
        // Navigate to specific drawing
        if let drawingNumber = userInfo["drawingNumber"] as? String {
            // Post notification to navigate to drawing
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDrawing"),
                object: nil,
                userInfo: ["drawingNumber": drawingNumber]
            )
        }
    }
    
    private func handleViewProjectAction(userInfo: [AnyHashable: Any]) {
        // Navigate to project
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToProject"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleDefaultNotificationTap(userInfo: [AnyHashable: Any]) {
        // Default action - navigate to drawings list
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToDrawings"),
            object: nil,
            userInfo: userInfo
        )
    }
} 