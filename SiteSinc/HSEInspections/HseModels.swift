import Foundation
import SwiftUI

// MARK: - HSE Inspections Models
// Mirrors apps/frontend/src/types/hse.ts and /api/hse-inspections responses.

// MARK: JSON value (inspection `data`, observation `categoryData`, comment `metadata`)

/// Minimal JSON value so Prisma JSON columns decode without loss.
/// HSE header/category answers are strings in practice, but legacy inspection
/// `data` can hold nested camera answers, arrays, numbers, etc.
enum HseJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([HseJSONValue])
    case object([String: HseJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([HseJSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: HseJSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    /// Human readable form for display (dropdown/text answers are strings).
    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "Yes" : "No"
        case .null: return ""
        case .array(let a): return a.map { $0.displayString }.joined(separator: ", ")
        case .object: return ""
        }
    }
}

// MARK: Users

struct HseUser: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let email: String
    let firstName: String?
    let lastName: String?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }

    var initials: String {
        String(displayName.prefix(2)).uppercased()
    }
}

// MARK: Templates

struct HseSectionField: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let type: String
    let required: Bool?
    let description: String?
    let placeholder: String?
    let options: [String]?
}

struct HseSection: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    /// Legacy checklist questions — current templates are sections only.
    let fields: [HseSectionField]?
}

struct HseObservationFieldDef: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let type: String // "dropdown" | "text"
    let required: Bool?
    let options: [String]?

    var isRequired: Bool { required ?? false }
}

/// Live revision payload embedded in available templates and inspection detail.
struct HseTemplateRevision: Codable, Identifiable, Equatable {
    let id: Int
    let versionNumber: Int
    let sections: [HseSection]?
    let observationFields: [HseObservationFieldDef]?
    let observationLocationsEnabled: Bool?

    var sectionList: [HseSection] { sections ?? [] }
    var observationFieldList: [HseObservationFieldDef] { observationFields ?? [] }
    var locationsEnabled: Bool { observationLocationsEnabled ?? false }
}

/// GET /hse-inspections/templates/available?projectId=
struct HseAvailableTemplate: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let description: String?
    let reference: String?
    let liveRevision: HseTemplateRevision?
}

struct HseTemplateRef: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let reference: String?
}

// MARK: Tenant configuration

/// GET /hse-inspections/categories
struct HseObservationCategory: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let sortOrder: Int?
    let active: Bool?
}

/// GET /hse-inspections/header-fields
struct HseInspectionHeaderField: Codable, Identifiable, Equatable {
    let id: Int
    let label: String
    let type: String // "dropdown" | "text"
    let options: [String]?
    let required: Bool
    let sortOrder: Int?
    let active: Bool?
}

// MARK: Statuses

enum HseInspectionStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case submitted
    case closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .gray
        case .submitted: return .blue
        case .closed: return .green
        }
    }
}

enum HseObservationStatus: String, Codable, CaseIterable, Identifiable {
    case open = "OPEN"
    case inProgress = "IN_PROGRESS"
    case pendingApproval = "PENDING_APPROVAL"
    case closed = "CLOSED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .pendingApproval: return "Pending Approval"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open: return .red
        case .inProgress: return .orange
        case .pendingApproval: return .purple
        case .closed: return .green
        }
    }
}

enum HsePhotoType: String, Codable, CaseIterable {
    case observation = "OBSERVATION"
    case progress = "PROGRESS"
    case closeout = "CLOSEOUT"

    var label: String {
        switch self {
        case .observation: return "Observation"
        case .progress: return "Progress"
        case .closeout: return "Close-out"
        }
    }
}

// MARK: Observations

/// Fields are optional beyond `id` because the register endpoint returns
/// trimmed photo rows (`select: { id: true }, take: 1`).
struct HseObservationPhoto: Codable, Identifiable, Equatable {
    let id: Int
    let fileKey: String?
    let fileName: String?
    let fileType: String?
    let fileUrl: String?
    let caption: String?
    let photoType: HsePhotoType?
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let capturedAt: Date?
    let uploadedAt: Date?
    let uploadedById: Int?

    var isImage: Bool { fileType?.hasPrefix("image/") ?? false }
}

struct HseObservationComment: Codable, Identifiable, Equatable {
    let id: Int
    let comment: String
    let type: String // "comment" | "status_change" | "assignment"
    let createdAt: Date
    let author: HseUser?
}

struct HseObservationCounts: Codable, Equatable {
    let OPEN: Int?
    let IN_PROGRESS: Int?
    let PENDING_APPROVAL: Int?
    let CLOSED: Int?

