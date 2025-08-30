import Foundation
import Combine
import Network

@MainActor
class OfflineSubmissionManager: ObservableObject {
    static let shared = OfflineSubmissionManager()
    
    @Published var pendingSubmissions: [OfflineSubmission] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sitesinc.offlineSubmissionManager")
    
    private init() {
        loadPendingSubmissions()
        
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("OfflineSubmissionManager: Network connection is back.")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds to ensure stable connection
                    self?.syncPendingSubmissions()
                }
            } else {
                print("OfflineSubmissionManager: No network connection.")
            }
        }
        monitor.start(queue: queue)
    }
    
    var pendingSubmissionsCount: Int {
        return pendingSubmissions.count
    }
    
    private var submissionsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let submissionsURL = paths[0].appendingPathComponent("offline_submissions")
        if !FileManager.default.fileExists(atPath: submissionsURL.path) {
            try? FileManager.default.createDirectory(at: submissionsURL, withIntermediateDirectories: true, attributes: nil)
        }
        return submissionsURL
    }
    
    func saveSubmission(_ submission: OfflineSubmission) {
        pendingSubmissions.append(submission)
        
        Task.detached {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let submissionsURL = documentsPath.appendingPathComponent("offline_submissions")
            
            // Create directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: submissionsURL.path) {
                try? FileManager.default.createDirectory(at: submissionsURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = submissionsURL.appendingPathComponent("\(submission.id).json")
            do {
                let data = try JSONEncoder().encode(submission)
                try data.write(to: fileURL)
                print("OfflineSubmissionManager: Saved submission offline: \(submission.id)")
            } catch {
                print("OfflineSubmissionManager: Failed to save submission offline: \(error)")
            }
        }
    }
    
    private func loadPendingSubmissions() {
        Task {
            let submissions = await Task.detached {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let submissionsURL = documentsPath.appendingPathComponent("offline_submissions")
                
                do {
                    let fileURLs = try FileManager.default.contentsOfDirectory(at: submissionsURL, includingPropertiesForKeys: nil)
                    let submissions = fileURLs.compactMap { url -> OfflineSubmission? in
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return try? JSONDecoder().decode(OfflineSubmission.self, from: data)
                    }
                    return submissions
                } catch {
                    print("OfflineSubmissionManager: Failed to load pending submissions: \(error)")
                    return [OfflineSubmission]()
                }
            }.value
            
            await MainActor.run {
                self.pendingSubmissions = submissions
                print("OfflineSubmissionManager: Loaded \(submissions.count) pending submissions.")
            }
        }
    }
    
    // Public method to manually trigger sync
    func manualSync() {
        print("OfflineSubmissionManager: Manual sync triggered")
        syncPendingSubmissions()
    }
    
    func syncPendingSubmissions() {
        guard !syncInProgress else {
            print("OfflineSubmissionManager: Sync already in progress, skipping")
            return
        }
        
        Task {
            let submissionsToSync = self.pendingSubmissions
            guard !submissionsToSync.isEmpty else {
                print("OfflineSubmissionManager: No pending submissions to sync")
                return
            }
            
            self.syncInProgress = true
            self.lastSyncError = nil
            
            print("OfflineSubmissionManager: Starting sync for \(submissionsToSync.count) submissions.")
            
            var successCount = 0
            var errorCount = 0
            
            let group = DispatchGroup()
            
            submissionsToSync.forEach { submission in
                group.enter()
                if let token = KeychainHelper.getToken() {
                    Task { [weak self] in
                        guard let self = self else {
                            group.leave()
                            return
                        }
                        do {
                            try await self.uploadSubmission(submission, token: token)
                            await self.removeSubmission(submission)
                            successCount += 1
                            print("OfflineSubmissionManager: Successfully synced submission: \(submission.id)")
                        } catch {
                            errorCount += 1
                            print("OfflineSubmissionManager: Failed to sync submission: \(submission.id), error: \(error.localizedDescription)")
                            await MainActor.run {
                                self.lastSyncError = "Failed to sync submission: \(error.localizedDescription)"
                            }
                        }
                        group.leave()
                    }
                } else {
                    errorCount += 1
                    print("OfflineSubmissionManager: Could not sync submission \(submission.id): missing token")
                    Task { [weak self] in
                        await MainActor.run {
                            self?.lastSyncError = "Authentication token missing"
                        }
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: DispatchQueue.main) { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.syncInProgress = false
                    print("OfflineSubmissionManager: Sync completed. Success: \(successCount), Errors: \(errorCount)")
                    if successCount > 0 && errorCount == 0 {
                        self.lastSyncError = nil
                    }
                }
            }
        }
    }
    
    private func uploadSubmission(_ submission: OfflineSubmission, token: String) async throws {
        var updatedResponses = submission.formData

        if let fileAttachments = submission.fileAttachments {
            for (fileName, data) in fileAttachments {
                let fileKey = try await uploadFileDataAsync(data: data, fileName: fileName, token: token)
                
                // Improved field mapping: extract the actual field ID from the filename
                let fieldId = extractFieldId(from: fileName)
                
                // Handle multiple files for the same field by appending to existing value
                if let existingValue = updatedResponses[fieldId], !existingValue.isEmpty {
                    updatedResponses[fieldId] = "\(existingValue),\(fileKey)"
                } else {
                    updatedResponses[fieldId] = fileKey
                }
                
                print("OfflineSubmissionManager: Mapped file \(fileName) to field \(fieldId) with key \(fileKey)")
            }
        }

        var submissionData = [
            "formTemplateId": submission.formTemplateId,
            "revisionId": submission.revisionId,
            "projectId": submission.projectId,
            "formData": updatedResponses,
            "status": submission.status
        ] as [String : Any]
        if let folderId = submission.folderId { submissionData["folderId"] = folderId }
        if let reference = submission.reference, !reference.isEmpty { submissionData["reference"] = reference }
        
        let jsonData = try JSONSerialization.data(withJSONObject: submissionData, options: [])
        
        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/submit")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "No response"
            throw NSError(domain: "APIError", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Sync failed: \(responseText)"])
        }
        
        print("OfflineSubmissionManager: Successfully uploaded submission: \(submission.id)")
    }

    // Improved field ID extraction
    private func extractFieldId(from fileName: String) -> String {
        // Handle different filename patterns:
        // "fieldId-captured-0.jpg" -> "fieldId" 
        // "fieldId-0.jpg" -> "fieldId"
        // "fieldId-signature.jpg" -> "fieldId"
        let baseName = (fileName as NSString).deletingPathExtension
        
        // Remove common suffixes
        let suffixesToRemove = ["-captured-\\d+$", "-\\d+$", "-signature$"]
        var fieldId = baseName
        
        for suffix in suffixesToRemove {
            if let regex = try? NSRegularExpression(pattern: suffix, options: []) {
                let range = NSRange(location: 0, length: fieldId.count)
                fieldId = regex.stringByReplacingMatches(in: fieldId, options: [], range: range, withTemplate: "")
                if fieldId != baseName { break } // Stop at first match
            }
        }
        
        return fieldId.isEmpty ? baseName : fieldId
    }

    // Add MIME type detection function
    private func mimeType(for fileName: String) -> String {
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        
        switch pathExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":
            return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":
            return "text/plain"
        case "pages":
            return "application/vnd.apple.pages"
        case "numbers":
            return "application/vnd.apple.numbers"
        case "key":
            return "application/vnd.apple.keynote"
        default:
            return "application/octet-stream"
        }
    }

    private func uploadFileDataAsync(data: Data, fileName: String, token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/upload-file")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Get proper MIME type for the file
        let contentType = mimeType(for: fileName)
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("OfflineSubmissionManager: Uploading file \(fileName) with MIME type \(contentType)")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "No response"
            print("OfflineSubmissionManager: File upload failed with status \(httpResponse.statusCode): \(responseText)")
            throw NSError(domain: "APIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "File upload failed: \(responseText)"])
        }
        
        guard let json = try? JSONDecoder().decode([String: String].self, from: responseData), let fileUrl = json["fileUrl"] else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "No response"
            throw NSError(domain: "APIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response for file upload: \(responseText)"])
        }
        
        print("OfflineSubmissionManager: File uploaded successfully: \(fileUrl)")
        return extractFileKey(from: fileUrl)
    }
    
    private func extractFileKey(from urlString: String) -> String {
        if let url = URL(string: urlString) {
            let path = url.path
            if path.hasPrefix("/") {
                return String(path.dropFirst())
            }
            return path
        }
        return urlString
    }
    
    private func removeSubmission(_ submission: OfflineSubmission) async {
        if let index = pendingSubmissions.firstIndex(where: { $0.id == submission.id }) {
            pendingSubmissions.remove(at: index)
            
            // File operations should be done off the main actor
            await Task.detached {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let submissionsURL = documentsPath.appendingPathComponent("offline_submissions")
                let fileURL = submissionsURL.appendingPathComponent("\(submission.id).json")
                try? FileManager.default.removeItem(at: fileURL)
                print("OfflineSubmissionManager: Removed synced submission: \(submission.id)")
            }.value
        }
    }
}

struct OfflineSubmission: Codable, Identifiable {
    let id: UUID
    let formTemplateId: Int
    let revisionId: Int
    let projectId: Int
    let formData: [String: String]
    // You'll need to store file data or paths if you have attachments
    let fileAttachments: [String: Data]? // For images, signatures, etc.
    let status: String
    let reference: String? // Optional reference field
    let folderId: Int? // Optional folder target
} 