import Foundation
import SwiftUI

class CacheManager {
    static let shared = CacheManager()

    private init() {}

    // MARK: - PDF Drawing Cache

    /// Clears all cached PDF drawing files
    func clearPDFDrawingCache() -> (success: Bool, message: String) {
        let fileManager = FileManager.default

        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (false, "Could not access documents directory")
        }

        var deletedFilesCount = 0
        var totalSizeCleared: Int64 = 0

        do {
            // Get all project directories
            let projectDirectories = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

            for projectDir in projectDirectories {
                if projectDir.lastPathComponent.hasPrefix("Project_") {
                    let projectDrawingsDir = projectDir.appendingPathComponent("drawings")

                    if fileManager.fileExists(atPath: projectDrawingsDir.path) {
                        let drawingFiles = try fileManager.contentsOfDirectory(at: projectDrawingsDir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)

                        for drawingFile in drawingFiles {
                            if drawingFile.pathExtension.lowercased() == "pdf" {
                                let fileSize = try drawingFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                try fileManager.removeItem(at: drawingFile)
                                deletedFilesCount += 1
                                totalSizeCleared += Int64(fileSize)
                            }
                        }
                    }
                }
            }

            let sizeString = formatFileSize(totalSizeCleared)
            return (true, "Cleared \(deletedFilesCount) PDF files (\(sizeString))")

        } catch {
            return (false, "Failed to clear PDF cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Drawings List Cache

    /// Clears cached drawings lists for all projects
    func clearDrawingsListCache() -> (success: Bool, message: String) {
        let fileManager = FileManager.default

        guard let cacheDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SiteSincCache") else {
            return (false, "Could not access cache directory")
        }

        do {
            if !fileManager.fileExists(atPath: cacheDirectory.path) {
                return (true, "No drawings cache found")
            }

            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
            var deletedFilesCount = 0
            var totalSizeCleared: Int64 = 0

            for cacheFile in cacheFiles {
                if cacheFile.lastPathComponent.hasPrefix("drawings_project_") && cacheFile.pathExtension == "json" {
                    let fileSize = try cacheFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try fileManager.removeItem(at: cacheFile)
                    deletedFilesCount += 1
                    totalSizeCleared += Int64(fileSize)
                }
            }

            if deletedFilesCount > 0 {
                let sizeString = formatFileSize(totalSizeCleared)
                return (true, "Cleared \(deletedFilesCount) drawings cache files (\(sizeString))")
            } else {
                return (true, "No drawings cache files found")
            }

        } catch {
            return (false, "Failed to clear drawings cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Markup Cache

    /// Clears cached markup data for all drawings
    func clearMarkupCache() -> (success: Bool, message: String) {
        let fileManager = FileManager.default

        guard let cacheDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SiteSincCache") else {
            return (false, "Could not access cache directory")
        }

        do {
            if !fileManager.fileExists(atPath: cacheDirectory.path) {
                return (true, "No markup cache found")
            }

            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
            var deletedFilesCount = 0
            var totalSizeCleared: Int64 = 0

            for cacheFile in cacheFiles {
                // Clear markup cache files (markups_d*_f*.json and references_d*_f*.json)
                if (cacheFile.lastPathComponent.hasPrefix("markups_d") || cacheFile.lastPathComponent.hasPrefix("references_d")) &&
                   cacheFile.pathExtension == "json" {
                    let fileSize = try cacheFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try fileManager.removeItem(at: cacheFile)
                    deletedFilesCount += 1
                    totalSizeCleared += Int64(fileSize)
                }
            }

            if deletedFilesCount > 0 {
                let sizeString = formatFileSize(totalSizeCleared)
                return (true, "Cleared \(deletedFilesCount) markup cache files (\(sizeString))")
            } else {
                return (true, "No markup cache files found")
            }

        } catch {
            return (false, "Failed to clear markup cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Combined Cache Clearing

    /// Clears all application caches
    func clearAllCaches() -> (success: Bool, message: String) {
        var results: [String] = []
        var overallSuccess = true

        // Clear PDF drawing cache
        let pdfResult = clearPDFDrawingCache()
        results.append("PDF Drawings: \(pdfResult.message)")
        if !pdfResult.success {
            overallSuccess = false
        }

        // Clear drawings list cache
        let drawingsResult = clearDrawingsListCache()
        results.append("Drawings List: \(drawingsResult.message)")
        if !drawingsResult.success {
            overallSuccess = false
        }

        // Clear markup cache
        let markupResult = clearMarkupCache()
        results.append("Markups: \(markupResult.message)")
        if !markupResult.success {
            overallSuccess = false
        }

        let combinedMessage = results.joined(separator: "\n")
        return (overallSuccess, combinedMessage)
    }

    // MARK: - Cache Size Calculation

    /// Calculates the total size of all caches
    func getCacheSize() -> (size: Int64, formatted: String) {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        // PDF drawing cache size
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let projectDirectories = (try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []

            for projectDir in projectDirectories {
                if projectDir.lastPathComponent.hasPrefix("Project_") {
                    let projectDrawingsDir = projectDir.appendingPathComponent("drawings")
                    totalSize += calculateDirectorySize(at: projectDrawingsDir)
                }
            }
        }

        // Drawings list cache size
        if let cacheDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SiteSincCache") {
            totalSize += calculateDirectorySize(at: cacheDirectory)
        }

        return (totalSize, formatFileSize(totalSize))
    }

    // MARK: - Helper Methods

    private func calculateDirectorySize(at directory: URL) -> Int64 {
        let fileManager = FileManager.default
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
                // Skip files we can't get size for
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
