import SwiftUI
import PhotosUI
import Combine

struct CreateRFIView: View {
    let projectId: Int
    let token: String
    let onSuccess: () -> Void
    
    @State private var title: String = ""
    @State private var query: String = ""
    @State private var managerId: Int?
    @State private var assignedUserIds: [Int] = []
    @State private var returnDate: Date? = Calendar.current.date(byAdding: .day, value: 7, to: Date())
    @State private var selectedFiles: [URL] = []
    @State private var selectedDrawings: [SelectedDrawing] = []
    @State private var users: [User] = []
    @State private var drawings: [Drawing] = []
    @State private var isSubmitting: Bool = false
    @State private var isLoadingUsers: Bool = false
    @State private var isLoadingDrawings: Bool = false
    @State private var errorMessage: String?
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showDrawingPicker: Bool = false
    @State private var showCameraPicker: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    // Mock currentUser (updated to match User struct in Models.swift)
    @State private var currentUser: User? = User(
        id: 1,
        firstName: "Test",
        lastName: "User",
        email: "user@example.com",
        tenantId: 1,
        companyId: 1,
        company: nil,
        roles: ["user"],
        permissions: ["create_rfis", "edit_rfis"],
        projectPermissions: nil,
        isSubscriptionOwner: false,
        assignedProjects: [1],
        assignedSubcontractOrders: nil,
        blocked: false,
        createdAt: nil,
        userRoles: nil,
        userPermissions: nil,
        tenants: nil
    )
    
    // Permission checks
    private var canCreateRFIs: Bool { currentUser?.permissions?.contains("create_rfis") ?? false }
    private var canEditRFIs: Bool { currentUser?.permissions?.contains("edit_rfis") ?? false }
    private var canManageRFIs: Bool { currentUser?.permissions?.contains("manage_rfis") ?? false }

    var body: some View {
        NavigationView {
            RFIFormView(
                title: $title,
                query: $query,
                managerId: $managerId,
                assignedUserIds: $assignedUserIds,
                returnDate: $returnDate,
                selectedFiles: $selectedFiles,
                selectedDrawings: $selectedDrawings,
                users: users,
                drawings: drawings,
                isSubmitting: $isSubmitting,
                isLoadingUsers: $isLoadingUsers,
                isLoadingDrawings: $isLoadingDrawings,
                errorMessage: $errorMessage,
                photosPickerItems: $photosPickerItems,
                showDrawingPicker: $showDrawingPicker,
                showCameraPicker: $showCameraPicker,
                canCreateRFIs: canCreateRFIs,
                canEditRFIs: canEditRFIs,
                canManageRFIs: canManageRFIs,
                onSubmit: submitRFI,
                onCancel: { dismiss() },
                fetchUsers: fetchUsers,
                fetchDrawings: fetchDrawings,
                saveFileToTemporaryDirectory: saveFileToTemporaryDirectory,
                onAppear: {
                    if let user = currentUser, users.contains(where: { $0.id == user.id }), managerId == nil {
                        managerId = user.id
                    }
                }
            )
        }
    }

    // MARK: - Helper Functions
    private func fetchUsers() {
        isLoadingUsers = true
        APIClient.fetchUsers(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoadingUsers = false
                switch result {
                case .success(let users):
                    self.users = users
                    // Ensure managerId is valid after fetching users
                    if let currentUserId = self.currentUser?.id, users.contains(where: { $0.id == currentUserId }) {
                        self.managerId = currentUserId
                    } else {
                        self.managerId = nil
                    }
                case .failure(let error):
                    self.errorMessage = "Failed to fetch users: \(error.localizedDescription)"
                }
            }
        }
    }

    private func fetchDrawings() {
        isLoadingDrawings = true
        APIClient.fetchDrawings(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoadingDrawings = false
                switch result {
                case .success(let drawings):
                    self.drawings = drawings
                case .failure(let error):
                    errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveFileToTemporaryDirectory(data: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving file: \(error)")
            return nil
        }
    }

    private func submitRFI() {
        guard !title.isEmpty, !query.isEmpty, managerId != nil, !assignedUserIds.isEmpty else {
            errorMessage = "Please fill in all required fields"
            return
        }

        isSubmitting = true
        errorMessage = nil

        // Step 1: Upload files
        var uploadedFiles: [[String: Any]] = []
        let group = DispatchGroup()
        var uploadError: String?

        for fileURL in selectedFiles {
            group.enter()
            guard let data = try? Data(contentsOf: fileURL) else {
                uploadError = "Failed to read file data"
                group.leave()
                continue
            }
            let fileName = fileURL.lastPathComponent
            let url = URL(string: "\(APIClient.baseURL)/rfis/upload-file")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let body = createMultipartFormData(data: data, fileName: fileName, boundary: boundary)
            request.httpBody = body
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                if let error = error {
                    uploadError = "Failed to upload file: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let fileData: UploadedFileResponse = try? JSONDecoder().decode(UploadedFileResponse.self, from: data) else {
                    uploadError = "Failed to decode upload response"
                    return
                }
                uploadedFiles.append([
                    "fileUrl": fileData.fileUrl,
                    "fileName": fileData.fileName,
                    "fileType": fileData.fileType
                ])
            }.resume()
        }

        group.notify(queue: .main) {
            if let uploadError = uploadError {
                self.errorMessage = uploadError
                self.isSubmitting = false
                return
            }

            // Step 2: Create RFI
            let body: [String: Any] = [
                "title": title,
                "query": query,
                "description": query,
                "projectId": projectId,
                "managerId": managerId!,
                "assignedUserIds": assignedUserIds,
                "returnDate": returnDate?.ISO8601Format() ?? "",
                "attachments": uploadedFiles,
                "drawings": selectedDrawings.map { ["drawingId": $0.drawingId, "revisionId": $0.revisionId] }
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                self.errorMessage = "Failed to encode request"
                self.isSubmitting = false
                return
            }

            let url = URL(string: "\(APIClient.baseURL)/rfis")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    if let error = error {
                        self.errorMessage = "Failed to create RFI: \(error.localizedDescription)"
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
                        self.errorMessage = "Failed to create RFI: Invalid response"
                        return
                    }

                    self.onSuccess()
                    self.dismiss()
                }
            }.resume()
        }
    }

    private func createMultipartFormData(data: Data, fileName: String, boundary: String) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

struct UploadedFileResponse: Decodable {
    let fileUrl: String
    let fileName: String
    let fileType: String
    let tenantId: Int
}
