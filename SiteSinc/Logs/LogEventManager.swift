import Foundation
import Combine

struct LogSSEEvent: Decodable {
    let type: String
    let log: Log?
    let projectId: Int?
    let timestamp: String?
    let message: String?
}

class LogEventManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = LogEventManager()

    @Published var lastEvent: LogSSEEvent?
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

    private override init() {
        super.init()
    }

    func connect(projectId: Int, token: String) {
        disconnect()
        currentProjectId = projectId
        currentToken = token
        reconnectAttempts = 0
        startConnection()
    }

    private func startConnection() {
        guard let projectId = currentProjectId, let token = currentToken else { return }

        var urlComponents = URLComponents(string: "\(APIClient.baseURL)/logs/events")
        urlComponents?.queryItems = [
            URLQueryItem(name: "projectId", value: String(projectId)),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = urlComponents?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = TimeInterval.infinity

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        dataTask = urlSession?.dataTask(with: request)
        dataTask?.resume()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        buffer = Data()
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            DispatchQueue.main.async { self.connectionError = "Connection lost. Pull to refresh." }
            return
        }
        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startConnection()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        guard let string = String(data: buffer, encoding: .utf8) else { return }
        let events = string.components(separatedBy: "\n\n")
        if !string.hasSuffix("\n\n") && events.count > 1 {
            buffer = events.last?.data(using: .utf8) ?? Data()
        } else if string.hasSuffix("\n\n") {
            buffer = Data()
        }
        for event in events.dropLast(string.hasSuffix("\n\n") ? 0 : 1) {
            processSSEEvent(event)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { self.isConnected = false }
        if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
        scheduleReconnect()
    }

    private func processSSEEvent(_ eventString: String) {
        var eventData: String?
        for line in eventString.components(separatedBy: "\n") {
            if line.hasPrefix("data: ") { eventData = String(line.dropFirst(6)) }
        }
        guard let jsonString = eventData, let jsonData = jsonString.data(using: .utf8) else { return }
        do {
            let event = try JSONDecoder().decode(LogSSEEvent.self, from: jsonData)
            handleEvent(event)
        } catch {
            print("LogEventManager: Failed to decode event: \(error)")
        }
    }

    private func handleEvent(_ event: LogSSEEvent) {
        DispatchQueue.main.async {
            self.lastEvent = event
            self.connectionError = nil
            switch event.type {
            case "connected":
                self.isConnected = true
                self.reconnectAttempts = 0
            case "created", "updated", "response":
                if let log = event.log, let projectId = event.projectId {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("LogUpdated"),
                        object: nil,
                        userInfo: ["log": log, "projectId": projectId, "eventType": event.type]
                    )
                }
            default:
                break
            }
        }
    }
}
