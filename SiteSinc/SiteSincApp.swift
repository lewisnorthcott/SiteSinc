import SwiftUI

@main
struct SiteSincApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var networkStatusManager = NetworkStatusManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                    migrateCachesIfNeeded()
                    
                    // Request location permission for photo location collection
                    locationManager.requestLocationPermission()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await sessionManager.validateSessionOnForeground() }
                    }
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
        NotificationManager.shared.addDebugMessage("❌ Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 Received remote notification: \(userInfo)")
        NotificationManager.shared.addDebugMessage("📱 Received remote notification: \(userInfo)")
        
        // Handle different notification types
        if let type = userInfo["type"] as? String {
            switch type {
            case "drawing_upload":
                handleDrawingUploadNotification(userInfo: userInfo)
            case "rfi_update":
                handleRFIUpdateNotification(userInfo: userInfo)
            default:
                print("📱 Unknown notification type: \(type)")
                NotificationManager.shared.addDebugMessage("📱 Unknown notification type: \(type)")
            }
        }
        
        completionHandler(.newData)
    }
    
    private func handleDrawingUploadNotification(userInfo: [AnyHashable: Any]) {
        guard let drawingTitle = userInfo["drawingTitle"] as? String,
              let projectName = userInfo["projectName"] as? String,
              let drawingNumber = userInfo["drawingNumber"] as? String else {
            print("❌ Missing required data for drawing upload notification")
            NotificationManager.shared.addDebugMessage("❌ Missing required data for drawing upload notification")
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
        NotificationManager.shared.addDebugMessage("📱 RFI update notification received")
    }
}

// MARK: - One-time migration from Caches to Application Support
private func migrateCachesIfNeeded() {
    let defaultsKey = "didMigrateCachesToAppSupport_v1"
    guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
    let fileManager = FileManager.default
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("SiteSincCache", isDirectory: true)
    try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)

    let patterns = [
        "projects.json",
        "drawings_project_",
        "documents_project_",
        "rfis_project_",
        "forms_project_",
        "form_submissions_project_",
        "form_attachment_paths_",
        "photo_paths_project_"
    ]

    if let items = try? fileManager.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
        for url in items {
            let name = url.lastPathComponent
            if patterns.contains(where: { name.hasPrefix($0) }) {
                let dest = appSupport.appendingPathComponent(name)
                if fileManager.fileExists(atPath: dest.path) { continue }
                try? fileManager.copyItem(at: url, to: dest)
            }
        }
    }
    UserDefaults.standard.set(true, forKey: defaultsKey)
}
