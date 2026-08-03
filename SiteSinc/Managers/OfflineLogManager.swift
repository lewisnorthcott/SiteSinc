import Foundation
import Combine
import Network

// MARK: - Offline Log Models

struct OfflineLog: Codable, Identifiable {
    let id: String
    let projectId: Int
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
    let attachments: [OfflineLogAttachment]?
    let createdAt: Date
    // NOTE: never persist auth tokens in queue files. Sync reads a fresh
    // token from the Keychain at send time. (Older queue files contained a
    // "token" key; it is ignored on decode.)

    // Incident fields
    let recordType: String?
    let isAnonymous: Bool?
    let occurredAt: String?
    let incidentSeverityBand: String?
    let injuryInvolved: Bool?
    let regulatoryNotifiable: Bool?
    let incidentPayload: IncidentPayload?
    
    struct OfflineLogAttachment: Codable {
        let fileName: String
        let fileType: String
        let fileData: Data // Store actual file data for offline
    }
}

struct OfflineLogResponse: Codable, Identifiable {
    let id: String
    let projectId: Int
    let logId: Int
    let response: String
    let accepted: Bool
    let photos: [OfflineResponsePhoto]
    let createdAt: Date
    
    struct OfflineResponsePhoto: Codable {
        let fileName: String
        let fileData: Data
    }
}

struct CachedLogData: Codable {
    let logs: [Log]
    let cachedAt: Date
    let projectId: Int
}

// MARK: - OfflineLogManager

@MainActor
class OfflineLogManager: ObservableObject {
    static let shared = OfflineLogManager()
    
    @Published var pendingLogs: [OfflineLog] = []
    @Published var pendingResponses: [OfflineLogResponse] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    @Published var isOffline = false
    
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sitesinc.offlineLogManager")
    
    private init() {
        loadPendingItems()
        setupNetworkMonitoring()
    }
    
    // MARK: - Computed Properties
    
    var pendingLogsCount: Int {
        return pendingLogs.count
    }
    
    var pendingResponsesCount: Int {
        return pendingResponses.count
    }
    
    var totalPendingCount: Int {
        return pendingLogsCount + pendingResponsesCount
    }
    
    // MARK: - Directory Management
    
