import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Network

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

struct FormSubmissionCreateView: View {
    let formId: Int
    let projectId: Int
    let token: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var form: FormModel?
    @State private var isLoading = true
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
            ZStack {
                Color.white.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if let form = form, let fields = form.currentRevision?.fields {
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
                    Text("Form template not found")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
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
            .onChange(of: documentPickerDelegate.selectedURL) { newURL in
                if let url = newURL, let fieldId = activeFieldId {
                    fileURLs[fieldId] = url
                }
            }
            .onAppear {
                fetchForm()
                startMonitoringNetwork()
            }
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

    private func fetchForm() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetchedForms = try await APIClient.fetchForms(projectId: projectId, token: token)
                await MainActor.run {
                    form = fetchedForms.first(where: { $0.id == formId })
                    if form == nil {
                        errorMessage = "Form template not found"
                    }
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func processSubmission(status: String) {
        guard let form = form, let revision = form.currentRevision else {
            errorMessage = "Form revision not available"
            return
        }

        isSubmitting = true
        submissionType = status
        
        Task {
            do {
                var updatedResponses = responses
                var fileDataAttachments: [String: Data] = [:]

                for (fieldId, items) in photoPickerItems {
                    if items.isEmpty { continue }
                    for (index, item) in items.enumerated() {
                        if let data = try await item.loadTransferable(type: Data.self) {
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

                if isOffline {
                    let offlineSubmission = OfflineSubmission(
                        id: UUID(),
                        formTemplateId: formId,
                        revisionId: revision.id,
                        projectId: projectId,
                        formData: updatedResponses,
                        fileAttachments: fileDataAttachments,
                        status: status
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

                for (fieldId, items) in photoPickerItems {
                    if items.isEmpty { continue }
                    var fileKeys: [String] = []
                    for (index, item) in items.enumerated() {
                        let fileKey = try await uploadPhotoPickerItemAsync(item, fieldId: fieldId, index: index, projectId: projectId)
                        fileKeys.append(fileKey)
                    }
                    updatedResponses[fieldId] = fileKeys.joined(separator: ",")
                }

                for (fieldId, signatureImage) in signatureImages {
                     let fileKey = try await uploadSignatureImageAsync(signatureImage, fieldId: fieldId, projectId: projectId)
                     updatedResponses[fieldId] = fileKey
                }

                for (fieldId, fileURL) in fileURLs {
                    let fileKey = try await uploadFileAsync(fileURL, fieldId: fieldId, projectId: projectId)
                    updatedResponses[fieldId] = fileKey
                }

                let submissionData = SubmissionData(
                    formTemplateId: formId,
                    revisionId: revision.id,
                    projectId: projectId,
                    formData: updatedResponses,
                    status: status
                )
                
                let jsonData = try JSONEncoder().encode(submissionData)
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

    @ViewBuilder
    private func renderFormField(field: FormField) -> some View {
        VStack(alignment: .leading) {
            Text(field.label)
                .font(.headline)
            
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
                
            case "image", "camera":
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
                .onChange(of: photoPickerItems[field.id]) { newItems in
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

            case "signature":
                VStack {
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

            default:
                Text("Unsupported field type: \(field.type)")
                    .foregroundColor(.red)
            }
        }
        .padding(.bottom)
    }

    private func uploadPhotoPickerItemAsync(_ item: PhotosPickerItem, fieldId: String, index: Int, projectId: Int) async throws -> String {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw NSError(domain: "ImageConversion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image data"])
        }
        let fileName = "\(fieldId)-\(index).jpg"
        return try await uploadFileDataAsync(data, fileName: fileName, fieldId: fieldId, projectId: projectId, mimeType: "image/jpeg")
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
        let url = URL(string: "\(APIClient.baseURL)/forms/upload-attachment")!
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
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDrawing {
                                    currentPath = Path()
                                    currentPath.move(to: value.location)
                                    isDrawing = true
                                }
                                currentPath.addLine(to: value.location)
                            }
                            .onEnded { _ in
                                paths.append(IdentifiablePath(path: currentPath))
                                currentPath = Path()
                                isDrawing = false
                                renderSignature()
                            }
                    )

                    HStack {
                        Button("Clear") {
                            paths.removeAll()
                            currentPath = Path()
                            isDrawing = false
                            signatureImage = nil
                        }
                        .padding()
                        Spacer()
                        Button("Done") {
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
        signatureImage = renderer.image { ctx in
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
    }
}

struct FormSubmissionCreateView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FormSubmissionCreateView(formId: 1, projectId: 1, token: "sample_token")
        }
    }
}
