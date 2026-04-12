import Foundation
import UIKit

// MARK: - Shared Date Formatters (top-level to avoid generic closure restrictions)
private let iso8601NoFracFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
    return f
}()

private let iso8601FracFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
    return f
}()

struct ErrorResponse: Decodable {
    let message: String?
    let error: String?
}

struct PasswordResetResponse: Decodable {
    let message: String?
}

enum APIError: Error {
    case tokenExpired
    // Permission denied (valid token but insufficient rights)
    case forbidden
    case invalidResponse(statusCode: Int)
    case badRequest(message: String)  // 400 with server error body
    case decodingError(Error)
    case networkError(Error)

    var displayMessage: String {
        switch self {
        case .tokenExpired: return "Session expired. Please sign in again."
        case .forbidden: return "You don’t have permission for this action."
        case .badRequest(let message): return message
        case .invalidResponse(let code):
            if code == 404 { return "Not found." }
            if code >= 500 { return "Server error. Please try again later." }
            return "Request failed (code \(code))."
        case .decodingError: return "Invalid response from server."
        case .networkError(let err): return (err as NSError).localizedDescription
        }
    }
}

struct APIClient {
    #if DEBUG
     static let baseURL = "http://localhost:3000/api"
//   static let baseURL = "https://sitesinc.onrender.com/api"
    #else
    static let baseURL = "https://sitesinc.onrender.com/api"
    #endif
    
    // Optional handler to attempt silent re-auth and return a fresh token for retry.
    // When set, API requests will retry once on 401/403.
    static var authRetryHandler: (() async -> String?)?

