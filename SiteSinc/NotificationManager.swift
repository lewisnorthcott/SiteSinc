import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var notificationPreferences: [String: Any] = [:]
    @Published var sessionManager: SessionManager?
    @Published var debugMessages: [String] = []
    @Published var currentBadgeCount: Int = 0
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        // Keep badge in sync when app launches/returns to foreground
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        // Defer async operations to avoid blocking initialization
        // These will run asynchronously after the app starts
        Task { @MainActor in
            await self.checkAuthorizationStatusAsync()
            await self.syncBadgeFromDeliveredAsync()
        }
    }
    
    // MARK: - Haptic Feedback
    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func triggerNotificationHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    // MARK: - Debug Logging
    func addDebugMessage(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            let debugMessage = "[\(timestamp)] \(message)"
            self.debugMessages.append(debugMessage)
            
            // Keep only last 20 messages
            if self.debugMessages.count > 20 {
                self.debugMessages.removeFirst()
            }
            
            // Also print to console for Xcode debugging
            print("🔍 [DEBUG] \(message)")
        }
    }
    
    func clearDebugMessages() {
        DispatchQueue.main.async {
            self.debugMessages.removeAll()
        }
    }
    
    // MARK: - Authorization
    func requestNotificationPermission() async -> Bool {
        addDebugMessage("🔍 Requesting notification permission...")
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await MainActor.run {
                self.isAuthorized = granted
                if granted {
                    self.addDebugMessage("✅ Notification permission granted")
                } else {
                    self.addDebugMessage("❌ Notification permission denied")
                }
            }
            
            if granted {
                await registerForRemoteNotifications()
            }
            
            return granted
        } catch {
            addDebugMessage("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() {
        Task { @MainActor in
            await checkAuthorizationStatusAsync()
        }
    }
    
    private func checkAuthorizationStatusAsync() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.isAuthorized = settings.authorizationStatus == .authorized
            self.addDebugMessage("🔍 Authorization status: \(settings.authorizationStatus.rawValue)")
        }
    }
    
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            self.addDebugMessage("🔄 Registering for remote notifications...")
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    // MARK: - Device Token Management
    func setDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        addDebugMessage("🎉 Received device token from Apple!")
        addDebugMessage("📱 Token length: \(deviceToken.count) bytes")
        addDebugMessage("📱 Token preview: \(token.prefix(10))...")
        
        // Store token in UserDefaults for API calls
        UserDefaults.standard.set(token, forKey: "deviceToken")
        
        // Send token to backend
        sendDeviceTokenToBackend(token)
    }
    
    private func sendDeviceTokenToBackend(_ token: String) {
        guard let userToken = self.sessionManager?.token else {
            addDebugMessage("❌ No session available for device token registration")
            return
        }
        
        addDebugMessage("🔍 Attempting to register device token with API...")
        addDebugMessage("🔍 API URL: \(APIClient.baseURL)/device-tokens/register")
        
        Task {
            do {
                try await APIClient.registerDeviceToken(token: userToken, deviceToken: token)
                addDebugMessage("✅ Device token registered successfully with API")
            } catch {
                addDebugMessage("❌ Failed to register device token: \(error)")
                addDebugMessage("🔍 Error details: \(error)")
            }
        }
    }
    
    // MARK: - Debug Functions
    func debugNotificationSetup() {
        addDebugMessage("🔍 === Notification Setup Debug ===")
        
        // Check stored token
        if let token = UserDefaults.standard.string(forKey: "deviceToken") {
            addDebugMessage("✅ Found stored device token: \(token.prefix(10))...")
        } else {
            addDebugMessage("❌ No stored device token found")
        }
        
        // Check authorization status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.addDebugMessage("🔍 Authorization Status: \(settings.authorizationStatus.rawValue)")
            self.addDebugMessage("🔍 Alert Setting: \(settings.alertSetting.rawValue)")
            self.addDebugMessage("🔍 Badge Setting: \(settings.badgeSetting.rawValue)")
            self.addDebugMessage("🔍 Sound Setting: \(settings.soundSetting.rawValue)")
        }
        
        // Check if we're registered for remote notifications
        let isRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
        addDebugMessage("🔍 Registered for Remote Notifications: \(isRegistered)")
        
        // Check session manager
        if let sessionManager = sessionManager {
            addDebugMessage("✅ Session manager is available")
            if let token = sessionManager.token {
                addDebugMessage("✅ User token available: \(token.prefix(10))...")
            } else {
                addDebugMessage("❌ User token not available")
            }
        } else {
            addDebugMessage("❌ Session manager not available")
        }
    }
    
    func forceTokenRefresh() {
        addDebugMessage("🔄 Forcing device token refresh...")
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func testNotificationRegistration() {
        addDebugMessage("🧪 Testing notification registration...")
        debugNotificationSetup()
        forceTokenRefresh()
    }
    
    // MARK: - Test Functions for Simulator
    /// Test function to simulate a drawing upload notification with deep linking
    /// Use this in the simulator to test notification navigation
    func testDrawingUploadNotification(projectId: Int, drawingId: Int, drawingNumber: String = "A-001", drawingTitle: String = "Test Drawing", projectName: String = "Test Project") {
        addDebugMessage("🧪 Testing drawing upload notification with deep link...")
        handleDrawingUploadNotification(
            drawingTitle: drawingTitle,
            projectName: projectName,
            drawingNumber: drawingNumber,
            drawingId: drawingId,
            projectId: projectId
        )
    }
    
    /// Test function to simulate a document upload notification with deep linking
    /// Use this in the simulator to test notification navigation
    func testDocumentUploadNotification(projectId: Int, documentId: Int, documentName: String = "Test Document", projectName: String = "Test Project") {
        addDebugMessage("🧪 Testing document upload notification with deep link...")
        handleDocumentUploadNotification(
            documentName: documentName,
            projectName: projectName,
            documentId: documentId,
            projectId: projectId
        )
    }
    
    // MARK: - Notification Preferences
    func fetchNotificationPreferences(projectId: Int) async {
        guard let userToken = self.sessionManager?.token else {
            print("❌ No session available for fetching notification preferences")
            return
        }
        
        // Backend returns all preferences, not filtered by projectId
        let url = URL(string: "\(APIClient.baseURL)/notifications/preferences")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Failed to fetch notification preferences: Invalid response")
                return
            }
            
            if httpResponse.statusCode == 200 {
                if let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run {
                        self.notificationPreferences = preferences
                    }
                    print("✅ Notification preferences fetched successfully")
                }
            } else {
                print("❌ Failed to fetch notification preferences: \(httpResponse.statusCode)")
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
        
        // Use the general preferences endpoint for all updates
        let url = URL(string: "\(APIClient.baseURL)/notifications/preferences")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: preferences)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ Notification preferences updated successfully")
                    await fetchNotificationPreferences(projectId: projectId)
                } else {
                    // Log error response for debugging
                    if let responseBody = String(data: data, encoding: .utf8) {
                        print("❌ Failed to update notification preferences (\(httpResponse.statusCode)): \(responseBody)")
                    } else {
                        print("❌ Failed to update notification preferences: \(httpResponse.statusCode)")
                    }
                }
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
    func handleDrawingUploadNotification(drawingTitle: String, projectName: String, drawingNumber: String, drawingId: Int? = nil, projectId: Int? = nil) {
        let title = "New Drawing Uploaded"
        let body = "Drawing \(drawingNumber): \(drawingTitle) has been uploaded to \(projectName)"
        
        var userInfo: [String: Any] = [
            "type": "drawing_upload",
            "drawingTitle": drawingTitle,
            "projectName": projectName,
            "drawingNumber": drawingNumber
        ]
        
        // Add IDs if available for deep linking
        if let drawingId = drawingId {
            userInfo["drawingId"] = drawingId
        }
        if let projectId = projectId {
            userInfo["projectId"] = projectId
        }
        
        scheduleLocalNotification(title: title, body: body, userInfo: userInfo)
    }
    
    // MARK: - Document Upload Notifications
    func handleDocumentUploadNotification(documentName: String, projectName: String, documentId: Int, projectId: Int) {
        let title = "New Document Uploaded"
        let body = "\(documentName) has been uploaded to \(projectName)"
        
        let userInfo: [String: Any] = [
            "type": "document_upload",
            "documentName": documentName,
            "projectName": projectName,
            "documentId": documentId,
            "projectId": projectId
        ]
        
        scheduleLocalNotification(title: title, body: body, userInfo: userInfo)
    }
    
    // MARK: - RFI Reminder Notifications
    // Note: RFI reminder notifications are now handled via backend push notifications
    // This ensures consistency with other notification types (drawings, documents, etc.)
    
    // MARK: - Badge Management
    func clearBadgeCount() {
        setBadgeCount(0)
        addDebugMessage("🧹 Badge count cleared")
    }
    
    func getBadgeCount() -> Int {
        return currentBadgeCount
    }
    
    func updateBadgeCount() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            // Note: iOS doesn't provide a direct way to get current badge count
            // We'll track it manually by counting delivered notifications
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                DispatchQueue.main.async {
                    self?.currentBadgeCount = notifications.count
                }
            }
        }
    }

    // MARK: - Explicit badge setters
    func setBadgeCount(_ count: Int) {
        // Prefer iOS 17+ API; fall back for earlier versions
        UNUserNotificationCenter.current().setBadgeCount(count) { [weak self] error in
            if let error = error { print("Error setting badge count: \(error)") }
            DispatchQueue.main.async {
                if #available(iOS 17.0, *) {
                    // No need to touch UIApplication badge in iOS 17+
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = count
                }
                self?.currentBadgeCount = count
            }
        }
    }

    @objc private func appWillEnterForeground() {
        Task { @MainActor in
            await syncBadgeFromDeliveredAsync()
        }
    }

    func syncBadgeFromDelivered() {
        Task { @MainActor in
            await syncBadgeFromDeliveredAsync()
        }
    }
    
    private func syncBadgeFromDeliveredAsync() async {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let count = notifications.count
        await MainActor.run {
            self.setBadgeCount(count)
        }
    }
    
    // MARK: - Notification Center Management
    func getDeliveredNotifications() async -> [UNNotification] {
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }
    
    func removeDeliveredNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        addDebugMessage("🗑️ Removed delivered notification: \(identifier)")
    }
    
    func removeAllDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        setBadgeCount(0)
        addDebugMessage("🗑️ Removed all delivered notifications")
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
        // Show notification even when app is in foreground with enhanced options
        completionHandler([.banner, .sound, .badge, .list])
        updateBadgeCount()
        triggerHapticFeedback()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Clear badge count when notification is tapped
        clearBadgeCount()
        
        // Handle notification actions
        switch response.actionIdentifier {
        case "VIEW_DRAWING":
            handleViewDrawingAction(userInfo: userInfo)
        case "VIEW_DOCUMENT":
            handleViewDocumentAction(userInfo: userInfo)
        case "VIEW_RFI":
            handleViewRFIAction(userInfo: userInfo)
        case "VIEW_PROJECT":
            handleViewProjectAction(userInfo: userInfo)
        default:
            // Default tap action
            handleDefaultNotificationTap(userInfo: userInfo)
        }
        
        completionHandler()
        triggerHapticFeedback()
    }
    
    private func handleViewDrawingAction(userInfo: [AnyHashable: Any]) {
        // Navigate to specific drawing
        // Handle both Int and String types from backend
        if let drawingId = extractInt(from: userInfo["drawingId"]),
           let projectId = extractInt(from: userInfo["projectId"]) {
            // Post notification to navigate - ProjectListView will handle navigating to project first
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDrawing"),
                object: nil,
                userInfo: ["projectId": projectId, "drawingId": drawingId]
            )
        } else if let drawingNumber = userInfo["drawingNumber"] as? String,
                  let projectId = extractInt(from: userInfo["projectId"]) {
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDrawing"),
                object: nil,
                userInfo: ["projectId": projectId, "drawingNumber": drawingNumber]
            )
        } else if let projectId = extractInt(from: userInfo["projectId"]) {
            // Fallback: navigate to drawings list for the project
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDrawings"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    }
    
    private func handleViewDocumentAction(userInfo: [AnyHashable: Any]) {
        // Navigate to specific document
        // Handle both Int and String types from backend
        if let documentId = extractInt(from: userInfo["documentId"]),
           let projectId = extractInt(from: userInfo["projectId"]) {
            // Post notification to navigate - ProjectListView will handle navigating to project first
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDocument"),
                object: nil,
                userInfo: ["projectId": projectId, "documentId": documentId]
            )
        } else if let projectId = extractInt(from: userInfo["projectId"]) {
            // Fallback: navigate to documents list for the project
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToDocuments"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    }
    
    private func handleViewRFIAction(userInfo: [AnyHashable: Any]) {
        // Navigate to specific RFI
        // Handle both Int and String types from backend
        if let rfiId = extractInt(from: userInfo["rfiId"]),
           let projectId = extractInt(from: userInfo["projectId"]) {
            // Post notification to navigate - ProjectListView will handle navigating to project first
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToRFI"),
                object: nil,
                userInfo: ["projectId": projectId, "rfiId": rfiId]
            )
        } else if let rfiNumber = userInfo["rfiNumber"] as? String,
                  let projectId = extractInt(from: userInfo["projectId"]),
                  let rfiNumberInt = Int(rfiNumber) {
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToRFI"),
                object: nil,
                userInfo: ["projectId": projectId, "rfiNumber": rfiNumberInt]
            )
        } else if let projectId = extractInt(from: userInfo["projectId"]) {
            // Fallback: navigate to RFI list for the project
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToRFIs"),
                object: nil,
                userInfo: ["projectId": projectId]
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
    
    /// Helper to convert string to Int, handling both string and Int types
    private func extractInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }
    
    private func handleDefaultNotificationTap(userInfo: [AnyHashable: Any]) {
        // Default action - try to navigate to specific item based on notification type
        if let type = userInfo["type"] as? String {
            switch type {
            case "drawing_upload", "drawing", "drawing_update":
                // Try to navigate to specific drawing
                if let drawingId = extractInt(from: userInfo["drawingId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingId": drawingId]
                    )
                    return
                } else if let drawingNumber = userInfo["drawingNumber"] as? String,
                          let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingNumber": drawingNumber]
                    )
                    return
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Backend sends drawing_update - navigate to drawings list
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawings"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "document_upload", "document", "document_update":
                // Navigate to specific document
                if let documentId = extractInt(from: userInfo["documentId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocument"),
                        object: nil,
                        userInfo: ["projectId": projectId, "documentId": documentId]
                    )
                    return
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Backend sends document_update - navigate to documents list
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocuments"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "rfi_update", "rfi":
                // Navigate to specific RFI
                // Backend sends: rfiId (string) or rfiNumber (string)
                if let rfiId = extractInt(from: userInfo["rfiId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiId": rfiId]
                    )
                    return
                } else if let rfiNumber = userInfo["rfiNumber"] as? String,
                          let projectId = extractInt(from: userInfo["projectId"]) {
                    // Try to extract RFI number and navigate
                    if let rfiNumberInt = Int(rfiNumber) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToRFI"),
                            object: nil,
                            userInfo: ["projectId": projectId, "rfiNumber": rfiNumberInt]
                        )
                        return
                    }
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Navigate to RFI list if no specific RFI ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFIs"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "material_requisition_update", "material_requisition", "requisition":
                // Navigate to specific requisition
                // Backend sends: requisitionId (string) or requisitionNumber (string)
                if let requisitionId = extractInt(from: userInfo["requisitionId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRequisition"),
                        object: nil,
                        userInfo: ["projectId": projectId, "requisitionId": requisitionId]
                    )
                    return
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Navigate to requisitions list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRequisitions"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "log_update", "log":
                // Navigate to specific log
                // Backend sends: logId (string) or logNumber (string)
                if let logId = extractInt(from: userInfo["logId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToLog"),
                        object: nil,
                        userInfo: ["projectId": projectId, "logId": logId]
                    )
                    return
                } else if let logNumber = userInfo["logNumber"] as? String,
                          let projectId = extractInt(from: userInfo["projectId"]) {
                    if let logNumberInt = Int(logNumber) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToLog"),
                            object: nil,
                            userInfo: ["projectId": projectId, "logNumber": logNumberInt]
                        )
                        return
                    }
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Navigate to logs list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToLogs"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "permit":
                if let permitId = extractInt(from: userInfo["permitId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToPermit"),
                        object: nil,
                        userInfo: ["projectId": projectId, "permitId": permitId]
                    )
                    return
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToPermit"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            case "snag_update", "snag":
                // Navigate to specific snag
                // Backend sends: snagId (string)
                if let snagId = extractInt(from: userInfo["snagId"]),
                   let projectId = extractInt(from: userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToSnag"),
                        object: nil,
                        userInfo: ["projectId": projectId, "snagId": snagId]
                    )
                    return
                } else if let projectId = extractInt(from: userInfo["projectId"]) {
                    // Navigate to snags list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToSnags"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            default:
                break
            }
        }
        
        // Fallback: navigate to drawings list if we can't determine specific item
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToDrawings"),
            object: nil,
            userInfo: userInfo
        )
    }
} 