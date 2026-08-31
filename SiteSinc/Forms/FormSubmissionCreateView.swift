import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Network
import AVFoundation
import UIKit

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

struct FormSubmissionCreateView: View {
    @State var form: FormModel
    let projectId: Int
    let token: String
    /// When set, form is part of a permit flow; submission will be linked to this permit.
    let permitId: Int?
    /// When set, POST body goes to `POST /permits/:id/closeout` instead of form submit.
    let permitCloseoutSubmitId: Int?
    /// When true with `permitCloseoutSubmitId`, posts to daily handback instead of final close-out.
    let permitCloseoutIsDaily: Bool
    let onSave: (() -> Void)?
    /// When set (e.g. permit flow), show this instead of "Create Form Submission".
    let navigationTitleOverride: String?
    @EnvironmentObject var sessionManager: SessionManager

    init(
        form: FormModel,
        projectId: Int,
        token: String,
        permitId: Int? = nil,
        permitCloseoutSubmitId: Int? = nil,
        permitCloseoutIsDaily: Bool = false,
        navigationTitleOverride: String? = nil,
        onSave: (() -> Void)? = nil
    ) {
        _form = State(initialValue: form)
        self.projectId = projectId
        self.token = token
        self.permitId = permitId
        self.permitCloseoutSubmitId = permitCloseoutSubmitId
        self.permitCloseoutIsDaily = permitCloseoutIsDaily
        self.navigationTitleOverride = navigationTitleOverride
        self.onSave = onSave
    }

    @State private var isLoading = false
    @State private var responses: [String: String] = [:]
    @State private var stagedCameraData: [String: [PhotoWithLocation]] = [:]
    @State private var isSubmitting = false
    @State private var photoPickerItems: [String: [PhotosPickerItem]] = [:]
    @State private var photoPreviews: [String: [UIImage]] = [:]
    @State private var signatureImages: [String: UIImage] = [:]
    @State private var fileURLs: [String: URL] = [:]
    @State private var showingSignaturePad: String?
    @StateObject private var documentPickerDelegate = DocumentPickerDelegateWrapper()
    @Environment(\.dismiss) private var dismiss
    @State private var isPickerPresented = false
    @State private var activeFieldId: String?

    @State private var showingCameraActionSheetForField: String?
    @State private var showingImagePicker = false
    @State private var showingPhotosPicker = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var capturedImages: [String: [UIImage]] = [:]

    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""

    @State private var isOffline = false
    private let monitor = NWPathMonitor()
    @State private var submissionType: String?
    
    // Full-screen multi-photo camera
    @State private var isCustomCameraPresented = false
    @State private var cameraSessionPhotos: [PhotoWithLocation] = []
    @State private var customCameraTargetFieldId: String?
    
    // Folder selection state
    @State private var formsRootFolderId: Int? = nil
    @State private var formsFolders: [APIClient.FormFolder] = []
    @State private var selectedFolderId: Int? = nil
    @State private var showFolderPicker: Bool = false
    
    // Location selection state
    @State private var selectedLocationId: Int? = nil
    @State private var drawingPin: FormDrawingPin? = nil
    @State private var isFormDetailsExpanded = true
    
    // Validation state
    @State private var isFormValid = false
    @State private var showValidationErrors = false
    @State private var bannerKind: FormBannerKind = .error
    @State private var bannerMessage: String?
    @State private var scrollToAnchor: String?
    @State private var submitProgressTitle = "Submitting"
    @State private var submitProgressDetail: String?
    @State private var submitProgressCurrent = 0
    @State private var submitProgressTotal = 1
    
    // Unsaved changes detection
    @State private var showCloseConfirmation = false

    // Optional photo markup (camera field)
    @State private var photoMarkupGateImage: UIImage?
    @State private var showPhotoMarkupGate = false
    @State private var photoMarkupGateApplyJPEG: ((Data) -> Void)?
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?

    private var hasUnsavedChanges: Bool {
        if !responses.isEmpty && responses.values.contains(where: { !$0.isEmpty }) { return true }
        if !photoPreviews.isEmpty && photoPreviews.values.contains(where: { !$0.isEmpty }) { return true }
        if !signatureImages.isEmpty { return true }
        if !fileURLs.isEmpty { return true }
        if !stagedCameraData.isEmpty && stagedCameraData.values.contains(where: { !$0.isEmpty }) { return true }
        if !capturedImages.isEmpty && capturedImages.values.contains(where: { !$0.isEmpty }) { return true }
        if selectedFolderId != nil || selectedLocationId != nil || drawingPin != nil { return true }
        if let reference = responses["reference"], !reference.isEmpty { return true }
        return false
    }

