import Foundation

// MARK: - Markup Models (shared with backend)

public enum MarkupType: String, Codable {
    case TEXT_NOTE
    case HIGHLIGHT
    case RECTANGLE
    case CIRCLE
    case ARROW
    case LINE
    case CLOUD
}

public struct MarkupBounds: Codable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var page: Int
}

public struct MarkupUser: Codable {
    public let id: Int?
    public let email: String?
    public let tenants: [TenantName]?

    public struct TenantName: Codable {
        public let firstName: String?
        public let lastName: String?
    }
}

public struct Markup: Codable, Identifiable {
    public let id: Int
    public let drawingId: Int
    public let drawingFileId: Int
    public let page: Int
    public let markupType: MarkupType
    public let bounds: MarkupBounds
    public let content: String?
    public let color: String
    public let opacity: Double
    public let strokeWidth: Double
    public let title: String?
    public let description: String?
    public let status: String?
    public let groupId: Int?
    public let groupTitle: String?
    public let createdAt: String?
    public let createdBy: MarkupUser?
}

public struct CreateMarkupRequest: Codable {
    public let drawingId: Int
    public let drawingFileId: Int
    public let page: Int
    public let markupType: MarkupType
    public let bounds: MarkupBounds
    public let content: String?
    public let color: String
    public let opacity: Double
    public let strokeWidth: Double
    public let title: String?
    public let description: String?
}

// MARK: - Drawing References (used by PdfViewer.tsx on web)
public struct DrawingReference: Codable, Identifiable {
    public let id: Int
    public let sourceDrawingId: Int
    public let sourceFileId: Int
    public let referencedDrawingNumber: String
    public let referencedDrawingId: Int?
    public let linkUrl: String?
    public let bounds: MarkupBounds?
    public let page: Int?
}


