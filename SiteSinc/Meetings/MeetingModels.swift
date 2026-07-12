import Foundation

// MARK: - Enums

enum MeetingStatus: String, Codable, Hashable {
    case draft = "DRAFT"
    case final = "FINAL"

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .final: return "Final"
        }
    }
}

enum MeetingActionStatus: String, Codable, Hashable {
    case open = "OPEN"
    case done = "DONE"

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .done: return "Done"
        }
    }
}

enum MeetingMinuteLineSection: String, Codable, Hashable {
    case minutes = "MINUTES"
    case previousActions = "PREVIOUS_ACTIONS"
}

enum MeetingAttendeeRole: String, Codable, Hashable, CaseIterable {
    case chair = "CHAIR"
    case present = "PRESENT"
    case apologies = "APOLOGIES"
    case distribution = "DISTRIBUTION"

    var displayName: String {
        switch self {
        case .chair: return "Chair"
        case .present: return "Present"
        case .apologies: return "Apologies"
        case .distribution: return "Distribution"
        }
    }
}

enum CopyActionsFilter: String, Codable, Hashable {
    case all
    case outstanding
}

// MARK: - User brief (API nests name under tenants)

struct MeetingUserTenant: Codable, Hashable {
    let firstName: String?
    let lastName: String?
}

struct MeetingUserBrief: Codable, Identifiable, Hashable {
    let id: Int
    let email: String?
    let tenants: [MeetingUserTenant]?
    let firstName: String?
    let lastName: String?

    var displayName: String {
        if let first = firstName ?? tenants?.first?.firstName,
           let last = lastName ?? tenants?.first?.lastName {
            let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        if let first = firstName ?? tenants?.first?.firstName, !first.isEmpty {
            return first
        }
        return email ?? "User #\(id)"
    }
}

// MARK: - Core entities

struct MeetingCategory: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sortOrder: Int?
    let active: Bool?
}

struct MeetingAttendee: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let role: MeetingAttendeeRole?
    let user: MeetingUserBrief?
}

struct MeetingAgendaItem: Codable, Identifiable, Hashable {
    let id: Int
    let sortOrder: Int?
    let title: String
    let durationMinutes: Int?
    let presenterUserId: Int?
    let notes: String?
    let presenter: MeetingUserBrief?
}

struct MeetingAgendaAttachment: Codable, Identifiable, Hashable {
    let id: Int
    let fileName: String
    let fileType: String?
    let fileSize: Int?
    let uploadedAt: String?
    let uploadedBy: MeetingUserBrief?
}

struct MeetingMinuteLineAttachment: Codable, Identifiable, Hashable {
    let id: Int
    let commentId: Int?
    let fileName: String
    let fileType: String?
    let fileSize: Int?
    let uploadedAt: String?
    let uploadedBy: MeetingUserBrief?
}

struct MeetingMinuteLineComment: Codable, Identifiable, Hashable {
    let id: Int
    let content: String
    let createdAt: String?
    let user: MeetingUserBrief?
    let attachments: [MeetingMinuteLineAttachment]?
}

struct MeetingMinuteLineAssignee: Codable, Hashable {
    let minuteLineId: Int?
    let userId: Int
    let user: MeetingUserBrief?
}

struct MeetingMinuteLine: Codable, Identifiable, Hashable {
    let id: Int
    let sortOrder: Int?
    let content: String
    let section: MeetingMinuteLineSection?
    let sourceMinuteLineId: Int?
    let sourceMeetingId: Int?
    let agendaItemId: Int?
    let dueDate: String?
    let status: MeetingActionStatus?
    let completedAt: String?
    let completedBy: MeetingUserBrief?
    let createdById: Int?
    let assignees: [MeetingMinuteLineAssignee]?
    let comments: [MeetingMinuteLineComment]?
    let attachments: [MeetingMinuteLineAttachment]?

    var isAction: Bool {
        !(assignees ?? []).isEmpty
    }

    var isOpenAction: Bool {
        isAction && (status ?? .open) == .open
    }

    var assigneeIds: [Int] {
        (assignees ?? []).map(\.userId)
    }
}

