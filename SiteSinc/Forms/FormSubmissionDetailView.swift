import SwiftUI
import PDFKit // Needed for PDF generation if using UIGraphicsPDFRenderer directly

struct IdentifiableURL: Identifiable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}

struct FormSubmissionDetailView: View {
    let submissionId: Int
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var submission: FormSubmission?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshedResponses: [String: FormResponseValue] = [:]
    @State private var galleryImageURLs: [URL] = []
    @State private var selectedImageIndex: Int = 0
    @State private var showGallery = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
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
                        fetchSubmission()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else if let submission = submission {
                ScrollView {
                    VStack(spacing: 24) {
                        // Main Header Card
                        VStack(alignment: .leading, spacing: 20) {
                            // Title and Project Name
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(submission.templateTitle)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill") // Changed icon
                                            .font(.callout) // Adjusted size
                                            .foregroundColor(.secondary) // Neutral color
                                        Text(projectName)
                                            .font(.callout) // Adjusted size
                                            .foregroundColor(.secondary) // Neutral color
                                            .fontWeight(.medium)
                                    }
                                }
                                Spacer()
                                StatusBadge(status: submission.status)
                            }
                            
                            Divider().padding(.vertical, 4)

                            // Info Cards Grid - now 2 columns, Date card includes time
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                InfoCard(
                                    icon: "number.square.fill",
                                    iconColor: .purple,
                                    title: "Form Number",
                                    value: submission.formNumber ?? "#\(submission.id)"
                                )
                                InfoCard(
                                    icon: "person.crop.circle.fill",
                                    iconColor: .green,
                                    title: "Submitted By",
                                    value: "\(submission.submittedBy.firstName) \(submission.submittedBy.lastName)"
                                )
                                InfoCard(
                                    icon: "calendar.badge.clock", // New icon for combined date/time
                                    iconColor: .orange,
                                    title: "Submitted At",
                                    value: formatDate(submission.submittedAt) // formatDate already includes time
                                ).gridCellColumns(2) // Make this card span 2 columns
                            }
                        }
                        .padding(20) // Slightly reduced padding
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
                        )

                        // Form Responses Section
                        if !submission.fields.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    Text("Form Responses")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("\(submission.fields.count) fields")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 24)
                                
                                VStack(spacing: 12) {
                                    ForEach(submission.fields, id: \.id) { field in
                                        ModernFormFieldCard(
                                            field: field,
                                            response: refreshedResponses,
                                            onImageTap: { urls, index in
                                                self.galleryImageURLs = urls
                                                self.selectedImageIndex = index
                                                self.showGallery = true
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        } else {
                            EmptyResponsesCard()
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Form Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("The requested form submission could not be found")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button(action: {
//                    shareSubmissionAsPDF()
//                }) {
//                    Image(systemName: "square.and.arrow.up")
//                        .font(.system(size: 16, weight: .medium))
//                }
//            }
        }
        .fullScreenCover(isPresented: $showGallery) {
            ImageGalleryView(urls: galleryImageURLs, selectedIndex: selectedImageIndex)
        }
        .onAppear {
            fetchSubmission()
        }
    }

    private func fetchSubmission() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let submissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
                await MainActor.run {
                    if let fetchedSubmission = submissions.first(where: { $0.id == submissionId }) {
                        self.submission = fetchedSubmission
                        // Initialize refreshedResponses with original responses (which might contain keys)
                        let initialResponses = fetchedSubmission.responses ?? [:]
                        self.refreshedResponses = initialResponses
                        print("[AttachmentRefresh] Initial self.refreshedResponses set: \(self.refreshedResponses)")
                        
                        // Now, refresh the URLs if they are keys
                        refreshAttachmentURLs(fields: fetchedSubmission.fields, responses: initialResponses)
                    } else {
                        errorMessage = "Submission not found"
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

    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, yyyy, h:mm a"
            return displayFormatter.string(from: date)
        }
        return dateString
    }

    private func formatTime(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            return displayFormatter.string(from: date)
        }
        return dateString
    }

    private func shareSubmissionAsPDF() {
        guard let submission = submission else {
            print("Submission data not available for PDF generation.")
            return
        }

        let pdfData = FormSubmissionPDFView(submission: submission, projectName: projectName, responses: refreshedResponses).generatePdfData()

        guard let data = pdfData, !data.isEmpty else {
            print("Failed to generate PDF data or data is empty.")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Submission-\(submission.id).pdf")
        do {
            try data.write(to: tempURL)
        } catch {
            print("Error saving PDF to temporary file: \(error)")
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("Could not find root view controller to present share sheet.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = rootViewController.view 
            popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        rootViewController.present(activityViewController, animated: true, completion: nil)
    }

    // MARK: - Attachment URL Refreshing (Restored)
    private func refreshAttachmentURLs(fields: [FormField], responses: [String: FormResponseValue]) {
        print("[AttachmentRefresh] Starting refreshAttachmentURLs. Initial responses count: \(responses.count)")
        var localUpdatedResponses = responses // Work with a local mutable copy, modified by completion handlers
        let group = DispatchGroup()
        var hasPendingRefreshes = false

        let attachmentFields = fields.filter { ["image", "attachment", "camera", "signature"].contains($0.type) }

        for field in attachmentFields {
            guard let responseValue = localUpdatedResponses[field.id] else {
                print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): No response value. Skipping.")
                continue
            }

            switch responseValue {
            case .string(let fileKey):
                if shouldRefreshToken(fileKey) {
                    hasPendingRefreshes = true
                    group.enter()
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Refreshing single key: \(fileKey)")
                    fetchAndReplaceToken(forKey: fileKey, fieldId: field.id, originalIndexInArray: nil, group: group) { (processedFieldId, newUrl, _) in
                        // This completion is called on main thread by fetchAndReplaceToken
                        localUpdatedResponses[processedFieldId] = .string(newUrl)
                        print("[AttachmentRefresh] Field '\(processedFieldId)': Single key updated in localUpdatedResponses to: \(newUrl)")
                    }
                } else {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Skipping refresh for single key (already URL or no pattern match): \(fileKey)")
                }

            case .stringArray(let fileKeys):
                print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Processing stringArray with \(fileKeys.count) keys.")
                var anItemInArrayNeededRefresh = false // To track if this specific array had any refresh attempts.

                for (index, key) in fileKeys.enumerated() {
                    if shouldRefreshToken(key) {
                        hasPendingRefreshes = true
                        anItemInArrayNeededRefresh = true
                        group.enter()
                        print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)) [\(index)]: Refreshing array key: \(key)")
                        fetchAndReplaceToken(forKey: key, fieldId: field.id, originalIndexInArray: index, group: group) { (processedFieldId, newUrl, idxOptional) in
                            // This completion is called on main thread by fetchAndReplaceToken
                            guard let idx = idxOptional else {
                                print("[AttachmentRefresh] Field '\(processedFieldId)' [\(index)]: CRITICAL ERROR - index was nil in completion for array key.")
                                return
                            }
                            if case .stringArray(var arr) = localUpdatedResponses[processedFieldId] {
                                if idx < arr.count {
                                    arr[idx] = newUrl
                                    localUpdatedResponses[processedFieldId] = .stringArray(arr)
                                    print("[AttachmentRefresh] Field '\(processedFieldId)' [\(idx)]: Array item in localUpdatedResponses updated to \(newUrl)")
                                } else {
                                    print("[AttachmentRefresh] Field '\(processedFieldId)' [\(idx)]: CRITICAL ERROR - Index out of bounds ([\(idx)] vs \(arr.count)) when updating array in localUpdatedResponses.")
                                }
                            } else {
                                print("[AttachmentRefresh] Field '\(processedFieldId)' [\(idx)]: CRITICAL ERROR - Expected stringArray in localUpdatedResponses for field \(processedFieldId) but found something else.")
                            }
                        }
                    } else {
                        print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)) [\(index)]: Skipping refresh for array key (already URL or no pattern match): \(key)")
                    }
                }
                 if anItemInArrayNeededRefresh {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Array items were processed for potential refresh. localUpdatedResponses will be updated by completions.")
                 }

            case .null:
                print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Null response. Skipping.")
            }
        }

        if !hasPendingRefreshes {
            print("[AttachmentRefresh] No pending refresh operations. self.refreshedResponses remains as initial.")
            return
        }

        group.notify(queue: .main) {
            print("[AttachmentRefresh] All URL refresh tasks dispatched and group notified. Finalizing self.refreshedResponses.")
            self.refreshedResponses = localUpdatedResponses
            print("[AttachmentRefresh] self.refreshedResponses has been updated. Final value: \(self.refreshedResponses)")
        }
    }

    private func shouldRefreshToken(_ key: String) -> Bool {
        // It's a key if it's a relative path (like "tenants/..." or contains "/forms/")
        // and not a full URL (doesn't start with http/https)
        let isLikelyKeyPattern = key.starts(with: "tenants/") || key.contains("/forms/")
        let isFullUrl = key.lowercased().starts(with: "http://") || key.lowercased().starts(with: "https://")
        let shouldRefresh = isLikelyKeyPattern && !isFullUrl
        // print("[AttachmentRefresh] shouldRefreshToken for key '\(key)': \(shouldRefresh)") // Less verbose
        return shouldRefresh
    }

    // fetchAndReplaceToken now uses a completion handler instead of inout parameter for responses
    private func fetchAndReplaceToken(
        forKey fileKey: String,
        fieldId: String,
        originalIndexInArray: Int?,
        group: DispatchGroup,
        completion: @escaping (_ fieldId: String, _ resultingUrl: String, _ indexInArray: Int?) -> Void
    ) {
        guard let url = URL(string: "\(APIClient.baseURL)/forms/refresh-attachment-url") else {
            print("[AttachmentRefresh] Field '\(fieldId)': Invalid base URL for refresh endpoint.")
            DispatchQueue.main.async { completion(fieldId, fileKey, originalIndexInArray) } // Call completion with original key
            group.leave()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let params = ["fileKey": fileKey]
        
        do {
            request.httpBody = try JSONEncoder().encode(params)
        } catch {
            print("[AttachmentRefresh] Field '\(fieldId)': Error encoding params for key '\(fileKey)': \(error)")
            DispatchQueue.main.async { completion(fieldId, fileKey, originalIndexInArray) } // Call completion with original key
            group.leave()
            return
        }

        // print("[AttachmentRefresh] Field '\(fieldId)': Calling API for key: '\(fileKey)', URL: \(url)") // Less verbose

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { group.leave() }
            var resultingUrl = fileKey // Default to original key on failure

            if let error = error {
                print("[AttachmentRefresh] Field '\(fieldId)': Network error for key '\(fileKey)': \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let data = data {
                    do {
                        let json = try JSONDecoder().decode([String: String].self, from: data)
                        if let newFileUrl = json["fileUrl"] {
                            resultingUrl = newFileUrl
                        } else {
                            print("[AttachmentRefresh] Field '\(fieldId)': 'fileUrl' key missing in JSON response for key '\(fileKey)'. Data: \(String(data: data, encoding: .utf8) ?? "empty")")
                        }
                    } catch {
                        print("[AttachmentRefresh] Field '\(fieldId)': JSON decoding error for key '\(fileKey)': \(error.localizedDescription). Data: \(String(data: data, encoding: .utf8) ?? "empty")")
                    }
                } else {
                    print("[AttachmentRefresh] Field '\(fieldId)': HTTP Error for key '\(fileKey)'. Status: \(httpResponse.statusCode). Data: \(String(data: data ?? Data(), encoding: .utf8) ?? "empty")")
                }
            } else {
                print("[AttachmentRefresh] Field '\(fieldId)': No HTTPResponse for key '\(fileKey)'.")
            }
            
            // Call the completion handler with the outcome on the main thread
            DispatchQueue.main.async {
                completion(fieldId, resultingUrl, originalIndexInArray)
            }
        }.resume()
    }
    // MARK: - End Attachment URL Refreshing
}

