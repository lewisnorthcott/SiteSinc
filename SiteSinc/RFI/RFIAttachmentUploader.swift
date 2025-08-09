import SwiftUI
import PhotosUI

struct RFIAttachmentUploader: View {
    let projectId: Int
    let rfiId: Int
    let onSuccess: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var uploadedFiles: [String] = []
    @State private var errorMessage: String?
    
    private var allowedTypes: [PHPickerFilter] {
        [.images, .videos]
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Upload Attachments")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select files to upload")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    PhotosPicker(
                        selection: $selectedItems,
                        matching: .any(of: allowedTypes)
                    ) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Select Files")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(uploading)
                }
                
                if !uploadedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Files")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(uploadedFiles, id: \.self) { fileName in
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(.blue)
                                        Text(fileName)
                                            .font(.caption)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                    }
                }
                
                if uploading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Uploading files...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Upload Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        uploadFiles()
                    }
                    .disabled(selectedItems.isEmpty || uploading)
                }
            }
        }
        .onChange(of: selectedItems) { oldItems, newItems in
            Task {
                await processSelectedItems(newItems)
            }
        }
    }
    
    private func processSelectedItems(_ items: [PhotosPickerItem]) async {
        uploadedFiles.removeAll()
        
        for item in items {
            if (try? await item.loadTransferable(type: Data.self)) != nil {
                let fileName = "file_\(UUID().uuidString).jpg" // Default to jpg, could be improved
                uploadedFiles.append(fileName)
            }
        }
    }
    
    private func uploadFiles() {
        guard !selectedItems.isEmpty else { return }
        
        uploading = true
        errorMessage = nil
        
        Task {
            do {
                for item in selectedItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        try await uploadFile(data: data)
                    }
                }
                
                await MainActor.run {
                    uploading = false
                    onSuccess()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    uploading = false
                    errorMessage = "Failed to upload files: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func uploadFile(data: Data) async throws {
        // 1) Upload raw file to RFI upload endpoint (requires auth)
        let uploadUrl = URL(string: "\(APIClient.baseURL)/rfis/upload-file")!
        var uploadRequest = URLRequest(url: uploadUrl)
        uploadRequest.httpMethod = "POST"
        // Attach bearer token if available from SessionManager stored globally; fall back to no token
        if let token = sessionManager.token { uploadRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let boundary = "Boundary-\(UUID().uuidString)"
        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"file.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        uploadRequest.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: uploadRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }
        let uploadResponse = try JSONDecoder().decode(UploadedFileResponse.self, from: responseData)

        // 2) Create the RFI attachment record (requires auth)
        // Prefer project-scoped endpoint; fall back to legacy
        let attachmentEndpoints = [
            "\(APIClient.baseURL)/projects/\(projectId)/rfis/\(rfiId)/attachments",
            "\(APIClient.baseURL)/rfis/\(rfiId)/attachments"
        ]
        var lastError: Error?
        for endpoint in attachmentEndpoints {
            do {
                guard let url = URL(string: endpoint) else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token = sessionManager.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let attachmentBody = [
                    "fileUrl": uploadResponse.fileUrl,
                    "fileName": uploadResponse.fileName,
                    "fileType": uploadResponse.fileType
                ]
                req.httpBody = try JSONEncoder().encode(attachmentBody)
                let (_, res) = try await URLSession.shared.data(for: req)
                if let http = res as? HTTPURLResponse, (200...201).contains(http.statusCode) {
                    lastError = nil
                    break
                } else {
                    lastError = NSError(domain: "", code: (res as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create attachment"])
                }
            } catch {
                lastError = error
            }
        }
        if let error = lastError { throw error }
    }
} 
