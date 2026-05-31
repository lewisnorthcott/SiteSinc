import Foundation
import SwiftUI

// MARK: - Incident classification

let incidentLogTypeNameKeywords: [String] = [
    "incident", "accident", "near miss", "near-miss", "nearmiss",
    "environmental", "property damage", "injury", "illness"
]

func logTypeNameMatchesIncidentHub(_ name: String) -> Bool {
    let n = name.lowercased()
    if incidentLogTypeNameKeywords.contains(where: { n.contains($0) }) { return true }
    if n.hasPrefix("safety") && (n.contains("hazard") || n.contains("violation")) { return true }
    return false
}

// MARK: - Severity

enum SeverityBand: String, Codable, CaseIterable, Identifiable {
    case low, medium, high, critical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .low: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .medium: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .high: return Color(red: 249/255, green: 115/255, blue: 22/255)
        case .critical: return Color(red: 220/255, green: 38/255, blue: 38/255)
        }
    }
}

// MARK: - RIDDOR

struct RiddorCriterion: Identifiable {
    let key: String
    let label: String
    let hint: String?
    let deadline: String
    var id: String { key }
}

let riddorCriteria: [RiddorCriterion] = [
    RiddorCriterion(
        key: "fatality",
        label: "A death resulted from a work-related accident",
        hint: nil,
        deadline: "Report to the HSE without delay (by phone), then within 10 days."
    ),
    RiddorCriterion(
        key: "specified_injury",
        label: "A specified injury occurred",
        hint: "Fracture (not fingers/thumbs/toes), amputation, permanent sight loss, crush to head/torso, serious burn, scalping, loss of consciousness, or hypothermia/asphyxia requiring resuscitation or 24h hospital admission.",
        deadline: "Report within 10 days of the accident."
    ),
    RiddorCriterion(
        key: "over_7_day",
        label: "A worker was unable to do their normal work for more than 7 days",
        hint: "Not counting the day of the accident, but including weekends and rest days.",
        deadline: "Report within 15 days of the accident."
    ),
    RiddorCriterion(
        key: "hospital_treatment",
        label: "A member of the public was taken to hospital for treatment",
        hint: nil,
        deadline: "Report within 10 days of the accident."
    ),
    RiddorCriterion(
        key: "occupational_disease",
        label: "A doctor diagnosed a reportable occupational disease",
        hint: "e.g. carpal tunnel, HAVS, occupational dermatitis, asthma, tendonitis, or cancer/disease linked to a known carcinogen.",
        deadline: "Report as soon as the diagnosis is received."
    ),
    RiddorCriterion(
        key: "dangerous_occurrence",
        label: "A dangerous occurrence (near miss) took place",
        hint: "e.g. collapse/overturning of plant, scaffold collapse, explosion or fire, electrical short causing fire, accidental release of a substance.",
        deadline: "Report without delay, then within 10 days."
    ),
    RiddorCriterion(
        key: "gas_incident",
        label: "A gas-related death, injury or dangerous gas fitting",
        hint: nil,
        deadline: "Report within 14 days (or as soon as practicable)."
    )
]

let riddorLabels: [String: String] = Dictionary(uniqueKeysWithValues: riddorCriteria.map { ($0.key, $0.label) })

func isRiddorReportable(_ selectedKeys: [String]) -> Bool {
    !selectedKeys.isEmpty
}

// MARK: - Body map

enum BodyViewSide: String, CaseIterable {
    case front, back
}

let bodyParts: [String] = [
    "head", "neck", "chest", "abdomen",
    "left_upper_arm", "left_forearm", "left_hand",
    "right_upper_arm", "right_forearm", "right_hand",
    "left_thigh", "left_shin", "left_foot",
    "right_thigh", "right_shin", "right_foot"
]

func bodyRegionId(view: BodyViewSide, part: String) -> String {
    "\(view.rawValue):\(part)"
}

private let frontBodyLabels: [String: String] = [
    "head": "Head", "neck": "Neck", "chest": "Chest", "abdomen": "Abdomen",
    "left_upper_arm": "Left upper arm", "left_forearm": "Left forearm", "left_hand": "Left hand",
    "right_upper_arm": "Right upper arm", "right_forearm": "Right forearm", "right_hand": "Right hand",
    "left_thigh": "Left thigh", "left_shin": "Left lower leg", "left_foot": "Left foot",
    "right_thigh": "Right thigh", "right_shin": "Right lower leg", "right_foot": "Right foot"
]

