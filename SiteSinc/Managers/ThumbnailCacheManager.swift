import Foundation
import UIKit

class ThumbnailCacheManager {
    static let shared = ThumbnailCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Store thumbnails in Application Support/SiteSincCache/thumbnails
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("SiteSincCache/thumbnails", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    // MARK: - Cache Path
    
    private func cachePath(for fileId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("thumbnail_\(fileId).jpg")
    }
    
    // MARK: - Check Cache
    
    /// Checks if a thumbnail exists in cache
    func hasCachedThumbnail(for fileId: Int) -> Bool {
        let path = cachePath(for: fileId)
        return fileManager.fileExists(atPath: path.path)
    }
    
    // MARK: - Get Cached Thumbnail
    
    /// Retrieves a cached thumbnail image
    func getCachedThumbnail(for fileId: Int) -> UIImage? {
        let path = cachePath(for: fileId)
        guard fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    /// Gets the cached thumbnail URL for use with AsyncImage
    func getCachedThumbnailURL(for fileId: Int) -> URL? {
        let path = cachePath(for: fileId)
        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }
        return path
    }
    
    // MARK: - Save Thumbnail
    
    /// Downloads and caches a thumbnail from a URL
    func cacheThumbnail(from urlString: String, for fileId: Int) async throws {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ThumbnailCacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Download the image
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ThumbnailCacheManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        
        // Verify it's an image
        guard let image = UIImage(data: data),
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ThumbnailCacheManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        
        // Save to cache
        let cachePath = self.cachePath(for: fileId)
        try imageData.write(to: cachePath)
        
        print("✅ Cached thumbnail for fileId: \(fileId)")
    }
    
    // MARK: - Clear Cache
    
    /// Clears all cached thumbnails
    func clearAllThumbnails() -> (success: Bool, message: String) {
        do {
            guard fileManager.fileExists(atPath: cacheDirectory.path) else {
                return (true, "No thumbnail cache found")
            }
            
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
            var deletedCount = 0
            var totalSize: Int64 = 0
            
            for file in files {
                if file.lastPathComponent.hasPrefix("thumbnail_") {
                    let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                    totalSize += Int64(fileSize)
                }
            }
            
            let sizeString = formatFileSize(totalSize)
            return (true, "Cleared \(deletedCount) thumbnails (\(sizeString))")
        } catch {
            return (false, "Failed to clear thumbnail cache: \(error.localizedDescription)")
        }
    }
    
    /// Clears thumbnails older than specified days
    func clearOldThumbnails(olderThanDays days: Int = 30) -> (success: Bool, message: String) {
        do {
            guard fileManager.fileExists(atPath: cacheDirectory.path) else {
                return (true, "No thumbnail cache found")
            }
            
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            var deletedCount = 0
            var totalSize: Int64 = 0
            
            for file in files {
                if file.lastPathComponent.hasPrefix("thumbnail_") {
                    let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    if let modificationDate = resourceValues.contentModificationDate,
                       modificationDate < cutoffDate {
                        let fileSize = resourceValues.fileSize ?? 0
                        try fileManager.removeItem(at: file)
                        deletedCount += 1
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            if deletedCount > 0 {
                let sizeString = formatFileSize(totalSize)
                return (true, "Cleared \(deletedCount) old thumbnails (\(sizeString))")
            } else {
                return (true, "No old thumbnails to clear")
            }
        } catch {
            return (false, "Failed to clear old thumbnails: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cache Size
    
    /// Calculates the total size of thumbnail cache
    func getThumbnailCacheSize() -> (size: Int64, formatted: String) {
        let size = calculateDirectorySize(at: cacheDirectory)
        return (size, formatFileSize(size))
    }
    
    // MARK: - Helper Methods
    
    private func calculateDirectorySize(at directory: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        guard fileManager.fileExists(atPath: directory.path) else {
            return 0
        }
        
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

