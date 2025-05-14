import Foundation

struct APIClient {
    #if DEBUG
    static let baseURL = "http://localhost:3000/api" // Local development
    #else
    static let baseURL = "https://sitesinc.onrender.com/api" // Production
    #endif
    
    static func login(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = ["email": email, "password": password]
        request.httpBody = try? JSONEncoder().encode(params)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let loginResponse = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            completion(.success(loginResponse.token))
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
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                struct Response: Decodable {
                    let token: String
                    let user: User
                }
                let response = try JSONDecoder().decode(Response.self, from: data)
                completion(.success((response.token, response.user)))
            } catch {
                print("Decoding error: \(error)")
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
            guard let data = data, let projects = try? JSONDecoder().decode([Project].self, from: data) else {
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
            guard let data = data else {
                print("No data returned from RFIs endpoint")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])))
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
    
    static func fetchForms(projectId: Int, token: String, completion: @escaping (Result<[Form], Error>) -> Void) {
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
                let forms = try JSONDecoder().decode([Form].self, from: data)
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

struct User: Codable, Identifiable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let email: String?
    let tenantId: Int?
    let companyId: Int?
    let company: Company?
    let roles: [String]?
    let permissions: [String]?
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
    }
    
    struct UserRole: Codable {
        let roles: Role
        struct Role: Codable {
            let id: Int
            let name: String
        }
    }
    
    struct UserPermission: Codable {
        let permission: Permission
        struct Permission: Codable {
            let id: Int
            let name: String
        }
    }
    
    struct UserTenant: Codable {
        let userId: Int
        let tenantId: Int
        let createdAt: String?
        let tenant: Tenant
    }
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
            
            // Decode the tenants array and extract firstName and lastName from the first element
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

struct Form: Codable, Identifiable {
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
