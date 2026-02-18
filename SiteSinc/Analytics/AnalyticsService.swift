import Foundation

/// Backend Activity Tracking Service
/// Tracks user activity and sends it to the backend API for storage in the UserActivity table.
/// - Only runs when the user is signed in (token set). Cleared on logout for privacy and battery.
/// - Optional user setting can disable monitoring; no background location or high-frequency updates.
class AnalyticsService {
    static let shared = AnalyticsService()
    
    private let baseURL: String
    private var authToken: String?
    
    private static let activityMonitoringKey = "activity_monitoring_enabled"
    
    /// When false, no activity is sent (user preference). Default true. Only applies when signed in.
    var isActivityMonitoringEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.activityMonitoringKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.activityMonitoringKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.activityMonitoringKey)
        }
    }
    
    private init() {
        // Use the same base URL as APIClient
        #if DEBUG
        self.baseURL = "http://localhost:3000/api"
        #else
        self.baseURL = "https://sitesinc.onrender.com/api"
        #endif
    }
    
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    /// Call on logout so we stop tracking and don't hold token. No activity is sent when not signed in.
    func clearAuthToken() {
        authToken = nil
        hasActiveProjectClock = false
        currentPage = nil
        pageStartTime = nil
        accumulatedTime = 0
        isActive = false
    }

    /// When true, activity payloads include user location (last known). Set by clock view when user is signed into a project.
    /// Location is only tracked when signed in to a project, not just signed into the app.
    private var hasActiveProjectClock: Bool = false
    func setSignedIntoProject(_ signedIn: Bool) {
        hasActiveProjectClock = signedIn
    }
    
    // MARK: - Page View Tracking
    
    private var currentPage: String?
    private var pageStartTime: Date?
    private var accumulatedTime: TimeInterval = 0
    private var isActive: Bool = true
    
    func trackPageView(_ page: String, projectId: Int? = nil, completion: ((String?) -> Void)? = nil) {
        guard authToken != nil, isActivityMonitoringEnabled else {
            completion?(nil)
            return
        }
        // Track exit from previous page if exists
        if let previousPage = currentPage, let startTime = pageStartTime {
            let timeSpent = Int(Date().timeIntervalSince(startTime) + accumulatedTime)
            if timeSpent > 0 {
                trackActivity(
                    action: "page_exit",
                    page: previousPage,
                    projectId: projectId,
                    timeSpent: timeSpent
                )
            }
        }
        
        // Reset for new page
        currentPage = page
        pageStartTime = Date()
        accumulatedTime = 0
        isActive = true
        
        // Track entry to new page (with small delay to ensure view is fully loaded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.trackActivity(
                action: "page_view",
                page: page,
                projectId: projectId,
                completion: completion
            )
        }
    }
    
    func trackPageExit(projectId: Int? = nil) {
        guard authToken != nil, isActivityMonitoringEnabled else { return }
        guard let page = currentPage, let startTime = pageStartTime else { return }
        let timeSpent = Int(Date().timeIntervalSince(startTime) + accumulatedTime)
        if timeSpent > 0 {
            trackActivity(
                action: "page_exit",
                page: page,
                projectId: projectId,
                timeSpent: timeSpent,
                useKeepalive: true
            )
        }
    }
    
    // MARK: - Activity Tracking
    
    func trackActivity(
        action: String,
        page: String? = nil,
        entityType: String? = nil,
        entityId: Int? = nil,
        projectId: Int? = nil,
        metadata: [String: Any]? = nil,
        timeSpent: Int? = nil,
        useKeepalive: Bool = false,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let token = authToken else {
            #if DEBUG
            print("⚠️ [Analytics] No auth token available (signed out)")
            #endif
            completion?(nil)
            return
        }
        guard isActivityMonitoringEnabled else {
            completion?(nil)
            return
        }
        
        let url = URL(string: "\(baseURL)/analytics/activity")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var mergedMetadata = (metadata ?? [String: Any]()) as [String: Any]
        if hasActiveProjectClock, let latLon = LocationManager.shared.lastKnownLatLon {
            mergedMetadata["latitude"] = latLon.lat
            mergedMetadata["longitude"] = latLon.lon
        }
        
        var body: [String: Any] = ["action": action]
        if let page = page { body["page"] = page }
        if let entityType = entityType { body["entityType"] = entityType }
        if let entityId = entityId { body["entityId"] = entityId }
        if let projectId = projectId { body["projectId"] = projectId }
        if !mergedMetadata.isEmpty { body["metadata"] = mergedMetadata }
        if let timeSpent = timeSpent { body["timeSpent"] = timeSpent }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            #if DEBUG
            print("❌ [Analytics] Failed to encode request body: \(error)")
            #endif
            completion?(nil)
            return
        }
        
        // Use URLSession with appropriate configuration
        let config = URLSessionConfiguration.default
        if useKeepalive {
            // For exit events, use longer timeouts to ensure delivery
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            // Use background configuration for better reliability on app termination
            config.isDiscretionary = false
        }
        let session = URLSession(configuration: config)
        
        session.dataTask(with: request) { data, response, error in
            var screenName: String? = nil
            
            if let error = error {
                #if DEBUG
                print("❌ [Analytics] Error: \(error.localizedDescription)")
                #endif
                completion?(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Parse response to extract screenName
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let returnedScreenName = json["screenName"] as? String {
                        screenName = returnedScreenName
                        #if DEBUG
                        print("✅ [Analytics] Tracked: \(action) - \(page ?? "no page"), screenName: \(returnedScreenName)")
                        #endif
                    } else {
                        #if DEBUG
                        print("✅ [Analytics] Tracked: \(action) - \(page ?? "no page") (no screenName in response)")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("⚠️ [Analytics] Failed: \(httpResponse.statusCode)")
                    #endif
                }
            }
            
            // Call completion handler with screenName (or nil if not available)
            completion?(screenName)
        }.resume()
    }
    
    // MARK: - App Lifecycle Handling
    
    func handleAppWillEnterBackground() {
        guard authToken != nil, isActivityMonitoringEnabled else { return }
        // Save accumulated time when app goes to background
        if let startTime = pageStartTime, isActive {
            accumulatedTime += Date().timeIntervalSince(startTime)
            pageStartTime = Date() // Reset for when app comes back
            isActive = false
        }
    }
    
    func handleAppWillEnterForeground() {
        guard authToken != nil, isActivityMonitoringEnabled else { return }
        // Resume tracking when app comes to foreground
        pageStartTime = Date()
        isActive = true
    }
    
    func handleAppWillTerminate() {
        guard authToken != nil, isActivityMonitoringEnabled else { return }
        trackPageExit()
    }
}