private let backBodyLabels: [String: String] = [
    "head": "Head (back)", "neck": "Nape of neck", "chest": "Upper back", "abdomen": "Lower back",
    "left_upper_arm": "Left upper arm", "left_forearm": "Left forearm", "left_hand": "Left hand",
    "right_upper_arm": "Right upper arm", "right_forearm": "Right forearm", "right_hand": "Right hand",
    "left_thigh": "Left thigh (back)", "left_shin": "Left calf", "left_foot": "Left heel",
    "right_thigh": "Right thigh (back)", "right_shin": "Right calf", "right_foot": "Right heel"
]

func bodyRegionLabel(_ id: String) -> String {
    let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
    let view = parts.count > 1 ? parts[0] : "front"
    let part = parts.count > 1 ? parts[1] : parts[0]
    let map = view == "back" ? backBodyLabels : frontBodyLabels
    return map[part] ?? part.replacingOccurrences(of: "_", with: " ")
}

// MARK: - Record types

enum IncidentRecordType: String, Codable, CaseIterable {
    case near_miss
    case incident
    case environmental
    case property_damage

    var displayTitle: String {
        switch self {
        case .near_miss: return "Near miss"
        case .incident: return "Incident"
        case .environmental: return "Environmental"
        case .property_damage: return "Property damage"
        }
    }
}

// MARK: - Payload helpers

struct IncidentPayload: Codable, Equatable {
    var bodyMap: [String]?
    var riddor: [String]?
    var fiveWhys: [String]?
    var relatedToolboxTalkUrl: String?
}

struct CreateLogIncidentFields {
    let recordType: IncidentRecordType?
    let isAnonymous: Bool
    let occurredAt: String?
    let severityBand: SeverityBand?
    let injuryInvolved: Bool
    let riddorReasons: [String]
    let bodyMap: [String]

    func apply(to request: inout CreateLogRequest, incidentMode: Bool) {
        guard incidentMode else { return }
        request.recordType = recordType?.rawValue
        request.isAnonymous = isAnonymous
        request.occurredAt = occurredAt
        request.incidentSeverityBand = severityBand?.rawValue
        request.injuryInvolved = injuryInvolved
        request.regulatoryNotifiable = isRiddorReportable(riddorReasons)

        var payload = IncidentPayload()
        if injuryInvolved && !bodyMap.isEmpty { payload.bodyMap = bodyMap }
        if !riddorReasons.isEmpty { payload.riddor = riddorReasons }
        if payload.bodyMap != nil || payload.riddor != nil {
            request.incidentPayload = payload
        }
    }
}

// MARK: - Log permissions helpers

struct LogPermissions {
    static func names(from user: User?) -> [String] {
        user?.permissions?.map { $0.name } ?? []
    }

    static func canViewLogs(_ user: User?) -> Bool {
        let p = names(from: user)
        return p.contains("view_logs") || p.contains("view_all_logs")
    }

    static func canCreateLogs(_ user: User?) -> Bool {
        let p = names(from: user)
        return p.contains("create_logs") || p.contains("manage_all_logs")
    }

    static func canReportIncidents(_ user: User?) -> Bool {
        let p = names(from: user)
        return p.contains("report_incidents") || p.contains("create_logs") || p.contains("manage_all_logs")
    }

    static func canManageAllLogs(_ user: User?) -> Bool {
        names(from: user).contains("manage_all_logs")
    }

    static func canViewAllLogs(_ user: User?) -> Bool {
        names(from: user).contains("view_all_logs")
    }

    static func canRespondToLogs(_ user: User?) -> Bool {
        names(from: user).contains("respond_to_logs")
    }

    static func canEditLog(_ user: User?, log: Log) -> Bool {
        guard let user else { return false }
        if canManageAllLogs(user) { return true }
        if names(from: user).contains("edit_logs"), log.createdById == user.id { return true }
        return false
    }

    static func canSeeReporterIdentity(_ user: User?, log: Log) -> Bool {
        guard log.isAnonymous == true else { return true }
        guard let user else { return false }
        if log.createdById == user.id { return true }
        return canManageAllLogs(user) || canViewAllLogs(user)
    }

    static func reporterDisplayName(_ log: Log, currentUser: User?) -> String {
        if log.createdBy?.anonymous == true && !canSeeReporterIdentity(currentUser, log: log) {
            return "Anonymous"
        }
        return log.createdBy?.displayName ?? "Unknown"
    }
}
