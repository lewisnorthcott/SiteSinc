import SwiftUI
import SwiftData

@main
struct SiteSincApp: App {
    init() {
        print("🚀 [App] SiteSincApp initializing...")
    }
    
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var networkStatusManager = NetworkStatusManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Lazy container creation - use in-memory only to avoid CloudKit issues
    // This ensures the app always starts, even if persistent storage fails
    private static var modelContainer: ModelContainer {
        get {
            print("🔄 [SwiftData] Accessing modelContainer (lazy initialization)...")
            return _modelContainer
        }
    }
    
    private static let _modelContainer: ModelContainer = {
        print("🔄 [SwiftData] Creating in-memory container...")
        // Use in-memory storage to completely bypass CloudKit and file system issues
        // This ensures the app always starts successfully
        let schema = Schema([RFIDraft.self, SelectedDrawing.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,  // Always in-memory to avoid CloudKit validation
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        
        do {
            print("🔄 [SwiftData] Attempting to create container...")
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ [SwiftData] In-memory container created successfully")
            return container
        } catch {
            print("❌ [SwiftData] Failed to create container: \(error)")
            // Last resort: create with absolute minimal config
            let minimalConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [minimalConfig])
                print("⚠️ [SwiftData] Created container with minimal config")
                return container
            } catch {
                print("❌ [SwiftData] CRITICAL: Even minimal config failed: \(error)")
                fatalError("Unable to create SwiftData container: \(error)")
            }
        }
    }()

    var body: some Scene {
        let _ = print("🔄 [App] Building scene body...")
        let _ = print("🔄 [App] SessionManager token: \(sessionManager.token != nil ? "exists" : "nil")")
        
        // Create container lazily when first accessed
        let container = SiteSincApp.modelContainer
        
        return WindowGroup {
            let _ = print("🔄 [App] Creating WindowGroup with ContentView...")
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
                .environmentObject(notificationManager)
                .preferredColorScheme(.light)
                .offlineBanner()
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    print("🔗 Universal link via onContinueUserActivity: \(url)")
                    handleDeepLink(url)
                }
                .onOpenURL { url in
                    // Handle custom URL schemes (if you add them later)
                    print("🔗 Custom URL scheme opened: \(url)")
                    handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandleUniversalLink"))) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        handleDeepLink(url)
                    }
                }
                .onAppear {
                    print("🔄 [App] WindowGroup onAppear called")
                    notificationManager.sessionManager = sessionManager
                    setupNotifications()
                    migrateCachesIfNeeded()
                    
                    // Request location permission for photo location collection
                    locationManager.requestLocationPermission()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    print("🔄 [App] Scene phase changed to: \(newPhase)")
                    if newPhase == .active {
                        Task { await sessionManager.validateSessionOnForeground() }
                    }
                }
        }
        .modelContainer(container)
    }
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Handling deep link: \(url.absoluteString)")
        
        // Parse URL path
        // Expected formats:
        // https://www.sitesinc.co.uk/projects/{projectId}/drawings/{drawingId}
        // https://www.sitesinc.co.uk/projects/{projectId}/documents/{documentId}
        // https://www.sitesinc.co.uk/projects/{projectId}/rfis/{rfiId}
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Also check query parameters as fallback
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        
        // Try path-based parsing first
        if pathComponents.count >= 4, pathComponents[0] == "projects" {
            let projectIdStr = pathComponents[1]
            let section = pathComponents[2]
            let itemIdStr = pathComponents[3]
            
            if let projectId = Int(projectIdStr), let itemId = Int(itemIdStr) {
                switch section {
                case "drawings":
                    print("🔗 Navigating to drawing \(itemId) in project \(projectId)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingId": itemId]
                    )
                    return
                case "documents":
                    print("🔗 Navigating to document \(itemId) in project \(projectId)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocument"),
                        object: nil,
                        userInfo: ["projectId": projectId, "documentId": itemId]
                    )
                    return
                case "rfis", "rfi":
                    print("🔗 Navigating to RFI \(itemId) in project \(projectId)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiId": itemId]
                    )
                    return
                default:
                    break
                }
            }
        }
        
        // Fallback: Try query parameters
        if let queryItems = queryItems {
            var projectId: Int?
            var drawingId: Int?
            var documentId: Int?
            var rfiId: Int?
            
            for item in queryItems {
                switch item.name {
                case "projectId", "project_id":
                    projectId = Int(item.value ?? "")
                case "drawingId", "drawing_id":
                    drawingId = Int(item.value ?? "")
                case "documentId", "document_id":
                    documentId = Int(item.value ?? "")
                case "rfiId", "rfi_id":
                    rfiId = Int(item.value ?? "")
                default:
                    break
                }
            }
            
            if let projectId = projectId {
                if let drawingId = drawingId {
                    print("🔗 Navigating to drawing \(drawingId) in project \(projectId) (from query)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingId": drawingId]
                    )
                    return
                } else if let documentId = documentId {
                    print("🔗 Navigating to document \(documentId) in project \(projectId) (from query)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocument"),
                        object: nil,
                        userInfo: ["projectId": projectId, "documentId": documentId]
                    )
                    return
                } else if let rfiId = rfiId {
                    print("🔗 Navigating to RFI \(rfiId) in project \(projectId) (from query)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiId": rfiId]
                    )
                    return
                } else {
                    // Just navigate to project
                    print("🔗 Navigating to project \(projectId) (from query)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToProject"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                    return
                }
            }
        }
        
        print("⚠️ Could not parse deep link: \(url.absoluteString)")
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
        
        // Restore RFI reminder schedule from preferences if user is logged in
        if sessionManager.token != nil {
            Task {
                // Try to restore reminder from any project's preferences (using first available project)
                // In a real scenario, you might want to check all projects or use a global preference
                await notificationManager.restoreRFIReminderFromPreferences()
            }
        }
    }
}

