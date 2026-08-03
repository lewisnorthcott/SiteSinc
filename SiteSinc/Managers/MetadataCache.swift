import Foundation

/// Single home for offline metadata JSON (cached project lists, drawings,
/// forms, RFIs, users, …).
///
/// Everything lives in Application Support/SiteSincCache. Older builds wrote
/// some of these files to Caches/, which iOS may purge under storage pressure
/// and which caused writer/reader/cleaner directory mismatches. Reads fall
/// back to the legacy Caches location so data written by older versions is
/// still found; removal clears both locations.
enum MetadataCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SiteSincCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    static func url(_ fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    private static func legacyURL(_ fileName: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)
    }

    static func write(_ data: Data, to fileName: String) throws {
        try data.write(to: url(fileName), options: .atomic)
    }

    static func read(_ fileName: String) -> Data? {
        if let data = try? Data(contentsOf: url(fileName)) { return data }
        return try? Data(contentsOf: legacyURL(fileName))
    }

    /// Removes the file from both the canonical and legacy locations.
    static func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(fileName))
        try? FileManager.default.removeItem(at: legacyURL(fileName))
    }
}