// MARK: - Field Rendering Views
// ... many lines of old TextFieldDisplay, YesNoNAFieldDisplay, SubheadingDisplay, AttachmentDisplay, renderFormField ...
// ... up to the line just before Previews ...

struct FormSubmissionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FormSubmissionDetailView(submissionId: 1, projectId: 1, token: "sample_token", projectName: "Sample Project")
        }
    }
}

// MARK: - PDF Generation

struct FormSubmissionPDFView: View {
    let submission: FormSubmission
    let projectName: String
    let responses: [String: FormResponseValue]

    @MainActor
    func generatePdfData() -> Data? {
        let renderer = ImageRenderer(content: self)
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData) else {
            return nil
        }

        renderer.render { size, contextRenderer in
            var mediaBox = CGRect(origin: .zero, size: size)
            
            guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return
            }
            
            pdfContext.beginPDFPage(nil)
            
            // Corrected call to the renderer function
            contextRenderer(pdfContext)
            
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }

        if pdfData.length > 0 {
            return pdfData as Data
        }
        
        return nil
    }

    // Simplified date formatter for PDF
    private func formatDate(_ string: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, yyyy, h:mm a"
            return displayFormatter.string(from: date)
        }
        return string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(submission.templateTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Project: \(projectName)")
                .font(.title3)
                .foregroundColor(.gray)
            
            Divider().padding(.vertical, 5)

            HStack {
                Text(submission.formNumber != nil ? "Form #\(submission.formNumber!)" : "Submission #\(submission.id)")
                Spacer()
                Text(submission.status.capitalized)
                    .fontWeight(.medium)
            }.font(.headline)

            HStack {
                Image(systemName: "person.fill")
                Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName)")
            }.font(.subheadline).foregroundColor(.gray)
            
            HStack {
                Image(systemName: "calendar")
                Text(formatDate(submission.submittedAt))
            }.font(.subheadline).foregroundColor(.gray)

            Divider().padding(.vertical, 5)
            
            Text("Form Responses")
                .font(.title.bold())
                .padding(.bottom, 5)

            ForEach(submission.fields, id: \.id) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label)
                        .font(.headline)
                        .fontWeight(.bold)

                    // Display the response value
                    if let responseValue = responses[field.id] {
                        // Handle different field types for PDF output
                        switch field.type {
                        case "camera", "signature", "files":
                            Text("[Attachment: \(responseValue.stringValue.split(separator: ",").count) file(s)]")
                                .font(.body)
                                .foregroundColor(.gray)
                        default:
                            Text(responseValue.stringValue)
                                .font(.body)
                        }
                    } else {
                        Text("No response")
                            .foregroundColor(.gray)
                            .font(.body)
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
        .padding() // Add padding for the entire content
        .foregroundColor(.black) // Ensure all text is black for PDF
        .background(Color.white) // Ensure PDF has a white background
    }
}

