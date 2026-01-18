import Foundation

/// Backend Activity Tracking Service
/// Tracks user activity and sends it to the backend API for storage in the UserActivity table
/// This complements GA4 tracking by providing detailed backend analytics
class AnalyticsService {
    static let shared = AnalyticsService()
    
    private let baseURL: String
    private var authToken: String?
    
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
    
    // MARK: - Page View Tracking
    
    private var currentPage: String?
    private var pageStartTime: Date?
    private var accumulatedTime: TimeInterval = 0
    private var isActive: Bool = true
    
    func trackPageView(_ page: String, projectId: Int? = nil, completion: ((String?) -> Void)? = nil) {
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
            print("⚠️ [Analytics] No auth token available")
            #endif
            completion?(nil)
            return
        }
        
        let url = URL(string: "\(baseURL)/analytics/activity")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["action": action]
        if let page = page { body["page"] = page }
        if let entityType = entityType { body["entityType"] = entityType }
        if let entityId = entityId { body["entityId"] = entityId }
        if let projectId = projectId { body["projectId"] = projectId }
        if let metadata = metadata { body["metadata"] = metadata }
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
        // Save accumulated time when app goes to background
        if let startTime = pageStartTime, isActive {
            accumulatedTime += Date().timeIntervalSince(startTime)
            pageStartTime = Date() // Reset for when app comes back
            isActive = false
        }
    }
    
    func handleAppWillEnterForeground() {
        // Resume tracking when app comes to foreground
        pageStartTime = Date()
        isActive = true
    }
    
    func handleAppWillTerminate() {
        // Final exit tracking
        trackPageExit()
    }
}
