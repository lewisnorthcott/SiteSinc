import SwiftUI
import PhotosUI
import AVFoundation

struct CreateLogView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let editingLog: Log?
    let onSuccess: () -> Void
    
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineLogManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Form state
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedTypeId: Int?
    @State private var selectedTradeId: Int?
    @State private var selectedStatusId: Int?
    @State private var selectedHazardId: Int?
    @State private var selectedConditionId: Int?
    @State private var selectedBehaviourId: Int?
    @State private var selectedPriorityId: Int?
    @State private var selectedFolderId: Int?
    @State private var selectedLocationId: Int?
    @State private var selectedAssigneeId: Int?
    @State private var selectedDistributionUserIds: Set<Int> = []
    @State private var dueDate: Date = Date()

    // Incident fields
    @State private var occurredAt = Date()
    @State private var severityBand: SeverityBand?
    @State private var injuryInvolved = false
    @State private var bodyMapRegions: Set<String> = []
    @State private var riddorKeys: Set<String> = []
    @State private var isAnonymous = false
    
    // Data
    @State private var logSettings: LogSettings?
    @State private var users: [User] = []
    
    // UI state
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showUserPicker = false
    @State private var showDistributionPicker = false
    @State private var savedOffline = false

    // Attachment state (defer upload until submit)
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var selectedFiles: [URL] = []
    @State private var uploadedAttachments: [CreateLogRequest.AttachmentData] = []
    @State private var attachmentErrorMessage: String?
    @State private var showCameraPicker = false
    @State private var showPhotosPicker = false
    @State private var showCameraActionSheet = false
    @State private var showCustomCamera = false
    @State private var cameraSessionPhotos: [PhotoWithLocation] = []
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var photoThumbnails: [UIImage] = []
    
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?
    @State private var photoMarkupGateImage: UIImage?
    @State private var showPhotoMarkupGate = false
    @State private var photoMarkupGateApplyJPEG: ((Data) -> Void)?
    
    private var isEditing: Bool { editingLog != nil }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedTypeId != nil &&
        selectedPriorityId != nil &&
        selectedAssigneeId != nil &&
        !selectedDistributionUserIds.isEmpty &&
        dueDate >= Calendar.current.startOfDay(for: Date())
    }
    
    init(projectId: Int, token: String, projectName: String, editingLog: Log? = nil, onSuccess: @escaping () -> Void) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.editingLog = editingLog
        self.onSuccess = onSuccess
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
                
                // Saved offline success overlay
                if savedOffline {
                    savedOfflineOverlay
                }
            }
            .navigationTitle(isEditing ? "Edit Log" : "Create Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadData()
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
        }
    }
    
    private var savedOfflineOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Saved Offline")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Your log will be synced when you're back online")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
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
            // Offline indicator
            if offlineManager.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline Mode - Log will be saved locally")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange)
            }
            
            Form {
                basicInfoSection

                if let settings = logSettings {
                    categorizationSection(settings)
                    if shouldShowSafetySection(settings: settings) {
                        safetySection(settings)
                    }
                    if shouldShowIncidentSection(settings: settings) {
                        incidentSection
                    }
                    assignmentSection
                    attachmentsSection
                }
            }
            
            // Submit button at bottom
            VStack(spacing: 0) {
                Divider()
                
                Button(action: {
                    submitLog()
                }) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isEditing ? "Update Log" : "Create Log")
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
        .sheet(isPresented: $showDistributionPicker) {
            MultiUserPickerView(
                users: users,
                selectedUserIds: $selectedDistributionUserIds,
                title: "Select Distribution"
            )
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerWithLocation(
                onImageCaptured: { photoWithLocation in
                    guard let ui = UIImage(data: photoWithLocation.image) else { return }
                    photoMarkupGateImage = ui
                    photoMarkupGateApplyJPEG = { jpeg in
                        if let url = saveFileToTemporaryDirectory(data: jpeg, fileName: "photo_\(UUID().uuidString).jpg") {
                            selectedFiles.append(url)
                        }
                        if let image = UIImage(data: jpeg) {
                            photoThumbnails.append(image)
                        }
                    }
                    showPhotoMarkupGate = true
                },
                onDismiss: { showCameraPicker = false }
            )
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photosPickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .fullScreenCover(isPresented: $showCustomCamera, onDismiss: {
            // Process all captured photos when camera is dismissed
            processCapturedPhotos()
            cameraSessionPhotos = []
        }) {
            CustomCameraView(capturedImages: $cameraSessionPhotos)
        }
        .confirmationDialog("Add Photos", isPresented: $showCameraActionSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                requestCameraPermissionAndShowPicker()
            }
            Button("Take Multiple Photos") {
                requestCameraPermissionAndShowCustomCamera()
            }
            Button("Choose From Library") {
                showPhotosPicker = true
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
        .confirmationDialog("Photo", isPresented: $showPhotoMarkupGate, titleVisibility: .visible) {
            Button("Use photo") {
                if let img = photoMarkupGateImage, let d = img.jpegData(compressionQuality: 0.8) {
                    photoMarkupGateApplyJPEG?(d)
                }
                photoMarkupGateImage = nil
                photoMarkupGateApplyJPEG = nil
            }
            Button("Mark up") {
                let img = photoMarkupGateImage
                let apply = photoMarkupGateApplyJPEG
                photoMarkupGateImage = nil
                photoMarkupGateApplyJPEG = nil
                showPhotoMarkupGate = false
                photoMarkupEditorOnDone = { data in
                    apply?(data)
                    dismissLogPhotoMarkupEditor()
                }
                photoMarkupEditorOnCancel = {
                    if let i = img, let d = i.jpegData(compressionQuality: 0.8) {
                        apply?(d)
                    }
                    dismissLogPhotoMarkupEditor()
                }
                if let ui = img {
                    photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
                }
            }
            Button("Cancel", role: .cancel) {
                photoMarkupGateImage = nil
                photoMarkupGateApplyJPEG = nil
            }
        } message: {
            Text("Use this photo as captured, or mark it up before adding.")
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
    
    private var basicInfoSection: some View {
        Section("Basic Information") {
            TextField("Title *", text: $title)
                .textInputAutocapitalization(.sentences)

            TextField("Description *", text: $description, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(3...6)
        }
    }
    
    private func categorizationSection(_ settings: LogSettings) -> some View {
        Section("Categorization") {
            Picker("Type *", selection: $selectedTypeId) {
                Text("Select Type").tag(nil as Int?)
                ForEach(settings.types, id: \.id) { type in
                    Text(type.name).tag(type.id as Int?)
                }
            }
            
            Picker("Trade", selection: $selectedTradeId) {
                Text("Select Trade").tag(nil as Int?)
                ForEach(settings.trades, id: \.id) { trade in
                    Text(trade.name).tag(trade.id as Int?)
                }
            }
            
            if isEditing {
                Picker("Status", selection: $selectedStatusId) {
                    Text("Select Status").tag(nil as Int?)
                    ForEach(settings.statuses, id: \.id) { status in
                        Text(status.name).tag(status.id as Int?)
                    }
                }
            } else {
                HStack {
                    Text("Status")
                    Spacer()
                    Text("Open")
                        .foregroundColor(.secondary)
                }
            }
            
            Picker("Priority *", selection: $selectedPriorityId) {
                Text("Select Priority").tag(nil as Int?)
                ForEach(settings.priorities, id: \.id) { priority in
                    Text(priority.name).tag(priority.id as Int?)
                }
            }
            
            if !settings.folders.isEmpty {
                Picker("Folder", selection: $selectedFolderId) {
                    Text("Select Folder").tag(nil as Int?)
                    ForEach(settings.folders, id: \.id) { folder in
                        Text(folder.name).tag(folder.id as Int?)
                    }
                }
            }
            
            LocationSelector(
                projectId: projectId,
                token: sessionManager.token ?? token,
                selectedLocationId: $selectedLocationId,
                placeholder: "Select location..."
            )
        }
    }
    
    private func shouldShowSafetySection(settings: LogSettings) -> Bool {
        guard let selectedTypeId = selectedTypeId else { return false }
        if let selectedType = settings.types.first(where: { $0.id == selectedTypeId }) {
            return selectedType.name.lowercased().contains("safety")
        }
        return false
    }

    private func shouldShowIncidentSection(settings: LogSettings) -> Bool {
        guard let selectedTypeId = selectedTypeId else { return false }
        if let selectedType = settings.types.first(where: { $0.id == selectedTypeId }) {
            return logTypeNameMatchesIncidentHub(selectedType.name)
        }
        return false
    }

    private var incidentSection: some View {
        Section("Incident details") {
            DatePicker("When did it happen?", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
            SeverityPickerView(selectedBand: $severityBand)
            Toggle("Someone was injured", isOn: $injuryInvolved)
            if injuryInvolved {
                BodyMapSelectorView(selectedRegions: $bodyMapRegions)
            }
            RiddorCheckView(selectedKeys: $riddorKeys)
            Toggle("Report anonymously", isOn: $isAnonymous)
        }
    }

    private func safetySection(_ settings: LogSettings) -> some View {
        Section("Safety Information") {
            Picker("Hazard", selection: $selectedHazardId) {
                Text("Select Hazard").tag(nil as Int?)
                ForEach(settings.hazards, id: \.id) { hazard in
                    Text(hazard.name).tag(hazard.id as Int?)
                }
            }
            
            Picker("Contributing Condition", selection: $selectedConditionId) {
                Text("Select Condition").tag(nil as Int?)
                ForEach(settings.conditions, id: \.id) { condition in
                    Text(condition.name).tag(condition.id as Int?)
                }
            }
            
            Picker("Contributing Behaviour", selection: $selectedBehaviourId) {
                Text("Select Behaviour").tag(nil as Int?)
                ForEach(settings.behaviours, id: \.id) { behaviour in
                    Text(behaviour.name).tag(behaviour.id as Int?)
                }
            }
        }
    }
    
    private var assignmentSection: some View {
        Section("Assignment") {
            HStack {
                Text("Assignee *")
                Spacer()
                Button(selectedAssigneeId == nil ? "Select Assignee" : assigneeName) {
                    showUserPicker = true
                }
                .foregroundColor(selectedAssigneeId == nil ? .secondary : .accentColor)
            }

            HStack {
                Text("Distribution *")
                Spacer()
                Button(selectedDistributionUserIds.isEmpty ? "Select Users" : "\(selectedDistributionUserIds.count) users") {
                    showDistributionPicker = true
                }
                .foregroundColor(selectedDistributionUserIds.isEmpty ? .secondary : .accentColor)
            }

            DatePicker("Due Date *", selection: $dueDate, in: Date()..., displayedComponents: [.date])
        }
    }
    
    
    

    private var attachmentsSection: some View {
        Section("Attachments") {
            if !photoThumbnails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Photos")
                        .font(.subheadline)
                        .fontWeight(.medium)

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
                                                openLogPhotoMarkupEditor(at: index)
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
            }

            Button(action: { showCameraActionSheet = true }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Add Photos")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            if let attachmentError = attachmentErrorMessage {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }
        }
    }
    
    private var assigneeName: String {
        guard let assigneeId = selectedAssigneeId,
              let user = users.first(where: { $0.id == assigneeId }) else {
            return "Select Assignee"
        }
        return userDisplayName(user)
    }
    
    private func userDisplayName(_ user: User) -> String {
        // First try top-level firstName/lastName
        if let firstName = user.firstName, let lastName = user.lastName,
           !firstName.isEmpty || !lastName.isEmpty {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        }
        
        // Fallback to tenant data
        if let tenant = user.tenants?.first {
            let firstName = tenant.firstName ?? ""
            let lastName = tenant.lastName ?? ""
            if !firstName.isEmpty || !lastName.isEmpty {
                return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Final fallback to email
        return user.email ?? "Unknown User"
    }
    
    private func loadData() {
        
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                async let settingsTask = APIClient.fetchLogSettings(projectId: projectId, token: sessionManager.token ?? token)
                async let usersTask = APIClient.fetchProjectUsers(projectId: projectId, token: sessionManager.token ?? token)
                
                let (settings, fetchedUsers) = try await (settingsTask, usersTask)
                
                await MainActor.run {
                    self.logSettings = settings
                    // Deduplicate by id in case backend fallback returns duplicates or multiple sources
                    var uniqueById: [Int: User] = [:]
                    for u in fetchedUsers { uniqueById[u.id] = u }
                    self.users = Array(uniqueById.values).sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
                    self.isLoading = false

                    // Set default status to "open" when creating new log
                    if editingLog == nil {
                        if let openStatus = settings.statuses.first(where: { $0.name.lowercased().contains("open") }) {
                            self.selectedStatusId = openStatus.id
                        }
                    }

                    // Populate form if editing
                    if let log = editingLog {
                        populateFormWithLog(log)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to create logs."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                self.errorMessage = "Logs feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                            }
                        default:
                            self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func populateFormWithLog(_ log: Log) {
        title = log.title ?? ""
        description = log.description ?? ""
        selectedTypeId = log.typeId
        selectedTradeId = log.tradeId
        selectedStatusId = log.statusId
        selectedHazardId = log.hazardId
        selectedConditionId = log.contributingConditionId
        selectedBehaviourId = log.contributingBehaviourId
        selectedPriorityId = log.priorityId
        selectedFolderId = log.folderId
        selectedLocationId = log.locationId
        selectedAssigneeId = log.assigneeId
        selectedDistributionUserIds = Set(log.distributions?.map { $0.userId } ?? [])

        if let dueDateString = log.dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dueDateString) {
                dueDate = date
            }
        }

        if let occurred = log.occurredAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: occurred) ?? ISO8601DateFormatter().date(from: occurred) {
                occurredAt = date
            }
        }
        severityBand = log.severityBand
        injuryInvolved = log.injuryInvolved ?? false
        bodyMapRegions = Set(log.incidentPayload?.bodyMap ?? [])
        riddorKeys = Set(log.incidentPayload?.riddor ?? [])
        isAnonymous = log.isAnonymous ?? false

        // Populate existing attachments
        if let logAttachments = log.attachments {
            uploadedAttachments = logAttachments.map { attachment in
                CreateLogRequest.AttachmentData(
                    fileUrl: attachment.fileUrl,
                    fileName: attachment.fileName,
                    fileType: attachment.fileType
                )
            }
        }
    }
    
    private func submitLog() {
        print("🔵 submitLog called - title: '\(title)'")
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Title is empty, returning early")
            return
        }

        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Description is empty, returning early")
            errorMessage = "Description is required"
            return
        }

        guard selectedTypeId != nil else {
            print("❌ Type is not selected, returning early")
            errorMessage = "Type is required"
            return
        }

        guard selectedPriorityId != nil else {
            print("❌ Priority is not selected, returning early")
            errorMessage = "Priority is required"
            return
        }

        guard selectedAssigneeId != nil else {
            print("❌ Assignee is not selected, returning early")
            errorMessage = "Assignee is required"
            return
        }

        guard !selectedDistributionUserIds.isEmpty else {
            print("❌ Distribution is empty, returning early")
            errorMessage = "Distribution is required"
            return
        }

        guard dueDate >= Calendar.current.startOfDay(for: Date()) else {
            print("❌ Due date is in the past, returning early")
            errorMessage = "Due date cannot be in the past"
            return
        }

        print("✅ All required fields are valid, proceeding with submission")
        Task {
            await MainActor.run {
                isSubmitting = true
                errorMessage = nil
            }
            
            // Check if we're offline - if editing, we can't edit offline (need server state)
            if offlineManager.isOffline && editingLog != nil {
                await MainActor.run {
                    self.isSubmitting = false
                    self.errorMessage = "Cannot edit logs while offline. Please connect to the internet."
                }
                return
            }
            
            do {
                let dueDateString: String = ISO8601DateFormatter().string(from: dueDate)
                
                // If offline, save for later sync
                if offlineManager.isOffline {
                    await saveLogOffline(dueDateString: dueDateString)
                    return
                }
                
                // Upload files now (deferred until submit)
                var attachments: [CreateLogRequest.AttachmentData] = []
                for url in selectedFiles {
                    if let data = try? Data(contentsOf: url) {
                        let att = try await uploadData(data: data, fileName: url.lastPathComponent, dataType: "logs")
                        attachments.append(att)
                    }
                }

                var logData = CreateLogRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                    typeId: selectedTypeId,
                    tradeId: selectedTradeId,
                    statusId: selectedStatusId,
                    hazardId: selectedHazardId,
                    contributingConditionId: selectedConditionId,
                    contributingBehaviourId: selectedBehaviourId,
                    dueDate: dueDateString,
                    priorityId: selectedPriorityId,
                    folderId: selectedFolderId,
                    isPrivate: false,
                    assigneeId: selectedAssigneeId,
                    distributionUserIds: selectedDistributionUserIds.isEmpty ? nil : Array(selectedDistributionUserIds),
                    location: nil,
                    specification: nil,
                    locationId: selectedLocationId,
                    attachments: attachments.isEmpty ? nil : attachments
                )

                let incidentMode = logSettings.flatMap { settings -> Bool in
                    guard let typeId = selectedTypeId,
                          let type = settings.types.first(where: { $0.id == typeId }) else { return false }
                    return logTypeNameMatchesIncidentHub(type.name)
                } ?? false
                CreateLogIncidentFields(
                    recordType: nil,
                    isAnonymous: isAnonymous,
                    occurredAt: ISO8601DateFormatter().string(from: occurredAt),
                    severityBand: severityBand,
                    injuryInvolved: injuryInvolved,
                    riddorReasons: Array(riddorKeys),
                    bodyMap: Array(bodyMapRegions)
                ).apply(to: &logData, incidentMode: incidentMode)
                
                if let log = editingLog {
                    _ = try await APIClient.updateLog(
                        projectId: projectId,
                        logId: log.id,
                        logData: logData,
                        token: sessionManager.token ?? token
                    )
                } else {
                    print("📤 Creating log with data: \(logData)")
                    let result = try await APIClient.createLog(
                        projectId: projectId,
                        logData: logData,
                        token: sessionManager.token ?? token
                    )
                    print("✅ Log created successfully: \(result.log.id)")
                }
                
                await MainActor.run {
                    self.isSubmitting = false
                    self.onSuccess()
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    print("❌ Log creation error: \(error)")
                    
                    // Check if it's a network error - offer to save offline
                    if let apiError = error as? APIError, case .networkError = apiError {
                        // Save offline instead
                        Task {
                            let dueDateString = ISO8601DateFormatter().string(from: dueDate)
                            await saveLogOffline(dueDateString: dueDateString)
                        }
                        return
                    }
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to \(isEditing ? "edit" : "create") logs."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                self.errorMessage = "Logs feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Failed to \(isEditing ? "update" : "create") log: \(error.localizedDescription)"
                            }
                        default:
                            self.errorMessage = "Failed to \(isEditing ? "update" : "create") log: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Failed to \(isEditing ? "update" : "create") log: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func saveLogOffline(dueDateString: String) async {
        // Collect attachment data
        var offlineAttachments: [OfflineLog.OfflineLogAttachment] = []
        for url in selectedFiles {
            if let data = try? Data(contentsOf: url) {
                let mimeType = getMimeType(for: url.pathExtension)
                offlineAttachments.append(OfflineLog.OfflineLogAttachment(
                    fileName: url.lastPathComponent,
                    fileType: mimeType,
                    fileData: data
                ))
            }
        }
        
        let offlineLog = OfflineLog(
            id: UUID().uuidString,
            projectId: projectId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
            typeId: selectedTypeId,
            tradeId: selectedTradeId,
            statusId: selectedStatusId,
            hazardId: selectedHazardId,
            contributingConditionId: selectedConditionId,
            contributingBehaviourId: selectedBehaviourId,
            dueDate: dueDateString,
            priorityId: selectedPriorityId,
            folderId: selectedFolderId,
            isPrivate: false,
            assigneeId: selectedAssigneeId,
            distributionUserIds: selectedDistributionUserIds.isEmpty ? nil : Array(selectedDistributionUserIds),
            location: nil,
            specification: nil,
            locationId: selectedLocationId,
            attachments: offlineAttachments.isEmpty ? nil : offlineAttachments,
            createdAt: Date(),
            token: sessionManager.token ?? token,
            recordType: nil,
            isAnonymous: nil,
            occurredAt: nil,
            incidentSeverityBand: nil,
            injuryInvolved: nil,
            regulatoryNotifiable: nil,
            incidentPayload: nil
        )
        
        offlineManager.saveLog(offlineLog)
        
        await MainActor.run {
            self.isSubmitting = false
            self.savedOffline = true
            
            // Show success message and dismiss after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.onSuccess()
            }
        }
    }
    
    private func getMimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
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
        default:
            return "application/octet-stream"
        }
    }

    private func addSelectedPhotosToFiles(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if let url = saveFileToTemporaryDirectory(data: data, fileName: "photo_\(UUID().uuidString).jpg") {
                        await MainActor.run { selectedFiles.append(url) }
                    }
                    if let image = UIImage(data: data) {
                        await MainActor.run { photoThumbnails.append(image) }
                    }
                }
            }
            await MainActor.run { photosPickerItems.removeAll() }
        } catch {
            await MainActor.run { attachmentErrorMessage = "Failed to add photo: \(error.localizedDescription)" }
        }
    }

    private func uploadData(data: Data, fileName: String, dataType: String) async throws -> CreateLogRequest.AttachmentData {
        guard let url = URL(string: "\(APIClient.baseURL)/upload") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let authToken = sessionManager.token ?? token
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = createMultipartFormData(data: data, fileName: fileName, boundary: boundary, dataType: dataType, mimeType: "application/octet-stream")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
        }

        // Debug: print the response
        if let jsonString = String(data: responseData, encoding: .utf8) {
            print("📥 Upload response: \(jsonString)")
        }

        // Try to decode the response - handle both possible formats
        do {
            let uploadResponse = try JSONDecoder().decode(UploadedFileResponse.self, from: responseData)
            return CreateLogRequest.AttachmentData(
                fileUrl: uploadResponse.fileUrl,
                fileName: uploadResponse.fileName,
                fileType: uploadResponse.fileType
            )
        } catch {
            print("⚠️ Failed to decode as UploadedFileResponse, trying alternative format: \(error)")
            // Try alternative format where the response might have different keys
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                print("📦 JSON keys: \(json.keys)")
                // Common alternative keys: "fileKey", "url", "file", "path", "key"
                let fileUrl = json["fileKey"] as? String ?? json["fileUrl"] as? String ?? json["url"] as? String ?? json["file"] as? String ?? json["path"] as? String ?? json["key"] as? String ?? ""
                let fileName = json["fileName"] as? String ?? json["name"] as? String ?? json["originalName"] as? String ?? fileName
                let fileType = json["fileType"] as? String ?? json["type"] as? String ?? json["mimeType"] as? String ?? "application/octet-stream"
                
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

        // dataType field
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"dataType\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(dataType)\r\n".data(using: .utf8)!)

        // file field
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func removeFile(at index: Int) { 
        selectedFiles.remove(at: index) 
    }
    
    private func removePhoto(at index: Int) {
        guard index < selectedFiles.count && index < photoThumbnails.count else { return }
        selectedFiles.remove(at: index)
        photoThumbnails.remove(at: index)
    }

    private func dismissLogPhotoMarkupEditor() {
        photoMarkupPresentation = nil
        photoMarkupEditorOnDone = nil
        photoMarkupEditorOnCancel = nil
    }

    private func replaceLogPhotoAt(index: Int, with jpegData: Data) {
        guard index < selectedFiles.count, index < photoThumbnails.count else { return }
        guard let newURL = saveFileToTemporaryDirectory(data: jpegData, fileName: "photo_\(UUID().uuidString).jpg") else { return }
        selectedFiles[index] = newURL
        if let img = UIImage(data: jpegData) {
            photoThumbnails[index] = img
        }
    }

    private func openLogPhotoMarkupEditor(at index: Int) {
        guard index < photoThumbnails.count else { return }
        let ui = photoThumbnails[index]
        photoMarkupEditorOnDone = { data in
            replaceLogPhotoAt(index: index, with: data)
            dismissLogPhotoMarkupEditor()
        }
        photoMarkupEditorOnCancel = {
            dismissLogPhotoMarkupEditor()
        }
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
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
    
    private func processCapturedPhotos() {
        // Process all captured photos when camera is dismissed
        // This ensures we get all photos, not just the ones processed incrementally
        for photoWithLocation in cameraSessionPhotos {
            if let url = saveFileToTemporaryDirectory(data: photoWithLocation.image, fileName: "photo_\(UUID().uuidString).jpg") {
                selectedFiles.append(url)
            }
            if let image = UIImage(data: photoWithLocation.image) {
                photoThumbnails.append(image)
            }
        }
    }
    
    private func requestCameraPermissionAndShowPicker() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            showCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCameraPicker = true
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
    
    private func requestCameraPermissionAndShowCustomCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            // Reset photos array when opening camera to start fresh
            cameraSessionPhotos = []
            showCustomCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        // Reset photos array when opening camera to start fresh
                        self.cameraSessionPhotos = []
                        self.showCustomCamera = true
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
}

