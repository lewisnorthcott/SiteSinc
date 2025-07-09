import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Network
import AVFoundation

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
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var responses: [String: String] = [:]
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
    
    // Validation state
    @State private var isFormValid = false
    @State private var showValidationErrors = false

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
                .navigationTitle("Create Form Submission")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                        }
                    }
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
                }

        }
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
                    onImageCaptured: { photoData in
                        guard let fieldId = activeFieldId, let uiImage = UIImage(data: photoData.image) else { return }
                        capturedImages[fieldId, default: []].append(uiImage)
                        photoPreviews[fieldId, default: []].append(uiImage)
                        
                        // Store the photo data with location for form submission
                        let photoDict = photoData.toDictionary()
                        if let jsonData = try? JSONSerialization.data(withJSONObject: photoDict),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            responses[fieldId] = jsonString
                        }
                    },
                    onDismiss: {
                        activeFieldId = nil
                        showingImagePicker = false
                    }
                )
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

                // Append newly selected items to the list for this field
                let existingItems = photoPickerItems[fieldId] ?? []
                photoPickerItems[fieldId] = existingItems + newItems

                // Generate and append new previews
                Task {
                    var newImages: [UIImage] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            newImages.append(image)
                        }
                    }
                    await MainActor.run {
                        let existingPreviews = photoPreviews[fieldId] ?? []
                        photoPreviews[fieldId] = existingPreviews + newImages
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
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .padding()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if form.currentRevision == nil {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("No Published Revision")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    Text("This form template doesn't have a published revision. Please edit the template and publish a version before creating a submission.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    // DEBUG INFO
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEBUG INFO:")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("Form ID: \(form.id)")
                            .font(.caption)
                        Text("Form Title: \(form.title)")
                            .font(.caption)
                        Text("Form Status: \(form.status)")
                            .font(.caption)
                        Text("CurrentRevision: \(form.currentRevision == nil ? "NIL" : "EXISTS")")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } else if let fields = form.currentRevision?.fields, !fields.isEmpty {
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

                        ForEach(fields, id: \.id) { field in
                            renderFormField(field: field)
                        }

                        HStack(spacing: 16) {
                            Button(action: {
                                processSubmission(status: "draft")
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
                                processSubmission(status: "submitted")
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
                    .padding()
                }
                .onAppear {
                    // Validate form on appear to set initial button state
                    validateForm()
                }
                .onChange(of: responses) { _, _ in validateForm() }
                .onChange(of: signatureImages) { _, _ in validateForm() }
                .onChange(of: photoPreviews) { _, _ in validateForm() }
                .onChange(of: capturedImages) { _, _ in validateForm() }
                .onChange(of: fileURLs) { _, _ in validateForm() }
            } else {
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
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text(permissionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
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
            errorMessage = "Form revision not available"
            return
        }

        // This is a safeguard. The button should be disabled if the form is invalid.
        if status == "submitted" && !isFormValid {
            showValidationErrors = true
            errorMessage = "Please fill in all required fields and ensure they meet the requirements."
            isSubmitting = false // Ensure we reset submitting state
            return
        }

        isSubmitting = true
        submissionType = status
        
        Task {
            do {
                var updatedResponses = responses
                var fileDataAttachments: [String: Data] = [:]
                
                // Determine the actual submission status
                var actualSubmissionStatus = status
                if status == "submitted" && hasCloseoutFields() {
                    // If form has closeout fields and is being submitted (not draft),
                    // set status to "awaiting_closeout"
                    actualSubmissionStatus = "awaiting_closeout"
                }

                if isOffline {
                    // --- Offline Logic ---
                    
                    // From Camera
                    for (fieldId, images) in capturedImages {
                        for (index, image) in images.enumerated() {
                            if let data = image.jpegData(compressionQuality: 0.8) {
                                fileDataAttachments["\(fieldId)-captured-\(index).jpg"] = data
                            }
                        }
                    }
                    
                    // From PhotoPicker
                    for (fieldId, items) in photoPickerItems {
                        for (index, item) in items.enumerated() {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                fileDataAttachments["\(fieldId)-\(index).jpg"] = data
                            }
                        }
                    }
                    
                    // From Signatures
                    for (fieldId, signatureImage) in signatureImages {
                        if let data = signatureImage.jpegData(compressionQuality: 0.8) {
                            fileDataAttachments["\(fieldId)-signature.jpg"] = data
                        }
                    }
                    
                    // From Files
                    for (fieldId, fileURL) in fileURLs {
                        if let data = try? Data(contentsOf: fileURL) {
                            fileDataAttachments["\(fieldId)-\(fileURL.lastPathComponent)"] = data
                        }
                    }
                    
                    let offlineSubmission = OfflineSubmission(
                        id: UUID(),
                        formTemplateId: form.id,
                        revisionId: revision.id,
                        projectId: projectId,
                        formData: updatedResponses,
                        fileAttachments: fileDataAttachments,
                        status: actualSubmissionStatus
                    )
                    OfflineSubmissionManager.shared.saveSubmission(offlineSubmission)
                    
                    await MainActor.run {
                        isSubmitting = false
                        submissionType = nil
                        errorMessage = "You are offline. Submission saved as draft and will be sent when you're back online."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            dismiss()
                        }
                    }
                    return
                }

                // --- Online Logic ---
                var allUploadedFileKeys: [String: [String]] = [:]

                // 1. Collect all image data first
                var filesToUploadByField: [String: [(fileName: String, data: Data)]] = [:]

                for (fieldId, items) in photoPickerItems {
                    for (index, item) in items.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let fileName = "\(fieldId)-\(index).jpg"
                            filesToUploadByField[fieldId, default: []].append((fileName: fileName, data: data))
                        }
                    }
                }
                
                for (fieldId, images) in capturedImages {
                    for (index, image) in images.enumerated() {
                        if let data = image.jpegData(compressionQuality: 0.8) {
                            let fileName = "\(fieldId)-captured-\(index).jpg"
                            filesToUploadByField[fieldId, default: []].append((fileName: fileName, data: data))
                        }
                    }
                }

                // 2. Batch upload images
                for (fieldId, files) in filesToUploadByField {
                    if !files.isEmpty {
                        let fileKeys = try await uploadBatchOfFilesAsync(files, fieldId: fieldId, projectId: projectId)
                        allUploadedFileKeys[fieldId, default: []].append(contentsOf: fileKeys)
                    }
                }

                // 3. Handle single uploads for other types
                for (fieldId, signatureImage) in signatureImages {
                     let fileKey = try await uploadSignatureImageAsync(signatureImage, fieldId: fieldId, projectId: projectId)
                     allUploadedFileKeys[fieldId, default: []].append(fileKey)
                }

                for (fieldId, fileURL) in fileURLs {
                    let fileKey = try await uploadFileAsync(fileURL, fieldId: fieldId, projectId: projectId)
                    allUploadedFileKeys[fieldId, default: []].append(fileKey)
                }
                
                // 4. Combine file keys for each field
                for (fieldId, keys) in allUploadedFileKeys {
                    if !keys.isEmpty {
                        updatedResponses[fieldId] = keys.joined(separator: ",")
                    }
                }

                                 // Convert repeater field strings back to JSON arrays for submission
                 var processedFormData: [String: Any] = [:]
                 
                 for (key, value) in updatedResponses {
                     // Find the field to check if it's a repeater
                     if let field = revision.fields.first(where: { $0.id == key }),
                        field.type == "repeater" {
                                                 // Parse JSON string back to array for repeater fields
                        if let data = value.data(using: .utf8),
                           let jsonArray = try? JSONSerialization.jsonObject(with: data) {
                            processedFormData[key] = jsonArray
                        } else {
                            processedFormData[key] = []
                        }
                     } else {
                         processedFormData[key] = value
                     }
                 }
                
                let submissionData: [String: Any] = [
                    "formTemplateId": form.id,
                    "revisionId": revision.id,
                    "projectId": projectId,
                    "formData": processedFormData,
                    "status": actualSubmissionStatus
                ]
                
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
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    let responseBody = String(data: (try? await URLSession.shared.data(for: request).0) ?? Data(), encoding: .utf8) ?? "No response body"
                    throw NSError(domain: "FormSubmission", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to submit form. Server response: \(responseBody)"])
                }
                
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionType = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestCameraPermissionAndShowPicker() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            // Permission already granted.
            showingImagePicker = true
        case .notDetermined:
            // Request permission.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showingImagePicker = true
                    } else {
                        // User denied permission.
                        self.permissionAlertMessage = "Camera access is required to take photos. Please enable it in Settings."
                        self.showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // Permission was denied or restricted.
            self.permissionAlertMessage = "Camera access has been denied. Please go to Settings to enable it for this app."
            self.showingPermissionAlert = true
        @unknown default:
            fatalError("Unhandled authorization status")
        }
    }

    @ViewBuilder
    private func renderFormField(field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                
            case "image":
                PhotosPicker(
                    selection: Binding(
                        get: { photoPickerItems[field.id] ?? [] },
                        set: { photoPickerItems[field.id] = $0 }
                    ),
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    Text("Select Images")
                }
                .onChange(of: photoPickerItems[field.id]) { _, newItems in
                    Task {
                        var loadedImages: [UIImage] = []
                        for item in newItems ?? [] {
                            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                                loadedImages.append(image)
                            }
                        }
                        await MainActor.run {
                            photoPreviews[field.id] = loadedImages
                        }
                    }
                }
                
                if let previews = photoPreviews[field.id], !previews.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(previews, id: \.self) { img in
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 100)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

            case "camera":
                VStack(alignment: .leading) {
                    if let previews = photoPreviews[field.id], !previews.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(previews, id: \.self) { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.5))
                                        )
                                }
                            }
                        }
                    }

                    Button(action: {
                        activeFieldId = field.id
                        showingCameraActionSheetForField = field.id
                    }) {
                        Label("Add Image(s)", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .actionSheet(isPresented: Binding(
                        get: { showingCameraActionSheetForField == field.id },
                        set: { if !$0 { showingCameraActionSheetForField = nil } }
                    )) {
                        ActionSheet(title: Text("Add Image"), buttons: [
                            .default(Text("Take Photo")) {
                                requestCameraPermissionAndShowPicker()
                            },
                            .default(Text("Choose From Library")) {
                                activeFieldId = field.id
                                showingPhotosPicker = true
                            },
                            .cancel()
                        ])
                    }
                }

            case "signature":
                VStack(alignment: .leading, spacing: 12) {
                    if let image = signatureImages[field.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .border(Color.gray)
                    } else {
                        Text("No signature")
                            .foregroundColor(.gray)
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .border(Color.gray)
                    }
                    Button("Sign") {
                        showingSignaturePad = field.id
                    }
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
                    formStatus: "draft", // Since this is create view, status is always draft initially
                    canApprove: false,   // No approval in create view
                    submitAction: {
                        // Closeout submit action - not applicable in create view
                    },
                    approveAction: {
                        // Closeout approve action - not applicable in create view  
                    }
                )

            default:
                Text("Unsupported field type: \(field.type)")
                    .foregroundColor(.red)
            }
        }
        .padding(.bottom)
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
    
    private func hasFieldError(_ field: FormField) -> Bool {
        if !showValidationErrors { return false }
        
        // Skip closeout fields in create view
        if field.type == "closeout" { return false }
        
        // Check basic required field
        if field.required {
            let value = responses[field.id] ?? ""
            let hasImage = (signatureImages[field.id] != nil || 
                           photoPreviews[field.id]?.isEmpty == false || 
                           capturedImages[field.id]?.isEmpty == false ||
                           fileURLs[field.id] != nil)
            
            if value.isEmpty && !hasImage {
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
        
        // Skip closeout fields in create view
        if field.type == "closeout" { return nil }
        
        // Check basic required field
        if field.required {
            let value = responses[field.id] ?? ""
            let hasImage = (signatureImages[field.id] != nil || 
                           photoPreviews[field.id]?.isEmpty == false || 
                           capturedImages[field.id]?.isEmpty == false ||
                           fileURLs[field.id] != nil)
            
            if value.isEmpty && !hasImage {
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
        
        for field in fields {
            if field.type == "subheading" { continue }
            
            // Skip closeout fields in create view - they're not applicable until after submission
            if field.type == "closeout" { continue }
            
            // Check basic required field
            if field.required {
                let value = responses[field.id] ?? ""
                let hasImage = (signatureImages[field.id] != nil ||
                               photoPreviews[field.id]?.isEmpty == false ||
                               capturedImages[field.id]?.isEmpty == false ||
                               fileURLs[field.id] != nil)
                
                print("🔍 [Validation] Field \(field.id) required: value='\(value)', hasImage=\(hasImage)")
                
                if value.isEmpty && !hasImage {
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
        }
        
        print("✅ [Validation] All fields valid!")
        isFormValid = true
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


