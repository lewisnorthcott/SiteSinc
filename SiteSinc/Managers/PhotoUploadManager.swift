import Foundation
import Combine
import Network
import UIKit

@MainActor
class PhotoUploadManager: ObservableObject {
    static let shared = PhotoUploadManager()
    
    @Published var pendingUploads: [PendingPhotoUpload] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sitesinc.photouploadmanager")
    
    private init() {
        loadPendingUploads()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("PhotoUploadManager: Network connection is back.")
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await self?.syncPendingUploads()
                }
            } else {
                print("PhotoUploadManager: No network connection.")
            }
        }
        monitor.start(queue: queue)
    }
    
    var pendingUploadsCount: Int {
        return pendingUploads.count
    }
    
    private var uploadsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let uploadsURL = paths[0].appendingPathComponent("offline_photo_uploads")
        if !FileManager.default.fileExists(atPath: uploadsURL.path) {
            try? FileManager.default.createDirectory(at: uploadsURL, withIntermediateDirectories: true, attributes: nil)
        }
        return uploadsURL
    }
    
    func saveUpload(_ upload: PendingPhotoUpload) async {
        pendingUploads.append(upload)
        Task.detached { [weak self] in
            guard let self = self else { return }
            let uploadsURL = await self.uploadsDirectory
            let fileURL = uploadsURL.appendingPathComponent("\(upload.id).json")
            do {
                let data = try JSONEncoder().encode(upload)
                try data.write(to: fileURL)
                print("PhotoUploadManager: Saved photo upload offline: \(upload.id)")
            } catch {
                print("PhotoUploadManager: Failed to save photo upload offline: \(error)")
            }
        }
    }
    
    private func loadPendingUploads() {
        Task { [weak self] in
            guard let self = self else { return }
            let uploads = await Task.detached { [weak self] in
                guard let self = self else { return [PendingPhotoUpload]() }
                let uploadsURL = await self.uploadsDirectory
                do {
                    let fileURLs = try FileManager.default.contentsOfDirectory(at: uploadsURL, includingPropertiesForKeys: nil)
                    let uploads = fileURLs.compactMap { url -> PendingPhotoUpload? in
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return try? JSONDecoder().decode(PendingPhotoUpload.self, from: data)
                    }
                    return uploads
                } catch {
                    print("PhotoUploadManager: Failed to load pending uploads: \(error)")
                    return [PendingPhotoUpload]()
                }
            }.value
            await MainActor.run {
                self.pendingUploads = uploads
                print("PhotoUploadManager: Loaded \(uploads.count) pending uploads.")
            }
        }
    }
    
    func manualSync() {
        print("PhotoUploadManager: Manual sync triggered")
        Task {
            await syncPendingUploads()
        }
    }
    
    func syncPendingUploads() async {
        guard !syncInProgress else {
            print("PhotoUploadManager: Sync already in progress, skipping")
            return
        }

        let uploadsToSync = pendingUploads
        guard !uploadsToSync.isEmpty else {
            print("PhotoUploadManager: No pending uploads to sync")
            return
        }
        
        syncInProgress = true
        lastSyncError = nil
        print("PhotoUploadManager: Starting sync for \(uploadsToSync.count) photo uploads.")
        var successCount = 0
        var errorCount = 0
        for upload in uploadsToSync {
            do {
                try await uploadPhoto(upload)
                await removeUpload(upload)
                successCount += 1
                print("PhotoUploadManager: Successfully synced photo upload: \(upload.id)")
            } catch {
                errorCount += 1
                let errorMessage = "Failed to sync photo upload: \(error.localizedDescription)"
                print("PhotoUploadManager: \(errorMessage), error: \(error)")
                lastSyncError = errorMessage
            }
        }
        
        syncInProgress = false
        print("PhotoUploadManager: Sync completed. Success: \(successCount), Errors: \(errorCount)")
        if successCount > 0 && errorCount == 0 {
            lastSyncError = nil
        }
    }

    private func uploadPhoto(_ upload: PendingPhotoUpload) async throws {
        guard let token = KeychainHelper.getToken() else {
            throw NSError(domain: "PhotoUploadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authentication token missing"])
        }
        let url = URL(string: "\(APIClient.baseURL)/photos/upload")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        // Add projectId
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"projectId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(upload.projectId)\r\n".data(using: .utf8)!)
        // Add description only if not empty
        if let desc = upload.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(desc)\r\n".data(using: .utf8)!)
        }
        // Add files
        if upload.images.isEmpty {
            throw NSError(domain: "PhotoUploadManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No images to upload"])
        }
        for (idx, jpegData) in upload.images.enumerated() {
            let fileName = "photo_\(upload.id.uuidString)_\(idx).jpg"
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(jpegData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "PhotoUploadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."])
        }

        guard httpResponse.statusCode == 201 else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "No response"
            throw NSError(domain: "PhotoUploadManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Photo upload failed: \(responseText)"])
        }
    }

    private func removeUpload(_ upload: PendingPhotoUpload) async {
        if let index = pendingUploads.firstIndex(where: { $0.id == upload.id }) {
            pendingUploads.remove(at: index)
            await Task.detached { [weak self] in
                guard let self = self else { return }
                let uploadsURL = await self.uploadsDirectory
                let fileURL = uploadsURL.appendingPathComponent("\(upload.id).json")
                try? FileManager.default.removeItem(at: fileURL)
                print("PhotoUploadManager: Removed synced photo upload: \(upload.id)")
            }.value
        }
    }
}

struct PendingPhotoUpload: Codable, Identifiable, Equatable {
    let id: UUID
    let projectId: Int
    let description: String?
    let images: [Data] // JPEG data
    let createdAt: Date
} 
