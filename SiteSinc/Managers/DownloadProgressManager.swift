import Foundation
import SwiftUI

@MainActor
final class DownloadProgressManager: ObservableObject {
    static let shared = DownloadProgressManager()
    @Published private(set) var projectState: [Int: ProjectDownloadState] = [:]

    private init() {}

    struct ProjectDownloadState {
        var isLoading: Bool
        var progress: Double
        var hasError: Bool
        var isOfflineEnabled: Bool
    }

    func status(for projectId: Int) -> ProjectDownloadState {
        projectState[projectId] ?? ProjectDownloadState(isLoading: false, progress: 0, hasError: false, isOfflineEnabled: UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)"))
    }

    func setLoading(projectId: Int, isLoading: Bool) {
        var state = status(for: projectId)
        state.isLoading = isLoading
        projectState[projectId] = state
    }

    func setProgress(projectId: Int, progress: Double) {
        var state = status(for: projectId)
        state.progress = progress
        state.isLoading = true
        projectState[projectId] = state
    }

    func setError(projectId: Int, hasError: Bool) {
        var state = status(for: projectId)
        state.hasError = hasError
        projectState[projectId] = state
    }

    func setOfflineEnabled(projectId: Int, enabled: Bool) {
        var state = status(for: projectId)
        state.isOfflineEnabled = enabled
        projectState[projectId] = state
    }
}


