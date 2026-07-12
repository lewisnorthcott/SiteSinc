import Foundation

// MARK: - Constants

enum ToolboxTalkHighRiskActivity: String, CaseIterable, Identifiable {
    case workingAtHeight = "WORKING_AT_HEIGHT"
    case confinedSpace = "CONFINED_SPACE"
    case hotWorks = "HOT_WORKS"
    case excavation = "EXCAVATION"
    case liftingOperations = "LIFTING_OPERATIONS"
    case manualHandling = "MANUAL_HANDLING"
    case electrical = "ELECTRICAL"
    case demolition = "DEMOLITION"
    case asbestos = "ASBESTOS"
    case plantMovement = "PLANT_MOVEMENT"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workingAtHeight: return "Working at height"
        case .confinedSpace: return "Confined space"
        case .hotWorks: return "Hot works"
        case .excavation: return "Excavation"
        case .liftingOperations: return "Lifting operations"
        case .manualHandling: return "Manual handling"
        case .electrical: return "Electrical"
        case .demolition: return "Demolition"
        case .asbestos: return "Asbestos"
        case .plantMovement: return "Plant movement"
        case .other: return "Other"
        }
    }
}

enum ToolboxTalkWebURLs {
    static let frontendOrigin = "https://www.sitesinc.co.uk"

    static func publicSignURL(token: String) -> String {
        "\(frontendOrigin)/public/toolbox-talks/sign/\(token)"
    }
}

// MARK: - Content

struct ToolboxTalkTopic: Codable, Identifiable, Hashable {
    var title: String
    var body: String?

    var id: String { "\(title)-\(body ?? "")" }
}

struct ToolboxTalkContent: Codable, Hashable {
    var topics: [ToolboxTalkTopic]?
    var highRiskActivities: [String]?
    var ppe: [String]?
    var handoutFileKeys: [String]?
    var declarationText: String?

    static let empty = ToolboxTalkContent(
        topics: [],
        highRiskActivities: [],
        ppe: [],
        handoutFileKeys: [],
        declarationText: "I confirm that I have attended this toolbox talk, understood the hazards and controls discussed, and will work in accordance with them."
    )
}

// MARK: - Nested helpers

struct ToolboxTalkUserRef: Codable, Identifiable, Hashable {
    let id: Int
    let email: String?
    let firstName: String?
    let lastName: String?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        return email ?? "User #\(id)"
    }
}

struct ToolboxTalkCompanyRef: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
}

struct ToolboxTalkTemplateRef: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let reference: String?
}

struct ToolboxTalkSessionCounts: Codable, Hashable {
    let attendees: Int?
    let signatures: Int?
    let attachments: Int?
}

struct ToolboxTalkTalkCounts: Codable, Hashable {
    let sessions: Int?
}

// MARK: - Revision

struct ToolboxTalkRevision: Codable, Identifiable, Hashable {
    let id: Int
    let versionNumber: Int?
    let status: String?
    let publishedAt: String?
    let createdAt: String?
    let content: ToolboxTalkContent?
    let createdBy: ToolboxTalkUserRef?
}

// MARK: - RAMS link

struct ToolboxTalkRamsRef: Codable, Identifiable, Hashable {
    let id: Int
    let reference: String?
    let title: String?
    let status: String?
    let currentRevisionId: Int?
}

struct ToolboxTalkRamsLink: Codable, Hashable {
    let id: Int?
    let projectToolboxTalkId: Int?
    let projectRamsId: Int?
    let projectRams: ToolboxTalkRamsRef?

    var stableId: Int { id ?? projectRamsId ?? 0 }
}

// MARK: - Session list item (embedded on talk)

struct ToolboxTalkSessionSummary: Codable, Identifiable, Hashable {
    let id: Int
    let scheduledFor: String?
    let status: String?
    let location: String?
    let deliveredAt: String?
    let completedAt: String?
    let presenter: ToolboxTalkUserRef?
    let _count: ToolboxTalkSessionCounts?
}

// MARK: - Project toolbox talk

struct ProjectToolboxTalk: Codable, Identifiable, Hashable {
    let id: Int
    let tenantId: Int?
    let projectId: Int?
    let reference: String
    let title: String
    let status: String?
    let owningCompanyId: Int?
    let sourceTemplateId: Int?
    let currentRevisionId: Int?
    let createdAt: String?
    let archivedAt: String?
    let owningCompany: ToolboxTalkCompanyRef?
    let sourceTemplate: ToolboxTalkTemplateRef?
    let createdBy: ToolboxTalkUserRef?
    let currentRevision: ToolboxTalkRevision?
    let revisions: [ToolboxTalkRevision]?
    let sessions: [ToolboxTalkSessionSummary]?
    let ramsLinks: [ToolboxTalkRamsLink]?
    let _count: ToolboxTalkTalkCounts?
}

// MARK: - Session detail

struct ToolboxTalkSignature: Codable, Identifiable, Hashable {
    let id: Int
    let signatureFileKey: String?
    let signatureUrl: String?
    let declarationText: String?
    let signMode: String?
    let signedAt: String?
    let fullName: String?
    let company: String?
    let userId: Int?
    let user: ToolboxTalkUserRef?
}

