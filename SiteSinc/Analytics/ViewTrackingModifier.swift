import SwiftUI

/// SwiftUI View Modifier for automatic page view tracking
/// Usage: `.trackPageView("/projects/123", projectId: 123)`
struct ViewTrackingModifier: ViewModifier {
    let page: String
    let projectId: Int?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsService.shared.trackPageView(page, projectId: projectId)
            }
            .onDisappear {
                AnalyticsService.shared.trackPageExit(projectId: projectId)
            }
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