    // MARK: - Helper Function for API Requests
    private static func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        return try await performRequest(request, retryOnAuthFailure: true)
    }

    private static func performRequest<T: Decodable>(_ request: URLRequest, retryOnAuthFailure: Bool) async throws -> T {
        do {
            print("🔍 [API] Making request to: \(request.url?.absoluteString ?? "unknown URL")")
            let (data, response) = try await URLSession.shared.data(for: request)

            if T.self == FormModel.self {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Raw JSON response for FormModel decoding at \(request.url?.absoluteString ?? "unknown URL"):\n\(jsonString)")
                }
            }
            
            // Log chat-related responses for debugging
            if T.self == ChatConversationWithMessages.self {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Raw JSON response for ChatConversationWithMessages at \(request.url?.absoluteString ?? "unknown URL"):\n\(jsonString)")
                }
            }
            
            // Log SendMessageResponse for debugging
            if T.self == SendMessageResponse.self {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Raw JSON response for SendMessageResponse at \(request.url?.absoluteString ?? "unknown URL"):\n\(jsonString)")
                }
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.invalidResponse(statusCode: -1)
            }
            
            print("🔍 [API] Response status: \(httpResponse.statusCode), data size: \(data.count) bytes")
            // Shared decoder configured for ISO8601 date strings (with and without fractional seconds)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                if let d = iso8601FracFormatter.date(from: dateString) { return d }
                if let d = iso8601NoFracFormatter.date(from: dateString) { return d }

                // Fallback to common explicit format if needed
                let fallback = DateFormatter()
                fallback.locale = Locale(identifier: "en_US_POSIX")
                fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                if let d = fallback.date(from: dateString) { return d }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
            }
            
            switch httpResponse.statusCode {
            case 200, 201:
                return try decoder.decode(T.self, from: data)
            case 204:
                // Many endpoints don't return a body on 204; fail decoding explicitly
                // Callers that expect empty results should not use performRequest
                throw APIError.invalidResponse(statusCode: 204)
            case 304:
                print("🔍 [API] 304 Not Modified response received")
                // Not Modified - return empty array for conversations if no data
                if T.self == [ChatConversation].self {
                    print("🔍 [API] Returning empty conversations array for 304")
                    return [] as! T
                }
                // For ChatConversationWithMessages, return empty messages array
                if T.self == ChatConversationWithMessages.self {
                    print("🔍 [API] Returning empty ChatConversationWithMessages for 304")
                    let emptyConversation = ChatConversationWithMessages(
                        id: 0,
                        projectId: 0,
                        userId: 0,
                        tenantId: 0,
                        title: nil,
                        createdAt: Date(),
                        updatedAt: Date(),
                        archived: false,
                        messages: []
                    )
                    return emptyConversation as! T
                }
                // For other types, try to decode or return empty
                if data.isEmpty {
                    print("❌ [API] 304 response with empty data for unsupported type")
                    throw APIError.invalidResponse(statusCode: 304)
                }
                print("🔍 [API] Attempting to decode 304 response data")
                return try decoder.decode(T.self, from: data)
            case 401, 403:
                if retryOnAuthFailure, let retryHandler = authRetryHandler {
                    if let newToken = await retryHandler() {
                        var retryRequest = request
                        retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        return try await performRequest(retryRequest, retryOnAuthFailure: false)
                    }
                }
                if httpResponse.statusCode == 401 {
                    throw APIError.tokenExpired
                }
                throw APIError.forbidden
            case 400:
                if let errResponse = try? decoder.decode(ErrorResponse.self, from: data),
                   let msg = errResponse.error ?? errResponse.message, !msg.isEmpty {
                    throw APIError.badRequest(message: msg)
                }
                throw APIError.invalidResponse(statusCode: 400)
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
        
        // The backend returns tenants with nested tenant/company objects.
        // Decode them directly into `User.UserTenant` (which already supports both shapes).
        let userTenants: [User.UserTenant] = loginResponse.user.tenants ?? []
        
        let user = User(
            id: loginResponse.user.id,
            firstName: loginResponse.user.firstName,
            lastName: loginResponse.user.lastName,
            email: loginResponse.user.email,
            tenantId: loginResponse.user.tenantId,
            companyId: loginResponse.user.companyId,
            company: loginResponse.user.company,
            roles: [], // Backend no longer sends roles in login response - fetch via /user-details
            permissions: [], // Backend no longer sends permissions in login response - fetch via /user-details
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
        let url = URL(string: "\(baseURL)/auth/request-reset")!
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

        // Custom request to allow retry on 500 due to unique sessionToken collision (backend bug)
        func tryOnce() async throws -> SelectTenantResponse {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(statusCode: -1) }
            switch http.statusCode {
            case 200, 201:
                return try JSONDecoder().decode(SelectTenantResponse.self, from: data)
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            case 500:
                // Inspect body; if Prisma P2002/unique sessionToken, treat as retryable
                if let body = String(data: data, encoding: .utf8), body.localizedCaseInsensitiveContains("P2002") || body.localizedCaseInsensitiveContains("sessionToken") {
                    throw NSError(domain: "SelectTenantRetryable", code: 500, userInfo: [NSLocalizedDescriptionKey: body])
                }
                throw APIError.invalidResponse(statusCode: 500)
            default:
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
        }

        // Retry with small backoff to ensure JWT iat differs
        do {
            let resp = try await tryOnce()
            return (resp.token, resp.user)
        } catch {
            // Only retry for the specific retryable marker
            if (error as NSError).domain == "SelectTenantRetryable" {
                try? await Task.sleep(nanoseconds: 1_200_000_000) // ~1.2s
                let resp = try await tryOnce()
                return (resp.token, resp.user)
            }
            throw error
        }
    }

    static func fetchUserDetails(token: String) async throws -> UserDetailsResponse {
        let url = URL(string: "\(baseURL)/auth/user-details")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: UserDetailsResponse = try await performRequest(request)
        return response
    }

    static func fetchProjects(token: String) async throws -> [Project] {
        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await performRequest(request)
    }

    // MARK: - Assets API
    struct AssetUser: Codable {
        let id: Int
        let email: String?
        let firstName: String?
        let lastName: String?
    }

    struct AssetGroupRef: Codable {
        let id: Int
        let name: String?
        let sortOrder: Int?
        let isActive: Bool?
    }

    struct Asset: Codable {
        let id: Int
        let tenantId: Int?
        let createdById: Int?
        let assignedToUserId: Int?
        let assetNumberInt: Int?
        let assetNumber: String
        let barcodeOrQrCode: String?
        let assetGroupId: Int?
        let departmentId: Int?
        let ownershipStatusId: Int?
        let assetStatusId: Int?
        let description: String?
        let make: String?
        let model: String?
        let year: Int?
        let serialNumber: String?
        let registrationNumber: String?
        let purchasePrice: Double?
        let purchaseDate: Date?
        let disposalDate: Date?
        let tax: Double?
        let createdAt: Date?
        let updatedAt: Date?
        let createdBy: AssetUser?
        let assignedTo: AssetUser?
        let assetGroup: AssetGroupRef?
        let department: AssetGroupRef?
        let ownershipStatus: AssetGroupRef?
        let assetStatus: AssetGroupRef?

        enum CodingKeys: String, CodingKey {
            case id, tenantId, createdById, assignedToUserId, assetNumberInt, assetNumber
            case barcodeOrQrCode, assetGroupId, departmentId, ownershipStatusId, assetStatusId
            case description, make, model, year, serialNumber, registrationNumber
            case purchasePrice, purchaseDate, disposalDate, tax, createdAt, updatedAt
            case createdBy, assignedTo, assetGroup, department, ownershipStatus, assetStatus
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            tenantId = try c.decodeIfPresent(Int.self, forKey: .tenantId)
            createdById = try c.decodeIfPresent(Int.self, forKey: .createdById)
            assignedToUserId = try c.decodeIfPresent(Int.self, forKey: .assignedToUserId)
            assetNumberInt = try c.decodeIfPresent(Int.self, forKey: .assetNumberInt)
            assetNumber = try c.decode(String.self, forKey: .assetNumber)
            barcodeOrQrCode = try c.decodeIfPresent(String.self, forKey: .barcodeOrQrCode)
            assetGroupId = try c.decodeIfPresent(Int.self, forKey: .assetGroupId)
            departmentId = try c.decodeIfPresent(Int.self, forKey: .departmentId)
            ownershipStatusId = try c.decodeIfPresent(Int.self, forKey: .ownershipStatusId)
            assetStatusId = try c.decodeIfPresent(Int.self, forKey: .assetStatusId)
            description = try c.decodeIfPresent(String.self, forKey: .description)
            make = try c.decodeIfPresent(String.self, forKey: .make)
            model = try c.decodeIfPresent(String.self, forKey: .model)
            year = try c.decodeIfPresent(Int.self, forKey: .year)
            serialNumber = try c.decodeIfPresent(String.self, forKey: .serialNumber)
            registrationNumber = try c.decodeIfPresent(String.self, forKey: .registrationNumber)
            purchasePrice = Self.decodeDecimal(c, forKey: .purchasePrice)
            purchaseDate = (try? c.decodeIfPresent(Date.self, forKey: .purchaseDate)) ?? nil
            disposalDate = (try? c.decodeIfPresent(Date.self, forKey: .disposalDate)) ?? nil
            tax = Self.decodeDecimal(c, forKey: .tax)
            createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
            updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? nil
            createdBy = try c.decodeIfPresent(AssetUser.self, forKey: .createdBy)
            assignedTo = try c.decodeIfPresent(AssetUser.self, forKey: .assignedTo)
            assetGroup = try c.decodeIfPresent(AssetGroupRef.self, forKey: .assetGroup)
            department = try c.decodeIfPresent(AssetGroupRef.self, forKey: .department)
            ownershipStatus = try c.decodeIfPresent(AssetGroupRef.self, forKey: .ownershipStatus)
            assetStatus = try c.decodeIfPresent(AssetGroupRef.self, forKey: .assetStatus)
        }

        private static func decodeDecimal(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
            if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d }
            return nil
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(tenantId, forKey: .tenantId)
            try c.encodeIfPresent(createdById, forKey: .createdById)
            try c.encodeIfPresent(assignedToUserId, forKey: .assignedToUserId)
            try c.encodeIfPresent(assetNumberInt, forKey: .assetNumberInt)
            try c.encode(assetNumber, forKey: .assetNumber)
            try c.encodeIfPresent(barcodeOrQrCode, forKey: .barcodeOrQrCode)
            try c.encodeIfPresent(assetGroupId, forKey: .assetGroupId)
            try c.encodeIfPresent(departmentId, forKey: .departmentId)
            try c.encodeIfPresent(ownershipStatusId, forKey: .ownershipStatusId)
            try c.encodeIfPresent(assetStatusId, forKey: .assetStatusId)
            try c.encodeIfPresent(description, forKey: .description)
            try c.encodeIfPresent(make, forKey: .make)
            try c.encodeIfPresent(model, forKey: .model)
            try c.encodeIfPresent(year, forKey: .year)
            try c.encodeIfPresent(serialNumber, forKey: .serialNumber)
            try c.encodeIfPresent(registrationNumber, forKey: .registrationNumber)
            try c.encodeIfPresent(purchasePrice, forKey: .purchasePrice)
            try c.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
            try c.encodeIfPresent(disposalDate, forKey: .disposalDate)
            try c.encodeIfPresent(tax, forKey: .tax)
            try c.encodeIfPresent(createdAt, forKey: .createdAt)
            try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
            try c.encodeIfPresent(createdBy, forKey: .createdBy)
            try c.encodeIfPresent(assignedTo, forKey: .assignedTo)
            try c.encodeIfPresent(assetGroup, forKey: .assetGroup)
            try c.encodeIfPresent(department, forKey: .department)
            try c.encodeIfPresent(ownershipStatus, forKey: .ownershipStatus)
            try c.encodeIfPresent(assetStatus, forKey: .assetStatus)
        }

        /// True if the asset can be checked out: not assigned and status is "Available" (from settings). Any other status (Broken, Stolen, Maintenance, etc.) does not allow check-out.
        var isEligibleForCheckOut: Bool {
            guard assignedToUserId == nil else { return false }
            let name = assetStatus?.name?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            return name.isEmpty || name == "available"
        }

        /// Label for check-out: "Available" only when status is Available; otherwise show the actual status from settings (e.g. "Broken"); "In use" when assigned.
        var checkOutEligibilityLabel: String {
            if assignedToUserId != nil { return "In use" }
            let name = assetStatus?.name?.trimmingCharacters(in: .whitespaces) ?? ""
            if name.isEmpty || name.lowercased() == "available" { return "Available" }
            return name
        }
    }

    static func fetchAssetByCode(code: String, token: String) async throws -> Asset {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        let url = URL(string: "\(baseURL)/assets/by-code?code=\(encoded)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequest(request)
    }

    /// List assets. Optional search (partial match on number, description, make, model, etc.). Optional availability: "available" or "in_use".
    static func fetchAssets(search: String? = nil, availability: String? = nil, token: String) async throws -> [Asset] {
        var components = URLComponents(string: "\(baseURL)/assets")!
        var queryItems: [URLQueryItem] = []
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: s))
        }
        if let a = availability {
            queryItems.append(URLQueryItem(name: "availability", value: a))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        let url = components.url!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequest(request)
    }

    /// Builds multipart body for asset check-out (userId + photo) or check-in (photo only).
    private static func assetCheckMultipartBody(userId: Int?, photoData: Data, boundary: String, isCheckOut: Bool) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        if let userId = userId {
            body.append(boundaryPrefix.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(userId)\r\n".data(using: .utf8)!)
        }
        let fileName = isCheckOut ? "check-out.jpg" : "check-in.jpg"
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(photoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func checkOutAsset(assetId: Int, userId: Int, photoData: Data, token: String) async throws -> Asset {
        let url = URL(string: "\(baseURL)/assets/\(assetId)/check-out")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = assetCheckMultipartBody(userId: userId, photoData: photoData, boundary: boundary, isCheckOut: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let d = iso8601FracFormatter.date(from: dateString) { return d }
            if let d = iso8601NoFracFormatter.date(from: dateString) { return d }
            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            if let d = fallback.date(from: dateString) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        switch httpResponse.statusCode {
        case 200, 201:
            return try decoder.decode(Asset.self, from: data)
        case 400, 403:
            if let errResponse = try? decoder.decode(ErrorResponse.self, from: data),
               let msg = errResponse.error ?? errResponse.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            if httpResponse.statusCode == 403 {
                throw APIError.forbidden
            }
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        case 401:
            throw APIError.tokenExpired
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    static func checkInAsset(assetId: Int, photoData: Data, token: String) async throws -> Asset {
        let url = URL(string: "\(baseURL)/assets/\(assetId)/check-in")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = assetCheckMultipartBody(userId: nil, photoData: photoData, boundary: boundary, isCheckOut: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let d = iso8601FracFormatter.date(from: dateString) { return d }
            if let d = iso8601NoFracFormatter.date(from: dateString) { return d }
            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            if let d = fallback.date(from: dateString) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        switch httpResponse.statusCode {
        case 200, 201:
            return try decoder.decode(Asset.self, from: data)
        case 400, 403:
            if let errResponse = try? decoder.decode(ErrorResponse.self, from: data),
               let msg = errResponse.error ?? errResponse.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            if httpResponse.statusCode == 403 {
                throw APIError.forbidden
            }
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        case 401:
            throw APIError.tokenExpired
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
    
    static func fetchDrawings(projectId: Int, token: String) async throws -> [Drawing] {
        let url = URL(string: "\(baseURL)/drawings?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let drawingResponse: DrawingResponse = try await performRequest(request)
        return drawingResponse.drawings.filter { $0.projectId == projectId }
    }
    
    // MARK: - Drawing Thumbnails
    struct ThumbnailResponse: Codable {
        let url: String?
        let cached: Bool?
        let needsGeneration: Bool?
    }
    
    static func fetchDrawingThumbnail(fileId: Int, token: String) async throws -> ThumbnailResponse {
        let url = URL(string: "\(baseURL)/drawings/thumbnail/\(fileId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return try await performRequest(request)
    }

    // MARK: - Drawing references (match web PdfViewer.tsx)
    static func fetchDrawingReferences(drawingId: Int, fileId: Int, token: String) async throws -> [DrawingReference] {
        // Mirrors web: GET /drawings/:drawingId/references?fileId=...
        do {
            let url = URL(string: "\(baseURL)/drawings/\(drawingId)/references?fileId=\(fileId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            struct Envelope: Codable { let references: [DrawingReference]? }
            let res: Envelope = try await performRequest(request)
            return res.references ?? []
        } catch APIError.invalidResponse(let status) where status == 404 {
            // Fallback: proxy through API route if backend mounts routes differently
            let url = URL(string: "\(baseURL)/drawings/\(drawingId)/references?fileId=\(fileId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            struct Envelope2: Codable { let references: [DrawingReference]? }
            let res: Envelope2 = try await performRequest(request)
            return res.references ?? []
        }
    }

    // MARK: - Markups API
    static func fetchDrawingMarkups(drawingId: Int, drawingFileId: Int, page: Int?, token: String, showPublishedOnly: Bool? = nil, showMyMarkupsOnly: Bool? = nil) async throws -> [Markup] {
        // Try known route variants in priority order (match web app behavior)
        // A) /markup/markups?drawingId=&drawingFileId=&page=...
        if let urlA = URL(string: "\(baseURL)/markup/markups") {
            var c = URLComponents(url: urlA, resolvingAgainstBaseURL: false)!
            var q = [
                URLQueryItem(name: "drawingId", value: String(drawingId)),
                URLQueryItem(name: "drawingFileId", value: String(drawingFileId))
            ]
            if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
            if let v = showPublishedOnly { q.append(URLQueryItem(name: "showPublishedOnly", value: v ? "true" : "false")) }
            if let v = showMyMarkupsOnly { q.append(URLQueryItem(name: "showMyMarkupsOnly", value: v ? "true" : "false")) }
            c.queryItems = q
            var req = URLRequest(url: c.url!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                struct Env: Codable { let markups: [Markup] }
                let res: Env = try await performRequest(req)
                return res.markups
            } catch APIError.invalidResponse(let status) where status == 404 { }
        }

        // B) /markups/markups?drawingId=&drawingFileId=&page=...
        if let urlB = URL(string: "\(baseURL)/markups/markups") {
            var c = URLComponents(url: urlB, resolvingAgainstBaseURL: false)!
            var q = [
                URLQueryItem(name: "drawingId", value: String(drawingId)),
                URLQueryItem(name: "drawingFileId", value: String(drawingFileId))
            ]
            if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
            if let v = showPublishedOnly { q.append(URLQueryItem(name: "showPublishedOnly", value: v ? "true" : "false")) }
            if let v = showMyMarkupsOnly { q.append(URLQueryItem(name: "showMyMarkupsOnly", value: v ? "true" : "false")) }
            c.queryItems = q
            var req = URLRequest(url: c.url!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                struct Env: Codable { let markups: [Markup] }
                let res: Env = try await performRequest(req)
                return res.markups
            } catch APIError.invalidResponse(let status) where status == 404 { }
        }

        // C) /drawings/:drawingId/markups?fileId=... (fallback)
        if let urlC = URL(string: "\(baseURL)/drawings/\(drawingId)/markups") {
            var c = URLComponents(url: urlC, resolvingAgainstBaseURL: false)!
            var q = [URLQueryItem(name: "fileId", value: String(drawingFileId))]
            if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
            if let v = showPublishedOnly { q.append(URLQueryItem(name: "showPublishedOnly", value: v ? "true" : "false")) }
            if let v = showMyMarkupsOnly { q.append(URLQueryItem(name: "showMyMarkupsOnly", value: v ? "true" : "false")) }
            c.queryItems = q
            var req = URLRequest(url: c.url!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            struct EnvC: Codable { let markups: [Markup] }
            let res: EnvC = try await performRequest(req)
            return res.markups
        }
        // If all variants failed, surface an error instead of falling through
        throw APIError.invalidResponse(statusCode: 404)
    }

    static func createMarkup(token: String, body: CreateMarkupRequest) async throws -> Markup {
        // Try variants in order (match web app behavior)
        // 1) POST /markup/markups
        if let url1 = URL(string: "\(baseURL)/markup/markups") {
            var req = URLRequest(url: url1)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
            do {
                struct Env: Codable { let markup: Markup }
                let res: Env = try await performRequest(req)
                return res.markup
            } catch APIError.invalidResponse(let status) where status == 404 { }
        }

        // 2) POST /markups/markups
        if let url2 = URL(string: "\(baseURL)/markups/markups") {
            var req = URLRequest(url: url2)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
            do {
                struct Env: Codable { let markup: Markup }
                let res: Env = try await performRequest(req)
                return res.markup
            } catch APIError.invalidResponse(let status) where status == 404 { }
        }

        // 3) POST /drawings/:drawingId/markups (fallback)
        if let url3 = URL(string: "\(baseURL)/drawings/\(body.drawingId)/markups") {
            var req = URLRequest(url: url3)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
            do {
                struct Env: Codable { let markup: Markup }
                let res: Env = try await performRequest(req)
                return res.markup
            } catch APIError.invalidResponse(let status) where status == 404 { }
        }

        // 4) As last resort, error
        throw APIError.invalidResponse(statusCode: 404)
    }

    static func deleteMarkup(token: String, markupId: Int) async throws {
        // Try /markup/markups/:id first (matches web app logs), then fallbacks
        func tryDelete(_ url: URL) async throws {
            print("🗑️ [DEBUG] APIClient.deleteMarkup - URL: \(url)")
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(statusCode: -1) }
            print("🗑️ [DEBUG] APIClient.deleteMarkup - Response status: \(http.statusCode)")
            if (200...299).contains(http.statusCode) { return }
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }

        if let u1 = URL(string: "\(baseURL)/markup/markups/\(markupId)") {
            do { try await tryDelete(u1); return } catch APIError.invalidResponse(let s) where s == 404 { }
        }
        if let u2 = URL(string: "\(baseURL)/markups/markups/\(markupId)") {
            do { try await tryDelete(u2); return } catch APIError.invalidResponse(let s) where s == 404 { }
        }
        let u3 = URL(string: "\(baseURL)/markups/\(markupId)")!
        try await tryDelete(u3)
    }

    static func publishMarkup(token: String, markupId: Int) async throws -> Markup? {
        func tryRequest(_ req: URLRequest) async throws -> Markup? {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            if http.statusCode == 401 { throw APIError.tokenExpired }
            if http.statusCode == 403 { throw APIError.forbidden }
            if (200...299).contains(http.statusCode) {
                // Try to decode either envelope or raw markup. If body is empty (e.g., 204), return nil to signal success without payload.
                if data.isEmpty { return nil }
                if let env = try? JSONDecoder().decode([String: Markup].self, from: data), let m = env["markup"] {
                    return m
                }
                if let m = try? JSONDecoder().decode(Markup.self, from: data) {
                    return m
                }
                // Body might be something else but still success. Treat as success without payload.
                return nil
            }
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }

        // Try PATCH /markup/markups/:id
        if let url1 = URL(string: "\(baseURL)/markup/markups/\(markupId)") {
            var req = URLRequest(url: url1)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["status": "PUBLISHED"]) 
            do { if let m = try await tryRequest(req) { return m } } catch APIError.invalidResponse(let status) where status == 404 || status == 405 || status == 500 { }
        }
        // Try POST /markup/markups/:id/publish
        if let url2 = URL(string: "\(baseURL)/markup/markups/\(markupId)/publish") {
            var req = URLRequest(url: url2)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do { if let m = try await tryRequest(req) { return m } } catch APIError.invalidResponse(let status) where status == 404 || status == 405 || status == 500 { }
        }
        // Try POST /markups/markups/:id/publish
        if let url3a = URL(string: "\(baseURL)/markups/markups/\(markupId)/publish") {
            var req = URLRequest(url: url3a)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do { if let m = try await tryRequest(req) { return m } } catch APIError.invalidResponse(let status) where status == 404 || status == 405 || status == 500 { }
        }
        // POST /markups/:id/publish (final fallback)
        let url3 = URL(string: "\(baseURL)/markups/\(markupId)/publish")!
        var req3 = URLRequest(url: url3)
        req3.httpMethod = "POST"
        req3.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req3.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await tryRequest(req3)
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
    
    static func fetchRFI(projectId: Int, rfiId: Int, token: String) async throws -> RFI {
        // Try project-scoped detail endpoint first
        if let url = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)") {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let resp: RFIDetailResponse = try await performRequest(req)
                return resp.rfi
            } catch APIError.invalidResponse(let status) where status == 404 {
                // fall through to legacy route
            }
        }
        // Fallback legacy endpoint returning RFI directly
        let legacy = URL(string: "\(baseURL)/rfis/\(rfiId)")!
        var legacyReq = URLRequest(url: legacy)
        legacyReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(legacyReq)
    }

    static func fetchPermits(projectId: Int, token: String) async throws -> [Permit] {
        let url = URL(string: "\(baseURL)/permits?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let permits: [Permit] = try await performRequest(request)
        return permits.filter { $0.projectId == projectId }
    }

    static func fetchPermitTypes(projectId: Int, token: String) async throws -> [PermitTypeListItem] {
        let url = URL(string: "\(baseURL)/permits/types?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }

    static func createPermit(
        projectId: Int,
        permitTypeId: Int,
        token: String,
        locationId: Int? = nil,
        dueDate: Date? = nil,
        worksDate: Date? = nil,
        validUntil: Date? = nil,
        formData: [String: Any]? = nil
    ) async throws -> Permit {
        let url = URL(string: "\(baseURL)/permits")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "projectId": projectId,
            "permitTypeId": permitTypeId
        ]
        if let locationId = locationId { body["locationId"] = locationId }
        let iso = ISO8601DateFormatter()
        if let dueDate = dueDate { body["dueDate"] = iso.string(from: dueDate) }
        if let worksDate = worksDate { body["worksDate"] = iso.string(from: worksDate) }
        if let validUntil = validUntil { body["validUntil"] = iso.string(from: validUntil) }
        if let formData = formData, !formData.isEmpty { body["formData"] = formData }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request)
    }

    static func updateRFIStatus(projectId: Int, rfiId: Int, status: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["status": status]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
    
    static func submitRFIResponse(projectId: Int, rfiId: Int, content: String, token: String) async throws {
        // Try project-scoped route first
        if let projectUrl = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)/responses") {
            var req = URLRequest(url: projectUrl)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["content": content])
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse {
                if http.statusCode == 401 { throw APIError.tokenExpired }
                if http.statusCode == 403 { throw APIError.forbidden }
                if (200...201).contains(http.statusCode) { return }
                if http.statusCode != 404 { throw APIError.invalidResponse(statusCode: http.statusCode) }
            }
        }
        // Fallback to legacy route without project scope
        let legacyUrl = URL(string: "\(baseURL)/rfis/\(rfiId)/responses")!
        var legacyReq = URLRequest(url: legacyUrl)
        legacyReq.httpMethod = "POST"
        legacyReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        legacyReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        legacyReq.httpBody = try JSONEncoder().encode(["content": content])
        let (_, legacyRes) = try await URLSession.shared.data(for: legacyReq)
        guard let legacyHttp = legacyRes as? HTTPURLResponse, (200...201).contains(legacyHttp.statusCode) else {
            if (legacyRes as? HTTPURLResponse)?.statusCode == 401 { throw APIError.tokenExpired }
            if (legacyRes as? HTTPURLResponse)?.statusCode == 403 { throw APIError.forbidden }
            throw APIError.invalidResponse(statusCode: (legacyRes as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
    
    static func reviewRFIResponse(projectId: Int, rfiId: Int, responseId: Int, status: String, rejectionReason: String? = nil, token: String) async throws {
        // First try project-scoped unified endpoint
        if let url = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)/responses/\(responseId)") {
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["status": status]
            if let reason = rejectionReason { body["rejectionReason"] = reason }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse {
                if http.statusCode == 401 { throw APIError.tokenExpired }
                if http.statusCode == 403 { throw APIError.forbidden }
                if http.statusCode == 200 { return }
                if http.statusCode != 404 { throw APIError.invalidResponse(statusCode: http.statusCode) }
            }
        }
        // Fallback to legacy accept/reject routes
        if status.lowercased() == "approved" {
            let acceptUrl = URL(string: "\(baseURL)/rfis/\(rfiId)/responses/\(responseId)/accept")!
            var req = URLRequest(url: acceptUrl)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
                if (res as? HTTPURLResponse)?.statusCode == 401 { throw APIError.tokenExpired }
                if (res as? HTTPURLResponse)?.statusCode == 403 { throw APIError.forbidden }
                throw APIError.invalidResponse(statusCode: (res as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return
        } else if status.lowercased() == "rejected" {
            let rejectUrl = URL(string: "\(baseURL)/rfis/\(rfiId)/responses/reject")!
            var req = URLRequest(url: rejectUrl)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["reason": rejectionReason ?? ""]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
                if (res as? HTTPURLResponse)?.statusCode == 401 { throw APIError.tokenExpired }
                if (res as? HTTPURLResponse)?.statusCode == 403 { throw APIError.forbidden }
                throw APIError.invalidResponse(statusCode: (res as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return
        }
        throw APIError.invalidResponse(statusCode: -1)
    }
    
    static func closeRFI(projectId: Int, rfiId: Int, token: String) async throws {
        // Try project-scoped endpoint
        if let url = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)") {
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["status": "CLOSED"]) 
            let (_, res) = try await URLSession.shared.data(for: req)
            if let http = res as? HTTPURLResponse {
                if http.statusCode == 401 { throw APIError.tokenExpired }
                if http.statusCode == 403 { throw APIError.forbidden }
                if http.statusCode == 200 { return }
                if http.statusCode != 404 { throw APIError.invalidResponse(statusCode: http.statusCode) }
            }
        }
        // Fallback to legacy endpoint
        let legacyUrl = URL(string: "\(baseURL)/rfis/\(rfiId)")!
        var legacyReq = URLRequest(url: legacyUrl)
        legacyReq.httpMethod = "PUT"
        legacyReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        legacyReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        legacyReq.httpBody = try JSONSerialization.data(withJSONObject: ["status": "CLOSED"])
        let (_, legacyRes) = try await URLSession.shared.data(for: legacyReq)
        guard let legacyHttp = legacyRes as? HTTPURLResponse, legacyHttp.statusCode == 200 else {
            if (legacyRes as? HTTPURLResponse)?.statusCode == 401 { throw APIError.tokenExpired }
            if (legacyRes as? HTTPURLResponse)?.statusCode == 403 { throw APIError.forbidden }
            throw APIError.invalidResponse(statusCode: (legacyRes as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
    
    // MARK: - Log API Methods
    
    static func fetchLogs(projectId: Int, token: String) async throws -> [Log] {
        print("Starting fetchLogs for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Debug: Print raw response
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response for fetchLogs:\n\(jsonString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            switch httpResponse.statusCode {
            case 200:
                // Some servers may return 200 with an empty body when there are no logs
                if data.isEmpty {
                    print("No logs returned (empty body). Treating as empty list.")
                    return []
                }
                let logResponse: LogResponse = try JSONDecoder().decode(LogResponse.self, from: data)
                print("Successfully decoded \(logResponse.logs.count) logs")
                return logResponse.logs
            case 204:
                // No Content -> return empty list rather than attempting to decode
                print("No Content (204) for logs. Returning empty list.")
                return []
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
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
    
    static func fetchLog(projectId: Int, logId: Int, token: String) async throws -> Log {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let logDetailResponse: LogDetailResponse = try await performRequest(request)
        return logDetailResponse.log
    }
    
    static func createLog(projectId: Int, logData: CreateLogRequest, token: String) async throws -> Log {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(logData)
        
        let logDetailResponse: LogDetailResponse = try await performRequest(request)
        return logDetailResponse.log
    }
    
    static func updateLog(projectId: Int, logId: Int, logData: CreateLogRequest, token: String) async throws -> Log {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(logData)
        
        let logDetailResponse: LogDetailResponse = try await performRequest(request)
        return logDetailResponse.log
    }
    
    static func submitLogResponse(projectId: Int, logId: Int, response: String, accepted: Bool = false, attachments: [Data] = [], attachmentNames: [String] = [], token: String) async throws {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Use multipart form data to support file attachments
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        
        // Add response text
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(response)\r\n".data(using: .utf8)!)
        
        // Add accepted flag
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"accepted\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(accepted)\r\n".data(using: .utf8)!)
        
        // Add attachments
        for (index, attachmentData) in attachments.enumerated() {
            let fileName = index < attachmentNames.count ? attachmentNames[index] : "photo_\(UUID().uuidString).jpg"
            body.append(boundaryPrefix.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"attachments\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(attachmentData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (_, httpResponse) = try await URLSession.shared.data(for: request)
        
        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        
        switch response.statusCode {
        case 200, 201:
            return
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: response.statusCode)
        }
    }
    
    static func acceptLogResponse(projectId: Int, logId: Int, responseId: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)/responses/\(responseId)/accept")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, httpResponse) = try await URLSession.shared.data(for: request)
        
        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        
        switch response.statusCode {
        case 200, 201:
            return
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: response.statusCode)
        }
    }
    
    static func fetchLogResponses(projectId: Int, logId: Int, token: String) async throws -> [Log.ResponseItem] {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)/responses")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response for fetchLogResponses(\(logId)):\n\(jsonString)")
            }
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(statusCode: -1) }
            switch http.statusCode {
            case 200:
                if data.isEmpty { return [] }
                let decoded: LogResponsesResponse = try JSONDecoder().decode(LogResponsesResponse.self, from: data)
                return decoded.responses
            case 204:
                return []
            case 404:
                // Treat missing route or not-found as no responses for robustness
                return []
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            default:
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
        } catch let e as APIError {
            throw e
        } catch let e as DecodingError {
            throw APIError.decodingError(e)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    static func fetchLogSettings(projectId: Int, token: String) async throws -> LogSettings {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/settings")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await performRequest(request)
    }
    
    // MARK: - Inspection API Methods
    
    static func fetchInspections(projectId: Int, token: String) async throws -> [Inspection] {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response for fetchInspections:\n\(jsonString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            switch httpResponse.statusCode {
            case 200:
                if data.isEmpty {
                    print("No inspections returned (empty body). Treating as empty list.")
                    return []
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let inspectionResponse: InspectionResponse = try decoder.decode(InspectionResponse.self, from: data)
                    print("Successfully decoded \(inspectionResponse.inspections.count) inspections")
                    return inspectionResponse.inspections
                } catch {
                    print("❌ Decoding error: \(error)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        case .typeMismatch(let type, let context):
                            print("Type mismatch for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        case .valueNotFound(let type, let context):
                            print("Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        case .dataCorrupted(let context):
                            print("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)")
                        @unknown default:
                            print("Unknown decoding error: \(decodingError)")
                        }
                    }
                    throw error
                }
            case 204:
                print("No Content (204) for inspections. Returning empty list.")
                return []
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
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
    
    static func fetchInspection(projectId: Int, inspectionId: Int, token: String) async throws -> Inspection {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let inspectionDetailResponse: InspectionDetailResponse = try await performRequest(request)
        return inspectionDetailResponse.inspection
    }
    
    static func createInspection(projectId: Int, inspectionData: CreateInspectionRequest, token: String) async throws -> Inspection {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(inspectionData)
        
        let inspectionDetailResponse: InspectionDetailResponse = try await performRequest(request)
        return inspectionDetailResponse.inspection
    }
    
    static func fetchProjectInspectionTemplates(projectId: Int, token: String) async throws -> ProjectInspectionTemplatesResponse {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspection-templates")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await performRequest(request)
    }
    
    static func submitStageResult(projectId: Int, inspectionId: Int, stageId: Int, status: String, notes: String?, token: String) async throws -> InspectionStageResult {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/result")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct StageResultRequest: Codable {
            let status: String
            let notes: String?
        }
        
        let requestBody = StageResultRequest(status: status, notes: notes)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        struct StageResultResponse: Decodable {
            let stageResult: InspectionStageResult
        }
        
        let response: StageResultResponse = try await performRequest(request)
        return response.stageResult
    }
    
    static func updateStageResult(projectId: Int, inspectionId: Int, stageId: Int, status: String, notes: String?, token: String) async throws -> InspectionStageResult {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/result")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct StageResultRequest: Codable {
            let status: String
            let notes: String?
        }
        
        let requestBody = StageResultRequest(status: status, notes: notes)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        struct StageResultResponse: Decodable {
            let stageResult: InspectionStageResult
        }
        
        let response: StageResultResponse = try await performRequest(request)
        return response.stageResult
    }
    
    static func fetchStagePhotos(projectId: Int, inspectionId: Int, stageId: Int, token: String) async throws -> [InspectionStagePhoto] {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/photos")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        struct PhotosResponse: Decodable {
            let photos: [InspectionStagePhoto]
        }
        
        let response: PhotosResponse = try await performRequest(request)
        return response.photos
    }
    
    static func fetchStageActivity(projectId: Int, inspectionId: Int, stageId: Int, token: String) async throws -> [StageActivity] {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/activity")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        struct ActivityResponse: Decodable {
            let activities: [StageActivity]
        }
        
        let response: ActivityResponse = try await performRequest(request)
        return response.activities
    }
    
    /// Creates a defect and log together for an inspection stage, properly linking them
    /// This is used when marking an inspection item as "NO" and creating a snag to track it
    static func createDefectLog(
        projectId: Int,
        inspectionId: Int,
        stageId: Int,
        title: String?,
        description: String?,
        defectDescription: String?,
        assigneeId: Int?,
        dueDate: String?,
        typeId: Int?,
        statusId: Int?,
        priorityId: Int?,
        tradeId: Int?,
        locationId: Int?,
        token: String
    ) async throws -> CreateDefectLogResponse {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/create-defect-log")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let description = description { body["description"] = description }
        if let defectDescription = defectDescription { body["defectDescription"] = defectDescription }
        if let assigneeId = assigneeId { body["assigneeId"] = assigneeId }
        if let dueDate = dueDate { body["dueDate"] = dueDate }
        if let typeId = typeId { body["typeId"] = typeId }
        if let statusId = statusId { body["statusId"] = statusId }
        if let priorityId = priorityId { body["priorityId"] = priorityId }
        if let tradeId = tradeId { body["tradeId"] = tradeId }
        if let locationId = locationId { body["locationId"] = locationId }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await performRequest(request)
    }
    
    static func uploadStagePhoto(projectId: Int, inspectionId: Int, stageId: Int, imageData: Data, fileName: String, caption: String?, latitude: Double?, longitude: Double?, accuracy: Double?, locationTimestamp: Date?, token: String) async throws -> InspectionStagePhoto {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/photos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add caption if provided
        if let caption = caption {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append(caption.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add location data if provided
        if let latitude = latitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"latitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(latitude)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let longitude = longitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"longitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(longitude)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let accuracy = accuracy {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"accuracy\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(accuracy)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let locationTimestamp = locationTimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestampString = formatter.string(from: locationTimestamp)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"locationTimestamp\"\r\n\r\n".data(using: .utf8)!)
            body.append(timestampString.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        struct PhotoResponse: Decodable {
            let photo: InspectionStagePhoto
        }
        
        let response: PhotoResponse = try await performRequest(request)
        return response.photo
    }
    
    static func deleteStagePhoto(projectId: Int, inspectionId: Int, stageId: Int, photoId: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/photos/\(photoId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        
        switch httpResponse.statusCode {
        case 200, 204:
            return
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Inspection Defect API Methods
    
    static func fetchInspectionDefects(projectId: Int, inspectionId: Int, token: String) async throws -> [InspectionDefect] {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/defects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: InspectionDefectsResponse = try await performRequest(request)
        return response.defects
    }
    
    static func createDefect(projectId: Int, inspectionId: Int, stageId: Int, description: String?, assignedToId: Int?, token: String) async throws -> InspectionDefect {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/stages/\(stageId)/defects")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = CreateDefectRequest(description: description, assignedToId: assignedToId)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        struct DefectResponse: Decodable {
            let defect: InspectionDefect
        }
        
        let response: DefectResponse = try await performRequest(request)
        return response.defect
    }
    
    static func rectifyDefect(projectId: Int, inspectionId: Int, defectId: Int, notes: String?, token: String) async throws -> InspectionDefect {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/defects/\(defectId)/rectify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = RectifyDefectRequest(notes: notes)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        struct DefectResponse: Decodable {
            let defect: InspectionDefect
        }
        
        let response: DefectResponse = try await performRequest(request)
        return response.defect
    }
    
    static func uploadDefectPhoto(projectId: Int, inspectionId: Int, defectId: Int, imageData: Data, fileName: String, latitude: Double?, longitude: Double?, accuracy: Double?, locationTimestamp: Date?, token: String) async throws -> InspectionDefect.InspectionDefectPhoto {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/defects/\(defectId)/photos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add location data if provided
        if let latitude = latitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"latitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(latitude)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let longitude = longitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"longitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(longitude)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let accuracy = accuracy {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"accuracy\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(accuracy)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        if let locationTimestamp = locationTimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestampString = formatter.string(from: locationTimestamp)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"locationTimestamp\"\r\n\r\n".data(using: .utf8)!)
            body.append(timestampString.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // API returns { photos: [...] } or { photo: {...} }
        struct PhotosResponse: Decodable {
            let photos: [InspectionDefect.InspectionDefectPhoto]?
            let photo: InspectionDefect.InspectionDefectPhoto?
        }
        
        let response: PhotosResponse = try await performRequest(request)
        
        // Return first photo from array, or single photo
        if let photos = response.photos, let firstPhoto = photos.first {
            return firstPhoto
        } else if let photo = response.photo {
            return photo
        } else {
            throw APIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "No photo in response")))
        }
    }
    
    static func approveDefect(projectId: Int, inspectionId: Int, defectId: Int, token: String) async throws -> InspectionDefect {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/defects/\(defectId)/approve")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        struct DefectResponse: Decodable {
            let defect: InspectionDefect
        }
        
        let response: DefectResponse = try await performRequest(request)
        return response.defect
    }
    
    static func rejectDefect(projectId: Int, inspectionId: Int, defectId: Int, rejectionNotes: String, token: String) async throws -> InspectionDefect {
        let url = URL(string: "\(baseURL)/inspections/projects/\(projectId)/inspections/\(inspectionId)/defects/\(defectId)/reject")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct RejectRequest: Codable {
            let rejectionNotes: String
        }
        
        let requestBody = RejectRequest(rejectionNotes: rejectionNotes)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        struct DefectResponse: Decodable {
            let defect: InspectionDefect
        }
        
        let response: DefectResponse = try await performRequest(request)
        return response.defect
    }
    
    static func fetchProjectLocations(projectId: Int, token: String) async throws -> [ProjectLocation] {
        let url = URL(string: "\(baseURL)/locations/project/\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Disable caching to avoid 304 responses with empty body
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            
            switch http.statusCode {
            case 200, 304: // 304 Not Modified means use cached response
                if data.isEmpty { 
                    print("🔍 [fetchProjectLocations] Empty response data")
                    return [] 
                }
                
                // Try to decode as wrapped response first
                if let decoded = try? JSONDecoder().decode(ProjectLocationsResponse.self, from: data) {
                    print("🔍 [fetchProjectLocations] Decoded wrapped response: \(decoded.locations.count) locations")
                    return decoded.locations
                }
                
                // Try to decode as direct array
                if let locations = try? JSONDecoder().decode([ProjectLocation].self, from: data) {
                    print("🔍 [fetchProjectLocations] Decoded direct array: \(locations.count) locations")
                    return locations
                }
                
                // If both fail, log the raw data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("🔍 [fetchProjectLocations] Failed to decode. Raw response: \(jsonString)")
                }
                throw APIError.decodingError(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode locations response")))
                
            case 404:
                // No locations endpoint or no locations - return empty array
                print("🔍 [fetchProjectLocations] 404 - No locations endpoint")
                return []
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            default:
                print("🔍 [fetchProjectLocations] Unexpected status code: \(http.statusCode)")
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
        } catch let e as APIError {
            throw e
        } catch let e as DecodingError {
            print("🔍 [fetchProjectLocations] Decoding error: \(e)")
            throw APIError.decodingError(e)
        } catch {
            print("🔍 [fetchProjectLocations] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    struct ProjectLocationsResponse: Codable {
        let locations: [ProjectLocation]
    }
    
    struct LogAttachmentDownloadResponse: Decodable {
        let downloadUrl: String
        let fileName: String
        let fileType: String
    }
    
    static func fetchLogAttachmentDownloadURL(projectId: Int, logId: Int, attachmentId: Int, token: String) async throws -> LogAttachmentDownloadResponse {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)/attachments/\(attachmentId)/download")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(statusCode: -1) }
            
            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(LogAttachmentDownloadResponse.self, from: data)
            case 400:
                // Attachment URL is missing
                throw APIError.invalidResponse(statusCode: 400)
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.invalidResponse(statusCode: 404)
            default:
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
        } catch let e as APIError {
            throw e
        } catch let e as DecodingError {
            throw APIError.decodingError(e)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    static func fetchLogResponseAttachmentDownloadURL(projectId: Int, logId: Int, responseId: Int, attachmentId: Int, token: String) async throws -> LogAttachmentDownloadResponse {
        let url = URL(string: "\(baseURL)/logs/projects/\(projectId)/logs/\(logId)/responses/\(responseId)/attachments/\(attachmentId)/download")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse(statusCode: -1) }
            
            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(LogAttachmentDownloadResponse.self, from: data)
            case 400:
                throw APIError.invalidResponse(statusCode: 400)
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.invalidResponse(statusCode: 404)
            default:
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
        } catch let e as APIError {
            throw e
        } catch let e as DecodingError {
            throw APIError.decodingError(e)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    static func fetchProjectUsers(projectId: Int, token: String) async throws -> [User] {
        // Use the logs-specific endpoint
        let endpointUrl = URL(string: "\(baseURL)/logs/projects/\(projectId)/users")!
        var request = URLRequest(url: endpointUrl)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔍 [fetchProjectUsers] Requesting: \(endpointUrl.absoluteString) for project \(projectId)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"]))
        }
        
        print("🔍 [fetchProjectUsers] Response: status=\(httpResponse.statusCode), dataSize=\(data.count)")
        
        // Handle 304 Not Modified - check cache
        if httpResponse.statusCode == 304 {
            print("⚠️ [fetchProjectUsers] Got 304, checking cache")
            if let cachedResponse = URLCache.shared.cachedResponse(for: request),
               !cachedResponse.data.isEmpty {
                print("✅ [fetchProjectUsers] Using cached response (\(cachedResponse.data.count) bytes)")
                let usersResponse = try JSONDecoder().decode(UsersResponse.self, from: cachedResponse.data)
                return usersResponse.users
            } else if !data.isEmpty {
                // Sometimes 304 includes the data
                print("✅ [fetchProjectUsers] 304 with data (\(data.count) bytes)")
                let usersResponse = try JSONDecoder().decode(UsersResponse.self, from: data)
                return usersResponse.users
            } else {
                // No cache and no data - force fresh request
                print("🔄 [fetchProjectUsers] 304 with no data, forcing fresh request")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (freshData, freshResponse) = try await URLSession.shared.data(for: request)
                guard let freshHttpResponse = freshResponse as? HTTPURLResponse,
                      (200...299).contains(freshHttpResponse.statusCode) else {
                    throw APIError.invalidResponse(statusCode: (freshResponse as? HTTPURLResponse)?.statusCode ?? -1)
                }
                let usersResponse = try JSONDecoder().decode(UsersResponse.self, from: freshData)
                return usersResponse.users
            }
        }
        
        // Handle 200-299 success
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
        
        // Debug: Print raw JSON to diagnose decoding issues
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let users = json["users"] as? [[String: Any]] {
            print("🔍 [fetchProjectUsers] Found \(users.count) users in response")
            // Print each user with index
            for (index, user) in users.enumerated() {
                let userId = user["id"] ?? "nil"
                let email = user["email"] ?? "nil"
                let firstName = user["firstName"] ?? "nil"
                let lastName = user["lastName"] ?? "nil"
                if let company = user["company"] as? [String: Any] {
                    let companyId = company["id"] ?? "nil"
                    let companyName = company["name"] ?? "nil"
                    print("   [\(index)] User id=\(userId), email=\(email), name=\(firstName) \(lastName), company={id:\(companyId), name:\(companyName)}")
                } else {
                    print("   [\(index)] User id=\(userId), email=\(email), name=\(firstName) \(lastName), company=nil")
                }
            }
        } else if let jsonString = String(data: data, encoding: .utf8) {
            print("🔍 [fetchProjectUsers] Raw JSON (first 1000 chars):\n\(String(jsonString.prefix(1000)))")
        }
        
        // Decode and return
        do {
            let usersResponse = try JSONDecoder().decode(UsersResponse.self, from: data)
            print("✅ [fetchProjectUsers] Successfully decoded \(usersResponse.users.count) users")
            return usersResponse.users
        } catch let decodingError as DecodingError {
            print("❌ [fetchProjectUsers] Decoding failed:")
            print("   - Error: \(decodingError)")
            if case .keyNotFound(let key, let context) = decodingError {
                print("   - Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            } else if case .typeMismatch(let type, let context) = decodingError {
                print("   - Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            } else if case .valueNotFound(let type, let context) = decodingError {
                print("   - Value not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                // Try to identify which user index failed
                if let indexString = context.codingPath.first(where: { $0.intValue != nil })?.intValue {
                    print("   - Failed at user index: \(indexString)")
                    // Try to parse JSON manually to show the problematic user
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let users = json["users"] as? [[String: Any]],
                       indexString < users.count {
                        let problematicUser = users[indexString]
                        print("   - Problematic user data: id=\(problematicUser["id"] ?? "nil"), email=\(problematicUser["email"] ?? "nil"), company=\(problematicUser["company"] ?? "nil")")
                    }
                }
            }
            throw APIError.decodingError(decodingError)
        }
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
    
    // MARK: - Device Token Registration
    static func registerDeviceToken(token: String, deviceToken: String) async throws {
        let url = URL(string: "\(baseURL)/device-tokens/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = await [
            "token": deviceToken,
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "platform": "ios"
        ]
        request.httpBody = try JSONEncoder().encode(params)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
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
    
    // MARK: - Fetch Companies
    struct CompanyListItem: Codable, Identifiable {
        let id: Int
        let name: String
        let email: String?
        let phone: String?
        let address: String?
        let city: String?
        
        // Handle extra fields we don't need
        private enum CodingKeys: String, CodingKey {
            case id, name, email, phone, address, city
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            phone = try container.decodeIfPresent(String.self, forKey: .phone)
            address = try container.decodeIfPresent(String.self, forKey: .address)
            city = try container.decodeIfPresent(String.self, forKey: .city)
        }
    }
    
    struct CompaniesResponse: Codable {
        let companies: [CompanyListItem]
    }
    
    static func fetchCompanies(token: String) async throws -> [CompanyListItem] {
        let url = URL(string: "\(baseURL)/companies")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let response: CompaniesResponse = try await performRequest(request)
        return response.companies
    }

    // MARK: - Snag assignment options (project companies + assignable users in one call)
    private struct SnagAssignmentUserRaw: Decodable {
        let id: Int
        let email: String?
        let companyId: Int?
        let tenants: [SnagAssignmentTenantRaw]?
        struct SnagAssignmentTenantRaw: Decodable {
            let firstName: String?
            let lastName: String?
        }
    }

    private struct SnagAssignmentOptionsResponse: Decodable {
        let companies: [CompanyListItem]
        let users: [SnagAssignmentUserRaw]
    }

    /// Fetches companies associated with the project and users who can be assigned to snags (view_snags, accept_snags, submit_completion_snag).
    /// Use this when creating/editing snags so only project companies and assignable users are shown.
    static func fetchSnagAssignmentOptions(projectId: Int, token: String) async throws -> (companies: [CompanyListItem], users: [User]) {
        let url = URL(string: "\(baseURL)/snags/assignment-options?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: SnagAssignmentOptionsResponse = try await performRequest(request)
        let users = response.users.map { raw -> User in
            let first = raw.tenants?.first?.firstName
            let last = raw.tenants?.first?.lastName
            let company: User.Company? = raw.companyId.flatMap { cid in
                response.companies.first(where: { $0.id == cid }).map { User.Company(id: $0.id, name: $0.name, createdAt: nil, updatedAt: nil, tenantId: nil, reference: nil, mainCompanyId: nil, address: nil, city: nil, country: nil, email: nil, isActive: nil, phone: nil, state: nil, website: nil, zip: nil, typeId: nil, logoUrl: nil) }
            }
            return User(
                id: raw.id,
                firstName: first,
                lastName: last,
                email: raw.email,
                tenantId: nil,
                companyId: raw.companyId,
                company: company,
                roles: nil,
                permissions: nil,
                projectPermissions: nil,
                isSubscriptionOwner: nil,
                assignedProjects: nil,
                assignedSubcontractOrders: nil,
                blocked: nil,
                createdAt: nil,
                userRoles: nil,
                userPermissions: nil,
                tenants: nil
            )
        }
        return (response.companies, users)
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

    static func fetchFormDetails(formId: Int, token: String) async throws -> FormModel {
        let url = URL(string: "\(baseURL)/forms/\(formId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await performRequest(request)
    }

    static func fetchFormSubmissions(projectId: Int, token: String) async throws -> [FormSubmission] {
        let url = URL(string: "\(baseURL)/forms/submissions?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug logging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response for fetchFormSubmissions:\n\(jsonString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            
            print("📄 fetchFormSubmissions response status: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200, 204:
                // Debug: Print raw JSON before decoding
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 [FormSubmissions] Raw JSON response: \(jsonString)")
                }
                
                // Try to parse and examine the structure
                if let jsonArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    print("📄 [FormSubmissions] Found \(jsonArray.count) submissions")
                    
                    // Check first submission for camera fields
                    if let firstSubmission = jsonArray.first,
                       let responses = firstSubmission["responses"] as? [String: Any] {
                        print("📄 [FormSubmissions] First submission responses: \(responses)")
                        
                        // Look for camera fields
                        for (key, value) in responses {
                            if let cameraData = value as? [String: Any],
                               cameraData["image"] != nil,
                               cameraData["location"] != nil {
                                print("📄 [FormSubmissions] Found camera field '\(key)' with location data")
                            }
                        }
                    }
                }
                
                let submissions = try JSONDecoder().decode([FormSubmission].self, from: data)
                print("Fetched \(submissions.count) form submissions for projectId: \(projectId)")
                return submissions
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            default:
                throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            print("❌ fetchFormSubmissions decoding error: \(error)")
            if let data = try? await URLSession.shared.data(for: request).0,
               let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Raw JSON that failed to decode: \(jsonString)")
            }
            throw APIError.decodingError(error)
        } catch {
            print("❌ fetchFormSubmissions network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    static func fetchFormSubmissionPDF(submissionId: Int, token: String) async throws -> URL {
        let url = URL(string: "\(baseURL)/forms/submissions/\(submissionId)/download")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200:
            return try writeExportDataToTemporaryFile(
                data: data,
                response: httpResponse,
                defaultFilename: "form_submission_\(submissionId).pdf",
                defaultExtension: "pdf"
            )
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    static func fetchFormSubmissionsBulkDownload(submissionIds: [Int], token: String) async throws -> URL {
        let url = URL(string: "\(baseURL)/forms/submissions/bulk-download")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["submissionIds": submissionIds])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200:
            return try writeExportDataToTemporaryFile(
                data: data,
                response: httpResponse,
                defaultFilename: "form_submissions_\(Int(Date().timeIntervalSince1970)).zip",
                defaultExtension: "zip"
            )
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    struct FormDistributionResponse: Codable {
        let success: Bool
        let sent: Int
        let failed: Int
        let totalRecipients: Int
        let totalSubmissions: Int
    }

    static func distributeFormSubmissions(
        submissionIds: [Int],
        userIds: [Int],
        message: String?,
        token: String
    ) async throws -> FormDistributionResponse {
        let url = URL(string: "\(baseURL)/forms/submissions/distribute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "submissionIds": submissionIds,
            "userIds": userIds,
        ]
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["message"] = message
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(FormDistributionResponse.self, from: data)
        case 400:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let message = errorResponse.error ?? errorResponse.message {
                throw APIError.badRequest(message: message)
            }
            throw APIError.invalidResponse(statusCode: 400)
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    private static func writeExportDataToTemporaryFile(
        data: Data,
        response: HTTPURLResponse,
        defaultFilename: String,
        defaultExtension: String
    ) throws -> URL {
        let tmpDirectory = FileManager.default.temporaryDirectory
        let filenameFromHeader = extractFilename(from: response.value(forHTTPHeaderField: "Content-Disposition"))
        let filename = filenameFromHeader?.isEmpty == false ? filenameFromHeader! : defaultFilename
        let hasExtension = (filename as NSString).pathExtension.isEmpty == false
        let normalizedFilename = hasExtension ? filename : "\(filename).\(defaultExtension)"
        let destination = tmpDirectory.appendingPathComponent(normalizedFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func extractFilename(from contentDisposition: String?) -> String? {
        guard let contentDisposition else { return nil }
        let parts = contentDisposition.components(separatedBy: ";")
        for rawPart in parts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.lowercased().hasPrefix("filename=") {
                return part
                    .replacingOccurrences(of: "filename=", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
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
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
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

    // MARK: - Form Field Structure for API Request
    struct FormFieldData: Codable {
        let id: String // Should be unique, e.g., "field-0", "field-1"
        let label: String
        let type: String // e.g., "text", "yesNoNA", "image", "attachment", "dropdown", "checkbox", "radio", "subheading"
        let required: Bool
        let options: [String]?
    }

    // MARK: - Request Body for Creating Form Template
    struct CreateFormTemplateRequest: Codable {
        let title: String
        let reference: String?
        let description: String?
        let fields: [FormFieldData]
        // tenantId and createdById will be handled by the backend using the authenticated user
    }

    // MARK: - Response for Create Form Template (assuming it returns the created FormModel)
    // If the backend returns a different structure, this might need adjustment.
    // For now, let's assume it returns a FormModel similar to what fetchForms returns.

    // MARK: - Create Form Template
    static func createFormTemplate(token: String, templateData: CreateFormTemplateRequest) async throws -> FormModel {
        let url = URL(string: "\(baseURL)/forms")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(templateData)
        
        // Assuming the response will be a FormModel, similar to what's used in fetchForms
        return try await performRequest(request)
    }

    static func fetchFormTemplate(formId: Int, token: String) async throws -> FormModel {
        let url = URL(string: "\(baseURL)/forms/template/\(formId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequest(request)
    }
    
    // MARK: - Update Form Submission
    static func updateFormSubmission<T: Codable>(submissionId: Int, token: String, submissionData: T) async throws {
        // Try the specific update endpoint first
        let updateUrl = URL(string: "\(baseURL)/forms/submit/\(submissionId)")!
        var updateRequest = URLRequest(url: updateUrl)
        updateRequest.httpMethod = "PUT"
        updateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        updateRequest.httpBody = try JSONEncoder().encode(submissionData)
        
        print("🔄 [UpdateFormSubmission] Making PUT request to: \(updateUrl)")
        print("🔄 [UpdateFormSubmission] Request body: \(String(data: updateRequest.httpBody ?? Data(), encoding: .utf8) ?? "nil")")
        
        let (data, response) = try await URLSession.shared.data(for: updateRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        
        print("🔄 [UpdateFormSubmission] Response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔄 [UpdateFormSubmission] Response body: \(responseString)")
        }
        
        switch httpResponse.statusCode {
        case 200, 201, 204:
            return // Success
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.forbidden
        case 404:
            // If the PUT endpoint doesn't exist, try using PATCH instead
            print("🔄 [UpdateFormSubmission] PUT endpoint not found, trying PATCH...")
            let patchUrl = URL(string: "\(baseURL)/forms/submit/\(submissionId)")!
            var patchRequest = URLRequest(url: patchUrl)
            patchRequest.httpMethod = "PATCH"
            patchRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            patchRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            patchRequest.httpBody = try JSONEncoder().encode(submissionData)
            
            let (patchData, patchResponse) = try await URLSession.shared.data(for: patchRequest)
            
            guard let patchHttpResponse = patchResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            
            print("🔄 [UpdateFormSubmission] PATCH Response status: \(patchHttpResponse.statusCode)")
            if let patchResponseString = String(data: patchData, encoding: .utf8) {
                print("🔄 [UpdateFormSubmission] PATCH Response body: \(patchResponseString)")
            }
            
            switch patchHttpResponse.statusCode {
            case 200, 201, 204:
                return // Success
            case 401:
                throw APIError.tokenExpired
            case 403:
                throw APIError.forbidden
            default:
                let errorMessage = String(data: patchData, encoding: .utf8) ?? "Unknown error"
                print("❌ [UpdateFormSubmission] PATCH Error: \(errorMessage)")
                throw APIError.invalidResponse(statusCode: patchHttpResponse.statusCode)
            }
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ [UpdateFormSubmission] PUT Error: \(errorMessage)")
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    static func getPresignedUrl(forKey fileKey: String, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/forms/refresh-attachment-url")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let params = ["fileKey": fileKey]
        request.httpBody = try JSONEncoder().encode(params)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let json = try JSONDecoder().decode([String: String].self, from: data)
        if let newFileUrl = json["fileUrl"] {
            return newFileUrl
        } else {
            throw APIError.decodingError(NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "'fileUrl' key missing in response."]))
        }
    }
    
    // MARK: - Favorites API Methods

    struct FavoriteStatusResponse: Codable {
        let isFavourite: Bool
        let favouritedAt: String?
    }

    struct FavoriteToggleResponse: Codable {
        let isFavourite: Bool
        let favouritedAt: String?
    }

    struct FavoriteResponse: Codable {
        let favourites: [Drawing]
        let count: Int
    }

    struct FavoriteCountResponse: Codable {
        let count: Int
    }

    static func fetchDrawingFavoriteStatus(drawingId: Int, token: String) async throws -> FavoriteStatusResponse {
        let url = URL(string: "\(baseURL)/favourites/drawing/\(drawingId)/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(request)
    }

    static func toggleDrawingFavorite(drawingId: Int, token: String) async throws -> FavoriteToggleResponse {
        let url = URL(string: "\(baseURL)/favourites/drawing/\(drawingId)/toggle")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await performRequest(request)
    }

    static func fetchFavoriteDrawings(token: String, projectId: Int? = nil) async throws -> [Drawing] {
        var urlString = "\(baseURL)/favourites"
        if let projectId = projectId {
            urlString += "?projectId=\(projectId)"
        }
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: FavoriteResponse = try await performRequest(request)
        return response.favourites
    }

    static func fetchFavoriteCount(token: String, projectId: Int? = nil) async throws -> Int {
        var urlString = "\(baseURL)/favourites/count"
        if let projectId = projectId {
            urlString += "?projectId=\(projectId)"
        }
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: FavoriteCountResponse = try await performRequest(request)
        return response.count
    }

    // MARK: - Photo API Methods

    static func fetchProjectPhotos(projectId: Int, token: String) async throws -> [PhotoItem] {
        print("APIClient: fetchProjectPhotos called for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/photos/project/\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let photos: [PhotoItem] = try await performRequest(request)
        print("APIClient: fetchProjectPhotos returned \(photos.count) photos")
        return photos
    }
    
    static func fetchFormPhotos(projectId: Int, token: String) async throws -> [PhotoItem] {
        print("APIClient: fetchFormPhotos called for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/photos/forms/submissions/\(projectId)/photos")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let photos: [PhotoItem] = try await performRequest(request)
        print("APIClient: fetchFormPhotos returned \(photos.count) photos")
        return photos
    }
    
    // MARK: - Forms Folders (parity with web FormDialog)
    struct FormFolder: Codable, Identifiable {
        let id: Int
        let name: String
        let subfolders: [FormFolder]?
    }



    struct FormFoldersResponse: Codable {
        let formsRootFolderId: Int?
        let folders: [FormFolder]?
    }

    struct FormTemplateSettings: Codable {
        let defaultFolderId: Int?
    }

    static func fetchFormFolders(projectId: Int, token: String) async throws -> (rootId: Int?, folders: [FormFolder]) {
        let url = URL(string: "\(baseURL)/projects/\(projectId)/form-folders")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let res: FormFoldersResponse = try await performRequest(request)
        return (res.formsRootFolderId, res.folders ?? [])
    }



    static func fetchDrawingFolders(projectId: Int, token: String) async throws -> (rootId: Int?, folders: [DrawingFolder]) {
        // Backend route (drawingRoutes.ts): GET /projects/:projectId/folders
        let url = URL(string: "\(baseURL)/projects/\(projectId)/folders")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let res: DrawingFoldersResponse = try await performRequest(request)
        return (res.drawingRootFolderId, res.folders ?? [])
    }

    static func fetchFormTemplateSettings(formId: Int, projectId: Int, token: String) async throws -> FormTemplateSettings {
        let url = URL(string: "\(baseURL)/forms/templates/\(formId)/projects/\(projectId)/settings")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequest(request)
    }
    
    // MARK: - Snagging API
    struct SnagPosition: Codable {
        let x: Double
        let y: Double
        let page: Int

        init(x: Double, y: Double, page: Int) {
            self.x = x; self.y = y; self.page = page
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // x can be number or string
            if let xDouble = try? container.decode(Double.self, forKey: .x) {
                x = xDouble
            } else if let xString = try? container.decode(String.self, forKey: .x), let parsed = Double(xString) {
                x = parsed
            } else {
                throw DecodingError.dataCorruptedError(forKey: .x, in: container, debugDescription: "Invalid x")
            }
            if let yDouble = try? container.decode(Double.self, forKey: .y) {
                y = yDouble
            } else if let yString = try? container.decode(String.self, forKey: .y), let parsed = Double(yString) {
                y = parsed
            } else {
                throw DecodingError.dataCorruptedError(forKey: .y, in: container, debugDescription: "Invalid y")
            }
            page = (try? container.decode(Int.self, forKey: .page)) ?? 1
        }
    }

    struct SnagCompanyAssignment: Codable {
        let companyId: Int
        let company: Company?
    }

    struct SnagAttachment: Codable, Identifiable {
        let id: Int
        let fileName: String
        let fileUrl: String
        let fileType: String?
        let fileSize: Int?
        let photoType: String?
        let presignedUrl: String?
    }

    struct SnagAssignedUser: Codable {
        let id: Int
        let email: String?
        let tenants: [SnagAssignedUserTenant]?
        struct SnagAssignedUserTenant: Codable {
            let firstName: String?
            let lastName: String?
        }
        var displayName: String {
            if let t = tenants?.first, let first = t.firstName, let last = t.lastName, !first.isEmpty || !last.isEmpty {
                return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            }
            return email ?? "User #\(id)"
        }
    }

    struct Snag: Codable, Identifiable {
        let id: Int
        let title: String
        let description: String?
        let status: String
        let priority: String?
        let drawingId: Int
        let drawingFileId: Int
        let page: Int
        let position: SnagPosition
        let createdAt: String?
        let updatedAt: String?
        let projectId: Int?
        let userId: Int? // Assigned user ID (person responsible for the snag)
        let resolvedAt: String?
        let resolvedBy: SnagUser?
        let closedAt: String?
        let closedBy: SnagUser?
        /// Assigned user (person responsible); decoded from API key "User".
        let assignedUser: SnagAssignedUser?
        let assignments: [SnagCompanyAssignment]?
        var attachments: [SnagAttachment]?
        let comments: [SnagComment]?

        enum CodingKeys: String, CodingKey {
            case id, title, description, status, priority, drawingId, drawingFileId, page, position
            case createdAt, updatedAt, projectId, userId, resolvedAt, resolvedBy, closedAt, closedBy
            case assignments, attachments, comments
            case assignedUser = "User"
        }
    }
    
    struct SnagUser: Codable {
        let id: Int
        let firstName: String?
        let lastName: String?
        let email: String?
    }
    
    struct SnagComment: Codable, Identifiable {
        let id: Int
        let snagId: Int
        let userId: Int
        let comment: String
        let createdAt: String?
        let user: SnagCommentUser?
    }
    
    struct SnagCommentUser: Codable {
        let id: Int
        let email: String?
        let tenants: [SnagCommentUserTenant]?
    }
    
    struct SnagCommentUserTenant: Codable {
        let firstName: String?
        let lastName: String?
    }

    struct SnagListEnvelope: Codable { let snags: [Snag] }

    struct SnagSelectedDrawing: Codable, Identifiable {
        let id: Int
        let projectId: Int
        let drawingId: Int
        let drawingFileId: Int
        let selectedAt: String
        let drawing: Drawing
        let drawingFile: DrawingFile
    }

    struct SnagSelectedDrawingsEnvelope: Codable { let selectedDrawings: [SnagSelectedDrawing] }

    static func fetchSnagsForDrawing(projectId: Int, drawingId: Int, drawingFileId: Int? = nil, page: Int? = nil, token: String) async throws -> [Snag] {
        var comps = URLComponents(string: "\(baseURL)/snags/drawings/\(drawingId)/snags")!
        var items: [URLQueryItem] = [URLQueryItem(name: "projectId", value: String(projectId))]
        if let drawingFileId = drawingFileId { items.append(URLQueryItem(name: "fileId", value: String(drawingFileId))) }
        if let page = page { items.append(URLQueryItem(name: "page", value: String(page))) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let env: SnagListEnvelope = try await performRequest(req)
        return env.snags
    }

    static func fetchSelectedSnagDrawings(projectId: Int, token: String) async throws -> [SnagSelectedDrawing] {
        let url = URL(string: "\(baseURL)/snags/selected-drawings/\(projectId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let env: SnagSelectedDrawingsEnvelope = try await performRequest(req)
        return env.selectedDrawings
    }
    
    // MARK: - Fetch All Snags for Project
    struct ProjectSnagsEnvelope: Codable { let data: [SnagWithDrawing] }
    
    struct SnagWithDrawing: Codable, Identifiable {
        let id: Int
        let title: String
        let description: String?
        let status: String
        let priority: String?
        let drawingId: Int?
        let drawingFileId: Int?
        let page: Int?
        let position: SnagPositionFlexible?
        let createdAt: String?
        let updatedAt: String?
        let projectId: Int?
        let userId: Int?
        let resolvedAt: String?
        let closedAt: String?
        let assignments: [SnagCompanyAssignmentSimple]?
        let drawing: SnagDrawingInfo?
        let User: SnagUserInfo?
    }
    
    // Flexible position that handles JSON object from database
    struct SnagPositionFlexible: Codable {
        let x: Double?
        let y: Double?
        let page: Int?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Handle x as number or string
            if let xDouble = try? container.decode(Double.self, forKey: .x) {
                x = xDouble
            } else if let xString = try? container.decode(String.self, forKey: .x), let parsed = Double(xString) {
                x = parsed
            } else {
                x = nil
            }
            // Handle y as number or string
            if let yDouble = try? container.decode(Double.self, forKey: .y) {
                y = yDouble
            } else if let yString = try? container.decode(String.self, forKey: .y), let parsed = Double(yString) {
                y = parsed
            } else {
                y = nil
            }
            page = try? container.decode(Int.self, forKey: .page)
        }
    }
    
    struct SnagCompanyAssignmentSimple: Codable {
        let companyId: Int?
        let company: SnagCompanySimple?
    }
    
    struct SnagCompanySimple: Codable {
        let name: String?
    }
    
    struct SnagDrawingInfo: Codable {
        let title: String?
    }
    
    struct SnagUserInfo: Codable {
        let id: Int
        let email: String?
        let tenants: [SnagCommentUserTenant]?
    }
    
    static func fetchAllSnagsForProject(projectId: Int, token: String) async throws -> [SnagWithDrawing] {
        var comps = URLComponents(string: "\(baseURL)/snags")!
        comps.queryItems = [URLQueryItem(name: "projectId", value: String(projectId))]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let env: ProjectSnagsEnvelope = try await performRequest(req)
        return env.data
    }

    static func addSelectedSnagDrawing(projectId: Int, drawingId: Int, drawingFileId: Int, token: String) async throws -> SnagSelectedDrawing {
        let url = URL(string: "\(baseURL)/snags/selected-drawings/\(projectId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["drawingId": drawingId, "drawingFileId": drawingFileId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        struct Env: Codable { let selection: SnagSelectedDrawing }
        let env: Env = try await performRequest(req)
        return env.selection
    }

    static func removeSelectedSnagDrawing(projectId: Int, drawingId: Int, drawingFileId: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/snags/selected-drawings/\(projectId)/\(drawingId)/\(drawingFileId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse(statusCode: (res as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // Create snag with optional photos (multipart/form-data)
    static func createSnag(projectId: Int, drawingId: Int, drawingFileId: Int, page: Int, position: SnagPosition, title: String, description: String?, companyIds: [Int] = [], assigneeId: Int? = nil, priority: String? = nil, status: String? = nil, responseDate: String? = nil, photos: [Data] = [], token: String) async throws -> Snag {
        let url = URL(string: "\(baseURL)/snags")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFile(name: String, filename: String, mime: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "projectId", value: String(projectId))
        appendField(name: "drawingId", value: String(drawingId))
        appendField(name: "drawingFileId", value: String(drawingFileId))
        appendField(name: "page", value: String(page))
        let positionJson = String(data: try JSONEncoder().encode(position), encoding: .utf8) ?? "{}"
        appendField(name: "position", value: positionJson)
        appendField(name: "title", value: title)
        appendField(name: "description", value: description ?? "")
        if let assigneeId = assigneeId { appendField(name: "assigneeId", value: String(assigneeId)) }
        if let priority = priority { appendField(name: "priority", value: priority) }
        if let status = status { appendField(name: "status", value: status) }
        if let responseDate = responseDate { appendField(name: "responseDate", value: responseDate) }
        let companiesJson = String(data: try JSONSerialization.data(withJSONObject: companyIds), encoding: .utf8) ?? "[]"
        appendField(name: "companyIds", value: companiesJson)
        for (idx, photo) in photos.enumerated() {
            appendFile(name: "photos", filename: "photo_\(idx).jpg", mime: "image/jpeg", data: photo)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        return try await performRequest(req)
    }

    static func uploadSnagPhotos(snagId: Int, photos: [Data], token: String) async throws -> Snag {
        let url = URL(string: "\(baseURL)/snags/\(snagId)/photos")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func appendFile(name: String, filename: String, mime: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        for (idx, photo) in photos.enumerated() {
            appendFile(name: "photos", filename: "photo_\(idx).jpg", mime: "image/jpeg", data: photo)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await performRequest(req)
    }

    static func updateSnag(snagId: Int, fields: [String: Any], token: String) async throws -> Snag {
        let url = URL(string: "\(baseURL)/snags/\(snagId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await performRequest(req)
    }
    
    // Update snag status with photo attachments and optional comment (for resolving snags)
    static func updateSnagWithPhotos(snagId: Int, status: String, photos: [Data], comment: String? = nil, token: String) async throws -> Snag {
        // First upload photos if any
        if !photos.isEmpty {
            let photoUrl = URL(string: "\(baseURL)/snags/\(snagId)/photos")!
            var photoReq = URLRequest(url: photoUrl)
            photoReq.httpMethod = "POST"
            let boundary = "Boundary-\(UUID().uuidString)"
            photoReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            photoReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            func appendFile(name: String, filename: String, mime: String, data: Data) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
            
            for (idx, photo) in photos.enumerated() {
                appendFile(name: "photos", filename: "resolution_photo_\(idx).jpg", mime: "image/jpeg", data: photo)
            }
            
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            photoReq.httpBody = body
            
            // Upload photos first
            let _: Snag = try await performRequest(photoReq)
        }
        
        // Then update status with optional comment
        var fields: [String: Any] = ["status": status]
        if let comment = comment, !comment.isEmpty {
            fields["comment"] = comment
        }
        
        return try await updateSnag(snagId: snagId, fields: fields, token: token)
    }

    // Fetch a PDF for a drawingFileId via proxy endpoint, saving to a temporary file and returning URL
    static func fetchDrawingPDFViaProxy(drawingFileId: Int, token: String) async throws -> URL {
        let url = URL(string: "\(baseURL)/drawings/proxy-file/\(drawingFileId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snag_pdf_\(drawingFileId).pdf")
        try? FileManager.default.removeItem(at: tmp)
        try data.write(to: tmp)
        return tmp
    }
    
    static func fetchRFIPhotos(projectId: Int, token: String) async throws -> [PhotoItem] {
        print("APIClient: fetchRFIPhotos called for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/photos/rfis/\(projectId)/photos")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let photos: [PhotoItem] = try await performRequest(request)
        print("APIClient: fetchRFIPhotos returned \(photos.count) photos")
        return photos
    }
    
    static func fetchLogPhotos(projectId: Int, token: String) async throws -> [PhotoItem] {
        print("APIClient: fetchLogPhotos called for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/photos/logs/\(projectId)/photos")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let photos: [PhotoItem] = try await performRequest(request)
        print("APIClient: fetchLogPhotos returned \(photos.count) photos")
        return photos
    }
    
    static func fetchSnagPhotos(projectId: Int, token: String) async throws -> [PhotoItem] {
        print("APIClient: fetchSnagPhotos called for projectId: \(projectId)")
        let url = URL(string: "\(baseURL)/photos/snags/\(projectId)/photos")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let photos: [PhotoItem] = try await performRequest(request)
        print("APIClient: fetchSnagPhotos returned \(photos.count) photos")
        return photos
    }
    
    static func uploadProjectPhotos(token: String, uploadData: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/photos/project")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: uploadData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    static func fetchRFIResponses(rfiId: Int, projectId: Int, token: String) async throws -> [RFI.RFIResponseItem] {
        let url = URL(string: "\(baseURL)/projects/\(projectId)/rfis/\(rfiId)/responses")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performRequest(request)
    }
    
    // MARK: - Chat API Methods
    
    /// Fetch conversations for a project
    static func fetchConversations(projectId: Int, token: String, limit: Int = 20) async throws -> [ChatConversation] {
        let url = URL(string: "\(baseURL)/chat/conversations/\(projectId)?limit=\(limit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Avoid HTTP 304 caching responses that come back with empty bodies; we want a fresh payload
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return try await performRequest(request)
    }
    
    /// Create a new conversation
    static func createConversation(projectId: Int, token: String, title: String? = nil) async throws -> ChatConversation {
        let url = URL(string: "\(baseURL)/chat/conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = CreateConversationRequest(projectId: projectId, title: title)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        return try await performRequest(request)
    }
    
    /// Fetch messages for a specific conversation
    static func fetchConversationMessages(conversationId: Int, token: String, messageLimit: Int = 50) async throws -> [ChatMessage] {
        let url = URL(string: "\(baseURL)/chat/conversations/\(conversationId)/messages?messageLimit=\(messageLimit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Add cache control headers to avoid 304 responses
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        print("🔍 [API] Fetching messages for conversation \(conversationId)")
        let conversationWithMessages: ChatConversationWithMessages = try await performRequest(request)
        print("🔍 [API] Successfully fetched \(conversationWithMessages.messages.count) messages")
        return conversationWithMessages.messages
    }
    
    /// Send a message to a conversation
    static func sendMessage(conversationId: Int, message: String, token: String) async throws -> SendMessageResponse {
        let url = URL(string: "\(baseURL)/chat/conversations/\(conversationId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = SendMessageRequest(message: message)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        print("🔍 [API] Sending message to conversation \(conversationId): \(message)")
        let response: SendMessageResponse = try await performRequest(request)
        print("🔍 [API] Successfully sent message, got response with \(response.sources.count) sources")
        return response
    }
    
    /// Archive a conversation
    static func archiveConversation(conversationId: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/chat/conversations/\(conversationId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let _: EmptyResponse = try await performRequest(request)
    }
    
    // MARK: - Material Requisitions API Methods
    
    /// Fetch material requisitions for a project
    static func fetchMaterialRequisitions(projectId: Int, token: String) async throws -> [MaterialRequisition] {
        let url = URL(string: "\(baseURL)/material-requisitions/projects/\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionsResponse = try await performRequest(request)
        return response.requisitions
    }
    
    /// Fetch a single material requisition by ID
    static func fetchMaterialRequisition(id: Int, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionResponse = try await performRequest(request)
        return response.requisition
    }
    
    /// Fetch material requisitions where user is buyer (across all projects)
    static func fetchMaterialRequisitionsAsBuyer(token: String) async throws -> [MaterialRequisition] {
        let url = URL(string: "\(baseURL)/material-requisitions/buyer")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionsResponse = try await performRequest(request)
        return response.requisitions
    }
    
    /// Fetch material requisitions where user is requester (across all projects)
    static func fetchMaterialRequisitionsAsRequester(token: String) async throws -> [MaterialRequisition] {
        let url = URL(string: "\(baseURL)/material-requisitions/requester")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionsResponse = try await performRequest(request)
        return response.requisitions
    }
    
    /// Fetch available buyers for a project
    static func fetchMaterialRequisitionBuyers(projectId: Int, token: String) async throws -> [MaterialRequisitionBuyer] {
        let url = URL(string: "\(baseURL)/material-requisitions/projects/\(projectId)/buyers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionBuyersResponse = try await performRequest(request)
        return response.buyers
    }
    
    /// Fetch cost code headers (and codes) for use in material requisition item cost code selector
    static func fetchCostCodeHeadersForRequisitions(token: String) async throws -> [CostCodeHeader] {
        let url = URL(string: "\(baseURL)/cost-structure/headers/for-requisitions")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: [CostCodeHeader] = try await performRequest(request)
        return response
    }
    
    /// Create a new material requisition
    static func createMaterialRequisition(projectId: Int, request: CreateMaterialRequisitionRequest, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/projects/\(projectId)")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Custom encoding to handle AnyCodable
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(request)
        httpRequest.httpBody = jsonData
        
        let response: MaterialRequisitionResponse = try await performRequest(httpRequest)
        return response.requisition
    }
    
    /// Update a material requisition
    static func updateMaterialRequisition(id: Int, request: UpdateMaterialRequisitionRequest, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)")!
        print("🌐 [APIClient] Updating requisition \(id) at: \(url.absoluteString)")
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "PUT"
        httpRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(request)
        httpRequest.httpBody = jsonData
        
        // Log the request body
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("🌐 [APIClient] Request body:")
            print(jsonString)
        } else {
            print("⚠️ [APIClient] Could not convert request body to string")
        }
        
        let response: MaterialRequisitionResponse = try await performRequest(httpRequest)
        print("✅ [APIClient] Update successful")
        return response.requisition
    }
    
    /// Update material requisition status
    static func updateMaterialRequisitionStatus(id: Int, status: String, orderReference: String? = nil, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["status": status]
        if let orderReference = orderReference {
            body["orderReference"] = orderReference
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let response: MaterialRequisitionResponse = try await performRequest(request)
        return response.requisition
    }
    
    /// Assign buyer to a material requisition
    static func assignBuyerToMaterialRequisition(id: Int, buyerId: Int?, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)/assign-buyer")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = AssignBuyerRequest(buyerId: buyerId)
        request.httpBody = try JSONEncoder().encode(body)
        
        let response: MaterialRequisitionResponse = try await performRequest(request)
        return response.requisition
    }
    
    /// Archive a material requisition
    static func archiveMaterialRequisition(id: Int, token: String) async throws -> MaterialRequisition {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)/archive")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let response: MaterialRequisitionResponse = try await performRequest(request)
        return response.requisition
    }
    
    // MARK: - Timesheet Clock API (sign in/out per project)
    
    /// GET /timesheets/clock/geofence?projectId= – geofence and sign-in locations for a specific project (per-project)
    static func fetchTimesheetClockGeofence(projectId: Int, token: String) async throws -> TimesheetGeofenceResponse {
        var comp = URLComponents(string: "\(baseURL)/timesheets/clock/geofence")!
        comp.queryItems = [URLQueryItem(name: "projectId", value: String(projectId))]
        guard let url = comp.url else { throw APIError.networkError(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid geofence URL"])) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }
    
    /// GET /timesheets/clock/status – current user's active sign-ins
    static func fetchTimesheetClockStatus(token: String) async throws -> TimesheetClockStatusResponse {
        let url = URL(string: "\(baseURL)/timesheets/clock/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }
    
    /// GET /timesheets/clock/entry-projects – projects the user can clock into
    static func fetchTimesheetClockEntryProjects(token: String) async throws -> TimesheetClockProjectsResponse {
        let url = URL(string: "\(baseURL)/timesheets/clock/entry-projects")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }
    
    /// POST /timesheets/clock/sign-in – sign in to a project (latitude/longitude required when location required; clockLocationId optional, API can infer from lat/lon)
    static func timesheetClockSignIn(projectId: Int, latitude: Double?, longitude: Double?, clockLocationId: Int?, token: String) async throws -> TimesheetProjectClock {
        let url = URL(string: "\(baseURL)/timesheets/clock/sign-in")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["projectId": projectId]
        if let lat = latitude, let lon = longitude {
            body["latitude"] = lat
            body["longitude"] = lon
        }
        if let cid = clockLocationId {
            body["clockLocationId"] = cid
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request)
    }
    
    /// POST /timesheets/clock/sign-out – sign out from a project
    static func timesheetClockSignOut(projectId: Int, latitude: Double?, longitude: Double?, token: String) async throws -> TimesheetProjectClock {
        let url = URL(string: "\(baseURL)/timesheets/clock/sign-out")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["projectId": projectId]
        if let lat = latitude, let lon = longitude {
            body["latitude"] = lat
            body["longitude"] = lon
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request)
    }

    /// GET /timesheets/clock/history?projectId= & limit= – completed sign-in/sign-out sessions for this project (current user)
    static func fetchClockHistory(projectId: Int, limit: Int = 20, token: String) async throws -> [ClockHistorySession] {
        var comp = URLComponents(string: "\(baseURL)/timesheets/clock/history")!
        comp.queryItems = [URLQueryItem(name: "projectId", value: String(projectId)), URLQueryItem(name: "limit", value: String(limit))]
        guard let url = comp.url else { throw APIError.networkError(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid clock history URL"])) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: ClockHistoryResponse = try await performRequest(request)
        return response.sessions
    }

    // MARK: - Timesheets (submit for approval)

    /// GET /timesheets – current user's timesheets (my timesheets)
    static func fetchMyTimesheets(token: String) async throws -> [Timesheet] {
        let url = URL(string: "\(baseURL)/timesheets")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: TimesheetsListResponse = try await performRequest(request)
        return response.timesheets
    }

    /// GET /timesheets/:id – single timesheet with entries and expenses
    static func fetchTimesheet(id: Int, token: String) async throws -> Timesheet {
        let url = URL(string: "\(baseURL)/timesheets/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }

    /// POST /timesheets – create a draft timesheet (periodStart/periodEnd as ISO date strings; at least one entry required)
    static func createTimesheet(periodStart: Date, periodEnd: Date, entries: [[String: Any]], expenses: [[String: Any]] = [], token: String) async throws -> Timesheet {
        let url = URL(string: "\(baseURL)/timesheets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: Any] = [
            "periodStart": formatter.string(from: periodStart),
            "periodEnd": formatter.string(from: periodEnd),
            "entries": entries,
            "expenses": expenses
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request)
    }

    /// PATCH /timesheets/:id – update draft (entries, expenses)
    static func updateTimesheet(id: Int, entries: [[String: Any]], expenses: [[String: Any]], token: String) async throws -> Timesheet {
        let url = URL(string: "\(baseURL)/timesheets/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["entries": entries, "expenses": expenses]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request)
    }

    /// POST /timesheets/:id/submit – submit for approval
    static func submitTimesheet(id: Int, token: String) async throws -> Timesheet {
        let url = URL(string: "\(baseURL)/timesheets/\(id)/submit")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }

    /// Upload files for a material requisition
    static func uploadMaterialRequisitionFiles(id: Int, files: [Data], fileNames: [String], token: String) async throws -> [MaterialRequisitionAttachment] {
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)/files")!
        print("🌐 [APIClient] Uploading \(files.count) files to: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        for (index, fileData) in files.enumerated() {
            let fileName = index < fileNames.count ? fileNames[index] : "file_\(index).jpg"
            let mimeType = mimeTypeForFile(fileName: fileName)
            
            print("🌐 [APIClient] Adding file \(index + 1)/\(files.count): \(fileName) (\(fileData.count) bytes, \(mimeType))")
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        print("🌐 [APIClient] Request body size: \(body.count) bytes")
        
        let response: MaterialRequisitionFileUploadResponse = try await performRequest(request)
        print("✅ [APIClient] Upload successful. Received \(response.files.count) file(s) in response")
        return response.files
    }
    
    /// Get download URL for a material requisition file
    static func getMaterialRequisitionFileDownloadUrl(id: Int, fileKey: String, token: String) async throws -> String {
        let encodedFileKey = fileKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileKey
        let url = URL(string: "\(baseURL)/material-requisitions/\(id)/files/\(encodedFileKey)?format=json")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        struct DownloadUrlResponse: Codable {
            let downloadUrl: String
        }
        
        let response: DownloadUrlResponse = try await performRequest(request)
        return response.downloadUrl
    }
    
    /// Helper function to determine MIME type from file name
    private static func mimeTypeForFile(fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default: return "application/octet-stream"
        }
    }
    
    // MARK: - Qualifications
    
    /// Fetch the current user's qualifications
    static func fetchMyQualifications(token: String) async throws -> UserQualificationsResponse {
        let url = URL(string: "\(baseURL)/qualifications/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return try await performRequest(request)
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

    // Helper function to check permissions
    func hasPermissionToManageForms() -> Bool {
        if let roles = roles {
            for role in roles {
                // Assuming "Admin" or "Superadmin" roles have full permissions
                if role.name.uppercased() == "ADMIN" || role.name.uppercased() == "SUPERADMIN" {
                    return true
                }
            }
        }
        if let permissions = permissions {
            return permissions.contains { $0.name == "manage_forms" }
        }
        return false
    }

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
    
    /// Display name combining first and last name, falling back to email
    var displayName: String {
        let first = firstName ?? ""
        let last = lastName ?? ""
        let fullName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        if fullName.isEmpty {
            return email ?? "Unknown User"
        }
        return fullName
    }

    struct Company: Codable {
        let id: Int?
        let name: String?
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
    // Accept full tenant objects as returned by the backend
    let tenants: [User.UserTenant]?
}

struct SelectTenantResponse: Decodable {
    let token: String
    let user: User
}

struct LoginResponse: Decodable {
    let token: String
}

struct UserDetailsResponse: Decodable {
    let id: Int
    let email: String
    let roles: [Role]
    let permissions: [Permission]
    let tenants: [User.UserTenant]
    let isSubscriptionOwner: Bool
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

// MARK: - Drawing Folders
struct DrawingFolder: Codable, Identifiable {
    let id: Int
    let name: String
    let parentId: Int?
    let subfolders: [DrawingFolder]?
}

struct DrawingFoldersResponse: Codable {
    let drawingRootFolderId: Int?
    let folders: [DrawingFolder]?
}

struct Drawing: Codable, Identifiable {
    let id: Int
    let title: String
    let number: String
    let projectId: Int
    let status: String?
    let archived: Bool?
    let createdAt: String?
    let updatedAt: String?
    let revisions: [Revision]
    let company: Company?
    let discipline: String?
    let projectDiscipline: ProjectDiscipline?
    let projectDrawingType: ProjectDrawingType?
    var isOffline: Bool?
    let user: User?
    let folderId: Int?
    let folder: DrawingFolder?
    var isFavourite: Bool?
    var favouritedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case number
        case projectId
        case status
        case archived
        case createdAt
        case updatedAt
        case revisions
        case company
        case discipline
        case projectDiscipline = "ProjectDiscipline"
        case projectDrawingType = "ProjectDrawingType"
        case isOffline
        case user
        case folderId
        case folder
        case isFavourite
        case favouritedAt
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

struct RFIDetailResponse: Decodable {
    let rfi: RFI
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
    let manager: UserInfo?
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
            case firstName
            case lastName
            case tenants
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)

            // Prefer direct firstName/lastName if present
            if let directFirst = try container.decodeIfPresent(String.self, forKey: .firstName),
               let directLast = try container.decodeIfPresent(String.self, forKey: .lastName),
               !(directFirst.isEmpty && directLast.isEmpty) {
                firstName = directFirst
                lastName = directLast
                return
            }

            // Fallback to tenants array shape
            if let tenants = try container.decodeIfPresent([TenantInfo].self, forKey: .tenants),
               let tenant = tenants.first {
                firstName = tenant.firstName
                lastName = tenant.lastName
                return
            }

            // Final fallback
            firstName = "Unknown"
            lastName = "User"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(firstName, forKey: .firstName)
            try container.encode(lastName, forKey: .lastName)
            // Also include tenants array for compatibility with consumers expecting it
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

// Convenience builder for optimistic UI updates without altering the API model
extension RFI {
    func replacing(
        title: String? = nil,
        description: String? = nil,
        query: String? = nil,
        status: String? = nil,
        attachments: [RFIAttachment]? = nil,
        drawings: [RFIDrawing]? = nil,
        responses: [RFIResponseItem]? = nil,
        acceptedResponse: RFIResponseItem? = nil
    ) -> RFI {
        RFI(
            id: self.id,
            number: self.number,
            title: title ?? self.title,
            description: description ?? self.description,
            query: query ?? self.query,
            status: status ?? self.status,
            createdAt: self.createdAt,
            submittedDate: self.submittedDate,
            returnDate: self.returnDate,
            closedDate: self.closedDate,
            projectId: self.projectId,
            submittedBy: self.submittedBy,
            managerId: self.managerId,
            manager: self.manager,
            assignedUsers: self.assignedUsers,
            attachments: attachments ?? self.attachments,
            drawings: drawings ?? self.drawings,
            responses: responses ?? self.responses,
            acceptedResponse: acceptedResponse ?? self.acceptedResponse
        )
    }
}

// MARK: - Permit Models

struct Permit: Decodable, Identifiable {
    let id: Int
    let permitNumber: String
    let status: String
    let projectId: Int
    let permitTypeId: Int
    let formSubmissionId: Int?
    let submittedById: Int?
    let locationId: Int?
    let dueDate: Date?
    let worksDate: Date?
    let validUntil: Date?
    let submittedAt: Date?
    let approvedAt: Date?
    let closedAt: Date?
    let createdAt: Date?
    let permitType: PermitType?
    let submittedBy: PermitSubmittedBy?
    let currentStage: PermitStage?
    let location: PermitLocation?
    let approvalsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, permitNumber, status, projectId, permitTypeId, formSubmissionId, submittedById, locationId
        case dueDate, worksDate, validUntil, submittedAt, approvedAt, closedAt, createdAt
        case permitType, submittedBy, currentStage, location
        case approvalsCount = "_count"
    }

    struct PermitType: Decodable {
        let id: Int
        let name: String
        let prefix: String?
        let requiresCloseout: Bool?
    }

    struct PermitSubmittedBy: Decodable {
        let id: Int
        let email: String?
    }

    struct PermitStage: Decodable {
        let id: Int
        let name: String?
        let order: Int?
    }

    struct PermitLocation: Decodable {
        let id: Int
        let name: String?
    }

    struct PermitCount: Decodable {
        let approvals: Int?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        permitNumber = try c.decode(String.self, forKey: .permitNumber)
        status = try c.decode(String.self, forKey: .status)
        projectId = try c.decode(Int.self, forKey: .projectId)
        permitTypeId = try c.decode(Int.self, forKey: .permitTypeId)
        formSubmissionId = try c.decodeIfPresent(Int.self, forKey: .formSubmissionId)
        submittedById = try c.decodeIfPresent(Int.self, forKey: .submittedById)
        locationId = try c.decodeIfPresent(Int.self, forKey: .locationId)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        worksDate = try c.decodeIfPresent(Date.self, forKey: .worksDate)
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
        submittedAt = try c.decodeIfPresent(Date.self, forKey: .submittedAt)
        approvedAt = try c.decodeIfPresent(Date.self, forKey: .approvedAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        permitType = try c.decodeIfPresent(PermitType.self, forKey: .permitType)
        submittedBy = try c.decodeIfPresent(PermitSubmittedBy.self, forKey: .submittedBy)
        currentStage = try c.decodeIfPresent(PermitStage.self, forKey: .currentStage)
        location = try c.decodeIfPresent(PermitLocation.self, forKey: .location)
        if let count = try c.decodeIfPresent(PermitCount.self, forKey: .approvalsCount) {
            approvalsCount = count.approvals
        } else {
            approvalsCount = nil
        }
    }
}

struct PermitTypeListItem: Decodable, Identifiable {
    let id: Int
    let name: String
    let prefix: String?
    let description: String?
    /// Form template to fill when creating this permit type (same as web "Form: Al").
    let formTemplateId: Int?
}

// MARK: - Log Models

struct LogResponse: Decodable {
    let logs: [Log]
}

struct LogDetailResponse: Decodable {
    let log: Log
}

struct LogResponsesResponse: Decodable {
    let responses: [Log.ResponseItem]
}

struct Log: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String?
    let description: String?
    let projectId: Int
    let tenantId: Int
    let createdById: Int
    let assigneeId: Int?
    let dueDate: String?
    let priorityId: Int?
    let folderId: Int?
    let isPrivate: Bool
    let location: String?
    let specification: String?
    let locationId: Int?
    let typeId: Int?
    let tradeId: Int?
    let statusId: Int?
    let hazardId: Int?
    let contributingConditionId: Int?
    let contributingBehaviourId: Int?
    let createdAt: String
    let updatedAt: String
    
    // Related objects
    let type: LogType?
    let status: LogStatus?
    let hazard: LogHazard?
    let contributingBehaviour: LogBehaviour?
    let contributingCondition: LogCondition?
    let trade: LogTrade?
    let assignee: UserInfo?
    let logPriority: LogPriority?
    let attachments: [LogAttachment]?
    let createdBy: UserInfo?
    let distributions: [LogDistribution]?
    let responses: [ResponseItem]?
    let projectLocation: ProjectLocation?
    
    struct UserInfo: Codable {
        let id: Int
        let firstName: String?
        let lastName: String?
        let email: String?
        let Company: LogUserCompany?
        let tenants: [TenantInfo]?
        
        struct LogUserCompany: Codable {
            let id: Int
            let name: String
        }
        
        struct TenantInfo: Codable {
            let firstName: String
            let lastName: String
            let company: LogUserCompany?
        }
        
        var displayName: String {
            if let tenants = tenants, let tenant = tenants.first {
                return "\(tenant.firstName) \(tenant.lastName)"
            } else if let firstName = firstName, let lastName = lastName {
                return "\(firstName) \(lastName)"
            } else {
                return email ?? "Unknown User"
            }
        }
        
        var companyName: String? {
            // Prefer tenant-scoped company (matches current project/tenant) over the user's top-level company
            return tenants?.first?.company?.name ?? Company?.name
        }
    }
    
    struct LogType: Codable {
        let id: Int
        let name: String
        let order: Int
        let active: Bool
    }
    
    struct LogStatus: Codable {
        let id: Int
        let name: String
        let color: String?
        let order: Int
        let active: Bool
    }
    
    struct LogHazard: Codable {
        let id: Int
        let name: String
        let order: Int
        let active: Bool
    }
    
    struct LogBehaviour: Codable {
        let id: Int
        let name: String
        let order: Int
        let active: Bool
    }
    
    struct LogCondition: Codable {
        let id: Int
        let name: String
        let order: Int
        let active: Bool
    }
    
    struct LogTrade: Codable {
        let id: Int
        let name: String
        let order: Int
        let active: Bool
    }
    
    struct LogPriority: Codable {
        let id: Int
        let name: String
        let color: String?
        let order: Int
        let active: Bool
    }
    
    struct LogAttachment: Codable {
        let id: Int
        let fileUrl: String
        let fileName: String
        let fileType: String
        let uploadedById: Int?
        let tenantId: Int?
        // Some API responses return createdAt/updatedAt, others return uploadedAt only
        let createdAt: String?
        let updatedAt: String?
        let uploadedAt: String?
        var localPath: URL?
        
        enum CodingKeys: String, CodingKey {
            case id
            case fileUrl
            case fileName
            case fileType
            case uploadedById
            case tenantId
            case createdAt
            case updatedAt
            case uploadedAt
        }
    }
    
    struct LogDistribution: Codable {
        // Some API payloads omit id for distributions
        let id: Int?
        let logId: Int
        let userId: Int
        let user: UserInfo
        // Some payloads include assignedAt instead of createdAt/updatedAt
        let assignedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case logId
            case userId
            case user
            case assignedAt
        }
    }
    
    struct ResponseItem: Codable {
        let id: Int
        let logId: Int
        let userId: Int
        let response: String
        let accepted: Bool
        let tenantId: Int
        let createdAt: String
        let updatedAt: String?
        let user: UserInfo
        let attachments: [ResponseAttachment]?
        
        struct ResponseAttachment: Codable {
            let id: Int
            let fileName: String
            let fileType: String
            let uploadedAt: String?
        }
    }
}

struct CreateLogRequest: Codable {
    let title: String
    let description: String?
    let typeId: Int?
    let tradeId: Int?
    let statusId: Int?
    let hazardId: Int?
    let contributingConditionId: Int?
    let contributingBehaviourId: Int?
    let dueDate: String?
    let priorityId: Int?
    let folderId: Int?
    let isPrivate: Bool
    let assigneeId: Int?
    let distributionUserIds: [Int]?
    let location: String?
    let specification: String?
    let locationId: Int?
    let attachments: [AttachmentData]?
    
    struct AttachmentData: Codable {
        let fileUrl: String
        let fileName: String
        let fileType: String
    }
}

struct LogSettings: Codable {
    let types: [Log.LogType]
    let statuses: [Log.LogStatus]
    let hazards: [Log.LogHazard]
    let conditions: [Log.LogCondition]
    let behaviours: [Log.LogBehaviour]
    let trades: [Log.LogTrade]
    let priorities: [Log.LogPriority]
    let folders: [LogFolder]
    let logsRootFolderId: Int?
    let nextNumber: Int
}

struct LogFolder: Codable {
    let id: Int
    let name: String
    let parentId: Int?
}

// MARK: - Inspection Models

struct InspectionResponse: Decodable {
    let inspections: [Inspection]
}

struct InspectionDetailResponse: Decodable {
    let inspection: Inspection
}

struct ProjectInspectionTemplatesResponse: Decodable {
    let tenantTemplates: [InspectionTemplate]
    let projectTemplates: [ProjectInspectionTemplate]
}

struct Inspection: Codable, Identifiable {
    let id: Int
    let projectInspectionTemplateId: Int
    let inspectionNumber: Int
    let status: String // "NOT_STARTED" | "IN_PROGRESS" | "COMPLETED" | "FAILED"
    let locationId: Int
    let assignedToId: Int?
    let managerId: Int?
    let createdById: Int
    let startedAt: String?
    let completedAt: String?
    let signedOffAt: String?
    let signedOffById: Int?
    let notes: String?
    let createdAt: String
    let updatedAt: String?
    
    // Computed property for projectId - derived from projectInspectionTemplate
    var projectId: Int {
        return projectInspectionTemplate.projectId
    }
    
    // Related objects
    let location: ProjectLocation?
    let assignedTo: InspectionUserInfo?
    let manager: InspectionUserInfo?
    let createdBy: InspectionUserInfo?
    let signedOffBy: InspectionUserInfo?
    let projectInspectionTemplate: ProjectInspectionTemplate
    let stageResults: [InspectionStageResult]?
    
    struct InspectionUserInfo: Codable {
        let id: Int
        let email: String?
        let tenants: [InspectionTenantInfo]?
        
        struct InspectionTenantInfo: Codable {
            let firstName: String?
            let lastName: String?
            let company: InspectionCompany?
        }
        
        struct InspectionCompany: Codable {
            let id: Int
            let name: String?
        }
        
        var displayName: String {
            if let tenants = tenants, let tenant = tenants.first {
                let firstName = tenant.firstName ?? ""
                let lastName = tenant.lastName ?? ""
                if !firstName.isEmpty || !lastName.isEmpty {
                    return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                }
            }
            return email ?? "Unknown User"
        }
    }
}

struct InspectionTemplate: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let stagesSequential: Bool
    let isArchived: Bool?
    let sections: [InspectionTemplateSection]?
    let stages: [InspectionTemplateStage]?
    let _count: InspectionTemplateCount?
    
    struct InspectionTemplateCount: Codable {
        let stages: Int
    }
}

struct InspectionTemplateSection: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let order: Int
    let stages: [InspectionTemplateStage]?
}

struct ProjectInspectionTemplate: Codable, Identifiable {
    let id: Int
    let projectId: Int
    let templateId: Int
    let tenantId: Int
    let customName: String?
    let customStages: String? // JSON string, can be null
    let isActive: Bool
    let createdById: Int?
    let createdAt: String?
    let updatedAt: String?
    let template: InspectionTemplate
    let _count: ProjectInspectionTemplateCount?
    
    struct ProjectInspectionTemplateCount: Codable {
        let inspections: Int
    }
}

struct InspectionTemplateStage: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let order: Int
    let sectionId: Int?
}

struct InspectionStageResult: Codable, Identifiable {
    let id: Int
    let inspectionId: Int?
    let stageId: Int
    let status: String // "PENDING" | "YES" | "NO" | "N_A" | "SKIPPED"
    let notes: String?
    let completedAt: String?
    let completedById: Int?
    let createdAt: String?
    let updatedAt: String?
    let stage: InspectionTemplateStage
    let completedBy: Inspection.InspectionUserInfo?
    let _count: InspectionStageResultCount?
    
    struct InspectionStageResultCount: Codable {
        let defects: Int
    }
}

struct CreateInspectionRequest: Codable {
    let projectInspectionTemplateId: Int
    let locationId: Int
    let assignedToId: Int?
    let managerId: Int?
    let notes: String?
}

struct InspectionStagePhoto: Codable, Identifiable {
    let id: Int
    let stageResultId: Int
    let fileUrl: String
    let fileKey: String
    let fileName: String
    let fileType: String
    let caption: String?
    let uploadedById: Int
    let uploadedAt: String
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let locationTimestamp: String?
    let uploadedBy: Inspection.InspectionUserInfo?
}

struct InspectionStagePhotosResponse: Decodable {
    let photos: [InspectionStagePhoto]
}

// MARK: - Stage Activity Models

struct StageActivity: Codable, Identifiable {
    var id: String { "\(type)-\(timestamp)" }
    let type: String // "completion", "stage_photo", "form_response", "response_change", "form_photo", "status_change", "defect_created", "log_created", "log_closed"
    let timestamp: String
    let user: StageActivityUser?
    let status: String?
    let notes: String?
    let formItemId: String?
    let response: String?
    let oldResponse: String?
    let newResponse: String?
    let oldStatus: String?
    let newStatus: String?
    let defectId: Int?
    let description: String?
    let logId: Int?
    let logNumber: Int?
    let logTitle: String?
    let logStatus: String?
    let photo: StageActivityPhoto?
    
    struct StageActivityUser: Codable {
        let id: Int
        let email: String?
        let firstName: String?
        let lastName: String?
        
        var displayName: String {
            if let firstName = firstName, let lastName = lastName, !firstName.isEmpty || !lastName.isEmpty {
                return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            }
            return email ?? "Unknown"
        }
    }
    
    struct StageActivityPhoto: Codable {
        let id: Int
        let fileUrl: String
        let fileName: String
        let caption: String?
    }
}

// MARK: - Create Defect Log Response

struct CreateDefectLogResponse: Decodable {
    let defect: InspectionDefectResponse
    let log: Log
    let message: String?
    
    struct InspectionDefectResponse: Decodable {
        let id: Int
        let stageResultId: Int
        let description: String?
        let status: String
        let logId: Int?
        let createdById: Int?
        let assignedToId: Int?
    }
}

struct InspectionDefect: Codable, Identifiable {
    let id: Int
    let stageResultId: Int
    let snagId: Int?
    let logId: Int? // Link to Log (new defects use this instead of snagId)
    let description: String?
    let status: String // "OPEN" | "RECTIFIED" | "APPROVED" | "REJECTED"
    let assignedToId: Int?
    let createdById: Int
    let rectifiedById: Int?
    let rectifiedAt: String?
    let rectificationNotes: String?
    let approvedById: Int?
    let approvedAt: String?
    let rejectedById: Int?
    let rejectedAt: String?
    let rejectionNotes: String?
    let createdAt: String
    let updatedAt: String?
    
    // Related objects
    let stageResult: InspectionDefectStageResult?
    let createdBy: Inspection.InspectionUserInfo?
    let assignedTo: Inspection.InspectionUserInfo?
    let rectifiedBy: Inspection.InspectionUserInfo?
    let approvedBy: Inspection.InspectionUserInfo?
    let photos: [InspectionDefectPhoto]?
    let snag: InspectionDefectSnag?
    let log: InspectionDefectLog? // Linked Log (new defects use this)
    
    struct InspectionDefectStageResult: Codable {
        let stage: InspectionDefectStage
        let photos: [InspectionDefectStagePhoto]?
    }
    
    struct InspectionDefectStage: Codable {
        let id: Int
        let name: String
        let order: Int? // Optional because API might not always include it
    }
    
    struct InspectionDefectSnag: Codable {
        let id: Int
        let title: String
        let status: String
        let priority: String?
    }
    
    struct InspectionDefectLog: Codable {
        let id: Int
        let number: Int
        let title: String
        let description: String?
        let status: LogStatusInfo?
        let assigneeId: Int?
        let dueDate: String?
        
        struct LogStatusInfo: Codable {
            let id: Int
            let name: String
            let color: String?
        }
    }

    struct InspectionDefectStagePhoto: Codable, Identifiable {
        let id: Int
        let fileUrl: String
        let fileKey: String?
        let fileName: String
        let fileType: String?
        let caption: String?
        let uploadedById: Int
        let uploadedAt: String
        let latitude: Double?
        let longitude: Double?
        let accuracy: Double?
    }
    
    struct InspectionDefectPhoto: Codable, Identifiable {
        let id: Int
        let fileUrl: String
        let fileKey: String? // Optional - API might not always include this
        let fileName: String
        let uploadedById: Int
        let uploadedAt: String
        let uploadedBy: Inspection.InspectionUserInfo?
        let type: String?
    }
    
    // Computed property for display status
    var displayStatus: String {
        switch status {
        case "OPEN":
            return "Awaiting Rectification"
        case "RECTIFIED":
            return "Awaiting Review"
        case "APPROVED":
            return "Approved"
        case "REJECTED":
            return "Rejected"
        default:
            return status
        }
    }
    
}

struct InspectionDefectsResponse: Decodable {
    let defects: [InspectionDefect]
}

struct CreateDefectRequest: Codable {
    let description: String?
    let assignedToId: Int?
}

struct RectifyDefectRequest: Codable {
    let notes: String?
}

struct ProjectLocation: Codable, Identifiable {
    let id: Int
    let name: String
    let code: String?
    let parentId: Int?
    let children: [ProjectLocation]?
}

struct UsersResponse: Decodable {
    let users: [User]
}

struct FormSubmission: Identifiable, Codable {
    let id: Int
    let templateId: Int
    let templateTitle: String
    let revisionId: Int
    let versionNumber: Int?
    let status: String
    let submittedAt: String
    let submittedBy: UserInfo
    let responses: [String: FormResponseValue]?
    let fields: [FormField]
    let formNumber: String?
    let reference: String?
    let folderId: Int?
    let folder: Folder?
    let locationId: Int?
    let projectLocation: ProjectLocation?

    struct UserInfo: Codable {
        let firstName: String
        let lastName: String
    }
    
    struct CloseoutResponseValue: Codable {
        var photos: [String]?
        var signature: String?
        var status: String?
        var submittedAt: String?
        var submittedBy: String?
        var notes: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case templateId
        case templateTitle
        case revisionId
        case versionNumber
        case status
        case submittedAt
        case submittedBy
        case responses
        case fields
        case formNumber
        case reference
        case folderId
        case folder
        case locationId
        case projectLocation
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode simple fields
        id = try container.decode(Int.self, forKey: .id)
        templateId = try container.decode(Int.self, forKey: .templateId)
        templateTitle = try container.decode(String.self, forKey: .templateTitle)
        revisionId = try container.decode(Int.self, forKey: .revisionId)
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber)
        status = try container.decode(String.self, forKey: .status)
        submittedAt = try container.decode(String.self, forKey: .submittedAt)
        submittedBy = try container.decode(UserInfo.self, forKey: .submittedBy)
        fields = try container.decode([FormField].self, forKey: .fields)
        formNumber = try container.decodeIfPresent(String.self, forKey: .formNumber)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        folderId = try container.decodeIfPresent(Int.self, forKey: .folderId)
        folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
        locationId = try container.decodeIfPresent(Int.self, forKey: .locationId)
        projectLocation = try container.decodeIfPresent(ProjectLocation.self, forKey: .projectLocation)
        
        // Decode responses with a wrapper to handle mixed content
        if let rawResponses = try container.decodeIfPresent([String: FormResponseValueWrapper].self, forKey: .responses) {
            var cleanedResponses: [String: FormResponseValue] = [:]
            
            for (key, wrapper) in rawResponses {
                // Skip non-field entries like "templateId"
                if key == "templateId" {
                    continue
                }
                
                if let value = wrapper.value {
                    cleanedResponses[key] = value
                }
            }
            
            self.responses = cleanedResponses.isEmpty ? nil : cleanedResponses
        } else {
            self.responses = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(templateId, forKey: .templateId)
        try container.encode(templateTitle, forKey: .templateTitle)
        try container.encode(revisionId, forKey: .revisionId)
        try container.encodeIfPresent(versionNumber, forKey: .versionNumber)
        try container.encode(status, forKey: .status)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(submittedBy, forKey: .submittedBy)
        try container.encode(responses, forKey: .responses)
        try container.encode(fields, forKey: .fields)
        try container.encodeIfPresent(formNumber, forKey: .formNumber)
        try container.encodeIfPresent(reference, forKey: .reference)
    }
}

// Custom type to handle different response value types
// Wrapper to handle mixed content in responses dictionary
struct FormResponseValueWrapper: Codable {
    let value: FormResponseValue?
    
    init(from decoder: Decoder) throws {
        // Try to decode as FormResponseValue
        do {
            value = try FormResponseValue(from: decoder)
        } catch {
            // If it fails (e.g., for "templateId": "5"), set to nil
            value = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        if let value = value {
            try value.encode(to: encoder)
        }
    }
}

enum FormResponseValue: Codable {
    case string(String)
    case stringArray([String])
    case int(Int)
    case double(Double)
    case repeater([[String: FormResponseValue]])
    case closeout(FormSubmission.CloseoutResponseValue)
    case camera(CameraResponseValue)
    case cameraArray([CameraResponseValue])
    case null
    
    struct CameraResponseValue: Codable {
        var image: String
        let location: LocationData?
        let capturedAt: String?
        
        struct LocationData: Codable {
            let latitude: Double
            let longitude: Double
            let accuracy: Double?
            let timestamp: Double?
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as camera array first (for multiple photos with image + location)
        do {
            let cameraArray = try container.decode([CameraResponseValue].self)
            self = .cameraArray(cameraArray)
            return
        } catch {
            // Camera array decode failed, try single camera
        }
        
        // Try to decode as single camera data (for fields that have image + location)
        // Camera data comes as an object with image, location, and capturedAt properties
        do {
            let cameraData = try container.decode(CameraResponseValue.self)
            self = .camera(cameraData)
            return
        } catch {
            // Camera decode failed, try other types
        }
        
        if let repeaterData = try? container.decode([[String: FormResponseValue]].self) {
            self = .repeater(repeaterData)
            return
        }
        
        if let closeoutData = try? container.decode(FormSubmission.CloseoutResponseValue.self) {
            self = .closeout(closeoutData)
            return
        }

        // Try to decode repeater data from JSON string (for compatibility with mobile app)
        if let jsonString = try? container.decode(String.self),
           let jsonData = jsonString.data(using: .utf8) {
            // First try to decode as structured repeater data
            if let repeaterData = try? JSONDecoder().decode([[String: FormResponseValue]].self, from: jsonData) {
                self = .repeater(repeaterData)
                return
            }
            // If that fails, try to decode as simple array of string dictionaries
            if let simpleRepeaterData = try? JSONDecoder().decode([[String: String]].self, from: jsonData) {
                let convertedData = simpleRepeaterData.map { row in
                    row.mapValues { value in
                        FormResponseValue.string(value)
                    }
                }
                self = .repeater(convertedData)
                return
            }
        }
        
        if let stringArray = try? container.decode([String].self) {
            self = .stringArray(stringArray)
            return
        }
        
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }

        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        
        if container.decodeNil() {
            self = .null
            return
        }

        throw DecodingError.typeMismatch(FormResponseValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported form response value"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .stringArray(let array):
            try container.encode(array)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .repeater(let repeaterData):
            try container.encode(repeaterData)
        case .closeout(let closeoutData):
            try container.encode(closeoutData)
        case .camera(let cameraData):
            try container.encode(cameraData)
        case .cameraArray(let cameraArray):
            try container.encode(cameraArray)
        case .null:
            try container.encodeNil()
        }
    }
    
    // Helper properties for easier access
    var stringValue: String {
        switch self {
        case .string(let str): return str
        case .camera(let cameraData): return cameraData.image
        case .cameraArray(let cameraArray): return cameraArray.first?.image ?? ""
        default: return ""
        }
    }
    
    var stringArrayValue: [String] {
        switch self {
        case .stringArray(let arr): return arr
        case .string(let str): return [str]
        case .camera(let cameraData): return [cameraData.image]
        case .cameraArray(let cameraArray): return cameraArray.map { $0.image }
        default: return []
        }
    }
}

struct FormModel: Identifiable, Codable {
    let id: Int
    let title: String
    var reference: String?
    var description: String?
    let tenantId: Int
    let createdAt: String
    let updatedAt: String
    let createdById: Int?
    var status: String
    let isArchived: Bool
    let restrictToMainCompany: Bool
    let revisions: [FormRevision]?
    
    var currentRevision: FormRevision? {
        if let liveRevision = revisions?.first(where: { $0.isLive == true }) {
            return liveRevision
        }
        if let publishedRevision = revisions?.first(where: { $0.status?.lowercased() == "published" }) {
            return publishedRevision
        }
        return revisions?.sorted(by: { $0.versionNumber ?? 0 > $1.versionNumber ?? 0 }).first
    }
}

struct FormRevision: Codable {
    let id: Int
    let formTemplateId: Int?
    let versionNumber: Int?
    let fields: [FormField]
    let notes: String?
    let createdAt: String?
    let createdById: Int?
    let status: String?
    let isLive: Bool?
}

struct FormField: Codable {
    let id: String
    let label: String
    let type: String
    let required: Bool
    let options: [String]?
    let subFields: [FormField]?
    let minItems: Int?
    let maxItems: Int?
    let addButtonText: String?
    let removeButtonText: String?
    let description: String?
    let placeholder: String?
    let submissionRequirement: SubmissionRequirement?
    let closeoutSettings: CloseoutSettings?
    // Table field properties
    let tableColumns: [TableColumn]?
    let minRows: Int?
    let maxRows: Int?
    let enableRowNames: Bool?
    let rowNameLabel: String?
    let tableMode: String? // 'dynamic' or 'static'
    let staticRows: [StaticRow]?
}

struct TableColumn: Codable {
    let id: String
    let label: String
    let type: String // 'text', 'number', 'date', 'dropdown', 'checkbox'
    let required: Bool?
    let options: [String]?
}

struct StaticRow: Codable {
    let id: String
    let name: String
}

struct CloseoutSettings: Codable {
    let requiresApproval: Bool?
    let approvalRoles: [String]?
    let requiresSignature: Bool?
    let requiresPhotos: Bool?
    let requiresNotes: Bool?
    let minimumPhotos: Int?
    let autoCompleteOnApproval: Bool?
}

struct SubmissionRequirement: Codable {
    let requiredValue: String
    let validationMessage: String
    let requiredForSubmission: Bool
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

// MARK: - Timesheet Clock API Models

struct TimesheetGeofenceResponse: Decodable {
    let geofence: TimesheetGeofence?
    let signInAreaMode: String?
    let clockLocations: [TimesheetClockLocation]?
}

struct TimesheetClockLocation: Decodable {
    let id: Int
    let type: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let radiusMeters: Double?
}

struct TimesheetGeofence: Decodable {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double?
    let name: String?
}

struct TimesheetClockStatusResponse: Decodable {
    let activeClocks: [TimesheetActiveClock]
}

struct TimesheetActiveClock: Decodable {
    let id: Int
    let projectId: Int
    let project: TimesheetClockProject
    let signedInAt: Date
}

struct TimesheetClockProject: Decodable {
    let id: Int
    let name: String
    let reference: String
}

struct TimesheetClockProjectsResponse: Decodable {
    let projects: [TimesheetClockProject]
}

struct TimesheetProjectClock: Decodable {
    let id: Int
    let tenantId: Int
    let userId: Int
    let projectId: Int
    let signedInAt: Date
    let signedOutAt: Date?
    let project: TimesheetClockProject
}

struct ClockHistoryResponse: Decodable {
    let sessions: [ClockHistorySession]
}

struct ClockHistorySession: Decodable, Identifiable {
    let id: Int
    let signedInAt: Date
    let signedOutAt: Date
    let hours: Double
}

// MARK: - Timesheets (submit for approval) Models

struct TimesheetsListResponse: Decodable {
    let timesheets: [Timesheet]
}

struct Timesheet: Decodable, Identifiable {
    let id: Int
    let tenantId: Int
    let userId: Int
    let periodStart: Date
    let periodEnd: Date
    let status: String // DRAFT | SUBMITTED | APPROVED | REJECTED
    let entries: [TimesheetEntry]?
    let expenses: [TimesheetExpense]?
    let approvedBy: TimesheetApprovedBy?
}

struct TimesheetEntry: Decodable, Identifiable {
    let id: Int
    let timesheetId: Int
    let projectId: Int?
    let hours: Double
    let description: String?
    let fromTime: String?
    let toTime: String?
    let breakHours: Double?
    let unpaid: Bool?
    let isNonWorking: Bool?
    let project: TimesheetEntryProject?
}

struct TimesheetEntryProject: Decodable {
    let id: Int
    let name: String
    let reference: String?
}

struct TimesheetExpense: Decodable, Identifiable {
    let id: Int
    let timesheetId: Int
    let amount: Double
    let description: String?
}

struct TimesheetApprovedBy: Decodable {
    let id: Int
    let email: String?
    let tenants: [TimesheetTenantUser]?
}

struct TimesheetTenantUser: Decodable {
    let firstName: String?
    let lastName: String?
}

// MARK: - Chat Response Models

struct ChatConversationWithMessages: Codable {
    let id: Int
    let projectId: Int
    let userId: Int
    let tenantId: Int
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let archived: Bool
    let messages: [ChatMessage]
    
    enum CodingKeys: String, CodingKey {
        case id, projectId, userId, tenantId, title, archived, messages
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }
}

struct EmptyResponse: Codable {
    // Empty response for DELETE requests
}

// MARK: - Qualification Models

struct UserQualificationsResponse: Codable {
    let qualifications: [UserQualificationGroup]
    let totalQualifications: Int
    let userQualificationCount: Int
}

struct UserQualificationGroup: Codable, Identifiable {
    let qualification: QualificationInfo
    let records: [UserQualificationRecord]
    
    var id: Int { qualification.id }
}

struct QualificationInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let order: Int
}

struct UserQualificationRecord: Codable, Identifiable {
    let id: Int
    let qualificationId: Int
    let qualificationName: String
    let obtainedAt: String?
    let expiresAt: String?
    let notes: String?
    let fileUrl: String?
    let fileName: String?
    let isExpired: Bool
    let isCurrent: Bool?
    let cscsCardNumber: String?
    let cscsValidatedAt: String?
    let cscsValidationStatus: String?
}
