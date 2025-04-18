import SwiftUI
import PhotosUI
import Combine

struct CreateRFIView: View {
    let projectId: Int
    let token: String
    let onSuccess: () -> Void
    
    @State private var title = ""
    @State private var query = ""
    @State private var managerId: Int?
    @State private var assignedUserIds: [Int] = []
    @State private var returnDate: Date? = Calendar.current.date(byAdding: .day, value: 7, to: Date())
    @State private var selectedFiles: [URL] = []
    @State private var selectedDrawings: [SelectedDrawing] = []
    @State private var users: [User] = []
    @State private var drawings: [Drawing] = []
    @State private var isSubmitting = false
    @State private var isLoadingUsers = false
    @State private var isLoadingDrawings = false
    @State private var errorMessage: String?
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showDrawingPicker = false
    @Environment(\.dismiss) private var dismiss
    
    // Mock currentUser (replace with actual auth context)
    @State private var currentUser: User? = User(
        id: 1,
        email: "user@example.com",
        firstName: "Test",
        lastName: "User",
        tenantId: 1,
        companyId: 1,
        roles: ["user"],
        permissions: ["create_rfis", "edit_rfis"],
        isSubscriptionOwner: false
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
                canCreateRFIs: canCreateRFIs,
                canEditRFIs: canEditRFIs,
                canManageRFIs: canManageRFIs,
                onSubmit: submitRFI,
                onCancel: { dismiss() },
                fetchUsers: fetchUsers,
                fetchDrawings: fetchDrawings,
                saveFileToTemporaryDirectory: saveFileToTemporaryDirectory,
                onAppear: {
                    if let user = currentUser, managerId == nil {
                        managerId = user.id
                    }
                }
            )
        }
    }

    // MARK: - Helper Functions
    private func fetchUsers() {
        isLoadingUsers = true
        // Mock user data (replace with actual API call)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.users = [
                User(id: 1, email: "user1@example.com", firstName: "John", lastName: "Doe", tenantId: 1, companyId: 1, roles: ["user"], permissions: ["create_rfis"], isSubscriptionOwner: false),
                User(id: 2, email: "user2@example.com", firstName: "Jane", lastName: "Smith", tenantId: 1, companyId: 1, roles: ["user"], permissions: ["create_rfis"], isSubscriptionOwner: false)
            ]
            self.isLoadingUsers = false
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
                      let fileData = try? JSONDecoder().decode(UploadedFileResponse.self, from: data) else {
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

// MARK: - Form View
private struct RFIFormView: View {
    @Binding var title: String
    @Binding var query: String
    @Binding var managerId: Int?
    @Binding var assignedUserIds: [Int]
    @Binding var returnDate: Date?
    @Binding var selectedFiles: [URL]
    @Binding var selectedDrawings: [SelectedDrawing]
    let users: [User]
    let drawings: [Drawing]
    @Binding var isSubmitting: Bool
    @Binding var isLoadingUsers: Bool
    @Binding var isLoadingDrawings: Bool
    @Binding var errorMessage: String?
    @Binding var photosPickerItems: [PhotosPickerItem]
    @Binding var showDrawingPicker: Bool
    let canCreateRFIs: Bool
    let canEditRFIs: Bool
    let canManageRFIs: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let fetchUsers: () -> Void
    let fetchDrawings: () -> Void
    let saveFileToTemporaryDirectory: (Data, String) -> URL?
    let onAppear: () -> Void // Add onAppear parameter

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            if isLoadingUsers || isLoadingDrawings {
                ProgressView()
            } else if !canCreateRFIs {
                Text("You don't have permission to create RFIs")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        TitleSection(title: $title)
                        QuerySection(query: $query)
                        ManagerSection(managerId: $managerId, users: users, isLoading: isLoadingUsers)
                        AssignToSection(assignedUserIds: $assignedUserIds, users: users, isLoading: isLoadingUsers)
                        ResponseDateSection(returnDate: $returnDate)
                        if canEditRFIs || canManageRFIs {
                            AttachmentsSection(selectedFiles: $selectedFiles, photosPickerItems: $photosPickerItems)
                            DrawingsSection(selectedDrawings: $selectedDrawings, showDrawingPicker: $showDrawingPicker, isLoading: isLoadingDrawings)
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Create RFI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSubmit) {
                    Text(isSubmitting ? "Creating..." : "Create")
                }
                .disabled(isSubmitting || !canCreateRFIs || title.isEmpty || query.isEmpty || managerId == nil || assignedUserIds.isEmpty)
            }
        }
        .sheet(isPresented: $showDrawingPicker) {
            DrawingPickerView(
                drawings: drawings,
                selectedDrawings: $selectedDrawings,
                onDismiss: { showDrawingPicker = false }
            )
        }
        .onAppear {
            fetchUsers()
            fetchDrawings()
            onAppear() // Call the passed onAppear closure
        }
        .onChange(of: photosPickerItems) { _, newItems in
            Task {
                var newFiles: [URL] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Generate a generic filename
                        let fileName = "photo_\(UUID().uuidString).jpg"
                        if let url = saveFileToTemporaryDirectory(data, fileName) {
                            newFiles.append(url)
                        }
                    }
                }
                selectedFiles.append(contentsOf: newFiles)
            }
        }
    }

    // MARK: - Sub-Views
    private struct TitleSection: View {
        @Binding var title: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                TextField("Enter RFI title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private struct QuerySection: View {
        @Binding var query: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Query")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                TextEditor(text: $query)
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }

    private struct ManagerSection: View {
        @Binding var managerId: Int?
        let users: [User]
        let isLoading: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("RFI Manager")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Picker("Select RFI Manager", selection: $managerId) {
                    Text("Select a manager").tag(nil as Int?)
                    ForEach(users, id: \.id) { user in
                        Text("\(user.firstName ?? "") \(user.lastName ?? "")").tag(user.id as Int?)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isLoading)
            }
        }
    }

    private struct AssignToSection: View {
        @Binding var assignedUserIds: [Int]
        let users: [User]
        let isLoading: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assign To")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                MultiSelectPicker(items: users, selectedIds: $assignedUserIds)
                    .disabled(isLoading)
            }
        }
    }

    private struct ResponseDateSection: View {
        @Binding var returnDate: Date?
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Response By Date")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                DatePicker(
                    "Select date",
                    selection: Binding(
                        get: { returnDate ?? Date() },
                        set: { returnDate = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                HStack(spacing: 8) {
                    Button("Today") { returnDate = Date() }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    Button("Tomorrow") { returnDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    Button("Next Week") { returnDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                }
            }
        }
    }

    private struct AttachmentsSection: View {
        @Binding var selectedFiles: [URL]
        @Binding var photosPickerItems: [PhotosPickerItem]
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Attachments")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                PhotosPicker(
                    selection: $photosPickerItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "paperclip")
                        Text("Select Files")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                if !selectedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Files (\(selectedFiles.count))")
                            .font(.caption)
                            .foregroundColor(.gray)
                        ScrollView(.vertical) {
                            VStack(spacing: 8) {
                                ForEach(selectedFiles.indices, id: \.self) { index in
                                    HStack {
                                        Text(selectedFiles[index].lastPathComponent)
                                            .font(.caption)
                                        Spacer()
                                        Button {
                                            selectedFiles.remove(at: index)
                                            photosPickerItems.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                    }
                }
            }
        }
    }

    private struct DrawingsSection: View {
        @Binding var selectedDrawings: [SelectedDrawing]
        @Binding var showDrawingPicker: Bool
        let isLoading: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Link Drawings")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Button {
                    showDrawingPicker = true
                } label: {
                    HStack {
                        Text(selectedDrawings.isEmpty ? "Select drawings..." : "\(selectedDrawings.count) drawing\(selectedDrawings.count == 1 ? "" : "s") selected")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
                }
                .disabled(isLoading)
                if !selectedDrawings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView(.vertical) {
                            VStack(spacing: 8) {
                                ForEach(selectedDrawings) { drawing in
                                    HStack {
                                        Text("\(drawing.number) - Rev \(drawing.revisionNumber)")
                                            .font(.caption)
                                        Spacer()
                                        Button {
                                            selectedDrawings.removeAll { $0.drawingId == drawing.drawingId }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                    }
                }
            }
        }
    }
}

// MARK: - Models and Helpers
struct SelectedDrawing: Identifiable {
    let id = UUID()
    let drawingId: Int
    let revisionId: Int
    let number: String
    let revisionNumber: String
}

struct MultiSelectPicker: View {
    let items: [User]
    @Binding var selectedIds: [Int]
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Button(action: {
                        if selectedIds.contains(item.id) {
                            selectedIds.removeAll { $0 == item.id }
                        } else {
                            selectedIds.append(item.id)
                        }
                    }) {
                        HStack {
                            Text("\(item.firstName ?? "") \(item.lastName ?? "")")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedIds.contains(item.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .frame(maxHeight: 150)
    }
}

struct DrawingPickerView: View {
    let drawings: [Drawing]
    @Binding var selectedDrawings: [SelectedDrawing]
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(drawings, id: \.id) { drawing in
                    if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                        Button(action: {
                            if selectedDrawings.contains(where: { $0.drawingId == drawing.id }) {
                                selectedDrawings.removeAll { $0.drawingId == drawing.id }
                            } else {
                                selectedDrawings.append(SelectedDrawing(
                                    drawingId: drawing.id,
                                    revisionId: latestRevision.id,
                                    number: drawing.number,
                                    revisionNumber: latestRevision.revisionNumber ?? "N/A"
                                ))
                            }
                        }) {
                            HStack {
                                Text("\(drawing.number) - \(drawing.title)")
                                Spacer()
                                if selectedDrawings.contains(where: { $0.drawingId == drawing.id }) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Drawings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

struct UploadedFileResponse: Decodable {
    let fileUrl: String
    let fileName: String
    let fileType: String
    let tenantId: Int
}
