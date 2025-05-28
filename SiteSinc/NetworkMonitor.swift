import Network
import Foundation

@MainActor // 1. Isolate the class to the main actor
class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor") // Monitor callbacks on this queue
    private var networkIsAvailable: Bool = false
    private var hasReceivedInitialUpdate = false
    // 2. Explicitly mark the closure as @Sendable for clarity
    private var initialStatusCompletion: (@Sendable (Bool) -> Void)?

    private init() { // This init is now @MainActor
        monitor.pathUpdateHandler = { [weak self] path in // Called on 'self.queue'
            let isAvailable = path.status == .satisfied
            
            // Dispatch to main actor to update @MainActor properties
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                strongSelf.networkIsAvailable = isAvailable
                strongSelf.hasReceivedInitialUpdate = true
                print("NetworkMonitor: Network status updated - isNetworkAvailable: \(isAvailable)")
                if let completion = strongSelf.initialStatusCompletion {
                    completion(isAvailable)
                    strongSelf.initialStatusCompletion = nil
                }
            }
        }
        monitor.start(queue: queue)
    }

    // This function is now @MainActor.
    // It can be called synchronously from the main actor,
    // or asynchronously with 'await' from other actors.
    func isNetworkAvailable() -> Bool {
        return networkIsAvailable
    }

    // This async function will run on the MainActor.
    func waitForInitialNetworkStatus(timeout: TimeInterval = 5.0) async -> Bool {
        if hasReceivedInitialUpdate {
            return networkIsAvailable
        }
        
        return await withCheckedContinuation { continuation in
            self.initialStatusCompletion = { isAvailable in // Captures Sendable 'continuation'
                continuation.resume(returning: isAvailable)
            }
            print("NetworkMonitor: Waiting for initial network status")
            
            let deadline = DispatchTime.now() + timeout
            // The closure for asyncAfter runs on the main actor.
            // Capturing '[weak self]' (where self is @MainActor) is now safe
            // because the closure executes on the same main actor.
            DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                if let strongSelf = self, strongSelf.initialStatusCompletion != nil {
                    print("NetworkMonitor: Timeout waiting for initial network status, assuming unavailable")
                    strongSelf.initialStatusCompletion?(false)
                    strongSelf.initialStatusCompletion = nil
                }
            }
        }
    }
}
