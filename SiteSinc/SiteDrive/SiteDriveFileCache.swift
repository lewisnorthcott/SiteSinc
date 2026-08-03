import Foundation

/// Disk cache for downloaded SiteDrive revisions, following DrawingFileCache.
///
/// Files are keyed by revision id ("{revisionId}_{itemName}") so a new
/// revision of the same item can never be confused with a cached older copy.
/// Project drives cache under Project_{id}/sitedrive; the company drive under
/// SiteDriveCompany (revision ids are globally unique server-side).
enum SiteDriveFileCache {
    static func directory(scope: SiteDriveScope, projectId: Int) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        switch scope {
        case .project:
            return documentsDirectory.appendingPathComponent("Project_\(projectId)/sitedrive", isDirectory: true)
        case .company:
            return documentsDirectory.appendingPathComponent("SiteDriveCompany", isDirectory: true)
        }
    }

    static func cacheFileName(itemName: String, revisionId: Int) -> String {
        // Sanitise path separators so item names can't escape the cache dir.
        let safeName = itemName.replacingOccurrences(of: "/", with: "_")
        return "\(revisionId)_\(safeName)"
    }

    static func url(scope: SiteDriveScope, projectId: Int, itemName: String, revisionId: Int) -> URL {
        directory(scope: scope, projectId: projectId)
            .appendingPathComponent(cacheFileName(itemName: itemName, revisionId: revisionId))
    }

    /// Returns the locally cached copy for a revision, or nil.
    static func cachedURL(scope: SiteDriveScope, projectId: Int, itemName: String, revisionId: Int) -> URL? {
        let target = url(scope: scope, projectId: projectId, itemName: itemName, revisionId: revisionId)
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }

    /// Writes downloaded data to the cache and returns the file URL.
    @discardableResult
    static func store(_ data: Data, scope: SiteDriveScope, projectId: Int, itemName: String, revisionId: Int) throws -> URL {
        let dir = directory(scope: scope, projectId: projectId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = url(scope: scope, projectId: projectId, itemName: itemName, revisionId: revisionId)
        try data.write(to: target, options: .atomic)
        return target
    }
}