    var open: Int { OPEN ?? 0 }
    var inProgress: Int { IN_PROGRESS ?? 0 }
    var pendingApproval: Int { PENDING_APPROVAL ?? 0 }
    var closed: Int { CLOSED ?? 0 }
    var total: Int { open + inProgress + pendingApproval + closed }
    var openTotal: Int { open + inProgress + pendingApproval }
}

/// Parent inspection summary embedded on register observations.
struct HseObservationInspectionRef: Codable, Equatable {
    let id: Int
    let inspectionNumber: String?
    let status: HseInspectionStatus?
    let template: HseObservationInspectionTemplateRef?
    let revision: HseTemplateRevisionLite?
}

struct HseObservationInspectionTemplateRef: Codable, Equatable {
    let id: Int
    let title: String
}

/// Revision embedded on observations (no id/versionNumber in some selects).
struct HseTemplateRevisionLite: Codable, Equatable {
    let sections: [HseSection]?
    let observationFields: [HseObservationFieldDef]?
    let observationLocationsEnabled: Bool?
}

struct HseCountRef: Codable, Equatable {
    let photos: Int?
    let comments: Int?
}

struct HseLocationRef: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let code: String?
}

struct HseObservation: Codable, Identifiable, Equatable {
    let id: Int
    let inspectionId: Int
    let sectionId: String
    let description: String
    let categoryId: Int?
    let category: HseObservationCategory?
    let categoryData: [String: HseJSONValue]?
    let status: HseObservationStatus
    let raisedBy: HseUser?
    let assignedTo: HseUser?
    let closedBy: HseUser?
    let locationId: Int?
    let location: HseLocationRef?
    let dueDate: Date?
    let closeoutNotes: String?
    let rejectionNotes: String?
    let closedAt: Date?
    let createdAt: Date
    let updatedAt: Date?
    let photos: [HseObservationPhoto]?
    let comments: [HseObservationComment]?
    let inspection: HseObservationInspectionRef?
    let _count: HseCountRef?

    var photoCount: Int { _count?.photos ?? photos?.count ?? 0 }
    var commentCount: Int { _count?.comments ?? comments?.count ?? 0 }

    var isOverdue: Bool {
        guard status != .closed, let due = dueDate else { return false }
        return due < Date()
    }
}

// MARK: Inspections

struct HseInspectionKeyPerson: Codable, Identifiable, Equatable {
    let id: Int?
    let userId: Int
    let user: HseUser?

    // Some responses omit the join-row id; fall back to userId for Identifiable.
    var stableId: Int { id ?? userId }
}

struct HseInspection: Codable, Identifiable, Equatable {
    let id: Int
    let templateId: Int
    let revisionId: Int
    let projectId: Int
    let inspectionNumber: String?
    let reportVersion: Int?
    let rootInspectionId: Int?
    let isCurrent: Bool?
    let data: [String: HseJSONValue]?
    let headerData: [String: HseJSONValue]?
    let status: HseInspectionStatus
    let locationId: Int?
    let conductedAt: Date?
    let accompaniedById: Int?
    let accompaniedBy: HseUser?
    let keyPersonnel: [HseInspectionKeyPerson]?
    let submittedAt: Date?
    let closedAt: Date?
    let createdAt: Date
    let updatedAt: Date?
    let template: HseTemplateRef?
    let revision: HseTemplateRevision?
    let inspectedBy: HseUser?
    let inspectedById: Int?
    let location: HseLocationRef?
    let observations: [HseObservation]?
    let observationCounts: HseObservationCounts?
    let observationTotal: Int?

    var displayNumber: String {
        if let number = inspectionNumber, !number.isEmpty {
            if let version = reportVersion, version > 1 {
                return "\(number) (Rev \(version))"
            }
            return number
        }
        return "Draft"
    }

    var headerStrings: [String: String] {
        (headerData ?? [:]).reduce(into: [:]) { result, entry in
            let text = entry.value.displayString
            if !text.isEmpty { result[entry.key] = text }
        }
    }
}

// MARK: API response wrappers

struct HseProjectUsersResponse: Codable {
    let users: [HseUser]
}

struct HseUploadedFile: Codable {
    let fileKey: String
    let fileName: String
    let fileType: String
}

struct HseUploadFilesResponse: Codable {
    let files: [HseUploadedFile]
}

struct HseObservationPhotosResponse: Codable {
    let photos: [HseObservationPhoto]
}

struct HseRefreshUrlResponse: Codable {
    let url: String
}

/// Extra flag on POST /observations/:id/status responses: set when closing the
/// last observation auto-closed the parent inspection. Decoded from the same
/// payload as the updated observation.
struct HseInspectionClosedFlag: Codable {
    let inspectionClosed: Bool?
}

struct HseObservationStatusResult {
    let observation: HseObservation
    let inspectionClosed: Bool
}
