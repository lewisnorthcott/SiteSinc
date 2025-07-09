import SwiftUI

@main
struct SiteSincApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var networkStatusManager = NetworkStatusManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var locationManager = LocationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
                .environmentObject(notificationManager)
                .preferredColorScheme(.light)
                .offlineBanner()
                .onAppear {
                    notificationManager.sessionManager = sessionManager
                    setupNotifications()
                    
                    // Request location permission for photo location collection
                    locationManager.requestLocationPermission()
                }
        }
        .modelContainer(for: [RFIDraft.self, SelectedDrawing.self])
    }
    
    private func setupNotifications() {
        // Add notification actions
        notificationManager.addNotificationActions()
        
        // Request notification permission if not already granted
        if !notificationManager.isAuthorized {
            Task {
                await notificationManager.requestNotificationPermission()
            }
        }
    }
}

// MARK: - App Delegate for Device Token
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.setDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 Received remote notification: \(userInfo)")
        
        // Handle different notification types
        if let type = userInfo["type"] as? String {
            switch type {
            case "drawing_upload":
                handleDrawingUploadNotification(userInfo: userInfo)
            case "rfi_update":
                handleRFIUpdateNotification(userInfo: userInfo)
            default:
                print("📱 Unknown notification type: \(type)")
            }
        }
        
        completionHandler(.newData)
    }
    
    private func handleDrawingUploadNotification(userInfo: [AnyHashable: Any]) {
        guard let drawingTitle = userInfo["drawingTitle"] as? String,
              let projectName = userInfo["projectName"] as? String,
              let drawingNumber = userInfo["drawingNumber"] as? String else {
            print("❌ Missing required data for drawing upload notification")
            return
        }
        
        NotificationManager.shared.handleDrawingUploadNotification(
            drawingTitle: drawingTitle,
            projectName: projectName,
            drawingNumber: drawingNumber
        )
    }
    
    private func handleRFIUpdateNotification(userInfo: [AnyHashable: Any]) {
        // Handle RFI update notifications
        print("📱 RFI update notification received")
    }
}
