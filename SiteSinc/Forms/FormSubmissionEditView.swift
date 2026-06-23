import SwiftUI
import PhotosUI
import Network

struct FormSubmissionEditView: View {
    let submission: FormSubmission
    @State var form: FormModel
    let projectId: Int
    let token: String
    let onSave: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var photoPickerItems: [String: [PhotosPickerItem]] = [:]
    @State private var photoPreviews: [String: [UIImage]] = [:]
    @State private var signatureImages: [String: UIImage] = [:]
    @State private var activeFieldId: String?
    @State private var showingPhotosPicker = false
    @State private var showingImagePicker = false // Add this
    @State private var showingCameraActionSheet = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var stagedCameraData: [String: [PhotoWithLocation]] = [:] // Add this
    @State private var showingSignaturePad: String?
    @Environment(\.dismiss) private var dismiss

    @State private var isOffline = false
    private let monitor = NWPathMonitor()
    @State private var submissionType: String?
    
    // Validation state - added to match create view
    @State private var isFormValid = false
    @State private var showValidationErrors = false
    
    // Unsaved changes detection
    @State private var showCloseConfirmation = false

    // Optional photo markup (camera field)
    @State private var photoMarkupGateImage: UIImage?
    @State private var showPhotoMarkupGate = false
    @State private var photoMarkupGateApplyJPEG: ((Data) -> Void)?
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?
    
    // Location selection state
    @State private var selectedLocationId: Int? = nil
    
