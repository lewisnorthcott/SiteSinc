import Foundation
import Combine

@MainActor
class NetworkStatusManager: ObservableObject {
    @Published var isNetworkAvailable: Bool = true
    private var cancellables = Set<AnyCancellable>()
    
    static let shared = NetworkStatusManager()
    
    private init() {
        // Initialize network status
        Task {
            let initialStatus = await NetworkMonitor.shared.waitForInitialNetworkStatus()
            self.isNetworkAvailable = initialStatus
        }
        
        // Subscribe to network status changes
        NetworkMonitor.shared.networkStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAvailable in
                print("NetworkStatusManager: Network status changed - isNetworkAvailable: \(isAvailable)")
                self?.isNetworkAvailable = isAvailable
            }
            .store(in: &cancellables)
    }
}