struct MeetingReviewSource: Codable, Hashable, Identifiable {
    let id: Int
    let reference: String?
    let title: String?
    let meetingDate: String?
}

struct MeetingCounts: Codable, Hashable {
    let openActions: Int?
    let agendaItems: Int?
}

struct MeetingListItem: Codable, Identifiable, Hashable {
    let id: Int
    let reference: String
    let title: String
    let meetingDate: String
    let nextMeetingDate: String?
    let location: String?
    let status: MeetingStatus
    let isPrivate: Bool?
    let categoryId: Int?
    let category: MeetingCategory?
    let reviewSourceMeetingId: Int?
    let reviewSourceMeeting: MeetingReviewSource?
    let createdAt: String?
    let createdById: Int?
    let createdBy: MeetingUserBrief?
    let attendees: [MeetingAttendee]?
    let _count: MeetingCounts?

    var openActionsCount: Int { _count?.openActions ?? 0 }
    var agendaItemsCount: Int { _count?.agendaItems ?? 0 }
}

struct MeetingDetail: Codable, Identifiable, Hashable {
    let id: Int
    let reference: String
    let title: String
    let meetingDate: String
    let nextMeetingDate: String?
    let location: String?
    let notes: String?
    let status: MeetingStatus
    let isPrivate: Bool?
    let categoryId: Int?
    let category: MeetingCategory?
    let reviewSourceMeetingId: Int?
    let reviewSourceMeeting: MeetingReviewSource?
    let createdAt: String?
    let createdById: Int?
    let createdBy: MeetingUserBrief?
    let attendees: [MeetingAttendee]?
    let agendaItems: [MeetingAgendaItem]?
    let agendaAttachments: [MeetingAgendaAttachment]?
    let minuteLines: [MeetingMinuteLine]?
    let _count: MeetingCounts?

    var isEditable: Bool { status == .draft }

    var previousActionLines: [MeetingMinuteLine] {
        (minuteLines ?? []).filter { ($0.section ?? .minutes) == .previousActions }
    }

    var minuteSectionLines: [MeetingMinuteLine] {
        (minuteLines ?? []).filter { ($0.section ?? .minutes) == .minutes }
    }
}

// MARK: - Request / response envelopes

struct MeetingsListResponse: Codable {
    let meetings: [MeetingListItem]
}

struct MeetingDetailResponse: Codable {
    let meeting: MeetingDetail
}

struct MeetingCategoriesResponse: Codable {
    let categories: [MeetingCategory]
}

struct MeetingCategoryResponse: Codable {
    let category: MeetingCategory
}

struct MeetingCopyableActionsResponse: Codable {
    let meeting: MeetingReviewSource
    let actions: [MeetingMinuteLine]
}

struct MeetingMinuteLineCommentResponse: Codable {
    let comment: MeetingMinuteLineComment
}

struct MeetingMinuteLineResponse: Codable {
    let line: MeetingMinuteLine
}

struct MeetingMinuteLineUpdateResponse: Codable {
    let comment: MeetingMinuteLineComment?
    let attachment: MeetingMinuteLineAttachment?
    let line: MeetingMinuteLine?
}

struct MeetingAttachmentDownloadResponse: Codable {
    let url: String
    let fileName: String
}

struct MeetingAgendaAttachmentResponse: Codable {
    let attachment: MeetingAgendaAttachment
}

struct MeetingAttendeeInput: Codable, Hashable {
    let userId: Int
    let role: MeetingAttendeeRole?
}

struct CreateMeetingRequest: Codable {
    let title: String
    let meetingDate: String
    let nextMeetingDate: String?
    let location: String?
    let notes: String?
    let isPrivate: Bool?
    let categoryId: Int?
    let attendees: [MeetingAttendeeInput]?
    let copyFromMeetingId: Int?
    let copyActionsFilter: CopyActionsFilter?
}

struct UpdateMeetingRequest: Encodable {
    let title: String?
    let meetingDate: String?
    let nextMeetingDate: String?
    let location: String?
    let notes: String?
    let isPrivate: Bool?
    let categoryId: Int?
    let attendees: [MeetingAttendeeInput]?

