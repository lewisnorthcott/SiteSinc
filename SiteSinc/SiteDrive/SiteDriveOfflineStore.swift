import Foundation

// MARK: - Pin state

struct SiteDrivePinnedFile: Codable {
    let itemId: Int
    var revisionId: Int
    var cacheFileName: String
}

/// What the user chose to keep offline for one drive (scope + project), plus a
/// manifest of every file currently held on disk on their behalf. The manifest
/// lets reconciliation replace superseded revisions and delete files that are
/// no longer pinned without touching unrelated preview caches.
struct SiteDrivePinState: Codable {
    var folderIds: Set<Int> = []
    var itemIds: Set<Int> = []
    var files: [Int: SiteDrivePinnedFile] = [:]

    var isEmpty: Bool { folderIds.isEmpty && itemIds.isEmpty && files.isEmpty }
}

/// Publishes background offline-sync progress so any SiteDrive screen can show
/// a small status banner.
@MainActor
final class SiteDriveOfflineActivity: ObservableObject {
    static let shared = SiteDriveOfflineActivity()
    @Published var statusText: String?
    fileprivate var isReconciling = false
    private init() {}
}

// MARK: - Store

/// Offline support for SiteDrive, following the OneDrive model:
/// - metadata (capabilities, folder tree, item lists) is cached so the browser
///   works offline,
/// - file content is only downloaded when explicitly pinned ("Make Available
///   Offline") per file or per folder — never in bulk.
enum SiteDriveOfflineStore {

    // MARK: JSON helpers (MetadataCache-backed)

    private static func fileName(_ kind: String, scope: SiteDriveScope, projectId: Int, folderId: Int? = nil) -> String {
        var name = "sitedrive_\(kind)_\(scope.rawValue.lowercased())_\(projectId)"
        if kind == "items" {
            name += folderId.map { "_folder_\($0)" } ?? "_root"
        }
        return name + ".json"
    }

    private static func save<T: Encodable>(_ value: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? MetadataCache.write(data, to: file)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = MetadataCache.read(file) else { return nil }
        return try? APIClient.makeDecoder().decode(T.self, from: data)
    }

    // MARK: Metadata cache (offline browsing)

    static func saveCapabilities(_ caps: SiteDriveCapabilities, scope: SiteDriveScope, projectId: Int) {
        save(caps, to: fileName("caps", scope: scope, projectId: projectId))
    }

    static func loadCapabilities(scope: SiteDriveScope, projectId: Int) -> SiteDriveCapabilities? {
        load(SiteDriveCapabilities.self, from: fileName("caps", scope: scope, projectId: projectId))
    }

    static func saveFolders(_ folders: [SiteDriveFolder], scope: SiteDriveScope, projectId: Int) {
        save(folders, to: fileName("folders", scope: scope, projectId: projectId))
    }

    static func loadFolders(scope: SiteDriveScope, projectId: Int) -> [SiteDriveFolder]? {
        load([SiteDriveFolder].self, from: fileName("folders", scope: scope, projectId: projectId))
    }

    static func saveItems(_ page: SiteDriveItemsPage, scope: SiteDriveScope, projectId: Int, folderId: Int?) {
        save(page, to: fileName("items", scope: scope, projectId: projectId, folderId: folderId))
    }

    static func loadItems(scope: SiteDriveScope, projectId: Int, folderId: Int?) -> SiteDriveItemsPage? {
        load(SiteDriveItemsPage.self, from: fileName("items", scope: scope, projectId: projectId, folderId: folderId))
    }

    // MARK: Pin state persistence

    static func loadPinState(scope: SiteDriveScope, projectId: Int) -> SiteDrivePinState {
        load(SiteDrivePinState.self, from: fileName("pins", scope: scope, projectId: projectId)) ?? SiteDrivePinState()
    }

    static func savePinState(_ state: SiteDrivePinState, scope: SiteDriveScope, projectId: Int) {
        save(state, to: fileName("pins", scope: scope, projectId: projectId))
    }

    // MARK: Downloads

    /// Downloads one revision into the cache (no-op when already cached).
    @discardableResult
    static func downloadFile(
        itemId: Int,
        revisionId: Int,
        itemName: String,
        scope: SiteDriveScope,
        projectId: Int,
        token: String
    ) async throws -> URL {
        if let cached = SiteDriveFileCache.cachedURL(scope: scope, projectId: projectId, itemName: itemName, revisionId: revisionId) {
            return cached
        }
        let urlString = try await APIClient.fetchSiteDriveDownloadUrl(itemId: itemId, revisionId: revisionId, token: token)
        guard let url = URL(string: urlString) else {
            throw APIError.badRequest(message: "Invalid download URL.")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }
        return try SiteDriveFileCache.store(data, scope: scope, projectId: projectId, itemName: itemName, revisionId: revisionId)
    }

