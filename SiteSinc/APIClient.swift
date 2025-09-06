import Foundation
import UIKit

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
    case decodingError(Error)
    case networkError(Error)
}

struct APIClient {
    #if DEBUG
    static let baseURL = "http://localhost:3000/api"
//    static let baseURL = "https://sitesinc.onrender.com/api"
    #else
    static let baseURL = "https://sitesinc.onrender.com/api"
    #endif
    
    // MARK: - Helper Function for API Requests
    private static func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if T.self == FormModel.self {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Raw JSON response for FormModel decoding at \(request.url?.absoluteString ?? "unknown URL"):\n\(jsonString)")
                }
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: -1)
            }
            switch httpResponse.statusCode {
            case 200, 204:
                return try JSONDecoder().decode(T.self, from: data)
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
    
    static func fetchDrawings(projectId: Int, token: String) async throws -> [Drawing] {
        let url = URL(string: "\(baseURL)/drawings?projectId=\(projectId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let drawingResponse: DrawingResponse = try await performRequest(request)
        return drawingResponse.drawings.filter { $0.projectId == projectId }
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
        let assignments: [SnagCompanyAssignment]?
        var attachments: [SnagAttachment]?
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
    static func createSnag(projectId: Int, drawingId: Int, drawingFileId: Int, page: Int, position: SnagPosition, title: String, description: String?, companyIds: [Int] = [], priority: String? = nil, status: String? = nil, responseDate: String? = nil, photos: [Data] = [], token: String) async throws -> Snag {
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