// A helper view to render individual field responses for the PDF
struct PDFFieldResponseView: View {
    let field: FormField
    let value: FormResponseValue?

    var body: some View {
        // This will need to be expanded to properly display all types, 
        // including images and lists of attachments for the PDF.
        // For now, it will be similar to TextFieldDisplay but more basic.
        switch value {
        case .string(let stringValue):
            Text(stringValue.isEmpty ? "-" : stringValue)
        case .stringArray(let values):
            if values.isEmpty {
                Text("-")
            } else {
                VStack(alignment: .leading) {
                    ForEach(values, id: \.self) { val in
                        Text("- \(val)")
                    }
                }
            }
        case .null, .none:
            Text("-") // Placeholder for not provided
        }
    }
}

extension View {
    func generatePdfData(for submission: FormSubmission, projectName: String, responses: [String: FormResponseValue]) -> Data? {
        // Use FormSubmissionPDFView as the content for the PDF
        // Ensure the PDF view itself has a defined frame for layout within the hosting controller
        let pdfContentView = FormSubmissionPDFView(submission: submission, projectName: projectName, responses: responses)
            .background(Color.white) // Ensure a non-transparent background for the PDF content itself
            .padding() // Add some padding to see bounds

        let a4Rect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 paper size

        let hostingController = UIHostingController(
            rootView: pdfContentView
        )
        
        guard let uiView = hostingController.view else {
            print("PDF Error: Hosting controller view is nil")
            return nil
        }

        // Set an explicit frame for the hosting controller's view based on A4 width.
        // Height will be determined by content, up to a reasonable maximum for a single page or initial layout.
        let targetSize = CGSize(width: a4Rect.width, height: CGFloat.greatestFiniteMagnitude)
        let fittedSize = hostingController.sizeThatFits(in: targetSize)
        
        // Ensure the size has non-zero width and height
        let viewWidth = a4Rect.width
        let viewHeight = max(fittedSize.height, 100) // Use a minimum height if fittedSize is zero
        
        uiView.bounds = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
        uiView.frame = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
        uiView.backgroundColor = .white // Explicitly set background for the hosting view

        // Force layout update
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight))

        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            uiView.layer.render(in: context.cgContext)
        }
        
        if data.isEmpty {
            print("PDF Error: Generated PDF data is empty. View size: w:\(viewWidth) h:\(viewHeight)")
        }
        return data.isEmpty ? nil : data // Return nil if data is empty
    }
}

