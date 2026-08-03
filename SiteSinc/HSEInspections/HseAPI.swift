import Foundation

// MARK: - HSE Inspections API (/api/hse-inspections)
// Mirrors apps/api/src/routes/hseInspectionRoutes.ts.

extension APIClient {

    private static var hseBase: String { "\(baseURL)/hse-inspections" }

    private static let hseISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Request helpers

    private static func hseRequest(_ path: String, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(hseBase)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private static func hseJSONRequest(_ path: String, method: String, body: [String: Any], token: String) throws -> URLRequest {
        var request = hseRequest(path, method: method, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Decodes an HSE response, mapping server error bodies to APIError like
    /// performRequest does (which is private to APIClient.swift).
    private static func hseSend<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, http) = try await authorizedData(for: request)
        try hseCheckStatus(http, data: data)
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            print("❌ [HSE API] Decoding error for \(request.url?.absoluteString ?? ""): \(error)")
            throw APIError.decodingError(error)
        }
    }

    private static func hseSendIgnoringBody(_ request: URLRequest) async throws {
        let (data, http) = try await authorizedData(for: request)
        try hseCheckStatus(http, data: data)
    }

    private static func hseCheckStatus(_ http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200, 201, 204:
            return
        case 401:
            throw APIError.tokenExpired
        case 403:
            // Route-level errors (e.g. "Only the inspector can edit this
            // inspection") arrive as { error } with 403 — surface the message.
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let msg = err.error ?? err.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            throw APIError.forbidden
        default:
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let msg = err.error ?? err.message, !msg.isEmpty {
                throw APIError.badRequest(message: msg)
            }
            throw APIError.invalidResponse(statusCode: http.statusCode)
        }
    }

    // MARK: Tenant configuration

    static func fetchHseAvailableTemplates(projectId: Int, token: String) async throws -> [HseAvailableTemplate] {
        try await hseSend(hseRequest("/templates/available?projectId=\(projectId)", token: token))
    }

    static func fetchHseHeaderFields(token: String) async throws -> [HseInspectionHeaderField] {
        try await hseSend(hseRequest("/header-fields", token: token))
    }

    static func fetchHseCategories(token: String) async throws -> [HseObservationCategory] {
        try await hseSend(hseRequest("/categories", token: token))
    }

    static func fetchHseProjectUsers(projectId: Int, token: String) async throws -> [HseUser] {
        let response: HseProjectUsersResponse = try await hseSend(hseRequest("/projects/\(projectId)/users", token: token))
        return response.users.filter { !AppBrand.isHiddenPlatformUser(email: $0.email) }
    }

    // MARK: Inspections

    static func fetchHseInspections(projectId: Int, includeHistory: Bool = false, token: String) async throws -> [HseInspection] {
        let query = includeHistory ? "?includeHistory=true" : ""
        return try await hseSend(hseRequest("/projects/\(projectId)/inspections\(query)", token: token))
    }

    static func fetchHseInspection(projectId: Int, inspectionId: Int, token: String) async throws -> HseInspection {
        try await hseSend(hseRequest("/projects/\(projectId)/inspections/\(inspectionId)", token: token))
    }

    /// Creates an inspection. Status "draft" (default) or "submitted".
    static func createHseInspection(
        projectId: Int,
        templateId: Int,
        status: String = "draft",
        conductedAt: Date? = nil,
        accompaniedById: Int? = nil,
        keyPersonnelIds: [Int]? = nil,
        headerData: [String: String]? = nil,
        locationId: Int? = nil,
        token: String
    ) async throws -> HseInspection {
        var body: [String: Any] = [
            "templateId": templateId,
            "status": status,
            "data": [String: Any](),
        ]
        if let conductedAt { body["conductedAt"] = hseISOFormatter.string(from: conductedAt) }
        if let accompaniedById { body["accompaniedById"] = accompaniedById }
        if let keyPersonnelIds { body["keyPersonnelIds"] = keyPersonnelIds }
        if let headerData { body["headerData"] = headerData }
        if let locationId { body["locationId"] = locationId }
        return try await hseSend(try hseJSONRequest("/projects/\(projectId)/inspections", method: "POST", body: body, token: token))
    }

    /// Updates a draft (autosave header fields) and/or submits it.
    /// Pass `.some(nil)` in the optional-of-optional params to clear a value.
    static func updateHseInspection(
        projectId: Int,
        inspectionId: Int,
        status: String? = nil,
        conductedAt: Date?? = nil,
        accompaniedById: Int?? = nil,
        keyPersonnelIds: [Int]? = nil,
        headerData: [String: String]? = nil,
        locationId: Int?? = nil,
        token: String
    ) async throws -> HseInspection {
        var body: [String: Any] = [:]
        if let status { body["status"] = status }
        if let conductedAt { body["conductedAt"] = conductedAt.map { hseISOFormatter.string(from: $0) } ?? NSNull() }
        if let accompaniedById { body["accompaniedById"] = accompaniedById ?? NSNull() }
        if let keyPersonnelIds { body["keyPersonnelIds"] = keyPersonnelIds }
        if let headerData { body["headerData"] = headerData }
        if let locationId { body["locationId"] = locationId ?? NSNull() }
        return try await hseSend(try hseJSONRequest("/projects/\(projectId)/inspections/\(inspectionId)", method: "PUT", body: body, token: token))
    }

    /// Manually closes a submitted inspection (all observations must be closed).
    static func closeHseInspection(projectId: Int, inspectionId: Int, token: String) async throws -> HseInspection {
        try await hseSend(try hseJSONRequest("/projects/\(projectId)/inspections/\(inspectionId)", method: "PUT", body: ["status": "closed"], token: token))
    }

    static func deleteHseInspectionDraft(projectId: Int, inspectionId: Int, token: String) async throws {
        try await hseSendIgnoringBody(hseRequest("/projects/\(projectId)/inspections/\(inspectionId)", method: "DELETE", token: token))
    }

    /// Creates a new draft report revision from a submitted/closed inspection.
    static func createHseReportRevision(projectId: Int, inspectionId: Int, token: String) async throws -> HseInspection {
        var request = hseRequest("/projects/\(projectId)/inspections/\(inspectionId)/revisions", method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await hseSend(request)
    }

    // MARK: Observations

    static func fetchHseObservations(
        projectId: Int,
        status: HseObservationStatus? = nil,
        assignedToId: Int? = nil,
        inspectionId: Int? = nil,
        token: String
    ) async throws -> [HseObservation] {
        var components = URLComponents(string: "\(hseBase)/projects/\(projectId)/observations")!
        var items: [URLQueryItem] = []
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let assignedToId { items.append(URLQueryItem(name: "assignedToId", value: String(assignedToId))) }
        if let inspectionId { items.append(URLQueryItem(name: "inspectionId", value: String(inspectionId))) }
        if !items.isEmpty { components.queryItems = items }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return try await hseSend(request)
    }

    static func fetchHseObservation(projectId: Int, observationId: Int, token: String) async throws -> HseObservation {
        try await hseSend(hseRequest("/projects/\(projectId)/observations/\(observationId)", token: token))
    }

    static func createHseObservation(
        projectId: Int,
        inspectionId: Int,
        sectionId: String,
        description: String,
        categoryId: Int? = nil,
        categoryData: [String: String]? = nil,
        assignedToId: Int? = nil,
        dueDate: Date? = nil,
        locationId: Int? = nil,
        token: String
    ) async throws -> HseObservation {
        var body: [String: Any] = [
            "sectionId": sectionId,
            "description": description,
        ]
        if let categoryId { body["categoryId"] = categoryId }
        if let categoryData { body["categoryData"] = categoryData }
        if let assignedToId { body["assignedToId"] = assignedToId }
        if let dueDate { body["dueDate"] = hseISOFormatter.string(from: dueDate) }
        if let locationId { body["locationId"] = locationId }
        return try await hseSend(try hseJSONRequest("/projects/\(projectId)/inspections/\(inspectionId)/observations", method: "POST", body: body, token: token))
    }

    /// Partial update. Pass `.some(nil)` to clear assignee/due date/location.
    static func updateHseObservation(
        projectId: Int,
        observationId: Int,
        description: String? = nil,
        categoryId: Int?? = nil,
        categoryData: [String: String]? = nil,
        assignedToId: Int?? = nil,
        dueDate: Date?? = nil,
        locationId: Int?? = nil,
        token: String
    ) async throws -> HseObservation {
        var body: [String: Any] = [:]
        if let description { body["description"] = description }
        if let categoryId { body["categoryId"] = categoryId ?? NSNull() }
        if let categoryData { body["categoryData"] = categoryData }
        if let assignedToId { body["assignedToId"] = assignedToId ?? NSNull() }
        if let dueDate { body["dueDate"] = dueDate.map { hseISOFormatter.string(from: $0) } ?? NSNull() }
        if let locationId { body["locationId"] = locationId ?? NSNull() }
        return try await hseSend(try hseJSONRequest("/projects/\(projectId)/observations/\(observationId)", method: "PATCH", body: body, token: token))
    }

    static func deleteHseObservation(projectId: Int, observationId: Int, token: String) async throws {
        try await hseSendIgnoringBody(hseRequest("/projects/\(projectId)/observations/\(observationId)", method: "DELETE", token: token))
    }

    /// Workflow actions: "start", "submit" (notes required), "approve", "reject" (notes required).
    static func postHseObservationStatus(
        projectId: Int,
        observationId: Int,
        action: String,
        notes: String? = nil,
        token: String
    ) async throws -> HseObservationStatusResult {
        var body: [String: Any] = ["action": action]
        if let notes { body["notes"] = notes }
        let request = try hseJSONRequest("/projects/\(projectId)/observations/\(observationId)/status", method: "POST", body: body, token: token)
        let (data, http) = try await authorizedData(for: request)
        try hseCheckStatus(http, data: data)
        do {
            let observation = try makeDecoder().decode(HseObservation.self, from: data)
            let flag = try? JSONDecoder().decode(HseInspectionClosedFlag.self, from: data)
            return HseObservationStatusResult(observation: observation, inspectionClosed: flag?.inspectionClosed ?? false)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    static func addHseObservationComment(projectId: Int, observationId: Int, comment: String, token: String) async throws -> HseObservationComment {
        try await hseSend(try hseJSONRequest("/projects/\(projectId)/observations/\(observationId)/comments", method: "POST", body: ["comment": comment], token: token))
    }

    // MARK: Photos

    /// Uploads stamped photos to an observation. Images go in the `photos`
    /// multipart field; the server persists the GPS/timestamp metadata.
    static func uploadHseObservationPhotos(
        projectId: Int,
        observationId: Int,
        images: [(data: Data, fileName: String)],
        photoType: HsePhotoType,
        caption: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracy: Double? = nil,
        capturedAt: Date? = nil,
        token: String
    ) async throws -> [HseObservationPhoto] {
        var request = hseRequest("/projects/\(projectId)/observations/\(observationId)/photos", method: "POST", token: token)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        for image in images {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"photos\"; filename=\"\(image.fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(image.data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField("photoType", photoType.rawValue)
        if let caption, !caption.isEmpty { appendField("caption", caption) }
        if let latitude { appendField("latitude", String(latitude)) }
        if let longitude { appendField("longitude", String(longitude)) }
        if let accuracy { appendField("accuracy", String(accuracy)) }
        if let capturedAt { appendField("capturedAt", hseISOFormatter.string(from: capturedAt)) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let response: HseObservationPhotosResponse = try await hseSend(request)
        return response.photos
    }

    static func deleteHseObservationPhoto(projectId: Int, observationId: Int, photoId: Int, token: String) async throws {
        try await hseSendIgnoringBody(hseRequest("/projects/\(projectId)/observations/\(observationId)/photos/\(photoId)", method: "DELETE", token: token))
    }

    /// Re-signs an expired R2 URL for a stored file key.
    static func refreshHseFileUrl(fileKey: String, token: String) async throws -> String {
        let response: HseRefreshUrlResponse = try await hseSend(try hseJSONRequest("/refresh-url", method: "POST", body: ["fileKey": fileKey], token: token))
        return response.url
    }

    // MARK: PDF report

    static func downloadHseInspectionPdf(projectId: Int, inspectionId: Int, token: String) async throws -> Data {
        let request = hseRequest("/projects/\(projectId)/inspections/\(inspectionId)/pdf", token: token)
        let (data, http) = try await authorizedData(for: request)
        try hseCheckStatus(http, data: data)
        return data
    }
}
