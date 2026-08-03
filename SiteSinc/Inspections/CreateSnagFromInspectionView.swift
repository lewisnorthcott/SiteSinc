import SwiftUI
import PhotosUI
import AVFoundation

/// A specialized view for creating a snag log when an inspection stage fails (NO result).
/// Requires at least one photo to be attached before submission.
struct CreateSnagFromInspectionView: View {
    let inspection: Inspection
    let stageResult: InspectionStageResult
    let projectId: Int
    let token: String
    let onSuccess: () -> Void
    let onSkip: () -> Void
    
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    // Form state
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedPriorityId: Int?
    @State private var selectedAssigneeId: Int?
    @State private var selectedLocationId: Int?
    @State private var dueDate: Date = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default: 7 days from now
    
    // Data
    @State private var logSettings: LogSettings?
    @State private var users: [User] = []
    @State private var snagTypeId: Int?
    
    // Photo state
    @State private var photoThumbnails: [UIImage] = []
    @State private var selectedFiles: [URL] = []
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showCameraActionSheet = false
    @State private var cameraSessionPhotos: [PhotoWithLocation] = []
    @State private var showCustomCamera = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var stagePhotoCount: Int = 0 // Track how many photos came from the stage
    
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?
    
    // UI state
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showUserPicker = false
    @State private var showSkipConfirmation = false
    @FocusState private var focusedField: FocusedField?
    