    private struct SubmissionData: Codable {
        let formTemplateId: Int
        let revisionId: Int
        let projectId: Int
        let formData: [String: String]
        let status: String
    }

    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle(navigationTitleOverride ?? "Create Form")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(navigationTitleOverride ?? "Create Form")
                                .font(.headline)
                            Text(form.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            if hasUnsavedChanges {
                                showCloseConfirmation = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { hideKeyboard() }
                    }
                }
                .alert("Unsaved Changes", isPresented: $showCloseConfirmation) {
                    Button("Discard Changes", role: .destructive) {
                        dismiss()
                    }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
                .background(sheetAndPickerModifiers)
                 .onAppear {
                    print("✅ [FormSubmissionCreateView] View appeared.")
                    if let revision = form.currentRevision {
                        print("✅ [FormSubmissionCreateView] Current Revision IS PRESENT on appear. ID: \(revision.id), Fields: \(revision.fields.count)")
                    } else {
                        print("🚨 [FormSubmissionCreateView] Current Revision IS NIL on appear.")
                    }
                    startMonitoringNetwork()
                    // Don't validate immediately on appear
                     Task { await loadFoldersAndDefaults() }
                }
        }
        .formBrandTint()
    }

    @ViewBuilder
    private var sheetAndPickerModifiers: some View {
        EmptyView()
            .sheet(isPresented: Binding(
                get: { showingSignaturePad != nil },
                set: { if !$0 { showingSignaturePad = nil } }
            )) {
                if let fieldId = showingSignaturePad {
                    SignaturePadView(signatureImage: $signatureImages[fieldId])
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                DocumentPicker(delegate: documentPickerDelegate)
            }
            .sheet(isPresented: $showingImagePicker) {
                CameraPickerWithLocation(
                    onImageCaptured: { photoWithLocation in
                        guard let fieldId = activeFieldId else {
                            print("ERROR: activeFieldId is nil when trying to save camera photo")
                            return
                        }
                        guard let uiImage = UIImage(data: photoWithLocation.image) else {
                            print("ERROR: Could not create UIImage from captured photo data")
                            return
                        }
                        let loc = photoWithLocation.location
                        let cap = photoWithLocation.capturedAt
                        photoMarkupGateImage = uiImage
                        photoMarkupGateApplyJPEG = { data in
                            let fieldType = self.form.currentRevision?.fields.first(where: { $0.id == fieldId })?.type
                            let thumb = (UIImage(data: data) ?? uiImage).thumbnail(maxPixelSize: 400)
                            if fieldType == "camera" {
                                self.stagedCameraData[fieldId, default: []].append(
                                    PhotoWithLocation(image: data, location: loc, capturedAt: cap)
                                )
                            } else if let full = UIImage(data: data) {
                                self.capturedImages[fieldId, default: []].append(full)
                            }
                            self.photoPreviews[fieldId, default: []].append(thumb)
                            self.validateForm()
                        }
                        showPhotoMarkupGate = true
                    },
                    onDismiss: {
                        print("Camera picker dismissed, resetting activeFieldId")
                        activeFieldId = nil
                        showingImagePicker = false
                    }
                )
            }
            // Full-screen custom camera for multi-capture
            .fullScreenCover(isPresented: $isCustomCameraPresented, onDismiss: {
                // With immediate delivery in the camera controller, onChange handlers will have populated previews/staged for captures by the time dismiss runs.
                // We only need to set up a brief window for any *extremely* late appends, then clear.
                let target = customCameraTargetFieldId
                activeFieldId = nil
                customCameraTargetFieldId = nil
                cameraSessionPhotos = []
                if let fid = target {
                    // Re-arm transient target so a post-clear late append can still route via onChange.
                    customCameraTargetFieldId = fid
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if self.customCameraTargetFieldId == fid {
                            self.customCameraTargetFieldId = nil
                        }
                        if !self.cameraSessionPhotos.isEmpty {
                            self.cameraSessionPhotos = []
                        }
                    }
                }
            }) {
                CustomCameraView(capturedImages: $cameraSessionPhotos)
            }
            // As photos are captured in the custom camera, route them to the correct field type
            .onChange(of: cameraSessionPhotos) { oldValue, newValue in
                guard let fieldId = customCameraTargetFieldId ?? activeFieldId else { return }
                let newItems = Array(newValue.dropFirst(oldValue.count))
                guard !newItems.isEmpty else { return }
                let fieldType = form.currentRevision?.fields.first(where: { $0.id == fieldId })?.type
                var previews: [UIImage] = photoPreviews[fieldId] ?? []
                if fieldType == "camera" {
                    var staged: [PhotoWithLocation] = stagedCameraData[fieldId] ?? []
                    for p in newItems {
                        staged.append(p)
                        if let full = UIImage(data: p.image) {
                            previews.append(full.thumbnail(maxPixelSize: 400))
                        }
                    }
                    stagedCameraData[fieldId] = staged
                } else {
                    // Treat as regular image field; store *full-res* UIImages for later jpeg upload; thumbs only for display previews
                    var images: [UIImage] = capturedImages[fieldId] ?? []
                    for p in newItems {
                        if let full = UIImage(data: p.image) {
                            images.append(full) // keep full for quality upload
                            previews.append(full.thumbnail(maxPixelSize: 400))
                        }
                    }
                    capturedImages[fieldId] = images
                }
                photoPreviews[fieldId] = previews
            }
            .photosPicker(isPresented: $showingPhotosPicker, selection: $pickerSelection, maxSelectionCount: 5, matching: .images)
            .onChange(of: pickerSelection) { _, newItems in
                guard let fieldId = activeFieldId, !newItems.isEmpty else {
                    // Reset if no items were selected
                    if newItems.isEmpty {
                        activeFieldId = nil
                    }
                    return
                }

                // Check if this is a camera field
                let isCameraField = form.currentRevision?.fields.first(where: { $0.id == fieldId })?.type == "camera"
                
                if isCameraField {
                    // For camera fields, add to stagedCameraData (without location since it's from library)
                    Task {
                        var newPhotosWithLocation: [PhotoWithLocation] = []
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                let photoWithLocation = PhotoWithLocation(
                                    image: data,
                                    location: nil, // No location for library photos
                                    capturedAt: Date()
                                )
                                newPhotosWithLocation.append(photoWithLocation)
                            }
                        }
                        
                        await MainActor.run {
                            // Add to stagedCameraData for proper camera field processing
                            let existingCameraData = stagedCameraData[fieldId] ?? []
                            stagedCameraData[fieldId] = existingCameraData + newPhotosWithLocation
                            
                            // Also add to previews for UI display (downscaled)
                            var newImages: [UIImage] = []
                            for photoData in newPhotosWithLocation {
                                if let full = UIImage(data: photoData.image) {
                                    newImages.append(full.thumbnail(maxPixelSize: 400))
                                }
                            }
                            let existingPreviews = photoPreviews[fieldId] ?? []
                            photoPreviews[fieldId] = existingPreviews + newImages
                        }
                    }
                } else {
                    Task {
                        var newImages: [UIImage] = []
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                                newImages.append(image)
                            }
                        }
                        await MainActor.run {
                            capturedImages[fieldId, default: []].append(contentsOf: newImages)
                            let thumbs = newImages.map { $0.thumbnail(maxPixelSize: 400) }
                            photoPreviews[fieldId, default: []].append(contentsOf: thumbs)
                            validateForm()
                        }
                    }
                }

                // Reset for next use
                pickerSelection = []
                activeFieldId = nil
            }
            .onChange(of: documentPickerDelegate.selectedURL) { _, newURL in
                if let url = newURL, let fieldId = activeFieldId {
                    fileURLs[fieldId] = url
                }
            }
            .confirmationDialog("Photo", isPresented: $showPhotoMarkupGate, titleVisibility: .visible) {
                Button("Use photo") {
                    if let img = photoMarkupGateImage, let d = img.jpegData(compressionQuality: 0.8) {
                        photoMarkupGateApplyJPEG?(d)
                    }
                    photoMarkupGateImage = nil
                    photoMarkupGateApplyJPEG = nil
                    showPhotoMarkupGate = false
                }
                Button("Mark up") {
                    let img = photoMarkupGateImage
                    let apply = photoMarkupGateApplyJPEG
                    photoMarkupGateImage = nil
                    photoMarkupGateApplyJPEG = nil
                    showPhotoMarkupGate = false
                    photoMarkupEditorOnDone = { data in
                        apply?(data)
                        dismissFormPhotoMarkupEditor()
                    }
                    photoMarkupEditorOnCancel = {
                        if let i = img, let d = i.jpegData(compressionQuality: 0.8) {
                            apply?(d)
                        }
                        dismissFormPhotoMarkupEditor()
                    }
                    if let ui = img {
                        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
                    }
                }
                Button("Cancel", role: .cancel) {
                    photoMarkupGateImage = nil
                    photoMarkupGateApplyJPEG = nil
                    showPhotoMarkupGate = false
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

    private func dismissFormPhotoMarkupEditor() {
        photoMarkupPresentation = nil
        photoMarkupEditorOnDone = nil
        photoMarkupEditorOnCancel = nil
    }

    private func openCameraFieldMarkupEditor(fieldId: String, index: Int) {
        guard let staged = stagedCameraData[fieldId], index < staged.count,
              let ui = UIImage(data: staged[index].image) else { return }
        let loc = staged[index].location
        let cap = staged[index].capturedAt
        photoMarkupEditorOnDone = { newData in
            var arr = stagedCameraData[fieldId] ?? []
            guard index < arr.count else { return }
            arr[index] = PhotoWithLocation(image: newData, location: loc, capturedAt: cap)
            stagedCameraData[fieldId] = arr
            var prev = photoPreviews[fieldId] ?? []
            if index < prev.count, let im = UIImage(data: newData) {
                prev[index] = im
                photoPreviews[fieldId] = prev
            }
            validateForm()
            dismissFormPhotoMarkupEditor()
        }
        photoMarkupEditorOnCancel = {
            dismissFormPhotoMarkupEditor()
        }
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            BrandChrome.groupedBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().padding()
            } else if form.currentRevision == nil {
                noRevisionView
            } else if let fields = form.currentRevision?.fields, !fields.isEmpty {
                formScrollView(fields: fields)
            } else {
                noFieldsView
            }

            if isSubmitting {
                FormSubmitOverlay(
                    title: submitProgressTitle,
                    detail: submitProgressDetail,
                    current: submitProgressCurrent,
                    total: submitProgressTotal
                )
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text(permissionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    @ViewBuilder
    private var noRevisionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("No Published Revision")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            Text("This form template doesn't have a published revision. Edit the template and publish a version before creating a submission.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
    
    @ViewBuilder
    private func formScrollView(fields: [FormField]) -> some View {
        let completion = requiredCompletion(fields: fields)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let bannerMessage {
                        FormStatusBanner(kind: bannerKind, message: bannerMessage) {
                            self.bannerMessage = nil
                        }
                    }

                    FormCompletionMeter(completed: completion.completed, total: completion.total)

                    formDetailsSection
                        .id("formDetails")

                    ForEach(fields, id: \.id) { field in
                        renderFormField(field: field)
                            .formFieldSurface(needsAttention: showValidationErrors && fieldNeedsAttention(field))
                            .id(field.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollToAnchor) { _, anchor in
                guard let anchor else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(anchor, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                submissionButtons
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BrandChrome.cardBackground)
            }
        }
        .onAppear { validateForm() }
        .onChange(of: responses) { _, _ in validateForm() }
        .onChange(of: signatureImages) { _, _ in validateForm() }
        .onChange(of: photoPreviews) { _, _ in validateForm() }
        .onChange(of: capturedImages) { _, _ in validateForm() }
        .onChange(of: stagedCameraData) { _, _ in validateForm() }
        .onChange(of: fileURLs) { _, _ in validateForm() }
    }

    private var formDetailsSummary: String {
        var parts: [String] = []
        if let reference = responses["reference"], !reference.isEmpty { parts.append(reference) }
        if let name = selectedFolderName() { parts.append(name) }
        if let pin = drawingPin { parts.append(pin.label) }
        else if selectedLocationId != nil { parts.append("Location set") }
        return parts.isEmpty ? "Reference, folder and location" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var formDetailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isFormDetailsExpanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Form details")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(isFormDetailsExpanded ? "Reference, folder and location" : formDetailsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: isFormDetailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isFormDetailsExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Reference")
                                .font(.subheadline.weight(.semibold))
                            Text("*").foregroundStyle(BrandChrome.danger)
                        }
                        TextField("e.g. Plot 1, Manhole 29", text: Binding(
                            get: { responses["reference"] ?? "" },
                            set: { responses["reference"] = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .formInputBackground()
                    }

                    if !formsFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Folder")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                Text(selectedFolderName() ?? "No folder selected")
                                    .font(.subheadline)
                                    .foregroundStyle(selectedFolderName() == nil ? .secondary : .primary)
                                Spacer()
                                if selectedFolderId != nil {
                                    Button("Clear") { selectedFolderId = nil }
                                        .font(.caption.weight(.semibold))
                                }
                                Button(showFolderPicker ? "Hide" : "Choose") {
                                    showFolderPicker.toggle()
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            if showFolderPicker {
                                FolderPickerList(nodes: formsFolders, selectedFolderId: $selectedFolderId)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where is this?")
                            .font(.subheadline.weight(.semibold))
                        FormLocationPicker(
                            projectId: projectId,
                            token: token,
                            locationId: $selectedLocationId,
                            drawingPin: $drawingPin
                        )
                    }
                }
                .padding(14)
            }
        }
        .formCardChrome(
            needsAttention: showValidationErrors && (responses["reference"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
    
    @ViewBuilder
    private var submissionButtons: some View {
        VStack(spacing: 8) {
            if showValidationErrors && !isFormValid {
                let remaining = max(0, requiredCompletion(fields: form.currentRevision?.fields ?? []).total - requiredCompletion(fields: form.currentRevision?.fields ?? []).completed)
                Text(remaining == 1 ? "1 required field still needs a value." : "\(remaining) required fields still need a value.")
                    .font(.caption)
                    .foregroundStyle(BrandChrome.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button(action: {
                    processSubmission(status: "draft")
                }) {
                    Text("Save draft")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)

                Button(action: {
                    if isFormValid {
                        processSubmission(status: "submitted")
                    } else {
                        revealFirstIncompleteField()
                    }
                }) {
                    Text("Submit")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
    }
    
    @ViewBuilder
    private var noFieldsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Fields Found")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
            Text("This form template has a revision, but it doesn't contain any fields to display.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func startMonitoringNetwork() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOffline = path.status != .satisfied
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }

    private func processSubmission(status: String) {
        guard let revision = form.currentRevision else {
            showBanner(.error, "Form revision not available")
            return
        }

        // This is a safeguard. The button should be disabled if the form is invalid.
        if status == "submitted" && !isFormValid {
            revealFirstIncompleteField()
            isSubmitting = false
            return
        }

        isSubmitting = true
        submissionType = status
        bannerMessage = nil
        let uploadTotal = pendingUploadCount() + 1
        submitProgressTitle = status == "draft" ? "Saving draft" : "Submitting"
        submitProgressDetail = uploadTotal > 1 ? "Preparing files…" : "Saving form…"
        submitProgressCurrent = 0
        submitProgressTotal = uploadTotal
        
        Task {
            do {
                var updatedResponses = responses

                // Determine the actual submission status
                var actualSubmissionStatus = status
                if status == "submitted" && hasCloseoutFields() {
                    // If form has closeout fields and is being submitted (not draft),
                    // set status to "awaiting_closeout"
                    actualSubmissionStatus = "awaiting_closeout"
                }

                if isOffline {
                    // --- Offline Logic ---
                    if let offlineSubmission = await buildOfflineSubmission(revision: revision, actualSubmissionStatus: actualSubmissionStatus) {
                        OfflineSubmissionManager.shared.saveSubmission(offlineSubmission)
                        await MainActor.run {
                            isSubmitting = false
                            submissionType = nil
                            showBanner(.info, "You're offline. Saved as a draft and will send when you're back online.")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                onSave?()
                                dismiss()
                            }
                        }
                    } else {
                        await MainActor.run {
                            isSubmitting = false
                            submissionType = nil
                            showBanner(.error, "Could not save submission offline.")
                        }
                    }
                    return
                }

                // --- Online Logic ---
                var allUploadedFileKeys: [String: [String]] = [:]
                var finalCameraResponses: [String: [Any]] = [:]

                // 1. Collect all image data first
                var filesToUploadByField: [String: [(fileName: String, data: Data)]] = [:]

                for (fieldId, items) in photoPickerItems {
                    if RepeaterMediaSupport.isRepeaterMedia(fieldId) { continue }
                    // Skip camera fields - they should only be processed through stagedCameraData
                    if let field = revision.fields.first(where: { $0.id == fieldId }),
                       field.type == "camera" {
                        continue
                    }
                    
                    for (index, item) in items.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let fileName = "\(fieldId)-\(index).jpg"
                            filesToUploadByField[fieldId, default: []].append((fileName: fileName, data: data))
                        }
                    }
                }
                
                for (fieldId, images) in capturedImages {
                    if RepeaterMediaSupport.isRepeaterMedia(fieldId) { continue }
                    // Skip camera fields - they should only be processed through stagedCameraData
                    if let field = revision.fields.first(where: { $0.id == fieldId }),
                       field.type == "camera" {
                        continue
                    }
                    
                    for (index, image) in images.enumerated() {
                        if let data = image.jpegData(compressionQuality: 0.8) {
                            let fileName = "\(fieldId)-captured-\(index).jpg"
                            filesToUploadByField[fieldId, default: []].append((fileName: fileName, data: data))
                        }
                    }
                }

                // Handle Staged Camera Data separately to preserve metadata
                for (fieldId, photosWithLocation) in stagedCameraData {
                    if RepeaterMediaSupport.isRepeaterMedia(fieldId) { continue }
                    var cameraFieldResponses: [[String: Any]] = []
                    for photoData in photosWithLocation {
                        let fileName = "\(fieldId)-\(UUID().uuidString).jpg"
                        
                        // 1. Upload the image
                        let fileKey = try await uploadFileDataAsync(photoData.image, fileName: fileName, fieldId: fieldId, projectId: projectId, mimeType: "image/jpeg")
                        await tickSubmitProgress("Uploading photos…")
                        
                        // 2. Create the response object with file key and metadata
                        var responseDict: [String: Any] = [
                            "image": fileKey,
                            "capturedAt": ISO8601DateFormatter().string(from: photoData.capturedAt)
                        ]
                        
                        if let location = photoData.location {
                            responseDict["location"] = [
                                "latitude": location.coordinate.latitude,
                                "longitude": location.coordinate.longitude,
                                "accuracy": location.horizontalAccuracy,
                                "timestamp": location.timestamp.timeIntervalSince1970
                            ]
                        }
                        cameraFieldResponses.append(responseDict)
                    }
                    finalCameraResponses[fieldId] = cameraFieldResponses
                }


                // 2. Batch upload images from photo picker
                for (fieldId, files) in filesToUploadByField {
                    if !files.isEmpty {
                        let fileKeys = try await uploadBatchOfFilesAsync(files, fieldId: fieldId, projectId: projectId)
                        for _ in fileKeys {
                            await tickSubmitProgress("Uploading photos…")
                        }
                        allUploadedFileKeys[fieldId, default: []].append(contentsOf: fileKeys)
                    }
                }

                // 3. Handle single uploads for other types
                for (fieldId, signatureImage) in signatureImages {
                     let fileKey = try await uploadSignatureImageAsync(signatureImage, fieldId: fieldId, projectId: projectId)
                     allUploadedFileKeys[fieldId, default: []].append(fileKey)
                     await tickSubmitProgress("Uploading signatures…")
                }

                for (fieldId, fileURL) in fileURLs {
                    let fileKey = try await uploadFileAsync(fileURL, fieldId: fieldId, projectId: projectId)
                    allUploadedFileKeys[fieldId, default: []].append(fileKey)
                    await tickSubmitProgress("Uploading files…")
                }
                
                // 4. Combine file keys for each field
                for (fieldId, keys) in allUploadedFileKeys {
                    if !keys.isEmpty {
                        updatedResponses[fieldId] = keys.joined(separator: ",")
                    }
                }

                                 // Convert repeater and table field strings back to JSON arrays for submission
                 var processedFormData: [String: Any] = [:]
                 
                 for (key, value) in updatedResponses {
                     if RepeaterMediaSupport.isRepeaterMedia(key) { continue }
                     // Find the field to check if it's a repeater or table
                     if let field = revision.fields.first(where: { $0.id == key }) {
                        if field.type == "repeater" {
                            processedFormData[key] = RepeaterMediaSupport.parseRepeaterValue(value, subFields: field.subFields)
                        } else if field.type == "table" {
                            // Parse JSON string back to array for table fields
                            if let data = value.data(using: .utf8),
                               let jsonArray = try? JSONSerialization.jsonObject(with: data) {
                                processedFormData[key] = jsonArray
                            } else {
                                processedFormData[key] = []
                            }
                        } else if field.type == "links" {
                            processedFormData[key] = FormLinkItem.jsonObject(from: value)
                        } else {
                            processedFormData[key] = value
                        }
                     } else {
                         processedFormData[key] = value
                     }
                 }
                 
                 // Inject the fully-formed camera responses
                 for (fieldId, cameraData) in finalCameraResponses {
                     if RepeaterMediaSupport.isRepeaterMedia(fieldId) { continue }
                     processedFormData[fieldId] = cameraData
                 }

                try await RepeaterMediaSupport.injectPendingMedia(
                    into: &processedFormData,
                    fields: revision.fields,
                    stagedCameraData: stagedCameraData,
                    capturedImages: capturedImages
                ) { data, fileName, fieldId in
                    let key = try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId, projectId: projectId, mimeType: "image/jpeg")
                    await tickSubmitProgress("Uploading photos…")
                    return key
                }

                await MainActor.run {
                    submitProgressDetail = "Saving form…"
                    submitProgressCurrent = submitProgressTotal
                }

                if let closeoutId = permitCloseoutSubmitId {
                    if permitCloseoutIsDaily {
                        try await APIClient.submitPermitDailyHandback(id: closeoutId, token: token, formData: processedFormData)
                    } else {
                        try await APIClient.submitPermitCloseout(id: closeoutId, token: token, formData: processedFormData)
                    }
                    await MainActor.run {
                        isSubmitting = false
                        submissionType = nil
                        onSave?()
                        dismiss()
                    }
                    return
                }

                var submissionData: [String: Any] = [
                    "formTemplateId": form.id,
                    "revisionId": revision.id,
                    "projectId": projectId,
                    "formData": processedFormData,
                    "status": actualSubmissionStatus
                ]
                if let folderId = selectedFolderId { submissionData["folderId"] = folderId }
                applyFormLocationPayload(to: &submissionData, locationId: selectedLocationId, drawingPin: drawingPin)
                if let reference = responses["reference"], !reference.isEmpty { submissionData["reference"] = reference }
                if let permitId = permitId { submissionData["permitId"] = permitId }
                
                                 let jsonData = try JSONSerialization.data(withJSONObject: submissionData)
                 
                 // Debug logging
                 if let jsonString = String(data: jsonData, encoding: .utf8) {
                     print("📤 [FormSubmission] Sending data: \(jsonString)")
                 }
                let url = URL(string: "\(APIClient.baseURL)/forms/submit")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                
                let (responseData, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    let responseBody = String(data: responseData, encoding: .utf8) ?? "No response body"
                    throw NSError(domain: "FormSubmission", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to submit form. Server response: \(responseBody)"])
                }

                if let permitId, actualSubmissionStatus != "draft" {
                    try await APIClient.submitPermit(id: permitId, token: token)
                }
                
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    onSave?()
                    dismiss()
                }

            } catch {
                // If upload failed due to no signal or expired token, save offline so the submission isn't lost
                if isOfflineSaveableError(error), let revision = form.currentRevision {
                    var actualSubmissionStatus = submissionType ?? status
                    if actualSubmissionStatus == "submitted" && hasCloseoutFields() {
                        actualSubmissionStatus = "awaiting_closeout"
                    }
                    if let offlineSubmission = await buildOfflineSubmission(revision: revision, actualSubmissionStatus: actualSubmissionStatus) {
                        OfflineSubmissionManager.shared.saveSubmission(offlineSubmission)
                        await MainActor.run {
                            isSubmitting = false
                            submissionType = nil
                            showBanner(.info, "Couldn't send right now. Saved and will sync when you're back online.")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                onSave?()
                                dismiss()
                            }
                        }
                        return
                    }
                }
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    showBanner(.error, error.localizedDescription)
                }
            }
        }
    }

    /// Returns true if the error indicates we should save the submission offline (network or auth) instead of showing a failure.
    private func isOfflineSaveableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .dataNotAllowed:
                return true
            default:
                break
            }
        }
        let message = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        if message.contains("Token expired") || message.contains("AUTHENTICATION_REQUIRED") { return true }
        if (error as NSError).code == 401 { return true }
        return false
    }

    /// Builds an OfflineSubmission from current form state (used when offline or when upload fails).
    private func buildOfflineSubmission(revision: FormRevision, actualSubmissionStatus: String) async -> OfflineSubmission? {
        var fileDataAttachments: [String: Data] = [:]
        for (fieldId, images) in capturedImages {
            for (index, image) in images.enumerated() {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    fileDataAttachments["\(fieldId)-captured-\(index).jpg"] = data
                }
            }
        }
        for (fieldId, photosWithLocation) in stagedCameraData {
            for (index, photoData) in photosWithLocation.enumerated() {
                if !photoData.image.isEmpty {
                    fileDataAttachments["\(fieldId)-staged-\(index).jpg"] = photoData.image
                }
            }
        }
        for (fieldId, items) in photoPickerItems {
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    fileDataAttachments["\(fieldId)-\(index).jpg"] = data
                }
            }
        }
        for (fieldId, signatureImage) in signatureImages {
            if let data = signatureImage.jpegData(compressionQuality: 0.8) {
                fileDataAttachments["\(fieldId)-signature.jpg"] = data
            }
        }
        for (fieldId, fileURL) in fileURLs {
            if let data = try? Data(contentsOf: fileURL) {
                fileDataAttachments["\(fieldId)-\(fileURL.lastPathComponent)"] = data
            }
        }
        return OfflineSubmission(
            id: UUID(),
            formTemplateId: form.id,
            revisionId: revision.id,
            projectId: projectId,
            formData: responses,
            fileAttachments: fileDataAttachments.isEmpty ? nil : fileDataAttachments,
            status: actualSubmissionStatus,
            reference: responses["reference"],
            folderId: selectedFolderId,
            locationId: selectedLocationId,
            drawingPin: drawingPin
        )
    }

    // MARK: - Folders helpers
    private func loadFoldersAndDefaults() async {
        do {
            let (rootId, folders) = try await APIClient.fetchFormFolders(projectId: projectId, token: token)
            await MainActor.run {
                self.formsRootFolderId = rootId
                self.formsFolders = folders
            }
            // Default folder per template
            let settings = try await APIClient.fetchFormTemplateSettings(formId: form.id, projectId: projectId, token: token)
            await MainActor.run {
                if let def = settings.defaultFolderId { self.selectedFolderId = def }
            }
        } catch {
            print("[Folders] Failed to load folders/settings: \(error)")
        }
    }
    

    private struct FolderPickerList: View {
        let nodes: [APIClient.FormFolder]
        @Binding var selectedFolderId: Int?
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(nodes, id: \.id) { node in
                    FolderRow(node: node, level: 0, selectedFolderId: $selectedFolderId)
                }
            }
            .padding(8)
            .background(BrandChrome.secondaryCardBackground)
            .cornerRadius(8)
        }
    }

    private struct FolderRow: View {
        let node: APIClient.FormFolder
        let level: Int
        @Binding var selectedFolderId: Int?
        @State private var isExpanded: Bool = true
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let children = node.subfolders, !children.isEmpty {
                        Button(action: { isExpanded.toggle() }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // spacer to align with disclosure icon
                        Image(systemName: "chevron.right").opacity(0)
                            .font(.caption)
                    }
                    Button(action: { selectedFolderId = node.id }) {
                        HStack {
                            Image(systemName: selectedFolderId == node.id ? "checkmark.circle.fill" : "folder")
                                .foregroundColor(selectedFolderId == node.id ? BrandChrome.accent : BrandChrome.mutedLabel)
                            Text(node.name)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.leading, CGFloat(level) * 14)
                if isExpanded, let children = node.subfolders, !children.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(children, id: \.id) { child in
                            FolderRow(node: child, level: level + 1, selectedFolderId: $selectedFolderId)
                        }
                    }
                }
            }
        }
    }

    private func selectedFolderName() -> String? {
        func findName(in list: [APIClient.FormFolder]) -> String? {
            for f in list {
                if f.id == selectedFolderId { return f.name }
                if let c = f.subfolders, let n = findName(in: c) { return n }
            }
            return nil
        }
        return findName(in: formsFolders)
    }

    private func requestCameraPermissionAndShowPicker() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("Camera permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            // Permission already granted.
            print("Camera permission already granted, showing image picker")
            showingImagePicker = true
        case .notDetermined:
            // Request permission.
            print("Requesting camera permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    print("Camera permission result: \(granted)")
                    if granted {
                        print("Camera permission granted, showing image picker")
                        self.showingImagePicker = true
                    } else {
                        // User denied permission.
                        print("Camera permission denied by user")
                        self.permissionAlertMessage = "Camera access is required to take photos. Please enable it in Settings."
                        self.showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // Permission was denied or restricted.
            print("Camera permission denied or restricted")
            self.permissionAlertMessage = "Camera access has been denied. Please go to Settings to enable it for this app."
            self.showingPermissionAlert = true
        @unknown default:
            print("Unknown camera permission status")
            fatalError("Unhandled authorization status")
        }
    }

    @ViewBuilder
    private func renderFormField(field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !field.isDisplayOnly {
                HStack(spacing: 4) {
                    Text(field.label)
                        .font(.body.weight(.semibold))
                        .foregroundColor(showValidationErrors && fieldNeedsAttention(field) ? BrandChrome.danger : BrandChrome.titleColor)
                    if field.required {
                        Text("*")
                            .foregroundColor(BrandChrome.danger)
                            .font(.subheadline.weight(.medium))
                    }
                    if showValidationErrors && fieldNeedsAttention(field) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(BrandChrome.danger)
                            .font(.caption2)
                    }
                    Spacer(minLength: 0)
                }

                if let description = field.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showValidationErrors, let fieldError = getFieldError(field) {
                    Text(fieldError)
                        .font(.caption)
                        .foregroundColor(BrandChrome.danger)
                }

                if let submissionReq = field.submissionRequirement,
                   submissionReq.requiredForSubmission {
                    Text("Required: \(submissionReq.requiredValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            switch field.type {
            case "text":
                TextField(field.placeholder ?? "Enter text", text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .formInputBackground()
                
            case "textarea":
                TextEditor(text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .frame(minHeight: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .formInputBackground()
                
            case "yesNoNA":
                FormYesNoNAControl(value: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                
            case "image", "camera":
                FormPhotoFieldControl(
                    previews: photoPreviews[field.id] ?? [],
                    showMarkup: field.type == "camera",
                    onMarkup: field.type == "camera" ? { index in
                        openCameraFieldMarkupEditor(fieldId: field.id, index: index)
                    } : nil,
                    onRemove: { index in
                        removePhoto(fieldId: field.id, index: index)
                    },
                    addLabel: field.type == "camera" ? "Add photo(s)" : "Add image(s)",
                    onAdd: {
                        activeFieldId = field.id
                        showingCameraActionSheetForField = field.id
                    }
                )
                .confirmationDialog(
                    "Add photo",
                    isPresented: Binding(
                        get: { showingCameraActionSheetForField == field.id },
                        set: { if !$0 { showingCameraActionSheetForField = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Take photo") {
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        if status == .authorized {
                            customCameraTargetFieldId = activeFieldId ?? field.id
                            isCustomCameraPresented = true
                        } else if status == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .video) { granted in
                                DispatchQueue.main.async {
                                    if granted {
                                        self.customCameraTargetFieldId = self.activeFieldId ?? field.id
                                        self.isCustomCameraPresented = true
                                    }
                                }
                            }
                        } else {
                            permissionAlertMessage = "Camera access is required. Enable it in Settings."
                            showingPermissionAlert = true
                        }
                    }
                    Button("Choose from library") {
                        activeFieldId = field.id
                        showingPhotosPicker = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Take a new photo or pick from your library.")
                }

            case "signature":
                VStack(alignment: .leading, spacing: 6) {
                    if let image = signatureImages[field.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                            .border(Color.gray.opacity(0.4))
                    }
                    Button("Sign") {
                        showingSignaturePad = field.id
                    }
                    .buttonStyle(.bordered)
                }
                
            case "attachment":
                VStack(alignment: .leading) {
                    if let url = fileURLs[field.id] {
                        Text("Selected file: \(url.lastPathComponent)")
                    }
                    Button("Select File") {
                        activeFieldId = field.id
                        isPickerPresented = true
                    }
                    .buttonStyle(.bordered)
                }

            case "dropdown":
                Picker(field.label, selection: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                )) {
                    ForEach(field.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())

            case "checkbox":
                if let options = field.options, !options.isEmpty {
                    VStack(alignment: .leading) {
                        ForEach(options, id: \.self) { option in
                            Toggle(isOn: Binding(
                                get: { (responses[field.id + "_" + option] ?? "false") == "true" },
                                set: { responses[field.id + "_" + option] = $0 ? "true" : "false" }
                            )) {
                                Text(option)
                            }
                        }
                    }
                } else {
                    Toggle(isOn: Binding(
                        get: { (responses[field.id] ?? "false") == "true" },
                        set: { responses[field.id] = $0 ? "true" : "false" }
                    )) {
                        Text(field.label)
                    }
                }

            case "radio":
                if let options = field.options, !options.isEmpty {
                    Picker(field.label, selection: Binding(
                        get: { responses[field.id] ?? "" },
                        set: { responses[field.id] = $0 }
                    )) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Text("No options provided for radio field")
                        .foregroundColor(BrandChrome.danger)
                }

            case "heading":
                FormHeadingView(field: field)

            case "subheading":
                Text(field.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

            case "links":
                LinksFieldView(
                    field: field,
                    projectId: projectId,
                    token: token,
                    jsonValue: Binding(
                        get: { responses[field.id] ?? "[]" },
                        set: { responses[field.id] = $0 }
                    )
                )

            case "input":
                TextField(field.placeholder ?? "Enter value", text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .formInputBackground()

            case "repeater":
                RepeaterFieldView(
                    field: field,
                    responses: $responses,
                    stagedCameraData: $stagedCameraData,
                    capturedImages: $capturedImages,
                    photoPreviews: $photoPreviews
                )

            case "closeout":
                CloseoutFieldView(
                    field: field,
                    response: Binding(
                        get: { self.responses[field.id] },
                        set: { self.responses[field.id] = $0 }
                    ),
                    formStatus: "draft", // Since this is create view, status is always draft initially
                    canApprove: false,   // No approval in create view
                    submitAction: {
                        // Closeout submit action - not applicable in create view
                    },
                    approveAction: {
                        // Closeout approve action - not applicable in create view  
                    }
                )

            case "table":
                TableFieldView(
                    field: field,
                    responses: $responses
                )

            default:
                Text("Unsupported field type: \(field.type)")
                    .foregroundColor(BrandChrome.danger)
            }
        }
    }

    private func uploadBatchOfFilesAsync(_ files: [(fileName: String, data: Data)], fieldId: String, projectId: Int) async throws -> [String] {
        struct UploadResponse: Decodable {
            struct FileUploadResult: Decodable {
                let fileKey: String
            }
            let files: [FileUploadResult]
        }
        
        let url = URL(string: "\(APIClient.baseURL)/forms/upload-files")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "No error body"
            throw NSError(domain: "FileUpload", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Batch upload failed: \(errorBody)"])
        }

        let decodedResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return decodedResponse.files.map { $0.fileKey }
    }

    private func uploadSignatureImageAsync(_ image: UIImage, fieldId: String, projectId: Int) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ImageConversion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert signature to JPEG"])
        }
        let fileName = "\(fieldId)-signature.jpg"
        return try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId, projectId: projectId, mimeType: "image/jpeg")
    }

    private func uploadFileAsync(_ url: URL, fieldId: String, projectId: Int) async throws -> String {
        let data = try Data(contentsOf: url)
        return try await uploadFileDataAsync(data, fileName: url.lastPathComponent, fieldId: fieldId, projectId: projectId, mimeType: getMimeType(for: url))
    }

    private func uploadFileDataAsync(_ data: Data, fileName: String, fieldId: String, projectId: Int, mimeType: String) async throws -> String {
        let url = URL(string: "\(APIClient.baseURL)/forms/upload-file")!
        let boundary = "Boundary-\(UUID().uuidString)"
        let request = try createUploadRequest(url: url, boundary: boundary, data: data, fileName: fileName, mimeType: mimeType, projectId: projectId, fieldId: fieldId)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "No error body"
            print("Upload failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1). Body: \(errorBody)")
            throw NSError(domain: "FileUpload", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(errorBody)"])
        }

        let json = try JSONDecoder().decode([String: String].self, from: responseData)
        guard let fileKey = json["fileUrl"] else {
            throw NSError(domain: "FileUpload", code: -2, userInfo: [NSLocalizedDescriptionKey: "File key not found in response"])
        }
        
        return extractFileKey(from: fileKey) ?? fileKey
    }

    private func createUploadRequest(url: URL, boundary: String, data: Data, fileName: String, mimeType: String, projectId: Int, fieldId: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"projectId\"\r\n\r\n")
        body.append("\(projectId)\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body
        return request
    }

    private func extractFileKey(from urlString: String) -> String? {
        if let url = URL(string: urlString) {
            if url.query?.contains("AWSAccessKeyId") == true || url.query?.contains("X-Amz-Algorithm") == true {
                return String(url.path.dropFirst())
            }
        }
        let regex = try? NSRegularExpression(pattern: #"^tenants/.*/forms/.*$"#)
        let range = NSRange(location: 0, length: urlString.utf16.count)
        if regex?.firstMatch(in: urlString, options: [], range: range) != nil {
            return urlString
        }

        return urlString
    }

    private func fieldHasMedia(_ fieldId: String) -> Bool {
        signatureImages[fieldId] != nil
            || photoPreviews[fieldId]?.isEmpty == false
            || capturedImages[fieldId]?.isEmpty == false
            || stagedCameraData[fieldId]?.isEmpty == false
            || fileURLs[fieldId] != nil
    }

    private func fieldNeedsAttention(_ field: FormField) -> Bool {
        if field.isDisplayOnly || field.type == "closeout" { return false }

        if field.required {
            let value = responses[field.id] ?? ""
            if field.isEmptyAnswer(value) && !fieldHasMedia(field.id) {
                return true
            }
        }

        if let submissionReq = field.submissionRequirement, submissionReq.requiredForSubmission {
            let value = responses[field.id] ?? ""
            if value.lowercased() != submissionReq.requiredValue.lowercased() {
                return true
            }
        }

        if field.type == "repeater", let subFields = field.subFields {
            if let repeaterDataString = responses[field.id],
               let jsonData = repeaterDataString.data(using: .utf8),
               let repeaterRows = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                for (rowIndex, rowAny) in repeaterRows.enumerated() {
                    let rowData = rowAny.mapValues { RepeaterMediaSupport.jsonString(from: $0) }
                    for subField in subFields where subField.required {
                        if !RepeaterMediaSupport.subFieldHasValue(
                            repeaterId: field.id,
                            rowIndex: rowIndex,
                            rowData: rowData,
                            subField: subField,
                            stagedCameraData: stagedCameraData,
                            capturedImages: capturedImages
                        ) {
                            return true
                        }
                    }
                }
                if field.required && repeaterRows.isEmpty {
                    return true
                }
            } else if field.required {
                return true
            }
        }

        return false
    }

    private func requiredCompletion(fields: [FormField]) -> (completed: Int, total: Int) {
        var total = 1
        var completed = (responses["reference"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        for field in fields {
            if field.isDisplayOnly || field.type == "closeout" { continue }
            let required = field.required || (field.submissionRequirement?.requiredForSubmission == true)
            if !required { continue }
            total += 1
            if !fieldNeedsAttention(field) { completed += 1 }
        }
        return (completed, total)
    }

    private func revealFirstIncompleteField() {
        showValidationErrors = true
        bannerKind = .error
        let completion = requiredCompletion(fields: form.currentRevision?.fields ?? [])
        let remaining = max(0, completion.total - completion.completed)
        bannerMessage = remaining == 1
            ? "1 required field still needs a value."
            : "\(remaining) required fields still need a value."

        if (responses["reference"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isFormDetailsExpanded = true
            scrollToAnchor = nil
            DispatchQueue.main.async { scrollToAnchor = "formDetails" }
            return
        }
        if let field = form.currentRevision?.fields.first(where: { fieldNeedsAttention($0) }) {
            scrollToAnchor = nil
            DispatchQueue.main.async { scrollToAnchor = field.id }
        }
    }

    private func showBanner(_ kind: FormBannerKind, _ message: String) {
        bannerKind = kind
        bannerMessage = message
        if kind != .error {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if bannerMessage == message {
                    bannerMessage = nil
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func pendingUploadCount() -> Int {
        var count = 0
        for photos in stagedCameraData.values { count += photos.count }
        for images in capturedImages.values { count += images.count }
        for items in photoPickerItems.values { count += items.count }
        count += signatureImages.count
        count += fileURLs.count
        return count
    }

    private func tickSubmitProgress(_ detail: String) async {
        await MainActor.run {
            submitProgressCurrent = min(submitProgressCurrent + 1, submitProgressTotal)
            submitProgressDetail = detail
        }
    }

    private func getFieldError(_ field: FormField) -> String? {
        if !showValidationErrors { return nil }
        
        if field.isDisplayOnly { return nil }
        
        // Skip closeout fields in create view
        if field.type == "closeout" { return nil }
        
        // Check basic required field
        if field.required {
            let value = responses[field.id] ?? ""
            let hasImage = (signatureImages[field.id] != nil ||
                           photoPreviews[field.id]?.isEmpty == false ||
                           capturedImages[field.id]?.isEmpty == false ||
                           stagedCameraData[field.id]?.isEmpty == false ||
                           fileURLs[field.id] != nil)
            
            if field.isEmptyAnswer(value) && !hasImage {
                return "\(field.label) is required"
            }
        }
        
        // Check submission requirements
        if let submissionReq = field.submissionRequirement,
           submissionReq.requiredForSubmission {
            let value = responses[field.id] ?? ""
            if value != submissionReq.requiredValue {
                return submissionReq.validationMessage
            }
        }
        
        return nil
    }

    private func validateForm() {
        guard let fields = form.currentRevision?.fields else {
            isFormValid = true
            return
        }
        
        print("🔍 [Validation] Starting validation...")

        if (responses["reference"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isFormValid = false
            return
        }

        for field in fields {
            if field.isDisplayOnly { continue }
            
            // Skip closeout fields in create view - they're not applicable until after submission
            if field.type == "closeout" { continue }
            
            // Check basic required field
            if field.required {
                let value = responses[field.id] ?? ""
                let hasImage = (signatureImages[field.id] != nil ||
                               photoPreviews[field.id]?.isEmpty == false ||
                               capturedImages[field.id]?.isEmpty == false ||
                               stagedCameraData[field.id]?.isEmpty == false ||
                               fileURLs[field.id] != nil)
                
                print("🔍 [Validation] Field \(field.id) required: value='\(value)', hasImage=\(hasImage)")
                
                if field.isEmptyAnswer(value) && !hasImage {
                    print("❌ [Validation] Failed: Field \(field.id) is required but empty")
                    isFormValid = false
                    return
                }
            }
            
            // Check submission requirements
            if let submissionReq = field.submissionRequirement,
               submissionReq.requiredForSubmission {
                let value = responses[field.id] ?? ""
                print("🔍 [Validation] Field \(field.id) submission requirement: value='\(value)', required='\(submissionReq.requiredValue)'")
                
                // Use case-insensitive comparison
                if value.lowercased() != submissionReq.requiredValue.lowercased() {
                    print("❌ [Validation] Failed: Field \(field.id) submission requirement not met")
                    isFormValid = false
                    return
                }
            }
            
            // Check repeater field requirements
            if field.type == "repeater", let subFields = field.subFields {
                if let repeaterDataString = responses[field.id],
                   let jsonData = repeaterDataString.data(using: .utf8),
                   let repeaterRows = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    
                    for (rowIndex, rowAny) in repeaterRows.enumerated() {
                        let rowData = rowAny.mapValues { RepeaterMediaSupport.jsonString(from: $0) }
                        for subField in subFields {
                            if subField.required {
                                let hasValue = RepeaterMediaSupport.subFieldHasValue(
                                    repeaterId: field.id,
                                    rowIndex: rowIndex,
                                    rowData: rowData,
                                    subField: subField,
                                    stagedCameraData: stagedCameraData,
                                    capturedImages: capturedImages
                                )
                                if !hasValue {
                                    isFormValid = false
                                    return
                                }
                            }
                            
                            if let submissionReq = subField.submissionRequirement,
                               submissionReq.requiredForSubmission {
                                let subFieldValue = rowData[subField.id] ?? ""
                                if subFieldValue.lowercased() != submissionReq.requiredValue.lowercased() {
                                    isFormValid = false
                                    return
                                }
                            }
                        }
                    }
                }
            }
            
            // Check table field requirements
            if field.type == "table", let columns = field.tableColumns {
                if let tableDataString = responses[field.id],
                   let jsonData = tableDataString.data(using: .utf8),
                   let tableRows = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    
                    // Check minimum rows
                    if let minRows = field.minRows, tableRows.count < minRows {
                        isFormValid = false
                        return
                    }
                    
                    // Check required columns in each row
                    for rowData in tableRows {
                        for column in columns {
                            if column.required ?? false {
                                let cellValue = rowData[column.id]
                                let isEmpty: Bool
                                
                                if let stringValue = cellValue as? String {
                                    isEmpty = stringValue.isEmpty
                                } else if let numValue = cellValue as? NSNumber {
                                    isEmpty = numValue.doubleValue == 0 && column.type != "number"
                                } else if cellValue is Bool {
                                    isEmpty = false // Checkboxes are never "empty" (they're true/false)
                                } else {
                                    isEmpty = true
                                }
                                
                                if isEmpty {
                                    isFormValid = false
                                    return
                                }
                            }
                        }
                        
                        // Check row name if enabled
                        if field.enableRowNames ?? false {
                            let rowName = rowData["_rowName"] as? String ?? ""
                            if rowName.isEmpty {
                                isFormValid = false
                                return
                            }
                        }
                    }
                } else if field.required {
                    // Table is required but has no data
                    isFormValid = false
                    return
                }
            }
        }
        
        print("✅ [Validation] All fields valid!")
        isFormValid = true
    }
    
    // MARK: - Camera Image Management
    private func removePhoto(fieldId: String, index: Int) {
        if var previews = photoPreviews[fieldId], index < previews.count {
            previews.remove(at: index)
            photoPreviews[fieldId] = previews.isEmpty ? nil : previews
        }
        if var stagedData = stagedCameraData[fieldId], index < stagedData.count {
            stagedData.remove(at: index)
            stagedCameraData[fieldId] = stagedData.isEmpty ? nil : stagedData
        }
        if var captured = capturedImages[fieldId], index < captured.count {
            captured.remove(at: index)
            capturedImages[fieldId] = captured.isEmpty ? nil : captured
        }
        if var items = photoPickerItems[fieldId], index < items.count {
            items.remove(at: index)
            photoPickerItems[fieldId] = items.isEmpty ? nil : items
        }
        validateForm()
    }

    private func removeCameraImage(fieldId: String, index: Int) {
        removePhoto(fieldId: fieldId, index: index)
    }

    /// Applies photos captured via the multi CustomCameraView to the target field (used on dismiss and in onChange).
    private func applyCapturedPhotos(_ photos: [PhotoWithLocation], toField fieldId: String) {
        guard !photos.isEmpty else { return }
        let fieldType = form.currentRevision?.fields.first(where: { $0.id == fieldId })?.type
        var previews: [UIImage] = photoPreviews[fieldId] ?? []
        if fieldType == "camera" {
            var staged: [PhotoWithLocation] = stagedCameraData[fieldId] ?? []
            for p in photos {
                staged.append(p)
                if let full = UIImage(data: p.image) {
                    previews.append(full.thumbnail(maxPixelSize: 400))
                }
            }
            stagedCameraData[fieldId] = staged
        } else {
            var images: [UIImage] = capturedImages[fieldId] ?? []
            for p in photos {
                if let full = UIImage(data: p.image) {
                    images.append(full) // full res for upload
                    previews.append(full.thumbnail(maxPixelSize: 400))
                }
            }
            capturedImages[fieldId] = images
        }
        photoPreviews[fieldId] = previews
        validateForm()
    }

    // MARK: - Helper Functions
    
    private func hasCloseoutFields() -> Bool {
        guard let fields = form.currentRevision?.fields else { return false }
        return fields.contains { $0.type == "closeout" }
    }
    
    private func submitForm(status: String) {
        // This function is deprecated - use processSubmission instead
        processSubmission(status: status)
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    var delegate: DocumentPickerDelegateWrapper

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.delegate = delegate
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

class DocumentPickerDelegateWrapper: NSObject, UIDocumentPickerDelegate, ObservableObject {
    @Published var selectedURL: URL?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        selectedURL = urls.first
    }
}

private func getMimeType(for url: URL) -> String {
    let pathExtension = url.pathExtension
    if let uti = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
        return uti
    }
    return "application/octet-stream"
}

struct IdentifiablePath: Identifiable {
    let id = UUID()
    let path: Path
}

struct SignaturePadView: View {
    @Binding var signatureImage: UIImage?
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var paths: [IdentifiablePath] = []
    @State private var currentPath = Path()
    @State private var isDrawing = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray, lineWidth: 1)
                            .background(Color.white)
                            .frame(height: 200)
                        ForEach(paths) { identifiablePath in
                            identifiablePath.path.stroke(Color.black, lineWidth: 2)
                        }
                        currentPath.stroke(Color.black, lineWidth: 2)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .clipped()
                    .padding(8)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                print("📝 [SignaturePadView] Drawing stroke at: \(value.location)")
                                if !isDrawing {
                                    currentPath = Path()
                                    currentPath.move(to: value.location)
                                    isDrawing = true
                                    print("📝 [SignaturePadView] Started new stroke")
                                }
                                currentPath.addLine(to: value.location)
                            }
                            .onEnded { _ in
                                print("📝 [SignaturePadView] Stroke ended, paths count: \(paths.count)")
                                paths.append(IdentifiablePath(path: currentPath))
                                currentPath = Path()
                                isDrawing = false
                                
                                // Generate and set the signature image immediately
                                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
                                let image = renderer.image { ctx in
                                    UIColor.white.setFill()
                                    ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
                                    UIColor.black.setStroke()
                                    for identifiablePath in paths {
                                        ctx.cgContext.addPath(identifiablePath.path.cgPath)
                                        ctx.cgContext.setLineCap(.round)
                                        ctx.cgContext.setLineWidth(2)
                                        ctx.cgContext.strokePath()
                                    }
                                }
                                print("📝 [SignaturePadView] Generated signature image, setting to binding")
                                signatureImage = image
                                print("📝 [SignaturePadView] Signature binding set complete")
                            }
                    )

                    HStack {
                        Button("Clear") {
                            paths.removeAll()
                            currentPath = Path()
                            isDrawing = false
                            signatureImage = nil
                            print("📝 [SignaturePadView] Signature cleared, triggering binding with nil")
                        }
                        .padding()
                        Spacer()
                        Button("Done") {
                            // Ensure signature is rendered and saved before dismissing
                            if !paths.isEmpty && signatureImage == nil {
                                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
                                let image = renderer.image { ctx in
                                    UIColor.white.setFill()
                                    ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
                                    UIColor.black.setStroke()
                                    for identifiablePath in paths {
                                        ctx.cgContext.addPath(identifiablePath.path.cgPath)
                                        ctx.cgContext.setLineCap(.round)
                                        ctx.cgContext.setLineWidth(2)
                                        ctx.cgContext.strokePath()
                                    }
                                }
                                signatureImage = image
                                print("📝 [SignaturePadView] Final signature render on Done button")
                            }
                            print("📝 [SignaturePadView] Done button tapped, current signature: \(signatureImage != nil)")
                            onDismiss?()
                            dismiss()
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Signature")
        }
    }

    private func renderSignature() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.black.setStroke()
            for identifiablePath in paths {
                ctx.cgContext.addPath(identifiablePath.path.cgPath)
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineWidth(2)
                ctx.cgContext.strokePath()
            }
            ctx.cgContext.addPath(currentPath.cgPath)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokePath()
        }
        
        // Explicitly trigger the binding
        signatureImage = image
        print("📝 [SignaturePadView] Signature rendered and assigned to binding")
    }
}