// MARK: - Supporting UI Components

struct InfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
    }
}

struct ModernFormFieldCard: View {
    let field: FormField
    let response: [String: FormResponseValue]
    let onImageTap: (_ urls: [URL], _ index: Int) -> Void
    @State private var isShowingFullResponse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldIcon(for: field.type)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text(field.label)
                    .font(.headline)
                Spacer()
            }

            let responseValue = response[String(field.id)]
            let responseText = getResponseText(from: responseValue)

            Group {
                if field.type == .signature, let urlString = getSignatureURL(from: responseValue), let url = URL(string: urlString) {
                    KFImage(url)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                } else if field.type == .photo, let urls = getURLs(from: responseValue), !urls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                                Button(action: {
                                    self.onImageTap(urls, index)
                                }) {
                                    KFImage(url)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(8)
                                        .clipped()
                                }
                            }
                        }
                    }
                } else {
                    Text(responseText)
                        .foregroundColor(Color.primary)
                        .font(.body)
                        .lineLimit(isShowingFullResponse ? nil : 3)
                        .onTapGesture {
                            if responseText.count > 100 { // Only make it tappable if the text is long
                                withAnimation {
                                    isShowingFullResponse.toggle()
                                }
                            }
                        }
                }
            }
            .padding(.leading, 30) // Indent the response content
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func getResponseText(from response: FormResponseValue?) -> String {
        guard let response = response else { return "No response" }
        
        switch response {
        case .string(let str):
            return str.isEmpty ? "No response" : str
        case .array(let arr):
            return arr.isEmpty ? "No response" : arr.joined(separator: ", ")
        }
    }

    private func getSignatureURL(from response: FormResponseValue?) -> String? {
        guard let response = response else { return nil }
        if case .string(let urlString) = response {
            return urlString
        }
        return nil
    }
    
    private func getURLs(from response: FormResponseValue?) -> [URL]? {
        guard let response = response else { return nil }
        
        let urlStrings: [String]
        switch response {
        case .string(let str):
            // Handles both single URL and comma-separated URLs
            urlStrings = str.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        case .array(let arr):
            urlStrings = arr
        }
        
        return urlStrings.compactMap { URL(string: $0) }
    }

    @ViewBuilder
    private func fieldIcon(for type: FormField.FieldType) -> some View {
        switch type {
        case .text, .textarea:
            Image(systemName: "text.alignleft")
        case .yesNoNA:
            Image(systemName: "checkmark.circle")
        case .photo:
            Image(systemName: "photo.on.rectangle")
        case .attachment:
            Image(systemName: "paperclip")
        case .dropdown:
            Image(systemName: "chevron.down.square")
        case .checkbox:
            Image(systemName: "checkmark.square")
        case .radio:
            Image(systemName: "dot.square")
        case .signature:
            Image(systemName: "signature")
        case .input:
            Image(systemName: "keyboard")
        case .subheading:
            Image(systemName: "text.below.background")
        }
    }
}