    // MARK: Pinning

    static func pinItem(_ item: SiteDriveItem, scope: SiteDriveScope, projectId: Int, token: String) async throws {
        guard let revision = item.latestRevision else {
            throw APIError.badRequest(message: "This file has no uploaded versions.")
        }
        try await downloadFile(
            itemId: item.id,
            revisionId: revision.id,
            itemName: item.name,
            scope: scope,
            projectId: projectId,
            token: token
        )
        var state = loadPinState(scope: scope, projectId: projectId)
        state.itemIds.insert(item.id)
        state.files[item.id] = SiteDrivePinnedFile(
            itemId: item.id,
            revisionId: revision.id,
            cacheFileName: SiteDriveFileCache.cacheFileName(itemName: item.name, revisionId: revision.id)
        )
        savePinState(state, scope: scope, projectId: projectId)
    }

    static func unpinItem(itemId: Int, scope: SiteDriveScope, projectId: Int) {
        var state = loadPinState(scope: scope, projectId: projectId)
        state.itemIds.remove(itemId)
        savePinState(state, scope: scope, projectId: projectId)
        // File removal happens in reconcile(), which knows whether a pinned
        // folder still covers this item.
    }

    static func unpinFolder(folderId: Int, scope: SiteDriveScope, projectId: Int) {
        var state = loadPinState(scope: scope, projectId: projectId)
        state.folderIds.remove(folderId)
        savePinState(state, scope: scope, projectId: projectId)
    }

    /// Fetches every item in a folder's subtree (all pages). Used to show the
    /// total size before pinning and as the download worklist.
    static func collectFolderItems(
        _ folder: SiteDriveFolder,
        scope: SiteDriveScope,
        projectId: Int,
        token: String
    ) async throws -> [SiteDriveItem] {
        var result: [SiteDriveItem] = []
        var stack: [SiteDriveFolder] = [folder]
        while let current = stack.popLast() {
            stack.append(contentsOf: current.subfolders ?? [])
            var offset = 0
            while true {
                let page = try await APIClient.fetchSiteDriveItems(
                    scope: scope,
                    projectId: projectId,
                    folderId: current.id,
                    offset: offset,
                    limit: 200,
                    token: token
                )
                result.append(contentsOf: page.items)
                offset += page.items.count
                if page.items.isEmpty || offset >= page.total { break }
            }
        }
        return result
    }

    /// Pins a folder and downloads its (pre-collected) items sequentially.
    static func pinFolder(
        _ folder: SiteDriveFolder,
        items: [SiteDriveItem],
        scope: SiteDriveScope,
        projectId: Int,
        token: String
    ) async -> (downloaded: Int, failed: Int) {
        var state = loadPinState(scope: scope, projectId: projectId)
        state.folderIds.insert(folder.id)
        savePinState(state, scope: scope, projectId: projectId)

        var downloaded = 0
        var failed = 0
        for (index, item) in items.enumerated() {
            guard let revision = item.latestRevision else { continue }
            await MainActor.run {
                SiteDriveOfflineActivity.shared.statusText = "Downloading \(index + 1) of \(items.count)…"
            }
            do {
                try await downloadFile(
                    itemId: item.id,
                    revisionId: revision.id,
                    itemName: item.name,
                    scope: scope,
                    projectId: projectId,
                    token: token
                )
                state.files[item.id] = SiteDrivePinnedFile(
                    itemId: item.id,
                    revisionId: revision.id,
                    cacheFileName: SiteDriveFileCache.cacheFileName(itemName: item.name, revisionId: revision.id)
                )
                downloaded += 1
            } catch {
                failed += 1
                print("SiteDrive offline: failed to download \(item.name): \(error)")
            }
        }
        savePinState(state, scope: scope, projectId: projectId)
        await MainActor.run { SiteDriveOfflineActivity.shared.statusText = nil }
        return (downloaded, failed)
    }

    // MARK: Reconcile

