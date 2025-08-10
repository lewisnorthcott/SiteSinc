import SwiftUI
import PhotosUI
import Combine
import SwiftData

// MARK: - Supporting Types

// MARK: - RFI Form View

// MARK: - Helper Views

struct MultiSelectionPicker<Item: Identifiable>: View where Item.ID == Int {
    let title: String
    let items: [Item]
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedIds: [Int]
    let disabled: Bool
    let isLoading: Bool
    let displayName: (Item) -> String
    let fetchData: () -> Void
    
    var body: some View {
        NavigationLink {
            VStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Form {
                        ForEach(items) { item in
                            Button(action: {
                                if let index = selectedIds.firstIndex(of: item.id) {
                                    selectedIds.remove(at: index)
                                } else {
                                    selectedIds.append(item.id)
                                }
                            }) {
                                HStack {
                                    Text(displayName(item))
                                    Spacer()
                                    if selectedIds.contains(item.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
        } label: {
            Text(selectedIds.isEmpty ? "Select \(title)" : "Selected: \(selectedIds.count) \(title)")
                .accessibilityLabel("Select \(title.lowercased())")
        }
        .disabled(disabled || isLoading)
        .onAppear {
            fetchData()
        }
    }
}
    
struct CameraPickerView: View {
    let onImageCaptured: (Data) -> Void
    let onDismiss: () -> Void
    
    @State private var imageData: Data?
    
    var body: some View {
        ImagePicker(onImageCaptured: { data in
            self.imageData = data
            onImageCaptured(data)
            onDismiss()
        }, onDismiss: onDismiss)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let onImageCaptured: (Data) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onImageCaptured(data)
            }
            parent.onDismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

// MARK: - Main Create RFI View

struct CreateRFIView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onSuccess: () -> Void
    // Optional prefill from drawing markup
    let prefilledTitle: String?
    let prefilledAttachmentData: Data?
    let prefilledDrawing: SelectedDrawing?
    @EnvironmentObject var sessionManager: SessionManager
    
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
    @State private var capturedImageData: Data?
    @State private var showImagePreview: Bool = false
    @State private var isOffline: Bool = false
    @State private var showDraftSavedAlert: Bool = false
    @State private var showCancelConfirmation: Bool = false
    @State private var usersLoaded: Bool = false
    @State private var drawingsLoaded: Bool = false
    @State private var titleError: String?
    @State private var queryError: String?
    @State private var managerError: String?
    @State private var assignedUsersError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var didApplyPrefill: Bool = false
    
    @State private var currentUser: User? = nil
    
    private var canCreateRFIs: Bool { sessionManager.hasPermission("create_rfis") }
    private var canEditRFIs: Bool { sessionManager.hasPermission("edit_rfis") }
    private var canManageRFIs: Bool { sessionManager.hasPermission("manage_rfis") || sessionManager.hasPermission("manage_any_rfis") }
    
    private var hasUnsavedChanges: Bool {
        !title.isEmpty || !query.isEmpty || managerId != nil || !assignedUserIds.isEmpty || returnDate != nil || !selectedFiles.isEmpty || !selectedDrawings.isEmpty
    }

    private var onSubmitAction: () -> Void {
        isOffline ? saveDraft : submitRFI
    }

    private var onCancelAction: () -> Void {
        {
            if hasUnsavedChanges {
                showCancelConfirmation = true
            } else {
                dismiss()
            }
        }
    }

    private var onAppearAction: () -> Void {
        {
            if let user = currentUser, users.contains(where: { $0.id == user.id }), managerId == nil {
                managerId = user.id
            }
            syncDrafts()
        }
    }

    private var rfiFormView: some View {
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
            onSubmit: onSubmitAction,
            onCancel: onCancelAction,
            fetchUsers: fetchUsers,
            fetchDrawings: fetchDrawings,
            saveFileToTemporaryDirectory: saveFileToTemporaryDirectory,
            onAppear: onAppearAction
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                Group {
                    if canCreateRFIs || canManageRFIs {
                        rfiFormView
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("You don't have permission to create RFIs")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                    .frame(maxWidth: 900, maxHeight: 1200)
                    .padding()
                
                if isSubmitting {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                Text("Creating RFI...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(24)
                            .background(Color(.systemGray6).opacity(0.9))
                            .cornerRadius(12)
                        )
                }
                
                if isOffline {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("Offline Mode")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            currentUser = sessionManager.user
            applyPrefillIfNeeded()
        }
        .alert("Discard Changes?", isPresented: $showCancelConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .alert("Draft Saved", isPresented: $showDraftSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your RFI has been saved as a draft and will be submitted when you're back online.")
        }
        .sheet(isPresented: $showImagePreview) {
            if let data = capturedImageData, let uiImage = UIImage(data: data) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                showImagePreview = false
                                showCameraPicker = true
                            }) {
                                Label("Retake", systemImage: "camera")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                if let url = saveFileToTemporaryDirectory(data: data, fileName: "photo_\(UUID().uuidString).jpg") {
                                    selectedFiles.append(url)
                                }
                                showImagePreview = false
                            }) {
                                Label("Use Photo", systemImage: "checkmark")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .navigationTitle("Preview Photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showImagePreview = false
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: title) { oldValue, newValue in validateForm() }
        .onChange(of: query) { oldValue, newValue in validateForm() }
        .onChange(of: managerId) { oldValue, newValue in validateForm() }
        .onChange(of: assignedUserIds) { oldValue, newValue in validateForm() }
    }

    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill else { return }
        didApplyPrefill = true
        if let t = prefilledTitle, title.isEmpty { title = t }
        if let sd = prefilledDrawing, !selectedDrawings.contains(where: { $0.drawingId == sd.drawingId }) {
            selectedDrawings.append(sd)
        }
        if let data = prefilledAttachmentData,
           let url = saveFileToTemporaryDirectory(data: data, fileName: "markup_snapshot_\(UUID().uuidString).png") {
            if !selectedFiles.contains(url) { selectedFiles.append(url) }
        }
    }

    private func validateForm() {
        titleError = title.isEmpty ? "Title is required" : nil
        queryError = query.isEmpty ? "Query is required" : nil
        managerError = managerId == nil ? "Manager is required" : nil
        assignedUsersError = assignedUserIds.isEmpty ? "At least one assignee is required" : nil
    }

    private func fetchUsers() {
        if usersLoaded { return }
        usersLoaded = true
        isLoadingUsers = true
        Task {
            do {
                let fetchedUsers = try await APIClient.fetchUsers(projectId: projectId, token: token)
                // Extra safety: ensure only users assigned to this project are selectable
                let projectUsers = fetchedUsers.filter { user in
                    if let assigned = user.assignedProjects { return assigned.contains(projectId) }
                    // If backend already filtered and field is nil, include by default
                    return true
                }
                await MainActor.run {
                    self.users = projectUsers
                    saveUsersToCache(projectUsers)
                    if let currentUserId = self.currentUser?.id, projectUsers.contains(where: { $0.id == currentUserId }) {
                        self.managerId = currentUserId
                    } else {
                        self.managerId = nil
                    }
                    isLoadingUsers = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoadingUsers = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        isOffline = true
                        if let cachedUsers = loadUsersFromCache() {
                            self.users = cachedUsers
                            if let currentUserId = self.currentUser?.id, cachedUsers.contains(where: { $0.id == currentUserId }) {
                                self.managerId = currentUserId
                            } else {
                                self.managerId = nil
                            }
                            self.errorMessage = "Loaded cached users (offline mode)"
                        } else {
                            self.errorMessage = "No internet connection and no cached users available"
                        }
                    } else {
                        self.errorMessage = "Failed to fetch users: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func fetchDrawings() {
        if drawingsLoaded { return }
        drawingsLoaded = true
        isLoadingDrawings = true
        Task {
            do {
                let fetchedDrawings = try await APIClient.fetchDrawings(projectId: projectId, token: token)
                await MainActor.run {
                    self.drawings = fetchedDrawings
                    saveDrawingsToCache(fetchedDrawings)
                    isLoadingDrawings = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoadingDrawings = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        isOffline = true
                        if let cachedDrawings = loadDrawingsFromCache() {
                            self.drawings = cachedDrawings
                            self.errorMessage = "Loaded cached drawings (offline mode)"
                        } else {
                            self.errorMessage = "No internet connection and no cached drawings available"
                        }
                    } else {
                        self.errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func saveUsersToCache(_ users: [User]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(users) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("users_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(users.count) users to cache for project \(projectId)")
        }
    }

    private func loadUsersFromCache() -> [User]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("users_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedUsers = try? decoder.decode([User].self, from: data) {
                print("Loaded \(cachedUsers.count) users from cache for project \(projectId)")
                return cachedUsers
            }
        }
        return nil
    }

    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(drawings.count) drawings to cache for project \(projectId)")
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedDrawings = try? decoder.decode([Drawing].self, from: data) {
                print("Loaded \(cachedDrawings.count) drawings from cache for project \(projectId)")
                return cachedDrawings
            }
        }
        return nil
    }

    private func saveDraft() {
        let draft = RFIDraft(
            projectId: projectId,
            title: title,
            query: query,
            managerId: managerId,
            assignedUserIds: assignedUserIds,
            returnDate: returnDate,
            selectedFiles: selectedFiles.map { $0.path },
            selectedDrawings: selectedDrawings,
            createdAt: Date()
        )
        modelContext.insert(draft)
        try? modelContext.save()
        showDraftSavedAlert = true
        dismiss()
    }

    private func syncDrafts() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        guard let drafts = try? modelContext.fetch(fetchDescriptor), !drafts.isEmpty else { return }
        
        for draft in drafts {
            submitDraft(draft)
        }
    }

    private func submitDraft(_ draft: RFIDraft) {
        guard let managerId = draft.managerId else {
            errorMessage = "Manager ID is missing in draft"
            isSubmitting = false
            return
        }
        isSubmitting = true
        errorMessage = nil

        var uploadedFiles: [[String: Any]] = []
        let group = DispatchGroup()
        var uploadError: String?

        let fileURLs = draft.selectedFiles.compactMap { URL(fileURLWithPath: $0) }
        for fileURL in fileURLs {
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

            let body: [String: Any] = [
                "title": draft.title,
                "query": draft.query,
                "description": draft.query,
                "projectId": draft.projectId,
                "managerId": managerId,
                "assignedUserIds": draft.assignedUserIds,
                "returnDate": draft.returnDate?.ISO8601Format() ?? "",
                "attachments": uploadedFiles,
                "drawings": draft.selectedDrawings.map { ["drawingId": $0.drawingId, "revisionId": $0.revisionId] }
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
                        self.errorMessage = "Failed to sync draft RFI: \(error.localizedDescription)"
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
                        self.errorMessage = "Failed to sync draft RFI: Invalid response"
                        return
                    }

                    self.modelContext.delete(draft)
                    try? self.modelContext.save()
                    self.onSuccess()
                }
            }.resume()
        }
    }

    private func submitRFI() {
        guard !title.isEmpty, !query.isEmpty, managerId != nil, !assignedUserIds.isEmpty else {
            errorMessage = "Please fill in all required fields"
            return
        }

        isSubmitting = true
        errorMessage = nil

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
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        self.saveDraft()
                    } else {
                        uploadError = "Failed to upload file: \(error.localizedDescription)"
                    }
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
                        if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                            self.saveDraft()
                        } else {
                            self.errorMessage = "Failed to create RFI: \(error.localizedDescription)"
                        }
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



struct RFIFormConfiguration {
    let projectName: String
    let users: [User]
    let drawings: [Drawing]
    let canCreateRFIs: Bool
    let canEditRFIs: Bool
    let canManageRFIs: Bool
    let fetchUsers: () -> Void
    let fetchDrawings: () -> Void
    let saveFileToTemporaryDirectory: (Data, String) -> URL?
}

struct RFIFormState {
    let title: Binding<String>
    let query: Binding<String>
    let managerId: Binding<Int?>
    let assignedUserIds: Binding<[Int]>
    let returnDate: Binding<Date?>
    let selectedFiles: Binding<[URL]>
    let selectedDrawings: Binding<[SelectedDrawing]>
    let isSubmitting: Binding<Bool>
    let isLoadingUsers: Binding<Bool>
    let isLoadingDrawings: Binding<Bool>
    let errorMessage: Binding<String?>
    let photosPickerItems: Binding<[PhotosPickerItem]>
    let showDrawingPicker: Binding<Bool>
    let showCameraPicker: Binding<Bool>
}
