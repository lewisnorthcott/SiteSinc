import Foundation

// MARK: - Material Requisition Models

struct MaterialRequisition: Identifiable, Codable {
    let id: Int
    let projectId: Int
    let number: Int
    let formattedNumber: String?
    let title: String
    let status: MaterialRequisitionStatus
    let requestedById: Int
    let requestedBy: MaterialRequisitionUser?
    let buyerId: Int?
    let buyer: MaterialRequisitionUser?
    let notes: String?
    let requiredByDate: String?
    let quoteAttachments: [MaterialRequisitionAttachment]?
    let orderAttachments: [MaterialRequisitionAttachment]?
    let requisitionAttachments: [MaterialRequisitionAttachment]?
    let orderReference: String?
    let items: [MaterialRequisitionItem]?
    let totalValue: String?
    let deliveryTicketPhoto: MaterialRequisitionAttachment?
    let deliveryNotes: String?
    let createdAt: String?
    let submittedAt: String?
    let acceptedAt: String?
    let processedAt: String?
    let orderedAt: String?
    let deliveredAt: String?
    let completedAt: String?
    let archivedAt: String?
    let orderedById: Int?
    let orderedBy: MaterialRequisitionUser?
    
    enum CodingKeys: String, CodingKey {
        case id, projectId, number, formattedNumber, title, status
        case requestedById, requestedBy, buyerId, buyer
        case notes, requiredByDate, orderReference
        case quoteAttachments, orderAttachments, metadata
        case items, totalValue
        case deliveryTicketPhoto, deliveryNotes
        case createdAt, submittedAt, acceptedAt, processedAt
        case orderedAt, deliveredAt, completedAt, archivedAt
        case orderedById, orderedBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        projectId = try container.decode(Int.self, forKey: .projectId)
        number = try container.decode(Int.self, forKey: .number)
        formattedNumber = try container.decodeIfPresent(String.self, forKey: .formattedNumber)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(MaterialRequisitionStatus.self, forKey: .status)
        requestedById = try container.decode(Int.self, forKey: .requestedById)
        requestedBy = try container.decodeIfPresent(MaterialRequisitionUser.self, forKey: .requestedBy)
        buyerId = try container.decodeIfPresent(Int.self, forKey: .buyerId)
        buyer = try container.decodeIfPresent(MaterialRequisitionUser.self, forKey: .buyer)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        requiredByDate = try container.decodeIfPresent(String.self, forKey: .requiredByDate)
        orderReference = try container.decodeIfPresent(String.self, forKey: .orderReference)
        items = try container.decodeIfPresent([MaterialRequisitionItem].self, forKey: .items)
        totalValue = try container.decodeIfPresent(String.self, forKey: .totalValue)
        deliveryNotes = try container.decodeIfPresent(String.self, forKey: .deliveryNotes)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        acceptedAt = try container.decodeIfPresent(String.self, forKey: .acceptedAt)
        processedAt = try container.decodeIfPresent(String.self, forKey: .processedAt)
        orderedAt = try container.decodeIfPresent(String.self, forKey: .orderedAt)
        deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
        orderedById = try container.decodeIfPresent(Int.self, forKey: .orderedById)
        orderedBy = try container.decodeIfPresent(MaterialRequisitionUser.self, forKey: .orderedBy)
        
        // Handle attachments - they can be arrays or single objects
        if let quoteAttachmentsData = try? container.decodeIfPresent([MaterialRequisitionAttachment].self, forKey: .quoteAttachments) {
            quoteAttachments = quoteAttachmentsData
        } else if let quoteAttachmentData = try? container.decodeIfPresent(MaterialRequisitionAttachment.self, forKey: .quoteAttachments) {
            quoteAttachments = [quoteAttachmentData]
        } else {
            quoteAttachments = nil
        }
        
        if let orderAttachmentsData = try? container.decodeIfPresent([MaterialRequisitionAttachment].self, forKey: .orderAttachments) {
            orderAttachments = orderAttachmentsData
        } else if let orderAttachmentData = try? container.decodeIfPresent(MaterialRequisitionAttachment.self, forKey: .orderAttachments) {
            orderAttachments = [orderAttachmentData]
        } else {
            orderAttachments = nil
        }
        
        deliveryTicketPhoto = try container.decodeIfPresent(MaterialRequisitionAttachment.self, forKey: .deliveryTicketPhoto)
        
        // For now, don't parse requisitionAttachments from metadata
        // This can be handled differently if needed in the future
        requisitionAttachments = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(number, forKey: .number)
        try container.encodeIfPresent(formattedNumber, forKey: .formattedNumber)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(requestedById, forKey: .requestedById)
        try container.encodeIfPresent(requestedBy, forKey: .requestedBy)
        try container.encodeIfPresent(buyerId, forKey: .buyerId)
        try container.encodeIfPresent(buyer, forKey: .buyer)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(requiredByDate, forKey: .requiredByDate)
        try container.encodeIfPresent(orderReference, forKey: .orderReference)
        try container.encodeIfPresent(quoteAttachments, forKey: .quoteAttachments)
        try container.encodeIfPresent(orderAttachments, forKey: .orderAttachments)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(totalValue, forKey: .totalValue)
        try container.encodeIfPresent(deliveryTicketPhoto, forKey: .deliveryTicketPhoto)
        try container.encodeIfPresent(deliveryNotes, forKey: .deliveryNotes)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(submittedAt, forKey: .submittedAt)
        try container.encodeIfPresent(acceptedAt, forKey: .acceptedAt)
        try container.encodeIfPresent(processedAt, forKey: .processedAt)
        try container.encodeIfPresent(orderedAt, forKey: .orderedAt)
        try container.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(orderedById, forKey: .orderedById)
        try container.encodeIfPresent(orderedBy, forKey: .orderedBy)
    }
}