struct YesNoNABadge: View {
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorForAnswer(value))
                .frame(width: 12, height: 12)
            Text(formatAnswer(value))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(colorForAnswer(value))
            Spacer()
        }
        .padding(12)
        .background(colorForAnswer(value).opacity(0.1))
        .cornerRadius(8)
    }

    private func formatAnswer(_ answer: String) -> String {
        switch answer.lowercased() {
        case "yes": return "Yes"
        case "no": return "No"
        case "na": return "N/A"
        default: return "No response"
        }
    }

    private func colorForAnswer(_ answer: String) -> Color {
        switch answer.lowercased() {
        case "yes": return .green
        case "no": return .red
        case "na": return .orange
        default: return .secondary
        }
    }
}

struct ImagePreview: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                VStack {
                    ProgressView()
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
            case .failure:
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Failed to load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            @unknown default:
                EmptyView()
            }
        }
    }
}

struct FieldTypeIndicator: View {
    let type: String
    
    private var config: (icon: String, color: Color) {
        switch type {
        case "text", "textarea": return ("text.alignleft", .blue)
        case "yesNoNA": return ("checkmark.circle", .green)
        case "attachment": return ("paperclip", .orange)
        case "image", "camera", "signature": return ("camera", .purple)
        case "dropdown", "radio": return ("list.bullet", .indigo)
        case "checkbox": return ("checkmark.square", .teal)
        default: return ("questionmark.circle", .gray)
        }
    }
    