    private var logsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let logsURL = paths[0].appendingPathComponent("offline_logs")
        if !FileManager.default.fileExists(atPath: logsURL.path) {
            try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true, attributes: nil)
        }
        return logsURL
    }
    
    private var responsesDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let responsesURL = paths[0].appendingPathComponent("offline_log_responses")
        if !FileManager.default.fileExists(atPath: responsesURL.path) {
            try? FileManager.default.createDirectory(at: responsesURL, withIntermediateDirectories: true, attributes: nil)
        }
        return responsesURL
    }
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let cacheURL = paths[0].appendingPathComponent("log_cache")
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        return cacheURL
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                
                if wasOffline && path.status == .satisfied {
                    print("OfflineLogManager: Network connection restored")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    self?.syncPendingItems()
                } else if path.status != .satisfied {
                    print("OfflineLogManager: Network connection lost")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    // MARK: - Log Caching (for offline viewing)
    
    func cacheLogs(_ logs: [Log], forProject projectId: Int) {
        Task.detached {
            let cachedData = CachedLogData(logs: logs, cachedAt: Date(), projectId: projectId)
            let fileURL = await self.cacheDirectory.appendingPathComponent("project_\(projectId)_logs.json")
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(cachedData)
                try data.write(to: fileURL)
                print("OfflineLogManager: Cached \(logs.count) logs for project \(projectId)")
            } catch {
                print("OfflineLogManager: Failed to cache logs: \(error)")
            }
        }
    }
    
    func getCachedLogs(forProject projectId: Int) -> [Log]? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_logs.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedData = try decoder.decode(CachedLogData.self, from: data)
            
            // Check if cache is still valid (24 hours)
            let cacheAge = Date().timeIntervalSince(cachedData.cachedAt)
            if cacheAge > 86400 { // 24 hours
                print("OfflineLogManager: Cache expired for project \(projectId)")
                return nil
            }
            
            print("OfflineLogManager: Loaded \(cachedData.logs.count) cached logs for project \(projectId)")
            return cachedData.logs
        } catch {
            print("OfflineLogManager: Failed to decode cached logs: \(error)")
            return nil
        }
    }
    
    func getCacheAge(forProject projectId: Int) -> Date? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_logs.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // must match cacheLogs' encoder
        guard let cachedData = try? decoder.decode(CachedLogData.self, from: data) else {
            return nil
        }
        
        return cachedData.cachedAt
    }
    
    // MARK: - Pending Log Management
    
    func saveLog(_ log: OfflineLog) {
        pendingLogs.append(log)
        
        Task.detached {
            let fileURL = await self.logsDirectory.appendingPathComponent("\(log.id).json")
            do {
                let data = try JSONEncoder().encode(log)
                try data.write(to: fileURL)
                print("OfflineLogManager: Saved log offline: \(log.id)")
            } catch {
                print("OfflineLogManager: Failed to save log offline: \(error)")
            }
        }
    }

    func queueQuickCaptureLog(projectId: Int, projectName: String, request: CreateLogRequest, localFileURLs: [URL]) {
        let attachments: [OfflineLog.OfflineLogAttachment]? = localFileURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return OfflineLog.OfflineLogAttachment(fileName: url.lastPathComponent, fileType: "image/jpeg", fileData: data)
        }
        let offlineLog = OfflineLog(
            id: UUID().uuidString,
            projectId: projectId,
            title: request.title,
            description: request.description,
            typeId: request.typeId,
            tradeId: request.tradeId,
            statusId: request.statusId,
            hazardId: request.hazardId,
            contributingConditionId: request.contributingConditionId,
            contributingBehaviourId: request.contributingBehaviourId,
            dueDate: request.dueDate,
            priorityId: request.priorityId,
            folderId: request.folderId,
            isPrivate: request.isPrivate,
            assigneeId: request.assigneeId,
            distributionUserIds: request.distributionUserIds,
            location: request.location,
            specification: request.specification,
            locationId: request.locationId,
            attachments: attachments?.isEmpty == false ? attachments : nil,
            createdAt: Date(),
            recordType: request.recordType,
            isAnonymous: request.isAnonymous,
            occurredAt: request.occurredAt,
            incidentSeverityBand: request.incidentSeverityBand,
            injuryInvolved: request.injuryInvolved,
            regulatoryNotifiable: request.regulatoryNotifiable,
            incidentPayload: request.incidentPayload
        )
        saveLog(offlineLog)
    }
    
    func saveResponse(_ response: OfflineLogResponse) {
        pendingResponses.append(response)
        
        Task.detached {
            let fileURL = await self.responsesDirectory.appendingPathComponent("\(response.id).json")
            do {
                let data = try JSONEncoder().encode(response)
                try data.write(to: fileURL)
                print("OfflineLogManager: Saved response offline: \(response.id)")
            } catch {
                print("OfflineLogManager: Failed to save response offline: \(error)")
            }
        }
    }
    
    private func loadPendingItems() {
        Task {
            // Load pending logs
            let logs = await Task.detached {
                let fileURLs = (try? FileManager.default.contentsOfDirectory(
                    at: await self.logsDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
                
                return fileURLs.compactMap { url -> OfflineLog? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(OfflineLog.self, from: data)
                }
            }.value
            
            // Load pending responses
            let responses = await Task.detached {
                let fileURLs = (try? FileManager.default.contentsOfDirectory(
                    at: await self.responsesDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
                
                return fileURLs.compactMap { url -> OfflineLogResponse? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(OfflineLogResponse.self, from: data)
                }
            }.value
            
            await MainActor.run {
                self.pendingLogs = logs
                self.pendingResponses = responses
                print("OfflineLogManager: Loaded \(logs.count) pending logs, \(responses.count) pending responses")
            }
        }
    }
    
    // MARK: - Sync
    
    func manualSync() {
        print("OfflineLogManager: Manual sync triggered")
        syncPendingItems()
    }
    
    private func syncPendingItems() {
        guard !syncInProgress else {
            print("OfflineLogManager: Sync already in progress")
            return
        }
        
        guard !pendingLogs.isEmpty || !pendingResponses.isEmpty else {
            print("OfflineLogManager: No pending items to sync")
            return
        }
        
        syncInProgress = true
        lastSyncError = nil
        
        Task {
            var logSuccessCount = 0
            var logErrorCount = 0
            var responseSuccessCount = 0
            var responseErrorCount = 0
            
            // Sync pending logs
            for log in pendingLogs {
                do {
                    try await syncLog(log)
                    await removePendingLog(log)
                    logSuccessCount += 1
                } catch {
                    print("OfflineLogManager: Failed to sync log \(log.id): \(error)")
                    logErrorCount += 1
                }
            }
            
            // Sync pending responses
            for response in pendingResponses {
                do {
                    try await syncResponse(response)
                    await removePendingResponse(response)
                    responseSuccessCount += 1
                } catch {
                    print("OfflineLogManager: Failed to sync response \(response.id): \(error)")
                    responseErrorCount += 1
                }
            }
            
            await MainActor.run {
                self.syncInProgress = false
                
                let totalErrors = logErrorCount + responseErrorCount
                if totalErrors > 0 {
                    self.lastSyncError = "Failed to sync \(totalErrors) item(s)"
                }
                
                print("OfflineLogManager: Sync complete. Logs: \(logSuccessCount) success, \(logErrorCount) errors. Responses: \(responseSuccessCount) success, \(responseErrorCount) errors")
            }
        }
    }
    
    private func syncLog(_ offlineLog: OfflineLog) async throws {
        // Always use a fresh token from the Keychain: a token frozen at queue
        // time may have expired while the device was offline.
        guard let token = KeychainHelper.getToken() else {
            throw NSError(domain: "OfflineLogManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication token missing"])
        }
        
        // First, upload any attachments
        var attachments: [CreateLogRequest.AttachmentData] = []
        
        if let offlineAttachments = offlineLog.attachments {
            for attachment in offlineAttachments {
                let uploadedAttachment = try await uploadAttachment(
                    data: attachment.fileData,
                    fileName: attachment.fileName,
                    fileType: attachment.fileType,
                    token: token
                )
                attachments.append(uploadedAttachment)
            }
        }
        
        // Create the log request
        var logData = CreateLogRequest(
            title: offlineLog.title,
            description: offlineLog.description,
            typeId: offlineLog.typeId,
            tradeId: offlineLog.tradeId,
            statusId: offlineLog.statusId,
            hazardId: offlineLog.hazardId,
            contributingConditionId: offlineLog.contributingConditionId,
            contributingBehaviourId: offlineLog.contributingBehaviourId,
            dueDate: offlineLog.dueDate,
            priorityId: offlineLog.priorityId,
            folderId: offlineLog.folderId,
            isPrivate: offlineLog.isPrivate,
            assigneeId: offlineLog.assigneeId,
            distributionUserIds: offlineLog.distributionUserIds,
            location: offlineLog.location,
            specification: offlineLog.specification,
            locationId: offlineLog.locationId,
            attachments: attachments.isEmpty ? nil : attachments
        )
        logData.recordType = offlineLog.recordType
        logData.isAnonymous = offlineLog.isAnonymous
        logData.occurredAt = offlineLog.occurredAt
        logData.incidentSeverityBand = offlineLog.incidentSeverityBand
        logData.injuryInvolved = offlineLog.injuryInvolved
        logData.regulatoryNotifiable = offlineLog.regulatoryNotifiable
        logData.incidentPayload = offlineLog.incidentPayload

        _ = try await APIClient.createLog(projectId: offlineLog.projectId, logData: logData, token: token)
        print("OfflineLogManager: Successfully synced log: \(offlineLog.title)")
    }
    
    private func syncResponse(_ offlineResponse: OfflineLogResponse) async throws {
        // Always use a fresh token from the Keychain (see syncLog).
        guard let token = KeychainHelper.getToken() else {
            throw NSError(domain: "OfflineLogManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication token missing"])
        }
        
        // Extract photo data and names
        var attachmentData: [Data] = []
        var attachmentNames: [String] = []
        
        for photo in offlineResponse.photos {
            attachmentData.append(photo.fileData)
            attachmentNames.append(photo.fileName)
        }
        
        // Submit response with attachments
        try await APIClient.submitLogResponse(
            projectId: offlineResponse.projectId,
            logId: offlineResponse.logId,
            response: offlineResponse.response,
            accepted: offlineResponse.accepted,
            attachments: attachmentData,
            attachmentNames: attachmentNames,
            token: token
        )
        
        print("OfflineLogManager: Successfully synced response for log \(offlineResponse.logId)")
    }
    
    private func uploadAttachment(data: Data, fileName: String, fileType: String, token: String) async throws -> CreateLogRequest.AttachmentData {
        let url = URL(string: "\(APIClient.baseURL)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add dataType field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"dataType\"\r\n\r\n".data(using: .utf8)!)
        body.append("logs\r\n".data(using: .utf8)!)
        
        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(fileType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        // Parse response
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            let fileUrl = json["fileKey"] as? String ?? json["fileUrl"] as? String ?? ""
            let returnedFileName = json["fileName"] as? String ?? fileName
            let returnedFileType = json["fileType"] as? String ?? fileType
            
            return CreateLogRequest.AttachmentData(
                fileUrl: fileUrl,
                fileName: returnedFileName,
                fileType: returnedFileType
            )
        }
        
        throw APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid upload response")))
    }
    
    private func removePendingLog(_ log: OfflineLog) async {
        // Delete the durable copy BEFORE dropping the in-memory item so a
        // failed delete can never lead to a silent duplicate at next launch.
        let fileURL = logsDirectory.appendingPathComponent("\(log.id).json")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            print("OfflineLogManager: Removed synced log: \(log.id)")
        } catch {
            print("OfflineLogManager: CRITICAL - could not delete synced log file \(log.id): \(error)")
            await MainActor.run {
                self.lastSyncError = "A synced log could not be cleared from the offline queue and may be re-sent on next launch."
            }
        }
        
        await MainActor.run {
            pendingLogs.removeAll { $0.id == log.id }
        }
    }
    
    private func removePendingResponse(_ response: OfflineLogResponse) async {
        let fileURL = responsesDirectory.appendingPathComponent("\(response.id).json")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            print("OfflineLogManager: Removed synced response: \(response.id)")
        } catch {
            print("OfflineLogManager: CRITICAL - could not delete synced response file \(response.id): \(error)")
            await MainActor.run {
                self.lastSyncError = "A synced response could not be cleared from the offline queue and may be re-sent on next launch."
            }
        }
        
        await MainActor.run {
            pendingResponses.removeAll { $0.id == response.id }
        }
    }
    
    // MARK: - Delete Pending Items
    
    func deletePendingLog(_ log: OfflineLog) {
        pendingLogs.removeAll { $0.id == log.id }
        
        let fileURL = logsDirectory.appendingPathComponent("\(log.id).json")
        try? FileManager.default.removeItem(at: fileURL)
        print("OfflineLogManager: Deleted pending log: \(log.id)")
    }
    
    func deletePendingResponse(_ response: OfflineLogResponse) {
        pendingResponses.removeAll { $0.id == response.id }
        
        let fileURL = responsesDirectory.appendingPathComponent("\(response.id).json")
        try? FileManager.default.removeItem(at: fileURL)
        print("OfflineLogManager: Deleted pending response: \(response.id)")
    }
}