enum MaterialRequisitionStatus: String, Codable, CaseIterable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case accepted = "ACCEPTED"
    case processing = "PROCESSING"
    case ordered = "ORDERED"
    case delivered = "DELIVERED"
    case completed = "COMPLETED"
    case archived = "ARCHIVED"
    case cancelled = "CANCELLED"
    case rejected = "REJECTED"
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .accepted: return "Accepted"
        case .processing: return "Processing"
        case .ordered: return "Ordered"
        case .delivered: return "Delivered"
        case .completed: return "Completed"
        case .archived: return "Archived"
        case .cancelled: return "Cancelled"
        case .rejected: return "Rejected"
        }
    }
    
    var color: String {
        switch self {
        case .draft: return "gray"
        case .submitted: return "blue"
        case .accepted: return "green"
        case .processing: return "orange"
        case .ordered: return "purple"
        case .delivered: return "teal"
        case .completed: return "green"
        case .archived: return "gray"
        case .cancelled: return "red"
        case .rejected: return "red"
        }
    }
}

struct MaterialRequisitionUser: Codable {
    let id: Int
    let email: String?
    let firstName: String?
    let lastName: String?
    
    var displayName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName {
            return firstName
        } else if let email = email {
            return email
        }
        return "Unknown User"
    }
}

struct MaterialRequisitionItem: Identifiable, Codable {
    let id: Int
    let lineItem: String?
    let description: String?
    let quantity: String?
    let unit: String?
    let rate: String?
    let total: String?
    let orderedQuantity: String?
    let orderedRate: String?
    let orderedTotal: String?
    let deliveredQuantity: String?
    let position: Int?
    
    var quantityValue: Double? {
        guard let quantity = quantity else { return nil }
        return Double(quantity)
    }
    
    var rateValue: Double? {
        guard let rate = rate else { return nil }
        return Double(rate)
    }
    
    var totalValue: Double? {
        guard let total = total else { return nil }
        return Double(total)
    }
}

struct MaterialRequisitionAttachment: Codable {
    let name: String?
    let type: String?
    let size: Int?
    let fileKey: String?
    let url: String?
}

struct MaterialRequisitionBuyer: Identifiable, Codable {
    let id: Int
    let email: String?
    let firstName: String?
    let lastName: String?
    
    var displayName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName {
            return firstName
        } else if let email = email {
            return email
        }
        return "Unknown User"
    }
}

// MARK: - API Response Models

struct MaterialRequisitionsResponse: Codable {
    let requisitions: [MaterialRequisition]
}

struct MaterialRequisitionResponse: Codable {
    let requisition: MaterialRequisition
}

struct MaterialRequisitionBuyersResponse: Codable {
    let buyers: [MaterialRequisitionBuyer]
}

struct MaterialRequisitionFileUploadResponse: Codable {
    let files: [MaterialRequisitionAttachment]
}

// MARK: - Request Models

struct CreateMaterialRequisitionRequest: Encodable {
    let title: String
    let buyerId: Int?
    let notes: String?
    let requiredByDate: String?
    let quoteAttachments: [[String: String]]?
    let orderAttachments: [[String: String]]?
    let orderReference: String?
    let metadata: [String: Any]?
    let items: [MaterialRequisitionItemInput]?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case title, buyerId, notes, requiredByDate
        case quoteAttachments, orderAttachments, orderReference
        case metadata, items, status
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(buyerId, forKey: .buyerId)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(requiredByDate, forKey: .requiredByDate)
        try container.encodeIfPresent(quoteAttachments, forKey: .quoteAttachments)
        try container.encodeIfPresent(orderAttachments, forKey: .orderAttachments)
        try container.encodeIfPresent(orderReference, forKey: .orderReference)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(status, forKey: .status)
        
        // Encode metadata as JSON if present
        if metadata != nil {
            // For now, skip metadata encoding - handle it differently if needed
            // Metadata encoding can be added later if needed
        }
    }
}

struct MaterialRequisitionItemInput: Codable {
    var lineItem: String?
    var description: String?
    var quantity: String?
    var unit: String?
    var rate: String?
    var total: String?
    var orderedQuantity: String?
    var orderedRate: String?
    var orderedTotal: String?
    var deliveredQuantity: String?
    var position: Int?
}

struct UpdateMaterialRequisitionRequest: Encodable {
    let title: String?
    let buyerId: Int?
    let notes: String?
    let requiredByDate: String?
    let quoteAttachments: [[String: String]]?
    let orderAttachments: [[String: String]]?
    let orderReference: String?
    let metadata: [String: Any]?
    let items: [MaterialRequisitionItemInput]?
    let deliveryTicketPhoto: [String: String]?
    let deliveryNotes: String?
    
    enum CodingKeys: String, CodingKey {
        case title, buyerId, notes, requiredByDate
        case quoteAttachments, orderAttachments, orderReference
        case metadata, items, deliveryTicketPhoto, deliveryNotes
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(buyerId, forKey: .buyerId)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(requiredByDate, forKey: .requiredByDate)
        try container.encodeIfPresent(quoteAttachments, forKey: .quoteAttachments)
        try container.encodeIfPresent(orderAttachments, forKey: .orderAttachments)
        try container.encodeIfPresent(orderReference, forKey: .orderReference)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(deliveryTicketPhoto, forKey: .deliveryTicketPhoto)
        try container.encodeIfPresent(deliveryNotes, forKey: .deliveryNotes)
    }
}

struct UpdateMaterialRequisitionStatusRequest: Codable {
    let status: String
    let orderReference: String?
}

struct AssignBuyerRequest: Codable {
    let buyerId: Int?
}
