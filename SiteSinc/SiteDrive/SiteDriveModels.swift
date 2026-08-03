import Foundation

// MARK: - SiteDrive models (/api/sitedrive)
// Mirrors apps/frontend/src/types/siteDrive.ts in the web app.

enum SiteDriveScope: String, Codable, CaseIterable {
    case company = "COMPANY"
    case project = "PROJECT"
}

struct SiteDriveCapabilities: Codable {
    let canView: Bool
    let canWrite: Bool
    let canManageFolders: Bool
    let canDelete: Bool
    let isMainCompany: Bool
    let isCompanyReadOnly: Bool
    let canManageSync: Bool?
}

struct SiteDriveUserRef: Codable, Hashable {
    let id: Int
    let email: String
}

struct SiteDriveFolder: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let parentId: Int?
    let isPrivate: Bool
    let updatedAt: Date?
    let subfolders: [SiteDriveFolder]?

    /// Depth-first search for a folder anywhere in a tree.
    static func find(id: Int, in folders: [SiteDriveFolder]) -> SiteDriveFolder? {
        for folder in folders {
            if folder.id == id { return folder }
            if let match = find(id: id, in: folder.subfolders ?? []) { return match }
        }
        return nil
    }

    /// True when `folderId` is this folder or any descendant (used to prevent
    /// moving a folder into itself).
    func containsInSubtree(_ folderId: Int) -> Bool {
        if id == folderId { return true }
        return (subfolders ?? []).contains { $0.containsInSubtree(folderId) }
    }
}

struct SiteDriveRevision: Codable, Identifiable, Hashable {
    let id: Int
    let versionNumber: Int
    let fileUrl: String
    let mimeType: String?
    let sizeBytes: Int?
    let notes: String?
    let createdAt: Date
    let downloadUrl: String?
    let uploadedBy: SiteDriveUserRef?
}

struct SiteDriveItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let folderId: Int?
    let scope: SiteDriveScope
    let projectId: Int?
    let createdAt: Date
    let updatedAt: Date
    let externalWebUrl: String?
    let latestRevision: SiteDriveRevision?
    let revisions: [SiteDriveRevision]?
    let uploadedBy: SiteDriveUserRef?
}

struct SiteDriveItemsPage: Codable {
    let items: [SiteDriveItem]
    let total: Int
}

struct SiteDriveUploadResponse: Decodable {
    let item: SiteDriveItem
    let revision: SiteDriveRevision?
    let isNewItem: Bool?
    let downloadUrl: String?
}

struct SiteDriveDownloadUrlResponse: Decodable {
    let downloadUrl: String
}

struct SiteDriveOnlineUrlResponse: Decodable {
    let webUrl: String?
}

// MARK: - Display helpers

extension SiteDriveItem {
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var isPdf: Bool {
        fileExtension == "pdf" || latestRevision?.mimeType == "application/pdf"
    }

    var isImage: Bool {
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff"].contains(fileExtension) { return true }
        return latestRevision?.mimeType?.hasPrefix("image/") == true
    }

    var isOfficeFile: Bool {
        ["doc", "docx", "xls", "xlsx", "xlsm", "ppt", "pptx"].contains(fileExtension)
    }

    /// SF Symbol name for the file type.
    var iconName: String {
        switch fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff": return "photo.fill"
        case "mp4", "mov", "avi", "m4v": return "film.fill"
        case "mp3", "wav", "m4a": return "waveform"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "xlsm", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.on.rectangle.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "dwg", "dxf": return "compass.drawing"
        default: return "doc.fill"
        }
    }

    var iconColor: String {
        switch fileExtension {
        case "pdf": return "#EF4444"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff": return "#8B5CF6"
        case "doc", "docx": return "#2563EB"
        case "xls", "xlsx", "xlsm", "csv": return "#16A34A"
        case "ppt", "pptx": return "#EA580C"
        default: return "#64748B"
        }
    }
}

extension SiteDriveRevision {
    var formattedSize: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