// Helper function to get display name for a user
func userDisplayName(_ user: User) -> String {
    // First try top-level firstName/lastName
    if let firstName = user.firstName, let lastName = user.lastName,
       !firstName.isEmpty || !lastName.isEmpty {
        return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    // Fallback to tenant data
    if let tenant = user.tenants?.first {
        let firstName = tenant.firstName ?? ""
        let lastName = tenant.lastName ?? ""
        if !firstName.isEmpty || !lastName.isEmpty {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        }
    }
    
    // Final fallback to email
    return user.email ?? "Unknown User"
}

struct UserPickerView: View {
    let users: [User]
    @Binding var selectedUserId: Int?
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(users, id: \.id) { user in
                    Button(action: {
                        selectedUserId = user.id
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(userDisplayName(user))
                                    .foregroundColor(.primary)
                                
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedUserId == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if selectedUserId != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            selectedUserId = nil
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct MultiUserPickerView: View {
    let users: [User]
    @Binding var selectedUserIds: Set<Int>
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(users, id: \.id) { user in
                    Button(action: {
                        if selectedUserIds.contains(user.id) {
                            selectedUserIds.remove(user.id)
                        } else {
                            selectedUserIds.insert(user.id)
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(userDisplayName(user))
                                    .foregroundColor(.primary)
                                
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedUserIds.contains(user.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

