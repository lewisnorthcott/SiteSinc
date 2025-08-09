import Foundation

@MainActor
final class MarkupSyncManager: ObservableObject {
    static let shared = MarkupSyncManager()

    private init() {}

    private struct PendingMarkup: Codable, Identifiable {
        let id: String // local UUID
        let drawingId: Int
        let drawingFileId: Int
        let body: CreateMarkupRequest
        let createdAt: Date
    }

    private func cacheBaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SiteSincCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func pendingFileURL(drawingId: Int, drawingFileId: Int) -> URL {
        cacheBaseURL().appendingPathComponent("pending_markups_d\(drawingId)_f\(drawingFileId).json")
    }

    private func loadPending(drawingId: Int, drawingFileId: Int) -> [PendingMarkup] {
        let url = pendingFileURL(drawingId: drawingId, drawingFileId: drawingFileId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingMarkup].self, from: data)) ?? []
    }

    private func savePending(_ items: [PendingMarkup], drawingId: Int, drawingFileId: Int) {
        let url = pendingFileURL(drawingId: drawingId, drawingFileId: drawingFileId)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url) }
    }

    func enqueue(body: CreateMarkupRequest) {
        var items = loadPending(drawingId: body.drawingId, drawingFileId: body.drawingFileId)
        let item = PendingMarkup(id: UUID().uuidString, drawingId: body.drawingId, drawingFileId: body.drawingFileId, body: body, createdAt: Date())
        items.append(item)
        savePending(items, drawingId: body.drawingId, drawingFileId: body.drawingFileId)
    }

    func syncPendingMarkups(drawingId: Int, drawingFileId: Int, token: String, onEachSuccess: ((Markup) -> Void)? = nil) async {
        let items = loadPending(drawingId: drawingId, drawingFileId: drawingFileId)
        guard !items.isEmpty else { return }
        var remaining: [PendingMarkup] = []
        for item in items {
            do {
                let created = try await APIClient.createMarkup(token: token, body: item.body)
                onEachSuccess?(created)
            } catch {
                remaining.append(item)
            }
        }
        savePending(remaining, drawingId: drawingId, drawingFileId: drawingFileId)
    }
}


