import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAnalytics

@main
struct SiteSincApp: App {
    init() {
        print("🚀 [App] SiteSincApp initializing...")
        
        // Enable analytics debug mode in debug builds
        #if DEBUG
        AnalyticsManager.shared.debugMode = true
        #endif
        
        // Set initial auth token for analytics if available
        if let token = KeychainHelper.getToken() {
            AnalyticsService.shared.setAuthToken(token)
        }
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
                    setupAnalytics()
                    // Enable automatic silent reauth + retry for API calls (401/403).
                    APIClient.authRetryHandler = {
                        let success = await sessionManager.attemptSilentReauth()
                        return success ? sessionManager.token : nil
                    }
                    
                    // Run migration asynchronously to avoid blocking UI
                    Task.detached(priority: .utility) {
                        migrateCachesIfNeeded()
                    }
                    
                    // Request location permission for photo location collection
                    locationManager.requestLocationPermission()
                    
                    // Set initial analytics user properties if logged in
                    if let user = sessionManager.user {
                        AnalyticsManager.shared.setUserId(user.id)
                        AnalyticsManager.shared.setTenantId(sessionManager.selectedTenantId)
                    }
                    
                    // Set auth token for backend analytics if available
                    if let token = sessionManager.token {
                        AnalyticsService.shared.setAuthToken(token)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    print("🔄 [App] Scene phase changed to: \(newPhase)")
                    switch newPhase {
                    case .active:
                        Task { await sessionManager.validateSessionOnForeground() }
                        AnalyticsService.shared.handleAppWillEnterForeground()
                    case .background, .inactive:
                        AnalyticsService.shared.handleAppWillEnterBackground()
                    @unknown default:
                        break
                    }
                }
                .onChange(of: sessionManager.token) { oldValue, newValue in
                    // Activity monitoring only when signed in; clear on logout for privacy and battery
                    if let token = newValue {
                        AnalyticsService.shared.setAuthToken(token)
                    } else {
                        AnalyticsService.shared.clearAuthToken()
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
        
        // Cancel any existing local RFI reminder notifications (now handled via backend push)
        if sessionManager.token != nil {
            Task {
                // Remove any old local RFI reminder notifications
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rfi_daily_reminder"])
            }
        }
    }
    
    private func setupAnalytics() {
        // Handle app lifecycle events for analytics
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            AnalyticsService.shared.handleAppWillEnterForeground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            AnalyticsService.shared.handleAppWillEnterBackground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            AnalyticsService.shared.handleAppWillTerminate()
        }
    }
}

// MARK: - App Delegate for Device Token and Universal Links
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()
        print("🔥 [Firebase] Firebase configured successfully")
        return true
    }
    
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
            case "drawing_upload", "drawing", "drawing_update":
                handleDrawingNotification(userInfo: userInfo)
            case "document_upload", "document", "document_update":
                handleDocumentNotification(userInfo: userInfo)
            case "rfi_update", "rfi":
                handleRFIUpdateNotification(userInfo: userInfo)
            case "material_requisition_update", "material_requisition", "requisition":
                handleMaterialRequisitionNotification(userInfo: userInfo)
            case "log_update", "log":
                handleLogNotification(userInfo: userInfo)
            case "snag_update", "snag":
                handleSnagNotification(userInfo: userInfo)
            default:
                print("📱 Unknown notification type: \(type)")
                NotificationManager.shared.addDebugMessage("📱 Unknown notification type: \(type)")
            }
        }
        
        completionHandler(.newData)
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
    
    private func handleDrawingNotification(userInfo: [AnyHashable: Any]) {
        // Handle both old format (drawing_upload) and new format (drawing_update)
        let projectName = userInfo["projectName"] as? String ?? "Project"
        
        // New format from backend: drawing_update with projectId as string
        if let projectIdString = userInfo["projectId"] as? String,
           let projectId = Int(projectIdString) {
            // Backend sends drawing_update - just log it, navigation handled on tap
            print("📱 Drawing update notification for project \(projectId)")
            NotificationManager.shared.addDebugMessage("📱 Drawing update notification received")
            return
        }
        
        // Old format: drawing_upload with specific drawing details
        if let drawingTitle = userInfo["drawingTitle"] as? String,
           let drawingNumber = userInfo["drawingNumber"] as? String {
            let drawingId = extractInt(from: userInfo["drawingId"])
            let projectId = extractInt(from: userInfo["projectId"])
            
            NotificationManager.shared.handleDrawingUploadNotification(
                drawingTitle: drawingTitle,
                projectName: projectName,
                drawingNumber: drawingNumber,
                drawingId: drawingId,
                projectId: projectId
            )
        } else {
            print("⚠️ Drawing notification received but missing required fields")
            NotificationManager.shared.addDebugMessage("⚠️ Drawing notification received but missing required fields")
        }
    }
    
    private func handleDocumentNotification(userInfo: [AnyHashable: Any]) {
        // Handle both old format (document_upload) and new format (document_update)
        let projectName = userInfo["projectName"] as? String ?? "Project"
        
        // New format from backend: document_update with projectId as string
        if let projectIdString = userInfo["projectId"] as? String,
           let projectId = Int(projectIdString) {
            // Backend sends document_update - just log it, navigation handled on tap
            print("📱 Document update notification for project \(projectId)")
            NotificationManager.shared.addDebugMessage("📱 Document update notification received")
            return
        }
        
        // Old format: document_upload with specific document details
        if let documentName = userInfo["documentName"] as? String ?? userInfo["name"] as? String,
           let documentId = extractInt(from: userInfo["documentId"]),
           let projectId = extractInt(from: userInfo["projectId"]) {
            NotificationManager.shared.handleDocumentUploadNotification(
                documentName: documentName,
                projectName: projectName,
                documentId: documentId,
                projectId: projectId
            )
        } else {
            print("⚠️ Document notification received but missing required fields")
            NotificationManager.shared.addDebugMessage("⚠️ Document notification received but missing required fields")
        }
    }
    
    private func handleRFIUpdateNotification(userInfo: [AnyHashable: Any]) {
        // Handle RFI update notifications from backend
        print("📱 RFI update notification received")
        NotificationManager.shared.addDebugMessage("📱 RFI update notification received")
        
        // Backend sends: projectId (string), projectName, rfiId (string), rfiNumber (string)
        // Navigation will be handled when user taps the notification
    }
    
    private func handleMaterialRequisitionNotification(userInfo: [AnyHashable: Any]) {
        // Handle material requisition notifications from backend
        print("📱 Material requisition notification received")
        NotificationManager.shared.addDebugMessage("📱 Material requisition notification received")
        
        // Backend sends: projectId (string), projectName, requisitionId (string), requisitionNumber (string)
        // Navigation will be handled when user taps the notification
    }
    
    private func handleLogNotification(userInfo: [AnyHashable: Any]) {
        // Handle log notifications from backend
        print("📱 Log notification received")
        NotificationManager.shared.addDebugMessage("📱 Log notification received")
        
        // Backend sends: projectId (string), projectName, logId (string), logNumber (string)
        // Navigation will be handled when user taps the notification
    }
    
    private func handleSnagNotification(userInfo: [AnyHashable: Any]) {
        // Handle snag notifications from backend
        print("📱 Snag notification received")
        NotificationManager.shared.addDebugMessage("📱 Snag notification received")
        
        // Backend sends: projectId (string), projectName, snagId (string)
        // Navigation will be handled when user taps the notification
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
