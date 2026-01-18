import SwiftUI

/// SwiftUI View Modifier for automatic page view tracking
/// Usage: `.trackPageView("/projects/123", projectId: 123)`
/// 
/// This tracks page views to:
/// 1. Backend API (via AnalyticsService) for internal analytics
/// 2. GA4 (via AnalyticsManager) with page_view events matching frontend format
struct ViewTrackingModifier: ViewModifier {
    let page: String
    let projectId: Int?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Track to backend API and get screenName from response
                AnalyticsService.shared.trackPageView(page, projectId: projectId) { screenName in
                    // Use backend-generated screenName for GA4 (consistent across platforms)
                    // Fallback to local pageTitle() if backend doesn't return screenName
                    let finalScreenName = screenName ?? self.pageTitle(from: page)
                    
                    // Track to GA4 with page_view event (matching frontend format)
                    var params: [String: Any] = [
                        "page_path": page,
                        "page_title": finalScreenName
                    ]
                    if let projectId = projectId {
                        params["project_id"] = String(projectId)
                    }
                    AnalyticsManager.shared.trackEvent(.pageView, parameters: params)
                    
                    #if DEBUG
                    if screenName == nil {
                        print("⚠️ [Analytics] Using fallback screenName for page: \(page)")
                    } else {
                        print("✅ [Analytics] Using backend screenName: \(finalScreenName) for page: \(page)")
                    }
                    #endif
                }
            }
            .onDisappear {
                AnalyticsService.shared.trackPageExit(projectId: projectId)
            }
    }
    
    /// Extract a readable page title from the page path
    /// Used as fallback if backend doesn't return screenName
    private func pageTitle(from path: String) -> String {
        // Convert paths like "/projects/123/drawings" to "Drawings - Project 123"
        if path.hasPrefix("/projects/") {
            let components = path.split(separator: "/")
            if components.count >= 2 {
                let projectId = components[1]
                if components.count >= 3 {
                    let section = components[2].capitalized
                    // Handle plural forms
                    let sectionName = section.replacingOccurrences(of: "Rfi", with: "RFI")
                    return "\(sectionName) - Project \(projectId)"
                } else {
                    return "Project \(projectId)"
                }
            }
        }
        // Fallback: use path as title
        return path.isEmpty ? "SiteSinc" : path
    }
}

extension View {
    /// Track page views automatically when the view appears/disappears
    /// - Parameters:
    ///   - page: The page path (e.g., "/projects/123" or "/projects/123/rfi")
    ///   - projectId: Optional project ID for project-specific tracking
    /// - Returns: Modified view with tracking enabled
    func trackPageView(_ page: String, projectId: Int? = nil) -> some View {
        modifier(ViewTrackingModifier(page: page, projectId: projectId))
    }
}