    private enum FocusedField {
        case title, description
    }
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedPriorityId != nil &&
        selectedAssigneeId != nil &&
        !photoThumbnails.isEmpty // At least one photo required
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else {
                    formContent
                }
            }
            .navigationTitle("Create Snag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        showSkipConfirmation = true
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                loadData()
                prefillFromInspection()
                loadStagePhotos()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Skip Snag Creation?", isPresented: $showSkipConfirmation) {
                Button("Skip", role: .destructive) {
                    onSkip()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to skip creating a snag? The failed inspection stage will still be recorded.")
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var formContent: some View {
        VStack(spacing: 0) {
            Form {
                // Stage information section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Inspection Failed")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        
                        Text("Stage: \(stageResult.stage.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("A photo of the defect is required to create this snag.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 4)
                }
                
                // Photo section (required)
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Photos")
                                .font(.headline)
                            Text("*")
                                .foregroundColor(.red)
                            Spacer()
                            if photoThumbnails.isEmpty {
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("\(photoThumbnails.count) photo(s)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if !photoThumbnails.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(photoThumbnails.enumerated()), id: \.offset) { index, image in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 80, height: 80)
                                                .clipped()
                                                .cornerRadius(8)
                                            
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Button {
                                                        openSnagPhotoMarkupEditor(at: index)
                                                    } label: {
                                                        Image(systemName: "pencil.tip.crop.circle")
                                                            .font(.system(size: 16))
                                                            .foregroundStyle(.white)
                                                            .padding(5)
                                                            .background(.ultraThinMaterial, in: Circle())
                                                    }
                                                    .accessibilityLabel("Mark up photo")
                                                    Spacer()
                                                }
                                            }
                                            .padding(4)
                                            
                                            Button(action: { removePhoto(at: index) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white)
                                                    .clipShape(Circle())
                                            }
                                            .offset(x: 8, y: -8)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        Button(action: {
                            focusedField = nil
                            showCameraActionSheet = true
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text(photoThumbnails.isEmpty ? "Add Photo of Defect" : "Add More Photos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(photoThumbnails.isEmpty ? Color.orange : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                } header: {
                    Text("Defect Photo")
                }
                
                // Basic info section
                Section("Snag Details") {
                    TextField("Title *", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .title)
                    
                    TextField("Description *", text: $description, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .description)
                }
                
                // Priority and assignment
                if let settings = logSettings {
                    Section("Priority & Assignment") {
                        Picker("Priority *", selection: $selectedPriorityId) {
                            Text("Select Priority").tag(nil as Int?)
                            ForEach(settings.priorities, id: \.id) { priority in
                                Text(priority.name).tag(priority.id as Int?)
                            }
                        }
                        
                        HStack {
                            Text("Assignee *")
                            Spacer()
                            Button(selectedAssigneeId == nil ? "Select Assignee" : assigneeName) {
                                showUserPicker = true
                            }
                            .foregroundColor(selectedAssigneeId == nil ? .secondary : .accentColor)
                        }
                        
                        DatePicker("Due Date", selection: $dueDate, in: Date()..., displayedComponents: [.date])
                    }
                    
                    // Location (optional, pre-filled from inspection)
                    Section("Location") {
                        LocationSelector(
                            projectId: projectId,
                            token: currentToken,
                            selectedLocationId: $selectedLocationId,
                            placeholder: "Select location..."
                        )
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Submit button at bottom
            VStack(spacing: 0) {
                Divider()
                
                Button(action: {
                    submitSnag()
                }) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Create Snag")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (isSubmitting || !isFormValid)
                        ? Color.gray
                        : Color.blue
                    )
                    .foregroundColor(.white)
                    .cornerRadius(0)
                }
                .disabled(isSubmitting || !isFormValid)
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showUserPicker) {
            UserPickerView(
                users: users,
                selectedUserId: $selectedAssigneeId,
                title: "Select Assignee"
            )
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photosPickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .fullScreenCover(isPresented: $showCustomCamera, onDismiss: {
            processCapturedPhotos()
            cameraSessionPhotos = []
        }) {
            CustomCameraView(capturedImages: $cameraSessionPhotos)
        }
        .confirmationDialog("Add Photos", isPresented: $showCameraActionSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                // Multi-shot camera: take one photo or several, then tap Done.
                requestCameraPermissionAndShowCustomCamera()
            }
            Button("Choose From Library") {
                // Defer until the dialog has finished dismissing; presenting a picker
                // while the dialog is animating out gets silently dropped inside a sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showPhotosPicker = true
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Camera Permission", isPresented: $showingPermissionAlert) {
            Button("OK") { }
        } message: {
            Text(permissionAlertMessage)
        }
        .onChange(of: photosPickerItems) { oldItems, newItems in
            Task { await addSelectedPhotosToFiles(newItems) }
        }
        .fullScreenCover(item: $photoMarkupPresentation) { item in
            PhotoMarkupEditorScreen(
                image: item.image,
                onDone: { data in
                    photoMarkupEditorOnDone?(data)
                },
                onCancel: {
                    photoMarkupEditorOnCancel?()
                }
            )
        }
    }
    
    private var assigneeName: String {
        guard let assigneeId = selectedAssigneeId,
              let user = users.first(where: { $0.id == assigneeId }) else {
            return "Select Assignee"
        }
        return userDisplayName(user)
    }
    
    private func prefillFromInspection() {
        // Pre-fill title with stage name
        title = "Snag: \(stageResult.stage.name)"
        
        // Pre-fill description with context
        let templateName = inspection.projectInspectionTemplate.template.name
        description = "Defect identified during inspection #\(inspection.inspectionNumber) - \(templateName)\n\nStage: \(stageResult.stage.name)"
        
        // Pre-fill location from inspection
        selectedLocationId = inspection.locationId
    }
    
    private func loadData() {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                async let settingsTask = APIClient.fetchLogSettings(projectId: projectId, token: currentToken)
                async let usersTask = APIClient.fetchProjectUsers(projectId: projectId, token: currentToken)
                
                let (settings, fetchedUsers) = try await (settingsTask, usersTask)
                
                await MainActor.run {
                    self.logSettings = settings
                    
                    // Deduplicate users
                    var uniqueById: [Int: User] = [:]
                    for u in fetchedUsers { uniqueById[u.id] = u }
                    self.users = Array(uniqueById.values).sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
                    
                    // Find the "snag" type ID (case-insensitive)
                    self.snagTypeId = settings.types.first(where: { 
                        $0.name.lowercased() == "snag" || $0.name.lowercased().contains("snag")
                    })?.id
                    
                    // Pre-select the inspection assignee if available
                    if let inspectionAssigneeId = inspection.assignedToId {
                        self.selectedAssigneeId = inspectionAssigneeId
                    }
                    
                    // Default to medium/normal priority if available
                    if let mediumPriority = settings.priorities.first(where: { 
                        $0.name.lowercased().contains("medium") || $0.name.lowercased().contains("normal")
                    }) {
                        self.selectedPriorityId = mediumPriority.id
                    } else if let firstPriority = settings.priorities.first {
                        self.selectedPriorityId = firstPriority.id
                    }
                    
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loadStagePhotos() {
        Task {
            do {
                // Fetch stage photos
                let stagePhotos = try await APIClient.fetchStagePhotos(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    stageId: stageResult.stageId,
                    token: currentToken
                )
                
                // Track how many photos came from the stage
                await MainActor.run {
                    stagePhotoCount = stagePhotos.count
                }
                
                // Download each photo and add to thumbnails and files
                for photo in stagePhotos {
                    await downloadAndAddPhoto(from: photo.fileUrl, fileName: photo.fileName)
                }
            } catch {
                print("Failed to load stage photos: \(error)")
                // Don't show error to user - photos are optional, user can add more
            }
        }
    }
    
    private func downloadAndAddPhoto(from urlString: String, fileName: String) async {
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Save to temporary directory
            if let fileURL = saveFileToTemporaryDirectory(data: data, fileName: fileName) {
                await MainActor.run {
                    selectedFiles.append(fileURL)
                }
            }
            
            // Create thumbnail
            if let image = UIImage(data: data) {
                await MainActor.run {
                    photoThumbnails.append(image)
                }
            }
        } catch {
            print("Failed to download photo from \(urlString): \(error)")
        }
    }
    
    private func submitSnag() {
        guard isFormValid else { return }
        guard !isSubmitting else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                let dueDateString = ISO8601DateFormatter().string(from: dueDate)
                
                // Find or default the snag type
                let typeId = snagTypeId ?? logSettings?.types.first?.id
                
                // Find the "open" status
                let openStatusId = logSettings?.statuses.first(where: { 
                    $0.name.lowercased().contains("open") 
                })?.id
                
                // Use the createDefectLog endpoint to properly link the defect and log
                // This endpoint automatically attaches stage photos to the log
                let response = try await APIClient.createDefectLog(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    stageId: stageResult.stageId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    defectDescription: nil,
                    assigneeId: selectedAssigneeId,
                    dueDate: dueDateString,
                    typeId: typeId,
                    statusId: openStatusId,
                    priorityId: selectedPriorityId,
                    tradeId: nil,
                    locationId: selectedLocationId,
                    token: currentToken
                )
                
                print("✅ Snag log created successfully: Log #\(response.log.id) linked to defect #\(response.defect.id)")
                if let message = response.message {
                    print("   \(message)")
                }
                
                // Upload any additional photos that aren't already stage photos
                // (The backend auto-attaches stage photos, but user may have added new ones)
                if selectedFiles.count > stagePhotoCount {
                    let newPhotoFiles = Array(selectedFiles.dropFirst(stagePhotoCount))
                    for url in newPhotoFiles {
                        if let data = try? Data(contentsOf: url) {
                            let att = try await uploadData(data: data, fileName: url.lastPathComponent, dataType: "logs")
                            // Add attachment to the created log
                            try await addAttachmentToLog(logId: response.log.id, attachment: att)
                        }
                    }
                }
                
                await MainActor.run {
                    isSubmitting = false
                    onSuccess()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to create snag: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func addAttachmentToLog(logId: Int, attachment: CreateLogRequest.AttachmentData) async throws {
        // Update the log with the new attachment
        // We need to use the update endpoint to add attachments
        let logData = CreateLogRequest(
            title: title,
            description: nil,
            typeId: nil,
            tradeId: nil,
            statusId: nil,
            hazardId: nil,
            contributingConditionId: nil,
            contributingBehaviourId: nil,
            dueDate: nil,
            priorityId: nil,
            folderId: nil,
            isPrivate: false,
            assigneeId: nil,
            distributionUserIds: nil,
            location: nil,
            specification: nil,
            locationId: nil,
            attachments: [attachment]
        )
        _ = try await APIClient.updateLog(projectId: projectId, logId: logId, logData: logData, token: currentToken)
    }
    
    // MARK: - Photo Helpers
    
    private func dismissSnagPhotoMarkupEditor() {
        photoMarkupPresentation = nil
        photoMarkupEditorOnDone = nil
        photoMarkupEditorOnCancel = nil
    }
    
    private func replaceSnagPhotoAt(index: Int, with jpegData: Data) {
        guard index < selectedFiles.count, index < photoThumbnails.count else { return }
        guard let newURL = saveFileToTemporaryDirectory(data: jpegData, fileName: "snag_\(UUID().uuidString).jpg") else { return }
        selectedFiles[index] = newURL
        if let img = UIImage(data: jpegData) {
            photoThumbnails[index] = img
        }
    }
    
    private func openSnagPhotoMarkupEditor(at index: Int) {
        guard index < photoThumbnails.count else { return }
        let ui = photoThumbnails[index]
        photoMarkupEditorOnDone = { data in
            replaceSnagPhotoAt(index: index, with: data)
            dismissSnagPhotoMarkupEditor()
        }
        photoMarkupEditorOnCancel = {
            dismissSnagPhotoMarkupEditor()
        }
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
    }
    
    private func removePhoto(at index: Int) {
        guard index < selectedFiles.count && index < photoThumbnails.count else { return }
        selectedFiles.remove(at: index)
        photoThumbnails.remove(at: index)
    }
    
    private func addSelectedPhotosToFiles(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if let url = saveFileToTemporaryDirectory(data: data, fileName: "snag_\(UUID().uuidString).jpg") {
                        await MainActor.run { selectedFiles.append(url) }
                    }
                    if let image = UIImage(data: data) {
                        await MainActor.run { photoThumbnails.append(image) }
                    }
                }
            }
            await MainActor.run { photosPickerItems.removeAll() }
        } catch {
            await MainActor.run { errorMessage = "Failed to add photo: \(error.localizedDescription)" }
        }
    }
    
    private func processCapturedPhotos() {
        for photoWithLocation in cameraSessionPhotos {
            if let url = saveFileToTemporaryDirectory(data: photoWithLocation.image, fileName: "snag_\(UUID().uuidString).jpg") {
                selectedFiles.append(url)
            }
            if let image = UIImage(data: photoWithLocation.image) {
                photoThumbnails.append(image)
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
    
    private func requestCameraPermissionAndShowCustomCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            presentCustomCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.presentCustomCamera()
                    } else {
                        self.permissionAlertMessage = "Camera access is required to take photos. Please enable it in Settings."
                        self.showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            self.permissionAlertMessage = "Camera access has been denied. Please go to Settings to enable it for this app."
            self.showingPermissionAlert = true
        @unknown default:
            break
        }
    }

    private func presentCustomCamera() {
        // Reset photos array when opening camera to start fresh
        cameraSessionPhotos = []
        // Defer presentation until the confirmation dialog has fully dismissed.
        // Presenting a fullScreenCover while the dialog is still animating out
        // (inside a sheet) gets silently dropped and the form jumps to the top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showCustomCamera = true
        }
    }
    
    private func uploadData(data: Data, fileName: String, dataType: String) async throws -> CreateLogRequest.AttachmentData {
        guard let url = URL(string: "\(APIClient.baseURL)/upload") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = createMultipartFormData(data: data, fileName: fileName, boundary: boundary, dataType: dataType, mimeType: "image/jpeg")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }

        do {
            let uploadResponse = try JSONDecoder().decode(UploadedFileResponse.self, from: responseData)
            return CreateLogRequest.AttachmentData(
                fileUrl: uploadResponse.fileUrl,
                fileName: uploadResponse.fileName,
                fileType: uploadResponse.fileType
            )
        } catch {
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                let fileUrl = json["fileKey"] as? String ?? json["fileUrl"] as? String ?? json["url"] as? String ?? ""
                let fileName = json["fileName"] as? String ?? fileName
                let fileType = json["fileType"] as? String ?? "image/jpeg"
                
                return CreateLogRequest.AttachmentData(
                    fileUrl: fileUrl,
                    fileName: fileName,
                    fileType: fileType
                )
            }
            throw error
        }
    }

    private func createMultipartFormData(data: Data, fileName: String, boundary: String, dataType: String, mimeType: String) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"dataType\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(dataType)\r\n".data(using: .utf8)!)

        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
