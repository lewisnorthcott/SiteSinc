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
    @State private var activeFieldId: String?
    @State private var showingPhotosPicker = false
    @State private var showingCameraActionSheet = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss

    @State private var isOffline = false
    private let monitor = NWPathMonitor()
    @State private var submissionType: String?

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
                .navigationTitle("Edit Form")
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
                .photosPicker(isPresented: $showingPhotosPicker, selection: $pickerSelection, maxSelectionCount: 5, matching: .images)
                .onChange(of: pickerSelection) { _, newItems in
                    guard let fieldId = activeFieldId, !newItems.isEmpty else {
                        if newItems.isEmpty {
                            activeFieldId = nil
                        }
                        return
                    }

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
                            photoPreviews[fieldId] = existingPreviews + newImages
                        }
                    }

                    pickerSelection = []
                    activeFieldId = nil
                }
                .actionSheet(isPresented: $showingCameraActionSheet) {
                    ActionSheet(title: Text("Add Image"), buttons: [
                        .default(Text("Choose From Library")) {
                            showingPhotosPicker = true
                        },
                        .cancel()
                    ])
                }
                .onAppear {
                    loadExistingData()
                    startMonitoringNetwork()
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
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadExistingData()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
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
                                    .background(isSubmitting ? Color.gray : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(isSubmitting)
                        }
                    }
                    .padding()
                }
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
    }

    private func loadExistingData() {
        isLoading = true
        
        // Load existing responses from the submission
        if let submissionResponses = submission.responses {
            for (key, value) in submissionResponses {
                switch value {
                case .string(let str):
                    responses[key] = str
                case .stringArray(let arr):
                    responses[key] = arr.joined(separator: ",")
                case .int(let intValue):
                    responses[key] = String(intValue)
                case .double(let doubleValue):
                    responses[key] = String(doubleValue)
                case .repeater(let repeaterData):
                    if let data = try? JSONEncoder().encode(repeaterData),
                       let jsonString = String(data: data, encoding: .utf8) {
                        responses[key] = jsonString
                    } else {
                        responses[key] = "[]"
                    }
                case .null:
                    responses[key] = ""
                }
            }
        }
        
        isLoading = false
    }

    private func renderFormField(field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(field.label)
                    .font(.headline)
                if field.required {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()
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

                    Button(action: {
                        activeFieldId = field.id
                        showingCameraActionSheet = true
                    }) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

            case "signature", "attachment":
                VStack(alignment: .leading, spacing: 8) {
                    if let existingValue = responses[field.id], !existingValue.isEmpty {
                        Text("Current: \(existingValue.prefix(50))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Text("\(field.type.capitalized) editing not available in edit mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            default:
                Text("Field type '\(field.type)' - Edit not supported yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
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

        isSubmitting = true
        submissionType = status
        errorMessage = nil

        Task {
            do {
                var updatedResponses = responses
                
                // First: Convert ALL existing image URLs to file keys
                for field in form.currentRevision?.fields ?? [] {
                    if ["photo", "camera", "image"].contains(field.type), 
                       let existingValue = updatedResponses[field.id], 
                       !existingValue.isEmpty {
                        // Extract file keys from existing URLs
                        let existingFileKeys = existingValue.split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .map { extractFileKey(from: $0) }
                        
                        updatedResponses[field.id] = existingFileKeys.joined(separator: ",")
                    }
                }
                
                // Second: Handle new photo uploads and add to existing file keys
                for (fieldId, items) in photoPickerItems {
                    if !items.isEmpty {
                        var newImageUrls: [String] = []
                        
                        for (index, item) in items.enumerated() {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                let fileName = "\(fieldId)-edit-\(index).jpg"
                                let fileKey = try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId)
                                newImageUrls.append(fileKey)
                            }
                        }
                        
                        if !newImageUrls.isEmpty {
                            // Add new file keys to existing ones
                            if let existingFileKeys = updatedResponses[fieldId], !existingFileKeys.isEmpty {
                                let allFileKeys = existingFileKeys + "," + newImageUrls.joined(separator: ",")
                                updatedResponses[fieldId] = allFileKeys
                            } else {
                                updatedResponses[fieldId] = newImageUrls.joined(separator: ",")
                            }
                        }
                    }
                }
                
                let submissionData = SubmissionData(
                    formTemplateId: form.id,
                    revisionId: currentRevision.id,
                    projectId: projectId,
                    formData: updatedResponses,
                    status: status
                )
                
                // Update the existing submission instead of creating a new one
                try await APIClient.updateFormSubmission(
                    submissionId: submission.id,
                    token: token,
                    submissionData: submissionData
                )
                
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
        
        // If it's a presigned URL, extract the path
        if let url = URL(string: urlString) {
            if url.query?.contains("AWSAccessKeyId") == true || url.query?.contains("X-Amz-Algorithm") == true {
                // Remove leading slash from path to get the file key
                return String(url.path.dropFirst())
            }
        }
        
        // Fallback: return the original string
        return urlString
    }
    
    private func getURLs(from urlString: String) -> [URL]? {
        // Handle both single URL and comma-separated URLs
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
} 