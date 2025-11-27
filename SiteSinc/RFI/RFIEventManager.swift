import Foundation
import Combine

/// Event types received from the RFI SSE endpoint
enum RFIEventType: String, Codable {
    case connected
    case created
    case updated
    case deleted
    case response_added
    case response_accepted
    case response_rejected
    case closed
    case reopened
}

/// Event data received from SSE for RFIs
struct RFISSEEvent: Codable {
    let type: String
    let rfi: RFI?
    let projectId: Int?
    let timestamp: String?
    let message: String?
}

/// Manager for handling real-time RFI events via SSE
class RFIEventManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = RFIEventManager()
    
    @Published var lastEvent: RFISSEEvent?
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    
    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private var currentProjectId: Int?
    private var currentToken: String?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 2.0
    
    // Callbacks for event handling
    var onRFICreated: ((RFI) -> Void)?
    var onRFIUpdated: ((RFI) -> Void)?
    var onRFIDeleted: ((Int) -> Void)?
    var onResponseAdded: ((RFI) -> Void)?
    var onResponseAccepted: ((RFI) -> Void)?
    var onResponseRejected: ((RFI) -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Connect to the SSE endpoint for a specific project
    func connect(projectId: Int, token: String) {
        // Disconnect from any existing connection
        disconnect()
        
        self.currentProjectId = projectId
        self.currentToken = token
        self.reconnectAttempts = 0
        
        startConnection()
    }
    
    private func startConnection() {
        guard let projectId = currentProjectId, let token = currentToken else {
            print("RFIEventManager: Missing projectId or token")
            return
        }
        
        let baseURL = APIClient.baseURL
        
        // Build the SSE URL with query parameters
        var urlComponents = URLComponents(string: "\(baseURL)/rfis/events")
        urlComponents?.queryItems = [
            URLQueryItem(name: "projectId", value: String(projectId)),
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let url = urlComponents?.url else {
            print("RFIEventManager: Invalid URL")
            return
        }
        
        print("RFIEventManager: Connecting to \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = TimeInterval.infinity // SSE connections should stay open
        
        // Create a session with delegate for streaming
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity
        
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        dataTask = urlSession?.dataTask(with: request)
        dataTask?.resume()
    }
    
    /// Disconnect from the SSE endpoint
    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        buffer = Data()
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        print("RFIEventManager: Disconnected")
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("RFIEventManager: Max reconnect attempts reached")
            DispatchQueue.main.async {
                self.connectionError = "Connection lost. Pull to refresh."
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
        
        print("RFIEventManager: Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts))")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startConnection()
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        
        // Parse SSE events from buffer
        guard let string = String(data: buffer, encoding: .utf8) else { return }
        
        // SSE events are separated by double newlines
        let events = string.components(separatedBy: "\n\n")
        
        // Keep the last incomplete event in buffer
        if !string.hasSuffix("\n\n") && events.count > 1 {
            buffer = events.last?.data(using: .utf8) ?? Data()
        } else if string.hasSuffix("\n\n") {
            buffer = Data()
        }
        
        // Process complete events
        for event in events.dropLast(string.hasSuffix("\n\n") ? 0 : 1) {
            processSSEEvent(event)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        if let error = error as NSError? {
            // Don't reconnect if cancelled
            if error.code == NSURLErrorCancelled {
                print("RFIEventManager: Connection cancelled")
                return
            }
            
            print("RFIEventManager: Connection error: \(error.localizedDescription)")
            scheduleReconnect()
        } else {
            // Server closed connection, try to reconnect
            print("RFIEventManager: Connection closed by server")
            scheduleReconnect()
        }
    }
    
    private func processSSEEvent(_ eventString: String) {
        var eventData: String?
        
        for line in eventString.components(separatedBy: "\n") {
            if line.hasPrefix("data: ") {
                eventData = String(line.dropFirst(6))
            } else if line.hasPrefix(":") {
                // Comment/keepalive, ignore
                continue
            }
        }
        
        guard let jsonString = eventData,
              let jsonData = jsonString.data(using: .utf8) else {
            return
        }
        
        do {
            let event = try JSONDecoder().decode(RFISSEEvent.self, from: jsonData)
            handleEvent(event)
        } catch {
            print("RFIEventManager: Failed to decode event: \(error)")
            // Try to print the raw JSON for debugging
            print("RFIEventManager: Raw JSON: \(jsonString)")
        }
    }
    
    private func handleEvent(_ event: RFISSEEvent) {
        print("RFIEventManager: Received event type: \(event.type)")
        
        DispatchQueue.main.async {
            self.lastEvent = event
            self.connectionError = nil
            
            switch event.type {
            case "connected":
                self.isConnected = true
                self.reconnectAttempts = 0
                print("RFIEventManager: Connected to SSE")
                
            case "created":
                if let rfi = event.rfi {
                    print("RFIEventManager: RFI created: \(rfi.id)")
                    self.onRFICreated?(rfi)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFICreated"),
                        object: nil,
                        userInfo: ["rfi": rfi, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "updated", "closed", "reopened":
                if let rfi = event.rfi {
                    print("RFIEventManager: RFI updated: \(rfi.id)")
                    self.onRFIUpdated?(rfi)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFIUpdated"),
                        object: nil,
                        userInfo: ["rfi": rfi, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "deleted":
                if let rfi = event.rfi {
                    print("RFIEventManager: RFI deleted: \(rfi.id)")
                    self.onRFIDeleted?(rfi.id)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFIDeleted"),
                        object: nil,
                        userInfo: ["rfiId": rfi.id, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "response_added":
                if let rfi = event.rfi {
                    print("RFIEventManager: Response added to RFI: \(rfi.id)")
                    self.onResponseAdded?(rfi)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFIResponseAdded"),
                        object: nil,
                        userInfo: ["rfi": rfi, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "response_accepted":
                if let rfi = event.rfi {
                    print("RFIEventManager: Response accepted for RFI: \(rfi.id)")
                    self.onResponseAccepted?(rfi)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFIResponseAccepted"),
                        object: nil,
                        userInfo: ["rfi": rfi, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "response_rejected":
                if let rfi = event.rfi {
                    print("RFIEventManager: Response rejected for RFI: \(rfi.id)")
                    self.onResponseRejected?(rfi)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RFIResponseRejected"),
                        object: nil,
                        userInfo: ["rfi": rfi, "projectId": event.projectId ?? 0]
                    )
                }
                
            default:
                print("RFIEventManager: Unknown event type: \(event.type)")
            }
        }
    }
}

