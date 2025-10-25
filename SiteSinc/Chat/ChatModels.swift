import Foundation

// MARK: - Chat Conversation Model
struct ChatConversation: Codable, Identifiable {
    let id: Int
    let projectId: Int
    let userId: Int
    let tenantId: Int
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let archived: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, projectId, userId, tenantId, title, archived
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Codable, Identifiable {
    let id: Int
    let conversationId: Int?
    let role: String // "user" or "assistant"
    let content: String
    let metadata: ChatMessageMetadata?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, role, content, metadata
        case createdAt = "createdAt"
    }
}

// MARK: - Chat Message Metadata
struct ChatMessageMetadata: Codable {
    let sources: [SimpleChatSource]?
    let tokenUsage: TokenUsage?
    let analytics: AnalyticsData?
    let error: Bool?
    let errorMessage: String?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case sources, analytics, error, timestamp
        case tokenUsage = "tokenUsage"
        case errorMessage = "errorMessage"
    }
}

// MARK: - Chat Source Model
struct ChatSource: Codable, Identifiable {
    let id: Int
    let sourceType: String
    let sourceId: Int
    let content: String?
    let metadata: ChatSourceMetadata?
    let similarity: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, content, metadata, similarity
        case sourceType = "sourceType"
        case sourceId = "sourceId"
    }
    
    // Computed property to get title from metadata or direct field
    var title: String {
        return metadata?.title ?? "Unknown Source"
    }
    
    // Computed properties for backward compatibility
    var drawingNumber: String? {
        return metadata?.drawingNumber
    }
    
    var documentNumber: String? {
        return metadata?.documentNumber
    }
    
    var rfiNumber: String? {
        return metadata?.rfiNumber
    }
}

// MARK: - Chat Source Metadata
struct ChatSourceMetadata: Codable {
    let title: String
    let fileName: String?
    let sourceId: Int
    let createdAt: String?
    let chunkIndex: Int?
    let sourceType: String
    let drawingNumber: String?
    let documentNumber: String?
    let rfiNumber: String?
    let folder: String?
    let company: String?
    let category: String?
    let discipline: String?
    let totalRevisions: Int?
    let currentRevision: Int?
    
    enum CodingKeys: String, CodingKey {
        case title, fileName, sourceId, createdAt, chunkIndex, sourceType, folder, company, category, discipline
        case drawingNumber = "drawingNumber"
        case documentNumber = "documentNumber"
        case rfiNumber = "rfiNumber"
        case totalRevisions = "totalRevisions"
        case currentRevision = "currentRevision"
    }
}

// MARK: - Simple Chat Source (for metadata sources without content)
struct SimpleChatSource: Codable, Identifiable {
    let id: Int
    let title: String
    let sourceId: Int
    let similarity: Double?
    let sourceType: String
    let drawingNumber: String?
    let documentNumber: String?
    let rfiNumber: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, similarity
        case sourceId = "sourceId"
        case sourceType = "sourceType"
        case drawingNumber = "drawingNumber"
        case documentNumber = "documentNumber"
        case rfiNumber = "rfiNumber"
    }
}

// MARK: - Token Usage Model
struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "promptTokens"
        case completionTokens = "completionTokens"
        case totalTokens = "totalTokens"
    }
}

// MARK: - Analytics Data Model
struct AnalyticsData: Codable {
    let query: AnalyticsQuery?
    let results: [AnalyticsResult]?
    let timestamp: String?
}

// MARK: - Analytics Query Model
struct AnalyticsQuery: Codable {
    let entityType: String?
    let period: String?
    let status: String?
    let projectId: Int?
    let tenantId: Int
}

// MARK: - Analytics Result Model
struct AnalyticsResult: Codable {
    let entityType: String
    let period: String
    let count: Int
    let startDate: Date
    let endDate: Date
    let projectId: Int?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case entityType, period, count, status
        case startDate = "startDate"
        case endDate = "endDate"
        case projectId = "projectId"
    }
}

// MARK: - Send Message Response Model
struct SendMessageResponse: Codable {
    let message: ChatMessage
    let response: ChatMessage
    let sources: [ChatSource]
    let tokenUsage: TokenUsage?
    
    enum CodingKeys: String, CodingKey {
        case message, response, sources
        case tokenUsage = "tokenUsage"
    }
}

// MARK: - Create Conversation Request
struct CreateConversationRequest: Codable {
    let projectId: Int
    let title: String?
}

// MARK: - Send Message Request
struct SendMessageRequest: Codable {
    let message: String
}
