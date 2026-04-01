import Foundation
import Combine

/// Event data received from the permit SSE endpoint (GET /permits/events)
struct PermitSSEEvent: Decodable {
    let type: String
    let permit: Permit?
    let projectId: Int?
    let timestamp: String?
    let message: String?
}

/// Manager for handling real-time permit events via SSE (same pattern as material requisitions).
class PermitEventManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = PermitEventManager()

    @Published var lastEvent: PermitSSEEvent?
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

    private let iso8601Frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private override init() {
        super.init()
    }

    /// Connect to the permit SSE endpoint for a specific project
    func connect(projectId: Int, token: String) {
        disconnect()

        currentProjectId = projectId
        currentToken = token
        reconnectAttempts = 0

        startConnection()
    }

    private func startConnection() {
        guard let projectId = currentProjectId, let token = currentToken else {
            print("PermitEventManager: Missing projectId or token")
            return
        }

        let baseURL = APIClient.baseURL

        var urlComponents = URLComponents(string: "\(baseURL)/permits/events")
        urlComponents?.queryItems = [
            URLQueryItem(name: "projectId", value: String(projectId)),
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = urlComponents?.url else {
            print("PermitEventManager: Invalid URL")
            return
        }

        print("PermitEventManager: Connecting to permit events")

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

        print("PermitEventManager: Disconnected")
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("PermitEventManager: Max reconnect attempts reached")
            DispatchQueue.main.async {
                self.connectionError = "Connection lost. Pull to refresh."
            }
            return
        }

        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))

        print("PermitEventManager: Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startConnection()
        }
    }

    private var eventDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { [weak self] decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let d = self?.iso8601Frac.date(from: dateString) { return d }
            if let d = self?.iso8601NoFrac.date(from: dateString) { return d }
            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            if let d = fallback.date(from: dateString) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }

    // MARK: - URLSessionDataDelegate

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
        DispatchQueue.main.async {
            self.isConnected = false
        }

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                print("PermitEventManager: Connection cancelled")
                return
            }
            print("PermitEventManager: Connection error: \(error.localizedDescription)")
            scheduleReconnect()
        } else {
            print("PermitEventManager: Connection closed by server")
            scheduleReconnect()
        }
    }

    private func processSSEEvent(_ eventString: String) {
        var eventData: String?

        for line in eventString.components(separatedBy: "\n") {
            if line.hasPrefix("data: ") {
                eventData = String(line.dropFirst(6))
            } else if line.hasPrefix(":") {
                continue
            }
        }

        guard let jsonString = eventData,
              let jsonData = jsonString.data(using: .utf8) else {
            return
        }

        do {
            let event = try eventDecoder.decode(PermitSSEEvent.self, from: jsonData)
            handleEvent(event)
        } catch {
            print("PermitEventManager: Failed to decode event: \(error)")
        }
    }

    private func handleEvent(_ event: PermitSSEEvent) {
        print("PermitEventManager: Received event type: \(event.type)")

        DispatchQueue.main.async {
            self.lastEvent = event
            self.connectionError = nil

            switch event.type {
            case "connected":
                self.isConnected = true
                self.reconnectAttempts = 0
                print("PermitEventManager: Connected to SSE")

            case "created":
                if let permit = event.permit, let projectId = event.projectId {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PermitCreated"),
                        object: nil,
                        userInfo: ["permit": permit, "projectId": projectId]
                    )
                }

            case "updated", "submitted", "reviewed", "activated", "suspended", "reinstated", "closeout_submitted", "closeout_reviewed", "closed":
                if let permit = event.permit, let projectId = event.projectId {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PermitUpdated"),
                        object: nil,
                        userInfo: ["permit": permit, "projectId": projectId]
                    )
                }

            case "deleted":
                if let permit = event.permit, let projectId = event.projectId {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PermitDeleted"),
                        object: nil,
                        userInfo: ["permitId": permit.id, "projectId": projectId]
                    )
                }

            default:
                print("PermitEventManager: Unknown event type: \(event.type)")
            }
        }
    }
}