    enum CodingKeys: String, CodingKey {
        case title, meetingDate, nextMeetingDate, location, notes, isPrivate, categoryId, attendees
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(meetingDate, forKey: .meetingDate)
        // Explicit nulls so the API can clear optional fields
        try container.encode(nextMeetingDate, forKey: .nextMeetingDate)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(attendees, forKey: .attendees)
    }
}

struct AgendaItemInput: Codable, Hashable {
    let title: String
    let sortOrder: Int?
    let durationMinutes: Int?
    let presenterUserId: Int?
    let notes: String?
}

struct ReplaceAgendaItemsRequest: Codable {
    let items: [AgendaItemInput]
}

struct MinuteLineInput: Codable, Hashable {
    var id: Int?
    var content: String
    var sortOrder: Int?
    var agendaItemId: Int?
    var assigneeUserIds: [Int]?
    var dueDate: String?
}

struct ReplaceMinuteLinesRequest: Codable {
    let lines: [MinuteLineInput]
}

struct CopyPreviousActionsRequest: Codable {
    let sourceMeetingId: Int
    let filter: CopyActionsFilter
}

struct CompleteMinuteLineRequest: Codable {
    let comment: String?
}

// MARK: - Draft helpers (local editing)

struct AgendaDraftItem: Identifiable, Hashable {
    let id: UUID
    var serverId: Int?
    var title: String
    var durationMinutes: Int?
    var presenterUserId: Int?
    var notes: String

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        title: String = "",
        durationMinutes: Int? = nil,
        presenterUserId: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.serverId = serverId
        self.title = title
        self.durationMinutes = durationMinutes
        self.presenterUserId = presenterUserId
        self.notes = notes
    }

    static func from(_ item: MeetingAgendaItem) -> AgendaDraftItem {
        AgendaDraftItem(
            serverId: item.id,
            title: item.title,
            durationMinutes: item.durationMinutes,
            presenterUserId: item.presenterUserId,
            notes: item.notes ?? ""
        )
    }

    func toInput(sortOrder: Int) -> AgendaItemInput {
        AgendaItemInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: sortOrder,
            durationMinutes: durationMinutes,
            presenterUserId: presenterUserId,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
    }
}

struct MinuteDraftLine: Identifiable, Hashable {
    let id: UUID
    var serverId: Int?
    var content: String
    var agendaItemId: Int?
    var assigneeUserIds: [Int]
    var dueDate: Date?

    init(
        id: UUID = UUID(),
        serverId: Int? = nil,
        content: String = "",
        agendaItemId: Int? = nil,
        assigneeUserIds: [Int] = [],
        dueDate: Date? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.content = content
        self.agendaItemId = agendaItemId
        self.assigneeUserIds = assigneeUserIds
        self.dueDate = dueDate
    }

    static func from(_ line: MeetingMinuteLine) -> MinuteDraftLine {
        MinuteDraftLine(
            serverId: line.id,
            content: line.content,
            agendaItemId: line.agendaItemId,
            assigneeUserIds: line.assigneeIds,
            dueDate: line.dueDate.flatMap { MeetingDateFormatting.parseISO($0) }
        )
    }

    func toInput(sortOrder: Int) -> MinuteLineInput {
        MinuteLineInput(
            id: serverId,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: sortOrder,
            agendaItemId: agendaItemId,
            assigneeUserIds: assigneeUserIds,
            dueDate: dueDate.map { MeetingDateFormatting.isoString(from: $0) }
        )
    }
}

enum MeetingDateFormatting {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        isoFrac.date(from: string) ?? iso.date(from: string)
    }

    static func isoString(from date: Date) -> String {
        iso.string(from: date)
    }

    static func displayDateTime(_ string: String?) -> String {
        guard let string, let date = parseISO(string) else { return string ?? "—" }
        return display.string(from: date)
    }

    static func displayDay(_ string: String?) -> String {
        guard let string, let date = parseISO(string) else { return string ?? "—" }
        return dayOnly.string(from: date)
    }
}