// MARK: - App Delegate for Device Token and Universal Links
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.setDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
        NotificationManager.shared.addDebugMessage("❌ Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - Universal Links Support
    /// Handle universal links when app is launched or brought to foreground
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Handle universal links
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("🔗 Universal link received: \(url)")
            NotificationManager.shared.addDebugMessage("🔗 Universal link received: \(url.absoluteString)")
            handleUniversalLink(url)
            return true
        }
        return false
    }
    
    /// Handle universal links (called from app delegate)
    private func handleUniversalLink(_ url: URL) {
        // Post notification to handle deep link on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("HandleUniversalLink"),
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 Received remote notification: \(userInfo)")
        NotificationManager.shared.addDebugMessage("📱 Received remote notification: \(userInfo)")
        
        // Handle different notification types
        if let type = userInfo["type"] as? String {
            switch type {
            case "drawing_upload", "drawing":
                handleDrawingUploadNotification(userInfo: userInfo)
            case "document_upload", "document":
                handleDocumentUploadNotification(userInfo: userInfo)
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
        
        // Extract IDs if available from push notification
        let drawingId = userInfo["drawingId"] as? Int
        let projectId = userInfo["projectId"] as? Int
        
        NotificationManager.shared.handleDrawingUploadNotification(
            drawingTitle: drawingTitle,
            projectName: projectName,
            drawingNumber: drawingNumber,
            drawingId: drawingId,
            projectId: projectId
        )
    }
    
    private func handleDocumentUploadNotification(userInfo: [AnyHashable: Any]) {
        guard let documentName = userInfo["documentName"] as? String ?? userInfo["name"] as? String,
              let projectName = userInfo["projectName"] as? String,
              let documentId = userInfo["documentId"] as? Int,
              let projectId = userInfo["projectId"] as? Int else {
            print("❌ Missing required data for document upload notification")
            NotificationManager.shared.addDebugMessage("❌ Missing required data for document upload notification")
            return
        }
        
        NotificationManager.shared.handleDocumentUploadNotification(
            documentName: documentName,
            projectName: projectName,
            documentId: documentId,
            projectId: projectId
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