    var body: some View {
        Image(systemName: config.icon)
            .font(.caption)
            .foregroundColor(config.color)
            .padding(6)
            .background(config.color.opacity(0.1))
            .clipShape(Circle())
    }
}

struct ModernFormFieldContent: View {
    let field: FormField
    let value: FormResponseValue?
    
    var body: some View {
        switch field.type {
        case "text", "textarea", "number", "phone", "email":
            ModernTextContent(value: value)
        case "yesNoNA":
            ModernYesNoNAContent(value: value)
        case "attachment":
            ModernAttachmentContent(value: value)
        case "image", "camera", "signature":
            ModernImageContent(field: field, value: value)
        case "subheading":
            ModernSubheadingContent(field: field)
        default:
            ModernTextContent(value: value)
        }
    }
}

struct ModernTextContent: View {
    let value: FormResponseValue?
    
    var body: some View {
        switch value {
        case .string(let text):
            if text.isEmpty {
                EmptyResponseView()
            } else {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        case .stringArray(let arr):
            if arr.isEmpty {
                EmptyResponseView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(arr, id: \.self) { item in
                        HStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                            Text(item)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        case .null, .none:
            EmptyResponseView()
        }
    }
}

struct ModernYesNoNAContent: View {
    let value: FormResponseValue?
    
    var body: some View {
        switch value {
        case .string(let answer):
            HStack(spacing: 12) {
                Circle()
                    .fill(colorForAnswer(answer))
                    .frame(width: 12, height: 12)
                Text(formatAnswer(answer))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(colorForAnswer(answer))
                Spacer()
            }
            .padding(12)
            .background(colorForAnswer(answer).opacity(0.1))
            .cornerRadius(8)
        default:
            EmptyResponseView()
        }
    }
    
    private func formatAnswer(_ answer: String) -> String {
        switch answer.lowercased() {
        case "yes": return "Yes"
        case "no": return "No"
        case "na": return "N/A"
        default: return "No response"
        }
    }
    
    private func colorForAnswer(_ answer: String) -> Color {
        switch answer.lowercased() {
        case "yes": return .green
        case "no": return .red
        case "na": return .orange
        default: return .secondary
        }
    }
}

struct ModernAttachmentContent: View {
    let value: FormResponseValue?
    
    var body: some View {
        switch value {
        case .stringArray(let files):
            if files.isEmpty {
                EmptyResponseView()
            } else {
                VStack(spacing: 8) {
                    ForEach(files, id: \.self) { fileUrl in
                        if !fileUrl.isEmpty {
                            AttachmentRow(fileUrl: fileUrl)
                        }
                    }
                }
            }
        case .string(let file):
            if file.isEmpty {
                EmptyResponseView()
            } else {
                AttachmentRow(fileUrl: file)
            }
        default:
            EmptyResponseView()
        }
    }
}

struct AttachmentRow: View {
    let fileUrl: String
    
    var body: some View {
        Link(destination: URL(string: fileUrl)!) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text((fileUrl as NSString).lastPathComponent)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("Tap to open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct ModernImageContent: View {
    let field: FormField
    let value: FormResponseValue?
    
    var body: some View {
        switch value {
        case .string(let imageUrl):
            if imageUrl.isEmpty {
                EmptyResponseView()
            } else {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                } placeholder: {
                    VStack {
                        ProgressView()
                        Text("Loading image...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        default:
            EmptyResponseView()
        }
    }
}

struct ModernSubheadingContent: View {
    let field: FormField
    
    var body: some View {
        Text(field.label)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.primary)
            .padding(.vertical, 8)
    }
}

struct EmptyResponseView: View {
    var body: some View {
        HStack {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("No response provided")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct InfoItem: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
        }
    }
}

struct EmptyResponsesCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Responses")
                .font(.headline)
                .fontWeight(.medium)
            Text("This form submission contains no response data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

// Updated StatusBadge
//struct StatusBadge: View {
//    let status: String
//    
//    private var statusColor: Color {
//        switch status.lowercased() {
//        case "submitted": return .blue
//        case "draft": return .orange
//        case "approved": return .green
//        case "rejected": return .red
//        default: return .gray
//        }
//    }
//    
//    var body: some View {
//        Text(status.capitalized)
//            .font(.caption)
//            .fontWeight(.semibold)
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(statusColor.opacity(0.15))
//            .foregroundColor(statusColor)
//            .cornerRadius(20)
//    }
//}

// MARK: - Helper Extension for FormResponseValue
extension FormResponseValue {
    var stringValue: String {
        switch self {
        case .string(let str):
            return str
        case .stringArray(let arr):
            return arr.joined(separator: ", ")
        case .null:
            return ""
        }
    }

    var stringArrayValue: [String] {
        switch self {
        case .string(let str):
            // Handle comma-separated strings for multi-image fields
            return str.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .stringArray(let arr):
            return arr
        case .null:
            return []
        }
    }
}

// MARK: - UI Components for Form Fields

struct SubheadingCard: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.vertical, 8)
            Spacer()
        }
        .padding(.top, 16)
    }
}

// MARK: - Enlarged Image View
struct EnlargedImageView: View {
    @Environment(\.dismiss) var dismiss
    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)

            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5).clipShape(Circle()))
            }
            .padding()
        }
    }
}
