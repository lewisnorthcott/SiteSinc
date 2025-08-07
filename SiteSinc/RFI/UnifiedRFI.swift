//
//  UnifiedRFI.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import Foundation

enum UnifiedRFI: Identifiable {
    case server(RFI)
    case draft(RFIDraft)

    var id: Int {
        switch self {
        case .server(let rfi):
            return rfi.id
        case .draft(let draft):
            return draft.id.uuidString.hashValue
        }
    }

    var title: String? {
        switch self {
        case .server(let rfi):
            return rfi.title
        case .draft(let draft):
            return draft.title
        }
    }

    var number: Int {
        switch self {
        case .server(let rfi):
            return rfi.number
        case .draft:
            return 0
        }
    }

    var status: String? {
        switch self {
        case .server(let rfi):
            return rfi.status
        case .draft:
            return "Draft"
        }
    }

    var createdAt: String? {
        switch self {
        case .server(let rfi):
            return rfi.createdAt
        case .draft(let draft):
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: draft.createdAt)
        }
    }

    var query: String? {
        switch self {
        case .server(let rfi):
            return rfi.query
        case .draft(let draft):
            return draft.query
        }
    }

    var description: String? {
        switch self {
        case .server(let rfi):
            return rfi.description
        case .draft(let draft):
            return draft.query
        }
    }

    var attachments: [RFI.RFIAttachment]? {
        switch self {
        case .server(let rfi):
            return rfi.attachments
        case .draft:
            return nil
        }
    }

    var projectId: Int {
        switch self {
        case .server(let rfi):
            return rfi.projectId
        case .draft(let draft):
            return draft.projectId
        }
    }

    var draftObject: RFIDraft? {
        switch self {
        case .server:
            return nil
        case .draft(let draft):
            return draft
        }
    }

    var serverRFI: RFI? {
        switch self {
        case .server(let rfi):
            return rfi
        case .draft:
            return nil
        }
    }

    var selectedDrawings: [SelectedDrawing] {
        switch self {
        case .server:
            return []
        case .draft(let draft):
            return draft.selectedDrawings
        }
    }
    
    var returnDate: String? {
        switch self {
        case .server(let rfi):
            return rfi.returnDate
        case .draft(let draft):
            return draft.returnDate?.ISO8601Format()
        }
    }
    
    var assignedUsers: [RFI.AssignedUser]? {
        switch self {
        case .server(let rfi):
            return rfi.assignedUsers
        case .draft:
            return nil
        }
    }
    
    var drawings: [RFI.RFIDrawing]? {
        switch self {
        case .server(let rfi):
            return rfi.drawings
        case .draft:
            return nil
        }
    }
    
    var responses: [RFI.RFIResponseItem]? {
        switch self {
        case .server(let rfi):
            return rfi.responses
        case .draft:
            return nil
        }
    }
    
    var managerId: Int? {
        switch self {
        case .server(let rfi):
            return rfi.managerId
        case .draft:
            return nil
        }
    }
}