    /// Brings pinned content up to date: downloads new revisions of pinned
    /// files, drops pins for deleted server content, and removes files that are
    /// no longer covered by any pin. Runs in the background; safe to call on
    /// every online visit (skips when another run is active or nothing is
    /// pinned).
    static func reconcile(scope: SiteDriveScope, projectId: Int, token: String) async {
        var state = loadPinState(scope: scope, projectId: projectId)
        guard !state.isEmpty else { return }

        let alreadyRunning = await MainActor.run { () -> Bool in
            if SiteDriveOfflineActivity.shared.isReconciling { return true }
            SiteDriveOfflineActivity.shared.isReconciling = true
            return false
        }
        if alreadyRunning { return }
        defer {
            Task { @MainActor in
                SiteDriveOfflineActivity.shared.isReconciling = false
                SiteDriveOfflineActivity.shared.statusText = nil
            }
        }

        // Expected offline set: explicitly pinned items + everything inside pinned folders.
        var expected: [Int: (revisionId: Int, name: String)] = [:]

        do {
            let tree = try await APIClient.fetchSiteDriveFolders(scope: scope, projectId: projectId, token: token)

            for folderId in state.folderIds {
                guard let folder = SiteDriveFolder.find(id: folderId, in: tree) else {
                    state.folderIds.remove(folderId) // deleted on the server
                    continue
                }
                let items = try await collectFolderItems(folder, scope: scope, projectId: projectId, token: token)
                for item in items {
                    if let revision = item.latestRevision {
                        expected[item.id] = (revision.id, item.name)
                    }
                }
            }

            for itemId in state.itemIds {
                if expected[itemId] != nil { continue }
                do {
                    let detail = try await APIClient.fetchSiteDriveItem(itemId: itemId, token: token)
                    let revision = (detail.revisions ?? []).max { $0.versionNumber < $1.versionNumber } ?? detail.latestRevision
                    if let revision {
                        expected[itemId] = (revision.id, detail.name)
                    }
                } catch APIError.invalidResponse(let code) where code == 404 {
                    state.itemIds.remove(itemId) // deleted on the server
                } catch {
                    // Transient failure: keep the pin and the current copy.
                    if let existing = state.files[itemId] {
                        expected[itemId] = (revisionId: existing.revisionId, name: itemNameFromCacheFileName(existing.cacheFileName))
                    }
                }
            }
        } catch {
            print("SiteDrive offline: reconcile aborted (network): \(error)")
            return
        }

        let cacheDir = SiteDriveFileCache.directory(scope: scope, projectId: projectId)

        // Download new/changed revisions.
        let toUpdate = expected.filter { itemId, exp in
            guard let existing = state.files[itemId] else { return true }
            if existing.revisionId != exp.revisionId { return true }
            return SiteDriveFileCache.cachedURL(scope: scope, projectId: projectId, itemName: exp.name, revisionId: exp.revisionId) == nil
        }
        var updatedCount = 0
        for (itemId, exp) in toUpdate {
            updatedCount += 1
            await MainActor.run {
                SiteDriveOfflineActivity.shared.statusText = "Updating offline files (\(updatedCount) of \(toUpdate.count))…"
            }
            do {
                try await downloadFile(
                    itemId: itemId,
                    revisionId: exp.revisionId,
                    itemName: exp.name,
                    scope: scope,
                    projectId: projectId,
                    token: token
                )
                if let old = state.files[itemId] {
                    let newName = SiteDriveFileCache.cacheFileName(itemName: exp.name, revisionId: exp.revisionId)
                    if old.cacheFileName != newName {
                        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(old.cacheFileName))
                    }
                }
                state.files[itemId] = SiteDrivePinnedFile(
                    itemId: itemId,
                    revisionId: exp.revisionId,
                    cacheFileName: SiteDriveFileCache.cacheFileName(itemName: exp.name, revisionId: exp.revisionId)
                )
            } catch {
                print("SiteDrive offline: failed to update item \(itemId): \(error)")
            }
        }

        // Remove files no longer covered by any pin.
        for (itemId, record) in state.files where expected[itemId] == nil {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(record.cacheFileName))
            state.files.removeValue(forKey: itemId)
        }

        savePinState(state, scope: scope, projectId: projectId)
    }

    private static func itemNameFromCacheFileName(_ cacheFileName: String) -> String {
        // Cache names are "{revisionId}_{itemName}".
        guard let underscore = cacheFileName.firstIndex(of: "_") else { return cacheFileName }
        return String(cacheFileName[cacheFileName.index(after: underscore)...])
    }
}
