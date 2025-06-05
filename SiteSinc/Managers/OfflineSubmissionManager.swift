import Foundation
import Combine
import Network

class OfflineSubmissionManager: ObservableObject {
    static let shared = OfflineSubmissionManager()
    
    @Published var pendingSubmissions: [OfflineSubmission] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sitesinc.offlineSubmissionManager")
    
    private init() {
        loadPendingSubmissions()
        
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("Network connection is back.")
                self?.syncPendingSubmissions()
            } else {
                print("No network connection.")
            }
        }
        monitor.start(queue: queue)
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
        queue.async {
            self.pendingSubmissions.append(submission)
            let fileURL = self.submissionsDirectory.appendingPathComponent("\(submission.id).json")
            do {
                let data = try JSONEncoder().encode(submission)
                try data.write(to: fileURL)
                print("Saved submission offline: \(submission.id)")
            } catch {
                print("Failed to save submission offline: \(error)")
            }
        }
    }
    
    private func loadPendingSubmissions() {
        queue.async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.submissionsDirectory, includingPropertiesForKeys: nil)
                let submissions = fileURLs.compactMap { url -> OfflineSubmission? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(OfflineSubmission.self, from: data)
                }
                DispatchQueue.main.async {
                    self.pendingSubmissions = submissions
                    print("Loaded \(submissions.count) pending submissions.")
                }
            } catch {
                print("Failed to load pending submissions: \(error)")
            }
        }
    }
    
    func syncPendingSubmissions() {
        queue.async {
            let submissionsToSync = self.pendingSubmissions
            guard !submissionsToSync.isEmpty else { return }
            
            print("Starting sync for \(submissionsToSync.count) submissions.")
            
            submissionsToSync.forEach { submission in
                if let token = KeychainHelper.getToken() {
                    Task {
                        do {
                            try await self.uploadSubmission(submission, token: token)
                            self.removeSubmission(submission)
                        } catch {
                            print("Failed to sync submission: \(submission.id), error: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("Could not sync submission \(submission.id): missing token")
                }
            }
        }
    }
    
    private func uploadSubmission(_ submission: OfflineSubmission, token: String) async throws {
        var updatedResponses = submission.formData

        if let fileAttachments = submission.fileAttachments {
            for (fileName, data) in fileAttachments {
                let fileKey = try await uploadFileDataAsync(data: data, fileName: fileName, token: token)
                // This assumes the fileName can be used as a key or that the fieldId is part of the fileName.
                // This might need more robust logic to map fileName back to a fieldId.
                // For now, we'll use the fileName as a temporary key.
                let fieldId = (fileName as NSString).deletingPathExtension
                updatedResponses[fieldId] = fileKey
            }
        }

        let submissionData = [
            "formTemplateId": submission.formTemplateId,
            "revisionId": submission.revisionId,
            "projectId": submission.projectId,
            "formData": updatedResponses,
            "status": submission.status
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: submissionData, options: [])
        
        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/submit")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw NSError(domain: "APIError", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Sync failed"])
        }
        
        print("Successfully uploaded submission: \(submission.id)")
    }

    private func uploadFileDataAsync(data: Data, fileName: String, token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/upload-file")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!) // Adjust mime type if possible
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIError", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "File upload failed"])
        }
        
        guard let json = try? JSONDecoder().decode([String: String].self, from: responseData), let fileUrl = json["fileUrl"] else {
            throw NSError(domain: "APIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response for file upload"])
        }
        
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
    
    private func removeSubmission(_ submission: OfflineSubmission) {
        queue.async {
            if let index = self.pendingSubmissions.firstIndex(where: { $0.id == submission.id }) {
                self.pendingSubmissions.remove(at: index)
                let fileURL = self.submissionsDirectory.appendingPathComponent("\(submission.id).json")
                try? FileManager.default.removeItem(at: fileURL)
                print("Removed synced submission: \(submission.id)")
            }
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
} 