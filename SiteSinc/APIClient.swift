import Foundation

struct APIClient {
    #if DEBUG
    static let baseURL = "http://localhost:3000/api" // Local development
    #else
    static let baseURL = "https://sitesinc.onrender.com/api" // Production
    #endif
    
    static func login(email: String, password: String, completion: @escaping (Result<(String, User), Error>) -> Void) {
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = ["email": email, "password": password]
        request.httpBody = try? JSONEncoder().encode(params)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Login network error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("Login failed with status: \(statusCode)")
                completion(.failure(NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(statusCode)"])))
                return
            }
            guard let data = data else {
                print("No data returned from login endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let loginResponse = try JSONDecoder().decode(ExtendedLoginResponse.self, from: data)
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
                completion(.success((loginResponse.token, user)))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }

    static func selectTenant(token: String, tenantId: Int, completion: @escaping (Result<(String, User), Error>) -> Void) {
        let url = URL(string: "\(baseURL)/auth/select-tenant")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let params = ["tenantId": tenantId]
        request.httpBody = try? JSONEncoder().encode(params)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Select tenant network error: \(error)")
                completion(.failure(error))
                return
            }
            guard let data = data else {
                print("No data returned from select-tenant endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let response = try JSONDecoder().decode(SelectTenantResponse.self, from: data)
                completion(.success((response.token, response.user)))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }

    static func fetchProjects(token: String, completion: @escaping (Result<[Project], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            guard let projects = try? JSONDecoder().decode([Project].self, from: data) else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            completion(.success(projects))
        }.resume()
    }
    
    static func fetchDrawings(projectId: Int, token: String, completion: @escaping (Result<[Drawing], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/drawings?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw drawings response: \(jsonString)")
            } else {
                print("Failed to convert drawings response to string")
            }
            do {
                let drawingResponse = try JSONDecoder().decode(DrawingResponse.self, from: data)
                let filteredDrawings = drawingResponse.drawings.filter { $0.projectId == projectId }
                completion(.success(filteredDrawings))
            } catch {
                print("Decoding error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    static func fetchRFIs(projectId: Int, token: String, completion: @escaping (Result<[RFI], Error>) -> Void) {
        print("Starting fetchRFIs for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/rfis?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            print("Received response for fetchRFIs")
            if let error = error {
                print("Fetch RFIs error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])))
                return
            }
            guard let data = data else {
                print("No data returned from RFIs endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            print("HTTP Status Code: \(httpResponse.statusCode)")
            do {
                let rfiResponse = try JSONDecoder().decode(RFIResponse.self, from: data)
                let filteredRFIs = rfiResponse.rfis.filter { $0.projectId == projectId }
                print("Successfully decoded \(filteredRFIs.count) RFIs")
                completion(.success(filteredRFIs))
            } catch {
                print("Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(jsonString)")
                }
                completion(.failure(error))
            }
        }.resume()
    }
    
    static func downloadFile(from urlString: String, to localPath: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No file downloaded"])))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: localPath.path) {
                    try FileManager.default.removeItem(at: localPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: localPath)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    static func fetchUsers(projectId: Int, token: String, completion: @escaping (Result<[User], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/users?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Fetch users error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response for users fetch")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            if let data = data, let rawString = String(data: data, encoding: .utf8) {
                print("Raw users response: \(rawString)")
            }
            if httpResponse.statusCode == 304 || httpResponse.statusCode != 200 {
                print("Users fetch returned status \(httpResponse.statusCode)")
                completion(.success([]))
                return
            }
            guard let data = data else {
                print("No data returned from users endpoint")
                completion(.failure(NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "No data returned"])))
                return
            }
            do {
                let userResponse = try JSONDecoder().decode(UserResponse.self, from: data)
                print("Fetched \(userResponse.users.count) users for projectId: \(projectId)")
                completion(.success(userResponse.users))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }

    static func fetchTenants(token: String, completion: @escaping (Result<[Tenant], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/tenants")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Fetch tenants error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let rawData = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No data"
                print("Tenant fetch failed with status \(statusCode), raw data: \(rawData)")
                completion(.failure(NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            guard let data = data else {
                print("No data returned from tenants endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let tenants = try JSONDecoder().decode([Tenant].self, from: data)
                print("Fetched tenants: \(tenants)")
                completion(.success(tenants))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }
    
    static func fetchForms(projectId: Int, token: String, completion: @escaping (Result<[FormModel], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/forms/accessible?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Fetch forms error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let rawData = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No data"
                print("Forms fetch failed with status \(statusCode), raw data: \(rawData)")
                completion(.failure(NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            guard let data = data else {
                print("No data returned from forms endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let forms = try JSONDecoder().decode([FormModel].self, from: data)
                print("Fetched \(forms.count) forms for projectId: \(projectId)")
                completion(.success(forms))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }

    static func fetchFormSubmissions(projectId: Int, token: String, completion: @escaping (Result<[FormSubmission], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/forms/submissions?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Fetch form submissions error: \(error)")
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let rawData = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No data"
                print("Form submissions fetch failed with status \(statusCode), raw data: \(rawData)")
                completion(.failure(NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            guard let data = data else {
                print("No data returned from form submissions endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let submissions = try JSONDecoder().decode([FormSubmission].self, from: data)
                print("Fetched \(submissions.count) form submissions for projectId: \(projectId)")
                completion(.success(submissions))
            } catch {
                print("Decoding error: \(error), Raw data: \(String(data: data, encoding: .utf8) ?? "N/A")")
                completion(.failure(error))
            }
        }.resume()
    }
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
    let versionNumber: Int
    let status: String
    let drawingFiles: [DrawingFile]
    let createdAt: String?
    let revisionNumber: String?
}

struct DrawingFile: Codable {
    let id: Int
    let downloadUrl: String
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
