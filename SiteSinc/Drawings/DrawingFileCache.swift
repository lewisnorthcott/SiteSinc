import Foundation

/// Central helper for locating drawing PDFs cached for offline use.
///
/// Cached files are keyed by the drawing file's unique server id as well as
/// its name ("{id}_{fileName}") so a re-issued revision that reuses the same
/// fileName can never be confused with a previously cached (superseded) copy.
///
/// Older app versions cached files under the bare fileName. Those legacy
/// copies may hold a superseded revision, so they are only trusted when the
/// caller has no way to fetch a fresh copy (i.e. offline).
enum DrawingFileCache {
    static func directory(projectId: Int) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("Project_\(projectId)/drawings", isDirectory: true)
    }

    static func cacheFileName(for file: DrawingFile) -> String {
        "\(file.id)_\(file.fileName)"
    }

    /// Canonical (revision-safe) location for a drawing file.
    static func url(projectId: Int, file: DrawingFile) -> URL {
        directory(projectId: projectId).appendingPathComponent(cacheFileName(for: file))
    }

    /// Legacy location used by older app versions (fileName only).
    static func legacyURL(projectId: Int, file: DrawingFile) -> URL {
        directory(projectId: projectId).appendingPathComponent(file.fileName)
    }

    /// Returns a locally cached copy of the file, or nil.
    ///
    /// The revision-keyed copy is always trusted. A legacy filename-keyed copy
    /// is only returned when `allowLegacy` is true — pass true only when a
    /// fresh copy cannot be downloaded (offline), because the legacy copy may
    /// contain a superseded revision.
    static func cachedURL(projectId: Int, file: DrawingFile, allowLegacy: Bool) -> URL? {
        let canonical = url(projectId: projectId, file: file)
        if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
        if allowLegacy {
            let legacy = legacyURL(projectId: projectId, file: file)
            if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        }
        return nil
    }

    /// Whether any local copy (canonical or legacy) exists for the file.
    static func isCached(projectId: Int, file: DrawingFile) -> Bool {
        cachedURL(projectId: projectId, file: file, allowLegacy: true) != nil
    }

    /// Deletes files in the project's drawings cache whose names are not in
    /// `expected` — superseded revisions and legacy filename-keyed copies.
    /// Call after a successful full sync so stale content cannot linger.
    static func removeOrphans(projectId: Int, keeping expected: Set<String>) {
        let dir = directory(projectId: projectId)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in contents where !expected.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            print("DrawingFileCache: Removed stale cached drawing file: \(name)")
        }
    }
}
