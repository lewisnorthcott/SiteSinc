import Foundation

class DrawingAccessLogger {
    static let shared = DrawingAccessLogger()
    private let queueKey = "drawingAccessLogQueue"

    struct LogEntry: Codable {
        let fileId: Int
        let type: String // "view" or "download"
        let token: String
        let timestamp: Date
    }

    private init() {}

    func logAccess(fileId: Int, type: String, token: String) {
        guard let url = URL(string: "\(APIClient.baseURL)/drawings/proxy-file/\(fileId)?type=\(type)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("DrawingAccessLogger: Failed to log \(type): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    if !NetworkStatusManager.shared.isNetworkAvailable {
                        self.queueLog(fileId: fileId, type: type, token: token)
                    }
                }
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("DrawingAccessLogger: Server error \(httpResponse.statusCode), queueing log.")
                DispatchQueue.main.async {
                    if !NetworkStatusManager.shared.isNetworkAvailable {
                        self.queueLog(fileId: fileId, type: type, token: token)
                    }
                }
            }
        }
        task.resume()
    }

    private func queueLog(fileId: Int, type: String, token: String) {
        var queue = loadQueue()
        queue.append(LogEntry(fileId: fileId, type: type, token: token, timestamp: Date()))
        saveQueue(queue)
    }

    func flushQueue() {
        let queue = loadQueue()
        guard !queue.isEmpty else { return }
        var stillQueued: [LogEntry] = []
        let group = DispatchGroup()
        for entry in queue {
            group.enter()
            guard let url = URL(string: "\(APIClient.baseURL)/drawings/proxy-file/\(entry.fileId)?type=\(entry.type)") else {
                stillQueued.append(entry)
                group.leave()
                continue
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    print("DrawingAccessLogger: Failed to flush log: \(error.localizedDescription)")
                    stillQueued.append(entry)
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    stillQueued.append(entry)
                }
                group.leave()
            }
            task.resume()
        }
        group.notify(queue: .main) {
            self.saveQueue(stillQueued)
        }
    }

    private func loadQueue() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return queue
    }

    private func saveQueue(_ queue: [LogEntry]) {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
} 
