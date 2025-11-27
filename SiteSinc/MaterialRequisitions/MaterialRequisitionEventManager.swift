import Foundation
import Combine

/// Event types received from the SSE endpoint
enum MaterialRequisitionEventType: String, Codable {
    case connected
    case created
    case updated
    case deleted
    case assigned
    case unassigned
}

/// Event data received from SSE
struct MaterialRequisitionEvent: Codable {
    let type: String
    let requisition: MaterialRequisition?
    let projectId: Int?
    let timestamp: String?
    let message: String?
}

/// Manager for handling real-time material requisition events via SSE
class MaterialRequisitionEventManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = MaterialRequisitionEventManager()
    
    @Published var lastEvent: MaterialRequisitionEvent?
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
    var onRequisitionCreated: ((MaterialRequisition) -> Void)?
    var onRequisitionUpdated: ((MaterialRequisition) -> Void)?
    var onRequisitionDeleted: ((Int) -> Void)?
    
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
            print("MaterialRequisitionEventManager: Missing projectId or token")
            return
        }
        
        let baseURL = APIClient.baseURL
        
        // Build the SSE URL with query parameters
        var urlComponents = URLComponents(string: "\(baseURL)/material-requisitions/events")
        urlComponents?.queryItems = [
            URLQueryItem(name: "projectId", value: String(projectId)),
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let url = urlComponents?.url else {
            print("MaterialRequisitionEventManager: Invalid URL")
            return
        }
        
        print("MaterialRequisitionEventManager: Connecting to \(url.absoluteString)")
        
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
        
        print("MaterialRequisitionEventManager: Disconnected")
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("MaterialRequisitionEventManager: Max reconnect attempts reached")
            DispatchQueue.main.async {
                self.connectionError = "Connection lost. Pull to refresh."
            }
            return
        }
        
        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
        
        print("MaterialRequisitionEventManager: Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts))")
        
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
                print("MaterialRequisitionEventManager: Connection cancelled")
                return
            }
            
            print("MaterialRequisitionEventManager: Connection error: \(error.localizedDescription)")
            scheduleReconnect()
        } else {
            // Server closed connection, try to reconnect
            print("MaterialRequisitionEventManager: Connection closed by server")
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
            let event = try JSONDecoder().decode(MaterialRequisitionEvent.self, from: jsonData)
            handleEvent(event)
        } catch {
            print("MaterialRequisitionEventManager: Failed to decode event: \(error)")
            // Try to print the raw JSON for debugging
            print("MaterialRequisitionEventManager: Raw JSON: \(jsonString)")
        }
    }
    
    private func handleEvent(_ event: MaterialRequisitionEvent) {
        print("MaterialRequisitionEventManager: Received event type: \(event.type)")
        
        DispatchQueue.main.async {
            self.lastEvent = event
            self.connectionError = nil
            
            switch event.type {
            case "connected":
                self.isConnected = true
                self.reconnectAttempts = 0
                print("MaterialRequisitionEventManager: Connected to SSE")
                
            case "created":
                if let requisition = event.requisition {
                    print("MaterialRequisitionEventManager: Requisition created: \(requisition.id)")
                    self.onRequisitionCreated?(requisition)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MaterialRequisitionCreated"),
                        object: nil,
                        userInfo: ["requisition": requisition, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "updated", "assigned", "unassigned":
                if let requisition = event.requisition {
                    print("MaterialRequisitionEventManager: Requisition updated: \(requisition.id)")
                    self.onRequisitionUpdated?(requisition)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MaterialRequisitionUpdated"),
                        object: nil,
                        userInfo: ["requisition": requisition, "projectId": event.projectId ?? 0]
                    )
                }
                
            case "deleted":
                if let requisition = event.requisition {
                    print("MaterialRequisitionEventManager: Requisition deleted: \(requisition.id)")
                    self.onRequisitionDeleted?(requisition.id)
                    
                    // Post notification for views to handle
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MaterialRequisitionDeleted"),
                        object: nil,
                        userInfo: ["requisitionId": requisition.id, "projectId": event.projectId ?? 0]
                    )
                }
                
            default:
                print("MaterialRequisitionEventManager: Unknown event type: \(event.type)")
            }
        }
    }
}

