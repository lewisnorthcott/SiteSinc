import SwiftUI
import PhotosUI

struct FormSubmissionCreateView: View {
    let formId: Int
    let projectId: Int
    let token: String
    @State private var form: Form?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var photoPickerItems: [String: [PhotosPickerItem]] = [:]
    @State private var photoPreviews: [String: [UIImage]] = [:]
    @State private var signatureImages: [String: UIImage] = [:]
    @State private var fileURLs: [String: URL] = [:]
    @State private var showingSignaturePad: String?
    @Environment(\.dismiss) private var dismiss

    private struct SubmissionData: Codable {
        let formTemplateId: Int
        let revisionId: Int
        let projectId: Int
        let formData: [String: String]
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

                            Button(action: {
                                submitForm()
                            }) {
                                Text(isSubmitting ? "Submitting..." : "Submit Form")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isSubmitting ? Color.gray : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(isSubmitting)
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
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }
            )
            .sheet(isPresented: Binding(
                get: { showingSignaturePad != nil },
                set: { if !$0 { showingSignaturePad = nil } }
            )) {
                if let fieldId = showingSignaturePad {
                    SignaturePadView(signatureImage: $signatureImages[fieldId])
                }
            }
            .onAppear {
                fetchForm()
            }
        }
    }

    private func fetchForm() {
        APIClient.fetchForms(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let fetchedForms):
                    form = fetchedForms.first(where: { $0.id == formId })
                    if form == nil {
                        errorMessage = "Form template not found"
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func submitForm() {
        guard let form = form, let revision = form.currentRevision else {
            errorMessage = "Form revision not available"
            return
        }

        isSubmitting = true

        let group = DispatchGroup()
        var uploadErrors: [String] = []

        for (fieldId, items) in photoPickerItems {
            var fileKeys: [String] = []
            for (index, item) in items.enumerated() {
                group.enter()
                uploadPhotoPickerItem(item, fieldId: fieldId, index: index) { result in
                    defer { group.leave() }
                    switch result {
                    case .success(let fileKey):
                        fileKeys.append(fileKey)
                    case .failure(let error):
                        uploadErrors.append("Failed to upload image \(index) for \(fieldId): \(error.localizedDescription)")
                    }
                }
            }
            responses[fieldId] = fileKeys.joined(separator: ",")
        }

        for (fieldId, signatureImage) in signatureImages {
            group.enter()
            uploadSignatureImage(signatureImage, fieldId: fieldId) { result in
                defer { group.leave() }
                switch result {
                case .success(let fileKey):
                    responses[fieldId] = fileKey
                case .failure(let error):
                    uploadErrors.append("Failed to upload signature for \(fieldId): \(error.localizedDescription)")
                }
            }
        }

        for (fieldId, fileURL) in fileURLs {
            group.enter()
            uploadFile(fileURL, fieldId: fieldId) { result in
                defer { group.leave() }
                switch result {
                case .success(let fileKey):
                    responses[fieldId] = fileKey
                case .failure(let error):
                    uploadErrors.append("Failed to upload file for \(fieldId): \(error.localizedDescription)")
                }
            }
        }

        group.notify(queue: .main) {
            if !uploadErrors.isEmpty {
                isSubmitting = false
                errorMessage = uploadErrors.joined(separator: "\n")
                return
            }

            var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/submit")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let submissionData = SubmissionData(
                formTemplateId: formId,
                revisionId: revision.id,
                projectId: projectId,
                formData: responses
            )

            do {
                request.httpBody = try JSONEncoder().encode(submissionData)
            } catch {
                isSubmitting = false
                errorMessage = "Failed to encode form data: \(error.localizedDescription)"
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    if let error = error {
                        errorMessage = error.localizedDescription
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
                        errorMessage = "Failed to submit form"
                        return
                    }
                    dismiss()
                }
            }.resume()
        }
    }

    private func uploadPhotoPickerItem(_ item: PhotosPickerItem, fieldId: String, index: Int, completion: @escaping (Result<String, Error>) -> Void) {
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                guard let data = data else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data available"])))
                    return
                }
                uploadFileData(data, fileName: "\(fieldId)-\(index).jpg", fieldId: fieldId, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func uploadSignatureImage(_ image: UIImage, fieldId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert signature to data"])))
            return
        }
        uploadFileData(data, fileName: "\(fieldId)-signature.jpg", fieldId: fieldId, completion: completion)
    }

    private func uploadFile(_ url: URL, fieldId: String, completion: @escaping (Result<String, Error>) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            uploadFileData(data, fileName: url.lastPathComponent, fieldId: fieldId, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    private func uploadFileData(_ data: Data, fileName: String, fieldId: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/upload-file")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])))
                return
            }
            guard let data = data, let json = try? JSONDecoder().decode([String: String].self, from: data), let fileUrl = json["fileUrl"] else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            let fileKey = fileUrl.components(separatedBy: "amazonaws.com/").last ?? fileUrl
            completion(.success(fileKey))
        }.resume()
    }

    private func loadPhotoPreview(_ item: PhotosPickerItem, fieldId: String, index: Int) {
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if photoPreviews[fieldId] == nil {
                        photoPreviews[fieldId] = []
                    }
                    if photoPreviews[fieldId]!.count <= index {
                        photoPreviews[fieldId]!.append(image)
                    } else {
                        photoPreviews[fieldId]![index] = image
                    }
                }
            case .failure:
                break
            }
        }
    }

    @ViewBuilder
    private func renderFormField(field: FormField) -> some View {
        switch field.type {
        case "text", "number", "phone", "email":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField(field.label, text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.vertical, 4)

        case "textarea":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                ))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }
            .padding(.vertical, 4)

        case "yesNoNA":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker(field.label, selection: Binding(
                    get: { responses[field.id] ?? "" },
                    set: { responses[field.id] = $0 }
                )) {
                    Text("Select").tag("")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                    Text("N/A").tag("na")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding(.vertical, 4)

        case "dropdown", "radio":
            if let options = field.options {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label + (field.required ? " *" : ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker(field.label, selection: Binding(
                        get: { responses[field.id] ?? "" },
                        set: { responses[field.id] = $0 }
                    )) {
                        Text("Select").tag("")
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.vertical, 4)
            }

        case "checkbox":
            VStack(alignment: .leading, spacing: 4) {
                Toggle(field.label + (field.required ? " *" : ""), isOn: Binding(
                    get: { (responses[field.id] ?? "false") == "true" },
                    set: { responses[field.id] = $0 ? "true" : "false" }
                ))
            }
            .padding(.vertical, 4)

        case "subheading":
            Text(field.label)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .padding(.vertical, 8)

        case "attachment":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let fileURL = fileURLs[field.id] {
                    Text("Selected: \(fileURL.lastPathComponent)")
                        .font(.body)
                        .foregroundColor(.blue)
                } else {
                    Button(action: {
                        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .text])
                        documentPicker.delegate = DocumentPickerDelegate { url in
                            fileURLs[field.id] = url
                        }
                        UIApplication.shared.windows.first?.rootViewController?.present(documentPicker, animated: true)
                    }) {
                        Text("Select File")
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.vertical, 4)

        case "image", "camera":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                PhotosPicker(
                    selection: Binding(
                        get: { photoPickerItems[field.id] ?? [] },
                        set: { newItems in
                            photoPickerItems[field.id] = newItems
                            for (index, item) in newItems.enumerated() {
                                loadPhotoPreview(item, fieldId: field.id, index: index)
                            }
                        }
                    ),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(field.type == "camera" ? "Take Photo" : "Select Image")
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                if let previews = photoPreviews[field.id], !previews.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(previews.indices, id: \.self) { index in
                                Image(uiImage: previews[index])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 4)

        case "signature":
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label + (field.required ? " *" : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let signatureImage = signatureImages[field.id] {
                    Image(uiImage: signatureImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                Button(action: {
                    showingSignaturePad = field.id
                }) {
                    Text(signatureImages[field.id] == nil ? "Add Signature" : "Edit Signature")
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)

        default:
            Text("Unsupported field type: \(field.type)")
                .foregroundColor(.gray)
                .padding(.vertical, 4)
        }
    }
}

class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onSelect: (URL) -> Void

    init(onSelect: @escaping (URL) -> Void) {
        self.onSelect = onSelect
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            onSelect(url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
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
                                    // Start a new path with the initial point
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