    private var canApprove: Bool {
        sessionManager.user?.permissions?.contains { $0.name == "close_any_form" } ?? false
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
            contentWithModifiers
                .navigationTitle("Edit Form")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                }
                .alert("Unsaved Changes", isPresented: $showCloseConfirmation) {
                    Button("Discard Changes", role: .destructive) {
                        dismiss()
                    }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
        }
    }
    
    @ViewBuilder
    private var contentWithModifiers: some View {
        contentWithPickerModifiers
            .onAppear {
                loadExistingData()
                startMonitoringNetwork()
                validateForm()
            }
            .onChange(of: responses) { _, _ in validateForm() }
            .onChange(of: photoPreviews) { _, _ in validateForm() }
            .onChange(of: stagedCameraData) { _, _ in validateForm() }
            .onChange(of: signatureImages) { _, _ in validateForm() }
    }
    
    @ViewBuilder
    private var contentWithPickerModifiers: some View {
        contentWithSheetModifiers
            .photosPicker(isPresented: $showingPhotosPicker, selection: $pickerSelection, maxSelectionCount: 5, matching: .images)
            .onChange(of: pickerSelection) { _, newItems in
                handlePickerSelection(newItems)
            }
    }
    
    @ViewBuilder
    private var contentWithSheetModifiers: some View {
        mainContent
            .sheet(isPresented: $showingImagePicker) {
                CameraPickerWithLocation(
                    onImageCaptured: { photoWithLocation in
                        handleCameraCapture(photoWithLocation)
                    },
                    onDismiss: {
                        activeFieldId = nil
                        showingImagePicker = false
                    }
                )
            }
            .sheet(isPresented: Binding(
                get: { showingSignaturePad != nil },
                set: { if !$0 { showingSignaturePad = nil } }
            )) {
                if let fieldId = showingSignaturePad {
                    SignaturePadView(signatureImage: $signatureImages[fieldId])
                }
            }
            .confirmationDialog("Add Image", isPresented: $showingCameraActionSheet, titleVisibility: .visible) {
                Button("Take Photo") {
                    showingImagePicker = true
                }
                Button("Choose From Library") {
                    showingPhotosPicker = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("How would you like to add a photo?")
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
              UIImage(data: staged[index].image) != nil else { return }
        let loc = staged[index].location
        let cap = staged[index].capturedAt
        guard let ui = UIImage(data: staged[index].image) else { return }
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
    
    private func handlePickerSelection(_ newItems: [PhotosPickerItem]) {
        guard let fieldId = activeFieldId, !newItems.isEmpty else {
            if newItems.isEmpty {
                activeFieldId = nil
            }
            return
        }

        let isCameraField = form.currentRevision?.fields.first(where: { $0.id == fieldId })?.type == "camera"

        if isCameraField {
            Task {
                var newPhotosWithLocation: [PhotoWithLocation] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        newPhotosWithLocation.append(PhotoWithLocation(image: data, location: nil, capturedAt: Date()))
                    }
                }
                await MainActor.run {
                    let existingCamera = stagedCameraData[fieldId] ?? []
                    stagedCameraData[fieldId] = existingCamera + newPhotosWithLocation
                    var newImages: [UIImage] = []
                    for p in newPhotosWithLocation {
                        if let full = UIImage(data: p.image) { newImages.append(full.thumbnail(maxPixelSize: 400)) }
                    }
                    let existingPreviews = photoPreviews[fieldId] ?? []
                    photoPreviews[fieldId] = existingPreviews + newImages
                    validateForm()
                }
            }
        } else {
            let existingItems = photoPickerItems[fieldId] ?? []
            photoPickerItems[fieldId] = existingItems + newItems

            Task {
                var newImages: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        newImages.append(image)
                    }
                }
                await MainActor.run {
                    let existingPreviews = photoPreviews[fieldId] ?? []
                    let thumbs = newImages.map { $0.thumbnail(maxPixelSize: 400) }
                    photoPreviews[fieldId] = existingPreviews + thumbs
                }
            }
        }

        pickerSelection = []
        activeFieldId = nil
    }
    
    private func handleCameraCapture(_ photoWithLocation: PhotoWithLocation) {
        guard let fieldId = activeFieldId, let uiImage = UIImage(data: photoWithLocation.image) else { return }
        let loc = photoWithLocation.location
        let cap = photoWithLocation.capturedAt
        photoMarkupGateImage = uiImage
        photoMarkupGateApplyJPEG = { data in
            let p = PhotoWithLocation(image: data, location: loc, capturedAt: cap)
            stagedCameraData[fieldId, default: []].append(p)
            let thumb = (UIImage(data: data) ?? uiImage).thumbnail(maxPixelSize: 400)
            photoPreviews[fieldId, default: []].append(thumb)
            validateForm()
        }
        showPhotoMarkupGate = true
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if isLoading {
                ProgressView().padding()
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
            } else if let fields = form.currentRevision?.fields, !fields.isEmpty {
                formScrollView(fields: fields)
            } else {
                noFieldsView
            }
        }
    }
    
    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Error")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                loadExistingData()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    @ViewBuilder
    private func formScrollView(fields: [FormField]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(form.title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let reference = form.reference {
                    Text("Ref: \(reference)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Reference field input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reference (optional)")
                        .font(.subheadline).fontWeight(.semibold)
                    TextField("Enter reference number or identifier", text: Binding(
                        get: { responses["reference"] ?? "" },
                        set: { responses["reference"] = $0 }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Project location selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Location (optional)")
                        .font(.subheadline).fontWeight(.semibold)
                    
                    LocationSelector(
                        projectId: projectId,
                        token: token,
                        selectedLocationId: $selectedLocationId
                    )
                }

                ForEach(fields, id: \.id) { field in
                    renderFormField(field: field)
                }

                if !isCloseoutWorkflow() {
                    submissionButtons
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var submissionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                submitForm(status: "draft")
            }) {
                Text(isSubmitting && submissionType == "draft" ? "Saving..." : "Save as Draft")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSubmitting ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isSubmitting)

            Button(action: {
                submitForm(status: "submitted")
            }) {
                Text(isSubmitting && submissionType == "submitted" ? "Submitting..." : "Submit Form")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSubmitting || !isFormValid ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isSubmitting || !isFormValid)
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

    private func loadExistingData() {
        isLoading = true
        
        // Load existing responses from the submission
        if let submissionResponses = submission.responses {
            var newResponses: [String: String] = [:]
            var newPhotoPreviews: [String: [UIImage]] = [:]
            var newSignatureImages: [String: UIImage] = [:]

            Task {
                for (key, value) in submissionResponses {
                    // Check if this is a signature field
                    let isSignatureField = form.currentRevision?.fields.first(where: { $0.id == key })?.type == "signature"
                    
                    switch value {
                    case .string(let str):
                        newResponses[key] = str
                        // Load signature images
                        if isSignatureField, !str.isEmpty, let url = URL(string: str) {
                            if let (data, _) = try? await URLSession.shared.data(from: url),
                               let image = UIImage(data: data) {
                                newSignatureImages[key] = image
                            }
                        }
                    case .stringArray(let arr):
                        newResponses[key] = arr.joined(separator: ",")
                    case .int(let intValue):
                        newResponses[key] = String(intValue)
                    case .double(let doubleValue):
                        newResponses[key] = String(doubleValue)
                    case .repeater(let repeaterData):
                        if let data = try? JSONEncoder().encode(repeaterData),
                           let jsonString = String(data: data, encoding: .utf8) {
                            newResponses[key] = jsonString
                        }
                    case .closeout(let closeoutData):
                        if let data = try? JSONEncoder().encode(closeoutData),
                            let jsonString = String(data: data, encoding: .utf8) {
                            newResponses[key] = jsonString
                        }
                    case .camera(let cameraData):
                        // Handle single camera object
                        let urlString = cameraData.image
                        if let url = URL(string: urlString) {
                            if let data = try? await URLSession.shared.data(from: url).0,
                               let image = UIImage(data: data) {
                                newPhotoPreviews[key, default: []].append(image)
                            }
                        }
                        // Store as array for consistency
                        if let data = try? JSONEncoder().encode([cameraData]),
                           let jsonString = String(data: data, encoding: .utf8) {
                           newResponses[key] = jsonString
                        }
                    case .cameraArray(let cameraArray):
                        // Handle array of camera objects
                        for cameraData in cameraArray {
                            let urlString = cameraData.image
                            if let url = URL(string: urlString) {
                                if let data = try? await URLSession.shared.data(from: url).0,
                                   let image = UIImage(data: data) {
                                    newPhotoPreviews[key, default: []].append(image)
                                }
                            }
                        }
                        // Store the array
                        if let data = try? JSONEncoder().encode(cameraArray),
                           let jsonString = String(data: data, encoding: .utf8) {
                           newResponses[key] = jsonString
                        }

                    case .null:
                        newResponses[key] = ""
                    }
                }
                
                await MainActor.run {
                    self.responses = newResponses
                    self.photoPreviews = newPhotoPreviews
                    self.signatureImages = newSignatureImages
                    self.selectedLocationId = submission.locationId
                    self.isLoading = false
                    validateForm()
                }
            }
        } else {
            // Draft has no saved responses yet; stop loading and validate empty form
            Task { @MainActor in
                self.isLoading = false
                validateForm()
            }
        }
    }

    private func renderFormField(field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Don't render the label HStack for subheadings - they have their own rendering
            if field.type != "subheading" {
                HStack {
                    Text(field.label)
                        .font(.headline)
                        .foregroundColor(showValidationErrors && hasFieldError(field) ? .red : .primary)
                    if field.required {
                        Text("*")
                            .foregroundColor(.red)
                            .font(.headline)
                    }
                    if showValidationErrors && hasFieldError(field) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Spacer()
                }
                
                // Show field-specific validation error only when validation is enabled
                if showValidationErrors, let fieldError = getFieldError(field) {
                    Text(fieldError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // Show submission requirement info if present
                if let submissionReq = field.submissionRequirement,
                   submissionReq.requiredForSubmission {
                    Text("Required value: \(submissionReq.requiredValue)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            switch field.type {
            case "text":
                TextField("Enter text", text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case "textarea":
                TextEditor(text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
                
            case "yesNoNA":
                Picker("", selection: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                )) {
                    Text("Select").tag("")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                    Text("N/A").tag("na")
                }
                .pickerStyle(SegmentedPickerStyle())
                
            case "dropdown":
                Picker(field.label, selection: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                )) {
                    Text("Select").tag("")
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
                        Text("Select").tag("")
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Text("No options provided for radio field")
                        .foregroundColor(.red)
                }

            case "subheading":
                Text(field.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)

            case "input":
                TextField("Enter value", text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())

            case "photo", "camera", "image":
                VStack(alignment: .leading, spacing: 8) {
                    // Show existing images
                    if let existingValue = responses[field.id], !existingValue.isEmpty,
                       let urls = getURLs(from: existingValue), !urls.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ProgressView()
                                            .frame(width: 80, height: 80)
                                    }
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3))
                                    )
                                }
                            }
                        }
                    }
                    
                    // Show newly added images
                    if let previews = photoPreviews[field.id], !previews.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if field.type == "camera" {
                                    let stagedCount = stagedCameraData[field.id]?.count ?? 0
                                    let firstNewPreviewIndex = max(0, previews.count - stagedCount)
                                    ForEach(Array(previews.enumerated()), id: \.offset) { index, img in
                                        let stagedIndex = index - firstNewPreviewIndex
                                        let canMarkUp = stagedCount > 0 && index >= firstNewPreviewIndex && stagedIndex >= 0 && stagedIndex < stagedCount
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 80)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.blue.opacity(0.5))
                                                )
                                            if canMarkUp {
                                                VStack {
                                                    Spacer()
                                                    HStack {
                                                        Button {
                                                            openCameraFieldMarkupEditor(fieldId: field.id, index: stagedIndex)
                                                        } label: {
                                                            Image(systemName: "pencil.tip.crop.circle")
                                                                .font(.system(size: 18))
                                                                .foregroundStyle(.white)
                                                                .padding(5)
                                                                .background(.ultraThinMaterial, in: Circle())
                                                        }
                                                        .accessibilityLabel("Mark up photo")
                                                        Spacer()
                                                    }
                                                }
                                                .padding(4)
                                            }
                                            Text("NEW")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue)
                                                .cornerRadius(4)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                                .padding(4)
                                        }
                                        .frame(height: 80)
                                    }
                                } else {
                                    ForEach(previews, id: \.self) { img in
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 80)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.blue.opacity(0.5))
                                            )
                                            .overlay(
                                                Text("NEW")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue)
                                                    .cornerRadius(4),
                                                alignment: .topTrailing
                                            )
                                    }
                                }
                            }
                        }
                    }

                    Button(action: {
                        activeFieldId = field.id
                        showingCameraActionSheet = true
                    }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Add Image(s)")
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    }
                }

            case "signature":
                VStack(alignment: .leading, spacing: 12) {
                    if let image = signatureImages[field.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else if let existingValue = responses[field.id], !existingValue.isEmpty {
                        // Try to load from URL if not already loaded
                        AsyncImage(url: URL(string: existingValue)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 100)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            case .failure(_):
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.red)
                                    Text("Error loading signature")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text("Failed to display signature image")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: 100)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                            case .empty:
                                ProgressView()
                                    .frame(height: 100)
                            @unknown default:
                                ProgressView()
                                    .frame(height: 100)
                            }
                        }
                    } else {
                        Text("No signature")
                            .foregroundColor(.gray)
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Allow signature editing for drafts, but not for submitted forms
                    if submission.status.lowercased() == "draft" {
                        Button("Sign") {
                            showingSignaturePad = field.id
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("Signature editing not available in edit mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            case "attachment":
                VStack(alignment: .leading, spacing: 8) {
                    if let existingValue = responses[field.id], !existingValue.isEmpty {
                        Text("Current: \(existingValue.prefix(50))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Text("Attachment editing not available in edit mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case "repeater":
                RepeaterFieldView(
                    field: field,
                    responses: $responses
                )

            case "closeout":
                CloseoutFieldView(
                    field: field,
                    response: Binding(
                        get: { self.responses[field.id] },
                        set: { self.responses[field.id] = $0 }
                    ),
                    formStatus: submission.status,
                    canApprove: canApprove,
                    submitAction: {
                        submitCloseout(newStatus: "closeout_submitted")
                    },
                    approveAction: {
                        submitCloseout(newStatus: "completed")
                    }
                )

            case "table":
                TableFieldView(
                    field: field,
                    responses: $responses
                )

            default:
                Text("Unsupported field type: \(field.type)")
                    .foregroundColor(.red)
            }
        }
    }

    private func submitForm(status: String) {
        guard let token = sessionManager.token else {
            errorMessage = "Authentication token not found."
            return
        }
        
        guard let currentRevision = form.currentRevision else {
            errorMessage = "Form template revision not found."
            return
        }

        // Validate required fields only for submitted forms (not drafts)
        if status == "submitted" {
            if !isFormValid {
                showValidationErrors = true
                errorMessage = "Please fill in all required fields and ensure they meet the requirements."
                isSubmitting = false
                return
            }
        }

        isSubmitting = true
        submissionType = status
        errorMessage = nil

        Task {
            do {
                var processedFormData = responses.toAnyDictionary()

                // Convert repeater and table field strings back to JSON arrays for submission
                if let fields = form.currentRevision?.fields {
                    for field in fields {
                        if field.type == "repeater" || field.type == "table" {
                            if let value = processedFormData[field.id] as? String,
                               let data = value.data(using: .utf8),
                               let jsonArray = try? JSONSerialization.jsonObject(with: data) {
                                processedFormData[field.id] = jsonArray
                            }
                        }
                    }
                }

                // Handle signature fields - upload new signatures or extract file keys from existing ones
                if let fields = form.currentRevision?.fields {
                    for field in fields where field.type == "signature" {
                        // If there's a new signature image, upload it
                        if let newSignatureImage = signatureImages[field.id] {
                            let fileName = "\(field.id)-signature.jpg"
                            if let imageData = newSignatureImage.jpegData(compressionQuality: 0.8) {
                                let fileKey = try await uploadFileDataAsync(imageData, fileName: fileName, fieldId: field.id, mimeType: "image/jpeg")
                                processedFormData[field.id] = fileKey
                            }
                        } else if let existingValue = processedFormData[field.id] as? String, !existingValue.isEmpty {
                            // Extract the file key from the URL (could be presigned URL or file key)
                            let fileKey = extractFileKey(from: existingValue)
                            processedFormData[field.id] = fileKey
                        }
                    }
                }

                // Handle new attachments by uploading them
                
                // 1. Photo Library Images (these are simple string arrays)
                if !photoPickerItems.isEmpty {
                    for (fieldId, items) in photoPickerItems {
                        var newFileKeys: [String] = []
                        for (index, item) in items.enumerated() {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                let fileName = "\(fieldId)-edit-\(index).jpg"
                                let fileKey = try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId)
                                newFileKeys.append(fileKey)
                            }
                        }
                        
                        // Append to existing simple image fields
                        if let existingKeys = processedFormData[fieldId] as? String, !existingKeys.isEmpty {
                            processedFormData[fieldId] = existingKeys + "," + newFileKeys.joined(separator: ",")
                        } else {
                            processedFormData[fieldId] = newFileKeys.joined(separator: ",")
                        }
                    }
                }

                // 2. Newly taken Camera Photos (these need to be structured)
                if !stagedCameraData.isEmpty {
                    for (fieldId, newPhotos) in stagedCameraData {
                        // Get existing camera data if any
                        var existingCameraValues: [[String: Any]] = []
                        
                        if let existingData = submission.responses?[fieldId] {
                            switch existingData {
                            case .camera(let cameraValue):
                                // Single camera object - convert to array
                                if let data = try? JSONEncoder().encode(cameraValue),
                                   let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    existingCameraValues.append(decoded)
                                }
                            case .cameraArray(let cameraArray):
                                // Already an array - convert each to dictionary
                                for cameraValue in cameraArray {
                                    if let data = try? JSONEncoder().encode(cameraValue),
                                       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        existingCameraValues.append(decoded)
                                    }
                                }
                            default:
                                break
                            }
                        }
                        
                        // Upload new photos and create their data structure
                        for photoData in newPhotos {
                            let fileName = "\(fieldId)-\(UUID().uuidString).jpg"
                            let fileKey = try await uploadFileDataAsync(photoData.image, fileName: fileName, fieldId: fieldId, mimeType: "image/jpeg")
                            
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
                            existingCameraValues.append(responseDict)
                        }
                        
                        // Replace the field's value with the complete array of structured objects
                        processedFormData[fieldId] = existingCameraValues
                    }
                }

                var submissionDict: [String: Any] = [
                    "formTemplateId": form.id,
                    "revisionId": currentRevision.id,
                    "projectId": projectId,
                    "formData": processedFormData,
                    "status": status
                ]

                // Add reference if provided
                if let reference = responses["reference"], !reference.isEmpty {
                    submissionDict["reference"] = reference
                }
                
                // Add locationId if provided
                if let locationId = selectedLocationId {
                    submissionDict["locationId"] = locationId
                }
                
                // Create JSON data manually for mixed types
                let jsonData = try JSONSerialization.data(withJSONObject: submissionDict)
                let updateUrl = URL(string: "\(APIClient.baseURL)/forms/submit/\(submission.id)")!
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PUT"
                updateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.httpBody = jsonData
                
                let (_, response) = try await URLSession.shared.data(for: updateRequest)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    throw NSError(domain: "FormUpdate", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to update form submission"])
                }
                
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    onSave()
                    dismiss()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    errorMessage = "Failed to update submission: \(error.localizedDescription)"
                }
            }
        }
    }

    private func uploadFileDataAsync(_ data: Data, fileName: String, fieldId: String) async throws -> String {
        return try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId, mimeType: "image/jpeg") // Simplified for brevity
    }

    private func uploadFileDataAsync(_ data: Data, fileName: String, fieldId: String, mimeType: String) async throws -> String {
        let url = URL(string: "\(APIClient.baseURL)/forms/upload-file")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body

        print("🔄 [FileUpload] Uploading file: \(fileName)")

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "No error body"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("❌ [FileUpload] Upload failed: \(statusCode) - \(errorBody)")
            throw NSError(domain: "FileUpload", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(errorBody)"])
        }

        let json = try JSONDecoder().decode([String: String].self, from: responseData)
        guard let fileKey = json["fileKey"] else {
            print("❌ [FileUpload] fileKey not found in response: \(String(data: responseData, encoding: .utf8) ?? "nil")")
            throw NSError(domain: "FileUpload", code: -2, userInfo: [NSLocalizedDescriptionKey: "File key not found in response"])
        }
        
        print("✅ [FileUpload] File uploaded successfully: \(fileKey)")
        return fileKey
    }
    
    private func extractFileKey(from urlString: String) -> String {
        // If it's already a file key (starts with tenants/), return as-is
        if urlString.hasPrefix("tenants/") {
            return urlString
        }
        
        // Handle double-encoded URLs (URLs that contain another URL as a path component)
        // Example: "https://host.com/https%3A//host.com/tenants/1/forms/file.jpg?params"
        var workingString = urlString
        
        // Try to decode URL encoding first
        if let decoded = workingString.removingPercentEncoding {
            workingString = decoded
        }
        
        // If it's a presigned URL, extract the path
        if let url = URL(string: workingString) {
            let path = url.path
            
            // Check if the path contains a URL-encoded URL (double-encoded case)
            // Look for patterns like "/https://" or "/http://" in the path, or URL-encoded versions
            if path.contains("/https://") || path.contains("/http://") || path.contains("%3A//") {
                // Try to decode the path to get the inner URL
                if let decodedPath = path.removingPercentEncoding {
                    // Look for "https://" or "http://" in the decoded path
                    if let httpsRange = decodedPath.range(of: "https://") {
                        let urlString = String(decodedPath[httpsRange.lowerBound...])
                        // Extract up to query parameters or end
                        if let queryStart = urlString.firstIndex(of: "?") {
                            let innerURLString = String(urlString[..<queryStart])
                            if let innerURL = URL(string: innerURLString) {
                                let innerPath = innerURL.path
                                // Look for "tenants/" in the inner path
                                if let tenantsRange = innerPath.range(of: "tenants/") {
                                    let fileKeyStart = innerPath[tenantsRange.lowerBound...]
                                    // Extract up to query parameters
                                    if let queryStart = fileKeyStart.firstIndex(of: "?") {
                                        return String(fileKeyStart[..<queryStart])
                                    }
                                    return String(fileKeyStart)
                                }
                            }
                        } else {
                            // No query in the inner URL string, try to parse it
                            if let innerURL = URL(string: urlString) {
                                let innerPath = innerURL.path
                                if let tenantsRange = innerPath.range(of: "tenants/") {
                                    let fileKeyStart = innerPath[tenantsRange.lowerBound...]
                                    if let queryStart = fileKeyStart.firstIndex(of: "?") {
                                        return String(fileKeyStart[..<queryStart])
                                    }
                                    return String(fileKeyStart)
                                }
                            }
                        }
                    } else if let httpRange = decodedPath.range(of: "http://") {
                        let urlString = String(decodedPath[httpRange.lowerBound...])
                        if let queryStart = urlString.firstIndex(of: "?") {
                            let innerURLString = String(urlString[..<queryStart])
                            if let innerURL = URL(string: innerURLString) {
                                let innerPath = innerURL.path
                                if let tenantsRange = innerPath.range(of: "tenants/") {
                                    let fileKeyStart = innerPath[tenantsRange.lowerBound...]
                                    if let queryStart = fileKeyStart.firstIndex(of: "?") {
                                        return String(fileKeyStart[..<queryStart])
                                    }
                                    return String(fileKeyStart)
                                }
                            }
                        }
                    }
                }
            }
            
            // Look for "tenants/" directly in the path
            if let tenantsRange = path.range(of: "tenants/") {
                let fileKeyStart = path[tenantsRange.lowerBound...]
                // Extract up to query parameters
                if let queryStart = fileKeyStart.firstIndex(of: "?") {
                    return String(fileKeyStart[..<queryStart])
                }
                // Remove leading slash if present
                return fileKeyStart.hasPrefix("/") ? String(fileKeyStart.dropFirst()) : String(fileKeyStart)
            }
            
            // Standard presigned URL extraction
            if url.query?.contains("AWSAccessKeyId") == true || url.query?.contains("X-Amz-Algorithm") == true {
                // Remove leading slash from path
                let extractedPath = String(path.dropFirst())
                // If the path still contains "tenants/", use that part
                if let tenantsRange = extractedPath.range(of: "tenants/") {
                    let fileKeyStart = extractedPath[tenantsRange.lowerBound...]
                    if let queryStart = fileKeyStart.firstIndex(of: "?") {
                        return String(fileKeyStart[..<queryStart])
                    }
                    return String(fileKeyStart)
                }
                return extractedPath
            }
        }
        
        // Try to find "tenants/" in the raw string as a last resort
        // This handles cases where URL parsing fails but we can still extract the key
        if let tenantsRange = urlString.range(of: "tenants/") {
            let fileKeyStart = urlString[tenantsRange.lowerBound...]
            // Extract up to query parameters or URL encoding markers
            if let queryStart = fileKeyStart.firstIndex(of: "?") {
                let result = String(fileKeyStart[..<queryStart])
                // Remove any remaining URL encoding
                if let decoded = result.removingPercentEncoding {
                    return decoded
                }
                return result
            }
            // Remove any URL encoding
            if let decoded = fileKeyStart.removingPercentEncoding {
                return decoded
            }
            return String(fileKeyStart)
        }
        
        // Fallback: return the original string
        return urlString
    }
    
    private func getURLs(from urlString: String) -> [URL]? {
        // First try to parse as camera array JSON
        if let jsonData = urlString.data(using: .utf8),
           let cameraArray = try? JSONDecoder().decode([FormResponseValue.CameraResponseValue].self, from: jsonData) {
            let urls = cameraArray.compactMap { URL(string: $0.image) }
            return urls.isEmpty ? nil : urls
        }
        
        // Fall back to comma-separated URLs for other photo fields
        let urlStrings = urlString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let urls = urlStrings.compactMap { URL(string: $0) }
        return urls.isEmpty ? nil : urls
    }

    private func startMonitoringNetwork() {
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                isOffline = path.status != .satisfied
            }
        }
    }
    
    private func validateRequiredFields(fields: [FormField]) -> String? {
        for field in fields {
            // Skip subheading fields
            if field.type == "subheading" {
                continue
            }
            
            // Check basic required field validation
            if field.required {
                let value = responses[field.id] ?? ""
                // For edit view, we're more lenient with existing data
                if value.isEmpty {
                    return "Please fill in the required field: \(field.label.isEmpty ? field.id : field.label)"
                }
            }
            
            // Check submission requirement validation (advanced validation)
            if let submissionReq = field.submissionRequirement,
               submissionReq.requiredForSubmission {
                let value = responses[field.id] ?? ""
                
                if value != submissionReq.requiredValue {
                    return submissionReq.validationMessage
                }
            }
            
            // Validate repeater field subfields
            if field.type == "repeater", let subFields = field.subFields {
                // Get repeater data for this field
                if let repeaterDataString = responses[field.id],
                   let jsonData = repeaterDataString.data(using: .utf8),
                   let repeaterRows = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                    
                    for (rowIndex, rowData) in repeaterRows.enumerated() {
                        for subField in subFields {
                            if subField.required {
                                let subFieldValue = rowData[subField.id] ?? ""
                                if subFieldValue.isEmpty {
                                    return "Please fill in the required field in row \(rowIndex + 1): \(subField.label.isEmpty ? subField.id : subField.label)"
                                }
                            }
                            
                            // Check subfield submission requirements
                            if let submissionReq = subField.submissionRequirement,
                               submissionReq.requiredForSubmission {
                                let subFieldValue = rowData[subField.id] ?? ""
                                if subFieldValue != submissionReq.requiredValue {
                                    return "Row \(rowIndex + 1): \(submissionReq.validationMessage)"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil // No validation errors
    }
    
    private func hasFieldError(_ field: FormField) -> Bool {
        if !showValidationErrors { return false }
        
        // Check basic required field
        if field.required {
            let value = responses[field.id] ?? ""
            let hasImage = (photoPreviews[field.id]?.isEmpty == false)
            let hasSignature = (signatureImages[field.id] != nil)
            
            if value.isEmpty && !hasImage && !hasSignature {
                return true
            }
        }
        
        // Check submission requirements
        if let submissionReq = field.submissionRequirement,
           submissionReq.requiredForSubmission {
            let value = responses[field.id] ?? ""
            if value != submissionReq.requiredValue {
                return true
            }
        }
        
        return false
    }
    
    private func getFieldError(_ field: FormField) -> String? {
        if !showValidationErrors { return nil }
        
        // Check basic required field
        if field.required {
            let value = responses[field.id] ?? ""
            let hasImage = (photoPreviews[field.id]?.isEmpty == false)
            let hasSignature = (signatureImages[field.id] != nil)
            
            if value.isEmpty && !hasImage && !hasSignature {
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
        
        print("🔍 [EditView Validation] Starting validation...")
        
        for field in fields {
            if field.type == "subheading" { continue }
            
            // Check basic required field
            if field.required {
                let value = responses[field.id] ?? ""
                let hasImage = (photoPreviews[field.id]?.isEmpty == false)
                let hasSignature = (signatureImages[field.id] != nil)
                
                print("🔍 [EditView Validation] Field \(field.id) required: value='\(value)', hasImage=\(hasImage), hasSignature=\(hasSignature)")
                
                if value.isEmpty && !hasImage && !hasSignature {
                    print("❌ [EditView Validation] Failed: Field \(field.id) is required but empty")
                    isFormValid = false
                    return
                }
            }
            
            // Check submission requirements
            if let submissionReq = field.submissionRequirement,
               submissionReq.requiredForSubmission {
                let value = responses[field.id] ?? ""
                print("🔍 [EditView Validation] Field \(field.id) submission requirement: value='\(value)', required='\(submissionReq.requiredValue)'")
                
                // Use case-insensitive comparison like create view
                if value.lowercased() != submissionReq.requiredValue.lowercased() {
                    print("❌ [EditView Validation] Failed: Field \(field.id) submission requirement not met")
                    isFormValid = false
                    return
                }
            }
            
            // Check repeater field requirements
            if field.type == "repeater", let subFields = field.subFields {
                if let repeaterDataString = responses[field.id],
                   let jsonData = repeaterDataString.data(using: .utf8),
                   let repeaterRows = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                    
                    for rowData in repeaterRows {
                        for subField in subFields {
                            if subField.required {
                                let subFieldValue = rowData[subField.id] ?? ""
                                if subFieldValue.isEmpty {
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
        
        print("✅ [EditView Validation] All fields valid!")
        isFormValid = true
    }
    
    private var hasUnsavedChanges: Bool {
        // Check if any new photos have been picked (photoPickerItems are only added by user action)
        if !photoPickerItems.isEmpty && photoPickerItems.values.contains(where: { !$0.isEmpty }) {
            return true
        }
        
        // Check if any new camera photos have been captured (stagedCameraData are only added by user action)
        if !stagedCameraData.isEmpty && stagedCameraData.values.contains(where: { !$0.isEmpty }) {
            return true
        }
        
        // Check if photoPreviews has more items than what was initially loaded
        // This is a heuristic - if there are previews, they might be new additions
        // We'll be conservative and only flag if there are definitely new items via the checks above
        
        // Check if responses have changed from initial state
        if let submissionResponses = submission.responses {
            for (key, value) in responses {
                // Get the current value
                let currentValue = value
                
                // Get the submission value
                let submissionValue: String? = {
                    switch submissionResponses[key] {
                    case .string(let str): return str
                    case .stringArray(let arr): return arr.joined(separator: ",")
                    case .int(let intValue): return String(intValue)
                    case .double(let doubleValue): return String(doubleValue)
                    case .null, .none: return nil
                    default: return nil
                    }
                }()
                
                // Compare values (treating nil and empty string as the same)
                let current = currentValue.isEmpty ? nil : currentValue
                let original = (submissionValue ?? "").isEmpty ? nil : submissionValue
                
                if current != original {
                    return true
                }
            }
        } else {
            // If there were no initial responses, any non-empty responses mean changes
            if !responses.isEmpty {
                for (_, value) in responses {
                    if !value.isEmpty {
                        return true
                    }
                }
            }
        }
        
        // Check if reference has changed
        let currentReference = responses["reference"] ?? ""
        let submissionReference = submission.reference ?? ""
        if currentReference != submissionReference {
            return true
        }
        
        // Check if location has changed
        let currentLocationId = selectedLocationId
        let submissionLocationId = submission.locationId
        if currentLocationId != submissionLocationId {
            return true
        }
        
        // Note: We don't check signatureImages here because existing signatures are loaded into it,
        // making it hard to distinguish between existing and new signatures without more complex tracking
        
        return false
    }

    private func isCloseoutWorkflow() -> Bool {
        let status = submission.status.lowercased()
        let closeoutStatuses = ["awaiting_closeout", "closeout_pending", "closeout_submitted"]
        return closeoutStatuses.contains(status)
    }

    private func submitCloseout(newStatus: String) {
        // This function will handle submitting the closeout data
        // It will be similar to submitForm but tailored for closeout
        guard let token = sessionManager.token else {
            errorMessage = "Authentication token not found."
            return
        }
        
        guard let currentRevision = form.currentRevision else {
            errorMessage = "Form template revision not found."
            return
        }

        isSubmitting = true
        submissionType = newStatus
        errorMessage = nil

        Task {
            do {
                // Use the same processing logic as submitForm
                var processedFormData: [String: Any] = [:]
                for (key, value) in responses {
                    if let field = currentRevision.fields.first(where: { $0.id == key }) {
                        if field.type == "repeater" {
                            if let data = value.data(using: .utf8),
                               let jsonArray = try? JSONSerialization.jsonObject(with: data) {
                                processedFormData[key] = jsonArray
                            }
                        } else if field.type == "table" {
                            if let data = value.data(using: .utf8),
                               let jsonArray = try? JSONSerialization.jsonObject(with: data) {
                                processedFormData[key] = jsonArray
                            }
                        } else if field.type == "closeout" {
                            if let data = value.data(using: .utf8),
                               let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                                processedFormData[key] = jsonObject
                            }
                        } else {
                            processedFormData[key] = value
                        }
                    } else {
                        processedFormData[key] = value
                    }
                }
                
                var submissionDict: [String: Any] = [
                    "formTemplateId": form.id,
                    "revisionId": currentRevision.id,
                    "projectId": projectId,
                    "formData": processedFormData,
                    "status": newStatus
                ]
                
                // Add locationId if provided
                if let locationId = selectedLocationId {
                    submissionDict["locationId"] = locationId
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: submissionDict)
                let updateUrl = URL(string: "\(APIClient.baseURL)/forms/submit/\(submission.id)")!
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "PUT"
                updateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.httpBody = jsonData
                
                let (_, response) = try await URLSession.shared.data(for: updateRequest)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    throw NSError(domain: "FormUpdate", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to update form submission"])
                }
                
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    onSave()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    errorMessage = "Failed to update submission: \(error.localizedDescription)"
                }
            }
        }
    }
}

extension Dictionary where Key == String, Value == String {
    func toAnyDictionary() -> [String: Any] {
        var anyDict: [String: Any] = [:]
        for (key, value) in self {
            anyDict[key] = value
        }
        return anyDict
    }
}

