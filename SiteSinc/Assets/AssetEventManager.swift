//
//  AssetEventManager.swift
//  SiteSinc
//
//  Manager for real-time asset register updates via SSE (webhook events).
//  Connects to GET /api/assets/events?token=... and notifies when assets change.
//

import Foundation
import Combine

/// Minimal asset payload in SSE events (API may send id + assetNumber only)
struct AssetSSEEventPayload: Codable {
    let id: Int?
    let assetNumber: String?
}

/// Event data received from the asset SSE endpoint
struct AssetSSEEvent: Codable {
    let type: String
    let asset: AssetSSEEventPayload?
    let tenantId: Int?
    let timestamp: String?
    let message: String?
}

/// Manager for handling real-time asset events via SSE
class AssetEventManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = AssetEventManager()

    @Published var lastEvent: AssetSSEEvent?
    @Published var isConnected: Bool = false
    @Published var connectionError: String?

    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = Data()
    private var currentToken: String?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 2.0

    /// Called when any asset event is received (e.g. so the Assets screen can refresh its list)
    var onAssetsChanged: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Connect to the asset events SSE endpoint (tenant-scoped; no projectId)
    func connect(token: String) {
        disconnect()
        self.currentToken = token
        self.reconnectAttempts = 0
        startConnection()
    }

    private func startConnection() {
        guard let token = currentToken, !token.isEmpty else {
            print("AssetEventManager: Missing token")
            return
        }

        let baseURL = APIClient.baseURL
        var urlComponents = URLComponents(string: "\(baseURL)/assets/events")
        urlComponents?.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = urlComponents?.url else {
            print("AssetEventManager: Invalid URL")
            return
        }

        print("AssetEventManager: Connecting to asset events SSE")

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
        currentToken = nil

        DispatchQueue.main.async {
            self.isConnected = false
        }

        print("AssetEventManager: Disconnected")
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("AssetEventManager: Max reconnect attempts reached")
            DispatchQueue.main.async {
                self.connectionError = "Connection lost. Pull to refresh."
            }
            return
        }

        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
        print("AssetEventManager: Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startConnection()
        }
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
                print("AssetEventManager: Connection cancelled")
                return
            }
            print("AssetEventManager: Connection error: \(error.localizedDescription)")
            scheduleReconnect()
        } else {
            print("AssetEventManager: Connection closed by server")
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
              let jsonData = jsonString.data(using: .utf8) else { return }

        do {
            let event = try JSONDecoder().decode(AssetSSEEvent.self, from: jsonData)
            handleEvent(event)
        } catch {
            print("AssetEventManager: Failed to decode event: \(error)")
        }
    }

    private func handleEvent(_ event: AssetSSEEvent) {
        DispatchQueue.main.async {
            self.lastEvent = event
            self.connectionError = nil

            switch event.type {
            case "connected":
                self.isConnected = true
                self.reconnectAttempts = 0
                print("AssetEventManager: Connected to asset events SSE")

            case "created", "updated", "deleted", "checked_out", "checked_in", "status_changed",
                 "image_added", "image_deleted", "document_added", "document_deleted",
                 "maintenance_added", "maintenance_updated", "maintenance_deleted":
                print("AssetEventManager: Asset event: \(event.type)")
                self.onAssetsChanged?()

            default:
                print("AssetEventManager: Unknown event type: \(event.type)")
                self.onAssetsChanged?()
            }
        }
    }
}