struct ToolboxTalkAttendee: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let externalName: String?
    let externalCompany: String?
    let status: String?
    let latestSignatureId: Int?
    let user: ToolboxTalkUserRef?
    let latestSignature: ToolboxTalkSignature?

    var displayName: String {
        if let user = user { return user.displayName }
        if let externalName, !externalName.isEmpty { return externalName }
        return "Attendee #\(id)"
    }

    var hasSigned: Bool {
        latestSignatureId != nil || latestSignature != nil
    }
}

struct ToolboxTalkAttachment: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String?
    let fileKey: String
    let fileName: String?
    let fileSize: Int?
    let mimeType: String?
    let fileUrl: String?
    let createdAt: String?
}

struct ToolboxTalkSession: Codable, Identifiable, Hashable {
    let id: Int
    let projectId: Int?
    let projectToolboxTalkId: Int?
    let revisionId: Int?
    let scheduledFor: String?
    let deliveredAt: String?
    let completedAt: String?
    let presenterUserId: Int?
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
    let notes: String?
    let status: String?
    let topicsDiscussed: [ToolboxTalkTopic]?
    let highRiskActivities: [String]?
    let presenter: ToolboxTalkUserRef?
    let attendees: [ToolboxTalkAttendee]?
    let signatures: [ToolboxTalkSignature]?
    let attachments: [ToolboxTalkAttachment]?
    let revision: ToolboxTalkRevision?
    let _count: ToolboxTalkSessionCounts?
}

// MARK: - Templates & topics

struct ToolboxTalkTemplateRevision: Codable, Identifiable, Hashable {
    let id: Int
    let versionNumber: Int?
    let status: String?
    let content: ToolboxTalkContent?
    let publishedAt: String?
}

struct ToolboxTalkTemplate: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let reference: String?
    let description: String?
    let isArchived: Bool?
    let currentRevision: ToolboxTalkTemplateRevision?
    let createdAt: String?
}

struct ToolboxTalkTopicLibraryItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let body: String?
    let category: String?
    let defaultHighRiskActivities: [String]?
}

// MARK: - API responses / requests

struct ToolboxTalkShareTokenResponse: Codable {
    let token: String
}

struct ToolboxTalkDossierResponse: Codable {
    let fileKey: String?
    let presignedUrl: String?
}

struct ToolboxTalkFileUploadResponse: Codable {
    struct FileUploadResult: Codable {
        let fileKey: String?
        let fileUrl: String?
    }
    let files: [FileUploadResult]?
    let fileUrl: String?
    let fileKey: String?
}

struct CreateToolboxTalkRequest: Encodable {
    let reference: String
    let title: String
    let owningCompanyId: Int
    let content: ToolboxTalkContent?
    let sourceTemplateId: Int?
    let source: String?
}

struct CreateToolboxTalkFromTemplateRequest: Encodable {
    let templateId: Int
    let reference: String
    let title: String
    let owningCompanyId: Int
    let contentOverrides: ToolboxTalkContent?
}

struct CreateToolboxTalkRevisionRequest: Encodable {
    let content: ToolboxTalkContent
}

struct LinkRamsRequest: Encodable {
    let projectRamsId: Int
}

struct ScheduleToolboxTalkSessionRequest: Encodable {
    let scheduledFor: String?
    let location: String?
    let presenterUserId: Int?
    let attendeeUserIds: [Int]?
}

struct UpdateToolboxTalkSessionRequest: Encodable {
    let notes: String?
    let scheduledFor: String?
    let location: String?
    let topicsDiscussed: [ToolboxTalkTopic]?
    let highRiskActivities: [String]?
}

struct StartToolboxTalkSessionRequest: Encodable {
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
    let location: String?
}

struct SignToolboxTalkSessionRequest: Encodable {
    let signatureFileKey: String
    let declarationText: String?
    let signMode: String
    let fullName: String?
    let company: String?
    let userId: Int?
    let attendeeId: Int?
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
}

struct AddToolboxTalkAttachmentRequest: Encodable {
    let fileKey: String
    let fileName: String
    let fileSize: Int?
    let mimeType: String?
    let kind: String?
}

struct GenerateAIToolboxTalkContentRequest: Encodable {
    let title: String
    let description: String?
    let reference: String?
    let extraContext: String?
}

struct ShareTokenRequest: Encodable {
    let expiresIn: String?
}

// MARK: - Rollup status (client-side, matches web)

struct ToolboxTalkRollupStatus: Hashable {
    enum Tone {
        case neutral, info, warn, success, muted
    }

    let label: String
    let tone: Tone

    static func from(_ talk: ProjectToolboxTalk) -> ToolboxTalkRollupStatus {
        if talk.status == "ARCHIVED" {
            return ToolboxTalkRollupStatus(label: "Archived", tone: .muted)
        }
        let sessions = talk.sessions ?? []
        if sessions.contains(where: { $0.status == "IN_PROGRESS" }) {
            return ToolboxTalkRollupStatus(label: "In progress", tone: .info)
        }
        if sessions.contains(where: { $0.status == "SCHEDULED" }) {
            return ToolboxTalkRollupStatus(label: "Scheduled", tone: .warn)
        }
        if !sessions.isEmpty && sessions.allSatisfy({ $0.status == "COMPLETED" || $0.status == "CANCELLED" }) {
            return ToolboxTalkRollupStatus(label: "Completed", tone: .success)
        }
        if talk.status == "DRAFT" {
            return ToolboxTalkRollupStatus(label: "Draft", tone: .muted)
        }
        return ToolboxTalkRollupStatus(label: "No sessions yet", tone: .neutral)
    }
}
