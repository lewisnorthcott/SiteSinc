import Foundation

struct ErrorResponse: Decodable {
    let message: String?
    let error: String?
}

struct PasswordResetResponse: Decodable {
    let message: String?
}

enum APIError: Error {
    case tokenExpired
    case invalidResponse(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
}

struct APIClient {
    #if DEBUG
    static let baseURL = "http://localhost:3000/api"
    #else
    static let baseURL = "https://sitesinc.onrender.com/api"
    #endif
    
    // MARK: - Helper Function for API Requests
    private static func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            switch httpResponse.statusCode {
            case 200, 204:
                return try JSONDecoder().decode(T.self, from: data)
            case 403:
                throw APIError.tokenExpired
            default:
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    static func login(email: String, password: String) async throws -> (String, User) {
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(params)
        
        let loginResponse: ExtendedLoginResponse = try await performRequest(request)
        
        let userTenants = loginResponse.user.tenants?.map { loginTenant in
            User.UserTenant(
                userId: nil,
                tenantId: loginTenant.id,
                createdAt: nil,
                companyId: loginTenant.companyId,
                firstName: nil,
                lastName: nil,
                jobTitle: nil,
                phone: nil,
                isActive: nil,
                blocked: loginTenant.blocked,
                tenant: Tenant(
                    id: loginTenant.id,
                    name: loginTenant.name,
                    email: nil,
                    schemaName: nil,
                    createdAt: nil,
                    updatedAt: nil,
                    stripeCustomerId: nil,
                    subscriptionStatus: nil,
                    subscriptionCancelId: nil,
                    subscriptionCanelledAt: nil,
                    stripeSubscriptionId: nil,
                    subscriptionOwnerId: nil,
                    blocked: loginTenant.blocked
                ),
                company: User.Company(
                    id: loginTenant.companyId,
                    name: loginTenant.companyName,
                    createdAt: nil,
                    updatedAt: nil,
                    tenantId: nil,
                    reference: nil,
                    mainCompanyId: nil,
                    address: nil,
                    city: nil,
                    country: nil,
                    email: nil,
                    isActive: nil,
                    phone: nil,
                    state: nil,
                    website: nil,
                    zip: nil,
                    typeId: nil,
                    logoUrl: nil
                )
            )
        } ?? []
        
        let user = User(
            id: loginResponse.user.id,
            firstName: loginResponse.user.firstName,
            lastName: loginResponse.user.lastName,
            email: loginResponse.user.email,
            tenantId: loginResponse.user.tenantId,
            companyId: loginResponse.user.companyId,
            company: loginResponse.user.company,
            roles: loginResponse.user.roles,
            permissions: loginResponse.user.permissions,
            projectPermissions: loginResponse.user.projectPermissions,
            isSubscriptionOwner: loginResponse.user.isSubscriptionOwner,
            assignedProjects: loginResponse.user.assignedProjects,
            assignedSubcontractOrders: loginResponse.user.assignedSubcontractOrders,
            blocked: loginResponse.user.blocked,
            createdAt: loginResponse.user.createdAt,
            userRoles: loginResponse.user.UserRoles,
            userPermissions: loginResponse.user.UserPermissions,
            tenants: userTenants
        )
        return (loginResponse.token, user)
    }
    
    static func requestPasswordReset(email: String) async throws -> String {
        let url = URL(string: "\(baseURL)/auth/request-password-reset")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = ["email": email]
        request.httpBody = try JSONEncoder().encode(params)
        
        let response: PasswordResetResponse = try await performRequest(request)
        return response.message ?? "Password reset instructions sent. Please check your email."
    }

    static func selectTenant(token: String, tenantId: Int) async throws -> (String, User) {
        let url = URL(string: "\(baseURL)/auth/select-tenant")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let params = ["tenantId": tenantId]
        request.httpBody = try JSONEncoder().encode(params)

        let response: SelectTenantResponse = try await performRequest(request)
        return (response.token, response.user)
    }

    static func fetchProjects(token: String) async throws -> [Project] {
        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await performRequest(request)
    }
    
    static func fetchDrawings(projectId: Int, token: String) async throws -> [Drawing] {
        let url = URL(string: "\(baseURL)/drawings?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let drawingResponse: DrawingResponse = try await performRequest(request)
        return drawingResponse.drawings.filter { $0.projectId == projectId }
    }
    
    static func fetchRFIs(projectId: Int, token: String) async throws -> [RFI] {
        print("Starting fetchRFIs for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/rfis?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let rfiResponse: RFIResponse = try await performRequest(request)
        let filteredRFIs = rfiResponse.rfis.filter { $0.projectId == projectId }
        print("Successfully decoded \(filteredRFIs.count) RFIs")
        return filteredRFIs
    }
    
    static func downloadFile(from urlString: String, to localPath: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.networkError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        do {
            if FileManager.default.fileExists(atPath: localPath.path) {
                try FileManager.default.removeItem(at: localPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: localPath)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    static func fetchUsers(projectId: Int, token: String) async throws -> [User] {
        let url = URL(string: "\(baseURL)/users?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let userResponse: UserResponse = try await performRequest(request)
        print("Fetched \(userResponse.users.count) users for projectId: \(projectId)")
        return userResponse.users
    }

    static func fetchTenants(token: String) async throws -> [Tenant] {
        let url = URL(string: "\(baseURL)/tenants")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let tenants: [Tenant] = try await performRequest(request)
        print("Fetched tenants: \(tenants)")
        return tenants
    }
    
    static func fetchForms(projectId: Int, token: String) async throws -> [FormModel] {
        let url = URL(string: "\(baseURL)/forms/accessible?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let forms: [FormModel] = try await performRequest(request)
        print("Fetched \(forms.count) forms for projectId: \(projectId)")
        return forms
    }

    static func fetchFormSubmissions(projectId: Int, token: String) async throws -> [FormSubmission] {
        let url = URL(string: "\(baseURL)/forms/submissions?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let submissions: [FormSubmission] = try await performRequest(request)
        print("Fetched \(submissions.count) form submissions for projectId: \(projectId)")
        return submissions
    }
    
    static func fetchDocuments(projectId: Int, token: String) async throws -> [Document] {
        let url = URL(string: "\(baseURL)/documents?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        print("Fetching documents with token: \(token)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        print("Documents API response status: \(httpResponse.statusCode)")
        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("Raw JSON for documents: \(json)")
        }

        switch httpResponse.statusCode {
        case 200, 204:
            return try JSONDecoder().decode([Document].self, from: data) // Decode directly as array
        case 403:
            throw APIError.tokenExpired
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    static func fetchDocument(documentId: Int, token: String) async throws -> Document {
        let url = URL(string: "\(baseURL)/documents/\(documentId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: DocumentSingleResponse = try await performRequest(request)
        print("Fetched document with id: \(documentId)")
        return response.document
    }
}




//struct DocumentResponse: Codable {
//    let documents: [Document]
//}

struct DocumentSingleResponse: Codable {
    let document: Document
}

// Models
struct Tenant: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String?
    let schemaName: String?
    let createdAt: String?
    let updatedAt: String?
    let stripeCustomerId: String?
    let subscriptionStatus: String?
    let subscriptionCancelId: String?
    let subscriptionCanelledAt: String?
    let stripeSubscriptionId: String?
    let subscriptionOwnerId: Int?
    let blocked: Bool?
}

struct UserResponse: Codable {
    let users: [User]
    let pagination: Pagination?
    
    struct Pagination: Codable {
        let currentPage: Int
        let totalPages: Int
        let totalUsers: Int
    }
}

struct Permission: Codable {
    let id: Int
    let name: String
}

struct User: Codable, Identifiable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let email: String?
    let tenantId: Int?
    let companyId: Int?
    let company: Company?
    let roles: [Role]?
    let permissions: [Permission]?
    let projectPermissions: [Int: [String]]?
    let isSubscriptionOwner: Bool?
    let assignedProjects: [Int]?
    let assignedSubcontractOrders: [Int]?
    let blocked: Bool?
    let createdAt: String?
    let userRoles: [UserRole]?
    let userPermissions: [UserPermission]?
    let tenants: [UserTenant]?

    // Existing initializer for minimal creation
    init(id: Int, tenantId: Int?) {
        self.id = id
        self.tenantId = tenantId
        self.firstName = nil
        self.lastName = nil
        self.email = nil
        self.companyId = nil
        self.company = nil
        self.roles = nil
        self.permissions = nil
        self.projectPermissions = nil
        self.isSubscriptionOwner = nil
        self.assignedProjects = nil
        self.assignedSubcontractOrders = nil
        self.blocked = nil
        self.createdAt = nil
        self.userRoles = nil
        self.userPermissions = nil
        self.tenants = nil
    }

    // New initializer matching the login method usage
    init(
        id: Int,
        firstName: String?,
        lastName: String?,
        email: String?,
        tenantId: Int?,
        companyId: Int?,
        company: Company?,
        roles: [Role]?,
        permissions: [Permission]?,
        projectPermissions: [Int: [String]]?,
        isSubscriptionOwner: Bool?,
        assignedProjects: [Int]?,
        assignedSubcontractOrders: [Int]?,
        blocked: Bool?,
        createdAt: String?,
        userRoles: [UserRole]?,
        userPermissions: [UserPermission]?,
        tenants: [UserTenant]?
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.tenantId = tenantId
        self.companyId = companyId
        self.company = company
        self.roles = roles
        self.permissions = permissions
        self.projectPermissions = projectPermissions
        self.isSubscriptionOwner = isSubscriptionOwner
        self.assignedProjects = assignedProjects
        self.assignedSubcontractOrders = assignedSubcontractOrders
        self.blocked = blocked
        self.createdAt = createdAt
        self.userRoles = userRoles
        self.userPermissions = userPermissions
        self.tenants = tenants
    }

    struct Company: Codable {
        let id: Int
        let name: String
        let createdAt: String?
        let updatedAt: String?
        let tenantId: Int?
        let reference: String?
        let mainCompanyId: [Int]?
        let address: String?
        let city: String?
        let country: String?
        let email: String?
        let isActive: Bool?
        let phone: String?
        let state: String?
        let website: String?
        let zip: String?
        let typeId: Int?
        let logoUrl: String?
    }
    
    struct UserRole: Codable {
        let A: Int?
        let B: Int?
        let roles: Role
        struct Role: Codable {
            let id: Int
            let name: String
            let createdAt: String?
            let updatedAt: String?
            let userId: Int?
            let tenantId: Int?
        }
    }
    
    struct UserPermission: Codable {
        let userId: Int?
        let permissionId: Int?
        let tenantId: Int?
        let granted: Bool?
        let source: String?
        let sourceId: Int?
        let updatedAt: String?
        let permission: Permission
        struct Permission: Codable {
            let id: Int
            let name: String
            let createdAt: String?
            let updatedAt: String?
            let tenantId: Int?
        }
    }
    
    struct UserTenant: Codable {
        let userId: Int?
        let tenantId: Int?
        let createdAt: String?
        let companyId: Int?
        let firstName: String?
        let lastName: String?
        let jobTitle: String?
        let phone: String?
        let isActive: Bool?
        let blocked: Bool?
        let tenant: Tenant?
        let company: Company?

        // Custom initializer to match the parameters you're passing
        init(
            userId: Int? = nil,
            tenantId: Int? = nil,
            createdAt: String? = nil,
            companyId: Int? = nil,
            firstName: String? = nil,
            lastName: String? = nil,
            jobTitle: String? = nil,
            phone: String? = nil,
            isActive: Bool? = nil,
            blocked: Bool? = nil,
            tenant: Tenant? = nil,
            company: Company? = nil
        ) {
            self.userId = userId
            self.tenantId = tenantId
            self.createdAt = createdAt
            self.companyId = companyId
            self.firstName = firstName
            self.lastName = lastName
            self.jobTitle = jobTitle
            self.phone = phone
            self.isActive = isActive
            self.blocked = blocked
            self.tenant = tenant
            self.company = company
        }

        enum CodingKeys: String, CodingKey {
            case userId
            case tenantId
            case createdAt
            case companyId
            case firstName
            case lastName
            case jobTitle
            case phone
            case isActive
            case blocked
            case tenant
            case company
            case id
            case name
            case companyName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            userId = try container.decodeIfPresent(Int.self, forKey: .userId)
            tenantId = try container.decodeIfPresent(Int.self, forKey: .tenantId)
            createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            companyId = try container.decodeIfPresent(Int.self, forKey: .companyId)
            firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
            lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
            jobTitle = try container.decodeIfPresent(String.self, forKey: .jobTitle)
            phone = try container.decodeIfPresent(String.self, forKey: .phone)
            isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
            blocked = try container.decodeIfPresent(Bool.self, forKey: .blocked)
            company = try container.decodeIfPresent(Company.self, forKey: .company)

            if let tenant = try? container.decodeIfPresent(Tenant.self, forKey: .tenant) {
                self.tenant = tenant
            } else {
                let id = try container.decode(Int.self, forKey: .id)
                let name = try container.decode(String.self, forKey: .name)
                let blocked = try container.decodeIfPresent(Bool.self, forKey: .blocked)
                self.tenant = Tenant(
                    id: id,
                    name: name,
                    email: nil,
                    schemaName: nil,
                    createdAt: nil,
                    updatedAt: nil,
                    stripeCustomerId: nil,
                    subscriptionStatus: nil,
                    subscriptionCancelId: nil,
                    subscriptionCanelledAt: nil,
                    stripeSubscriptionId: nil,
                    subscriptionOwnerId: nil,
                    blocked: blocked
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(userId, forKey: .userId)
            try container.encodeIfPresent(tenantId, forKey: .tenantId)
            try container.encodeIfPresent(createdAt, forKey: .createdAt)
            try container.encodeIfPresent(companyId, forKey: .companyId)
            try container.encodeIfPresent(firstName, forKey: .firstName)
            try container.encodeIfPresent(lastName, forKey: .lastName)
            try container.encodeIfPresent(jobTitle, forKey: .jobTitle)
            try container.encodeIfPresent(phone, forKey: .phone)
            try container.encodeIfPresent(isActive, forKey: .isActive)
            try container.encodeIfPresent(blocked, forKey: .blocked)
            try container.encodeIfPresent(tenant, forKey: .tenant)
            try container.encodeIfPresent(company, forKey: .company)

            // If tenant is constructed from id, name, and blocked, encode those fields
            if tenant != nil {
                try container.encodeIfPresent(tenant?.id, forKey: .id)
                try container.encodeIfPresent(tenant?.name, forKey: .name)
                // companyName is not stored in UserTenant, so we skip it
            }
        }
    }
}

struct Role: Codable {
    let id: Int
    let name: String
}

struct ExtendedLoginResponse: Decodable {
    let token: String
    let user: ExtendedUser
}

struct LoginUserTenant: Decodable {
    let id: Int
    let name: String
    let companyId: Int
    let companyName: String
    let blocked: Bool
}

struct ExtendedUser: Decodable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let email: String?
    let tenantId: Int?
    let companyId: Int?
    let company: User.Company?
    let roles: [Role]?
    let permissions: [Permission]?
    let projectPermissions: [Int: [String]]?
    let isSubscriptionOwner: Bool?
    let assignedProjects: [Int]?
    let assignedSubcontractOrders: [Int]?
    let blocked: Bool?
    let createdAt: String?
    let UserRoles: [User.UserRole]?
    let UserPermissions: [User.UserPermission]?
    let tenants: [LoginUserTenant]?
}

struct SelectTenantResponse: Decodable {
    let token: String
    let user: User
}

struct LoginResponse: Decodable {
    let token: String
}

struct Project: Codable, Identifiable {
    let id: Int
    let name: String
    let reference: String
    let logoUrl: String?
    let location: String?
    let projectStatus: String?
    let description: String?
    let tenantId: Int?
}

struct DrawingResponse: Decodable {
    let drawings: [Drawing]
}

struct Drawing: Codable, Identifiable {
    let id: Int
    let title: String
    let number: String
    let projectId: Int
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let revisions: [Revision]
    let company: Company?
    let discipline: String?
    let projectDiscipline: ProjectDiscipline?
    let projectDrawingType: ProjectDrawingType?
    var isOffline: Bool?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case number
        case projectId
        case status
        case createdAt
        case updatedAt
        case revisions
        case company
        case discipline
        case projectDiscipline = "ProjectDiscipline"
        case projectDrawingType = "ProjectDrawingType"
        case isOffline
        case user
    }
}

struct ProjectDiscipline: Codable {
    let name: String?
}

struct ProjectDrawingType: Codable {
    let name: String?
}

struct Company: Codable {
    let id: Int
    let name: String
    let createdAt: String?
    let updatedAt: String?
}

struct Revision: Codable {
    let id: Int
    let drawingId: Int
    let versionNumber: Int
    let notes: String?
    let status: String
    let statusId: Int? // Changed to Int? to handle null values
    let uploadedAt: String?
    let uploadedById: Int?
    let revisionNumber: String?
    let tenantId: Int
    let archived: Bool
    let archivedAt: String?
    let archivedById: Int?
    let archiveReason: String?
    let drawingFiles: [DrawingFile]
    let uploadedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case drawingId
        case versionNumber
        case notes
        case status
        case statusId
        case uploadedAt
        case uploadedById
        case revisionNumber
        case tenantId
        case archived
        case archivedAt
        case archivedById
        case archiveReason
        case drawingFiles
        case uploadedBy
    }
}

struct DrawingFile: Codable {
    let id: Int
    let downloadUrl: String?
    let fileName: String
    let fileType: String
    let createdAt: String?
    var localPath: URL?
}

struct RFIResponse: Decodable {
    let rfis: [RFI]
}

struct RFI: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String?
    let description: String?
    let query: String?
    let status: String?
    let createdAt: String?
    let submittedDate: String?
    let returnDate: String?
    let closedDate: String?
    let projectId: Int
    let submittedBy: UserInfo?
    let managerId: Int?
    let assignedUsers: [AssignedUser]?
    let attachments: [RFIAttachment]?
    let drawings: [RFIDrawing]?
    let responses: [RFIResponseItem]?
    let acceptedResponse: RFIResponseItem?

    struct UserInfo: Codable {
        let id: Int
        let firstName: String
        let lastName: String

        enum CodingKeys: String, CodingKey {
            case id
            case tenants
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            
            let tenants = try container.decodeIfPresent([TenantInfo].self, forKey: .tenants) ?? []
            if let tenant = tenants.first {
                firstName = tenant.firstName
                lastName = tenant.lastName
            } else {
                firstName = "Unknown"
                lastName = "User"
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            let tenant = TenantInfo(firstName: firstName, lastName: lastName)
            try container.encode([tenant], forKey: .tenants)
        }

        struct TenantInfo: Codable {
            let firstName: String
            let lastName: String
        }
    }

    struct AssignedUser: Codable {
        let user: UserInfo
    }

    struct RFIAttachment: Codable {
        let id: Int
        let fileName: String
        let fileUrl: String
        let fileType: String
        let uploadedAt: String
        let downloadUrl: String?
        let uploadedById: Int
        let uploadedBy: UserInfo?
        var localPath: URL?
    }

    struct RFIDrawing: Codable {
        let id: Int
        let number: String
        let title: String
        let revisionNumber: String
        let downloadUrl: String?
    }

    struct RFIResponseItem: Codable {
        let id: Int
        let content: String
        let createdAt: String
        let updatedAt: String?
        let status: String
        let rejectionReason: String?
        let user: UserInfo
        let attachments: [RFIAttachment]?
    }
}

struct FormSubmission: Identifiable, Decodable {
    let id: Int
    let templateId: Int
    let templateTitle: String
    let revisionId: Int
    let status: String
    let submittedAt: String
    let submittedBy: UserInfo
    let responses: [String: FormResponseValue]?
    let fields: [FormField]

    struct UserInfo: Decodable {
        let firstName: String
        let lastName: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case templateId
        case templateTitle
        case revisionId
        case status
        case submittedAt
        case submittedBy
        case responses
        case fields
    }
}

// Custom type to handle different response value types
enum FormResponseValue: Decodable {
    case string(String)
    case stringArray([String])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([String].self) {
            self = .stringArray(arrayValue)
        } else {
            throw DecodingError.typeMismatch(FormResponseValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a String, [String], or null"))
        }
    }
}

struct FormModel: Codable, Identifiable {
    let id: Int
    let title: String
    let reference: String?
    let description: String?
    let tenantId: Int
    let createdAt: String
    let updatedAt: String
    let status: String
    let isArchived: Bool
    let restrictToMainCompany: Bool
    let currentRevision: FormRevision?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case reference
        case description
        case tenantId
        case createdAt
        case updatedAt
        case status
        case isArchived
        case restrictToMainCompany
        case currentRevision
    }
}

struct FormRevision: Codable {
    let id: Int
    let fields: [FormField]
}

struct FormField: Codable {
    let id: String
    let label: String
    let type: String
    let required: Bool
    let options: [String]?
}



struct Document: Codable, Identifiable {
    let id: Int
    let tenantId: Int
    let projectId: Int
    let name: String
    let fileUrl: String?
    let folderId: Int?
    let documentTypeId: Int?
    let projectDocumentTypeId: Int?
    let projectDocumentDisciplineId: Int?
    let metadata: [String: AnyCodable]?
    let createdAt: String?
    let updatedAt: String?
    var isOffline: Bool?
    let revisions: [DocumentRevision]
    let folder: Folder?
    let documentType: DocumentType?
    let projectDocumentType: ProjectDocumentType?
    let projectDocumentDiscipline: ProjectDocumentDiscipline?
    let uploadedBy: User?
    let company: Company?
    let companyId: Int?

    enum CodingKeys: String, CodingKey {
        case id, tenantId, projectId, name, fileUrl, folderId, documentTypeId
        case projectDocumentTypeId = "projectDocumentTypeId"
        case projectDocumentDisciplineId = "projectDocumentDisciplineId"
        case metadata, createdAt, updatedAt, isOffline, revisions, folder
        case documentType
        case projectDocumentType = "ProjectDocumentType"
        case projectDocumentDiscipline = "ProjectDocumentDiscipline"
        case uploadedBy, company, companyId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        tenantId = try container.decode(Int.self, forKey: .tenantId)
        projectId = try container.decode(Int.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl)
        folderId = try container.decodeIfPresent(Int.self, forKey: .folderId)
        documentTypeId = try container.decodeIfPresent(Int.self, forKey: .documentTypeId)
        projectDocumentTypeId = try container.decodeIfPresent(Int.self, forKey: .projectDocumentTypeId)
        projectDocumentDisciplineId = try container.decodeIfPresent(Int.self, forKey: .projectDocumentDisciplineId)
        metadata = try container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isOffline = try container.decodeIfPresent(Bool.self, forKey: .isOffline)
        revisions = try container.decode([DocumentRevision].self, forKey: .revisions)
        folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
        documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType)
        projectDocumentType = try container.decodeIfPresent(ProjectDocumentType.self, forKey: .projectDocumentType)
        projectDocumentDiscipline = try container.decodeIfPresent(ProjectDocumentDiscipline.self, forKey: .projectDocumentDiscipline)
        uploadedBy = try container.decodeIfPresent(User.self, forKey: .uploadedBy)
        company = try container.decodeIfPresent(Company.self, forKey: .company)
        // Handle "<null>" for companyId
        if container.contains(.companyId) {
            if let companyIdString = try? container.decode(String.self, forKey: .companyId), companyIdString == "<null>" {
                companyId = nil
            } else {
                companyId = try container.decodeIfPresent(Int.self, forKey: .companyId)
            }
        } else {
            companyId = nil
        }
    }
}

struct DocumentRevision: Codable, Identifiable {
    let id: Int
    let documentId: Int
    let versionNumber: Int
    let fileUrl: String
    let notes: String?
    let uploadedById: Int?
    let uploadedBy: String?
    let tenantId: Int
    let status: String?
    let statusId: Int?
    let metadata: [String: AnyCodable]?
    let createdAt: String?
    
    let projectDocumentStatus: ProjectDocumentStatus?
    let documentFiles: [DocumentFile]?
    let downloadUrl: String?
}

struct DocumentFile: Codable, Identifiable {
    let id: Int
    let fileName: String
    let fileUrl: String
    let downloadUrl: String?
}

struct Folder: Codable, Identifiable {
    let id: Int
    let name: String
    let isPrivate: Bool
}

struct DocumentType: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ProjectDocumentType: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ProjectDocumentDiscipline: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ProjectDocumentStatus: Codable, Identifiable {
    let id: Int
    let name: String
}

struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
