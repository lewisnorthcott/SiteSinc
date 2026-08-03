import Foundation
import UniformTypeIdentifiers

// MARK: - SiteDrive API (/api/sitedrive)
// Mirrors apps/api/src/routes/siteDriveRoutes.ts. Modeled on HseAPI.swift.

extension APIClient {

    private static var siteDriveBase: String { "\(baseURL)/sitedrive" }

    // MARK: Request helpers

    private static func siteDriveRequest(_ path: String, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(siteDriveBase)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private static func siteDriveJSONRequest(_ path: String, method: String, body: [String: Any], token: String) throws -> URLRequest {
        var request = siteDriveRequest(path, method: method, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func siteDriveSend<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, http) = try await authorizedData(for: request)
        try siteDriveCheckStatus(http, data: data)
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            print("❌ [SiteDrive API] Decoding error for \(request.url?.absoluteString ?? ""): \(error)")
            throw APIError.decodingError(error)
        }
    }

    private static func siteDriveSendIgnoringBody(_ request: URLRequest) async throws {
        let (data, http) = try await authorizedData(for: request)
        try siteDriveCheckStatus(http, data: data)
    }

    private static func siteDriveCheckStatus(_ http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200, 201, 204:
            return
        case 401:
            throw APIError.tokenExpired
        case 403:
            // Route-level messages (e.g. company drive is read-only) arrive as
            // { error } with 403 — surface them instead of a generic error.
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let msg = err.error ?? err.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            throw APIError.forbidden
        case 413:
            throw APIError.badRequest(message: "File is too large for SiteDrive (max 250 MB)")
        default:
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let msg = err.error ?? err.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }
    }

    // MARK: Capabilities / folders / items

    static func fetchSiteDriveCapabilities(scope: SiteDriveScope, projectId: Int, token: String) async throws -> SiteDriveCapabilities {
        try await siteDriveSend(siteDriveRequest("/capabilities?scope=\(scope.rawValue)&projectId=\(projectId)", token: token))
    }

    static func fetchSiteDriveFolders(scope: SiteDriveScope, projectId: Int, token: String) async throws -> [SiteDriveFolder] {
        try await siteDriveSend(siteDriveRequest("/folders?scope=\(scope.rawValue)&projectId=\(projectId)", token: token))
    }

    static func fetchSiteDriveItems(
        scope: SiteDriveScope,
        projectId: Int,
        folderId: Int?,
        offset: Int = 0,
        limit: Int = 60,
        token: String
    ) async throws -> SiteDriveItemsPage {
        var path = "/items?scope=\(scope.rawValue)&projectId=\(projectId)&offset=\(offset)&limit=\(limit)"
        if let folderId { path += "&folderId=\(folderId)" }
        return try await siteDriveSend(siteDriveRequest(path, token: token))
    }

    static func fetchSiteDriveItem(itemId: Int, token: String) async throws -> SiteDriveItem {
        try await siteDriveSend(siteDriveRequest("/items/\(itemId)", token: token))
    }

    // MARK: Folder mutations

    static func createSiteDriveFolder(
        scope: SiteDriveScope,
        projectId: Int,
        name: String,
        parentId: Int? = nil,
        isPrivate: Bool = false,
        token: String
    ) async throws -> SiteDriveFolder {
        var body: [String: Any] = [
            "scope": scope.rawValue,
            "projectId": projectId,
            "name": name,
            "isPrivate": isPrivate,
        ]
        if let parentId { body["parentId"] = parentId }
        return try await siteDriveSend(try siteDriveJSONRequest("/folders", method: "POST", body: body, token: token))
    }

    /// Partial update. Pass `.some(nil)` for `parentId` to move to root.
    static func updateSiteDriveFolder(
        folderId: Int,
        name: String? = nil,
        parentId: Int?? = nil,
        isPrivate: Bool? = nil,
        token: String
    ) async throws -> SiteDriveFolder {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let parentId { body["parentId"] = parentId ?? NSNull() }
        if let isPrivate { body["isPrivate"] = isPrivate }
        return try await siteDriveSend(try siteDriveJSONRequest("/folders/\(folderId)", method: "PUT", body: body, token: token))
    }

    /// Deletes a folder recursively (subfolders and files included).
    static func deleteSiteDriveFolder(folderId: Int, token: String) async throws {
        try await siteDriveSendIgnoringBody(siteDriveRequest("/folders/\(folderId)", method: "DELETE", token: token))
    }

    // MARK: Item mutations

    /// Partial update. Pass `.some(nil)` for `folderId` to move to root.
    static func updateSiteDriveItem(
        itemId: Int,
        name: String? = nil,
        folderId: Int?? = nil,
        token: String
    ) async throws -> SiteDriveItem {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let folderId { body["folderId"] = folderId ?? NSNull() }
        return try await siteDriveSend(try siteDriveJSONRequest("/items/\(itemId)", method: "PUT", body: body, token: token))
    }

    static func deleteSiteDriveItem(itemId: Int, token: String) async throws {
        try await siteDriveSendIgnoringBody(siteDriveRequest("/items/\(itemId)", method: "DELETE", token: token))
    }

    // MARK: URLs

    /// Presigned R2 URL (7-day expiry) for a specific revision.
    static func fetchSiteDriveDownloadUrl(itemId: Int, revisionId: Int, token: String) async throws -> String {
        let response: SiteDriveDownloadUrlResponse = try await siteDriveSend(
            siteDriveRequest("/items/\(itemId)/download/\(revisionId)", token: token)
        )
        return response.downloadUrl
    }

    /// SharePoint/M365 web URL for Office files, when the item is linked.
    static func fetchSiteDriveOnlineUrl(itemId: Int, token: String) async throws -> String? {
        let response: SiteDriveOnlineUrlResponse = try await siteDriveSend(
            siteDriveRequest("/items/\(itemId)/online-url", token: token)
        )
        return response.webUrl
    }

    // MARK: Upload

    /// Multipart upload. Uploading a file whose name already exists in the same
    /// folder creates a new revision (HTTP 200) instead of a new item (HTTP 201).
    static func uploadSiteDriveFile(
        scope: SiteDriveScope,
        projectId: Int,
        folderId: Int?,
        fileData: Data,
        fileName: String,
        mimeType: String? = nil,
        token: String
    ) async throws -> SiteDriveUploadResponse {
        var request = siteDriveRequest("/items/upload", method: "POST", token: token)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let resolvedMime = mimeType ?? Self.mimeType(forFileName: fileName)

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(resolvedMime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("scope", scope.rawValue)
        appendField("projectId", String(projectId))
        if let folderId { appendField("folderId", String(folderId)) }
        appendField("name", fileName)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await siteDriveSend(request)
    }

    private static func mimeType(forFileName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
