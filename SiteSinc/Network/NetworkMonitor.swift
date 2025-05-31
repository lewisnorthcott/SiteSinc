import Network
import Foundation
import Combine

@MainActor
class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var networkIsAvailable: Bool = true
    private var hasReceivedInitialUpdate = false
    private var initialStatusContinuation: (@Sendable (Bool) -> Void)?
    // Publisher for network status changes
    private let networkStatusSubject = PassthroughSubject<Bool, Never>()
    var networkStatusPublisher: AnyPublisher<Bool, Never> {
        networkStatusSubject.eraseToAnyPublisher()
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                strongSelf.networkIsAvailable = isAvailable
                strongSelf.hasReceivedInitialUpdate = true
                print("NetworkMonitor: Network status updated - isNetworkAvailable: \(isAvailable), path: \(path.status)")
                if let completion = strongSelf.initialStatusContinuation {
                    completion(isAvailable)
                    strongSelf.initialStatusContinuation = nil
                }
                // Publish the new network status
                strongSelf.networkStatusSubject.send(isAvailable)
            }
        }
        monitor.start(queue: queue)
    }

    func isNetworkAvailable() -> Bool {
        return networkIsAvailable
    }

    func waitForInitialNetworkStatus(timeout: TimeInterval = 10.0) async -> Bool {
        if hasReceivedInitialUpdate {
            print("NetworkMonitor: Already received initial update - isNetworkAvailable: \(networkIsAvailable)")
            return networkIsAvailable
        }
        
        // Perform a quick synchronous check to avoid unnecessary waiting
        let initialPath = monitor.currentPath
        if initialPath.status == .satisfied || initialPath.status == .unsatisfied {
            networkIsAvailable = initialPath.status == .satisfied
            hasReceivedInitialUpdate = true
            print("NetworkMonitor: Immediate initial network status - isNetworkAvailable: \(networkIsAvailable)")
            networkStatusSubject.send(networkIsAvailable)
            return networkIsAvailable
        }
        
        return await withCheckedContinuation { continuation in
            self.initialStatusContinuation = { isAvailable in
                continuation.resume(returning: isAvailable)
            }
            print("NetworkMonitor: Waiting for initial network status")
            
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                if let strongSelf = self, strongSelf.initialStatusContinuation != nil {
                    print("NetworkMonitor: Timeout waiting for initial network status after \(timeout)s, returning current status: \(strongSelf.networkIsAvailable)")
                    strongSelf.initialStatusContinuation?(strongSelf.networkIsAvailable)
                    strongSelf.initialStatusContinuation = nil
                }
            }
        }
    }
}
