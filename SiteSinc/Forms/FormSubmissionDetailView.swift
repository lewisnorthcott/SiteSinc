import SwiftUI
import PDFKit // Needed for PDF generation if using UIGraphicsPDFRenderer directly

class GalleryDataStore: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedIndex: Int = 0
    @Published var isPresented: Bool = false
    
    func setData(urls: [URL], selectedIndex: Int) {
        self.urls = urls
        self.selectedIndex = selectedIndex
        self.isPresented = true
    }
    
    func dismiss() {
        self.isPresented = false
    }
}

struct IdentifiableURL: Identifiable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        self.id = url.absoluteString
    }
}

struct CloseoutResponseDetailView: View {
    let closeoutData: FormSubmission.CloseoutResponseValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Closeout Information")
                .font(.headline)
                .fontWeight(.bold)
            
            if let status = closeoutData.status {
                HStack {
                    Text("Status:")
                        .fontWeight(.medium)
                    Text(status.capitalized)
                        .foregroundColor(statusColor(for: status))
                }
            }
            
            if let notes = closeoutData.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes:")
                        .fontWeight(.medium)
                    Text(notes)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }
            }
            
            if let signature = closeoutData.signature, !signature.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signature:")
                        .fontWeight(.medium)
                    
                    if let data = Data(base64Encoded: signature),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .background(Color.white)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .cornerRadius(6)
                    } else {
                        HStack {
                            Image(systemName: "signature")
                                .foregroundColor(.blue)
                            Text("Signature provided")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if let photos = closeoutData.photos, !photos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photos (\(photos.count)):")
                        .fontWeight(.medium)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(photos, id: \.self) { photoURLString in
                                AsyncImage(url: URL(string: photoURLString)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(8)
                                } placeholder: {
                                    VStack {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                        Text("Loading...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 80, height: 80)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "completed": return .green
        case "pending", "closeout_submitted": return .orange
        case "rejected": return .red
        default: return .secondary
        }
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
    @StateObject private var galleryStore = GalleryDataStore()
    @State private var attachmentPathMap: [String: String] = [:]

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
                                        Image(systemName: "folder.fill")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                        Text(folderDisplayName(for: submission))
                                            .font(.callout)
                                            .foregroundColor(.secondary)
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
                                            response: refreshedResponses[field.id],
                                            refreshedResponses: refreshedResponses,
                                            attachmentPathMap: attachmentPathMap,
                                            onImageTap: { urls, index in
                                                galleryStore.setData(urls: urls, selectedIndex: index)
                                            },
                                            galleryStore: galleryStore
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
        .fullScreenCover(isPresented: $galleryStore.isPresented) {
            ImageGalleryView(urls: galleryStore.urls, selectedIndex: galleryStore.selectedIndex)
        }
        .onAppear {
            fetchSubmission()
        }
    }

    private func folderDisplayName(for submission: FormSubmission) -> String {
        if let name = submission.folder?.name { return name }
        if let id = submission.folderId { return "Folder #\(id)" }
        return projectName
    }

    private func fetchSubmission() {
        isLoading = true
        errorMessage = nil
        Task {
            let isOffline = !NetworkStatusManager.shared.isNetworkAvailable
            let isOfflineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
            
            if isOffline && isOfflineModeEnabled {
                print("FormSubmissionDetailView: Offline mode detected. Loading from cache.")
                self.attachmentPathMap = self.loadAttachmentPathMapFromCache()
                if let cachedSubmissions = loadSubmissionsFromCache(), let submission = cachedSubmissions.first(where: { $0.id == submissionId }) {
                    await handleSuccessfulFetch(submission)
                } else {
                    await handleFetchError("Could not find this submission in the offline cache. Please sync online.")
                }
                return
            }

            do {
                let submissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
                if let fetchedSubmission = submissions.first(where: { $0.id == submissionId }) {
                    await handleSuccessfulFetch(fetchedSubmission)
                } else {
                    await handleFetchError("Submission not found on server.")
                }
            } catch APIError.tokenExpired {
                await MainActor.run { sessionManager.handleTokenExpiration() }
            } catch {
                if let cachedSubmissions = loadSubmissionsFromCache(), let submission = cachedSubmissions.first(where: { $0.id == submissionId }) {
                    print("FormSubmissionDetailView: Network failed. Loading from cache as fallback.")
                    await handleSuccessfulFetch(submission)
                } else {
                    await handleFetchError(error.localizedDescription)
                }
            }
        }
    }
    
    private func loadSubmissionsFromCache() -> [FormSubmission]? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("form_submissions_project_\(projectId).json")
        guard let data = try? Data(contentsOf: cacheURL) else {
            print("FormSubmissionDetailView: No cache file found at \(cacheURL.path)")
            return nil
        }
        do {
            let submissions = try JSONDecoder().decode([FormSubmission].self, from: data)
            print("FormSubmissionDetailView: Successfully decoded \(submissions.count) submissions from cache.")
            return submissions
        } catch {
            print("FormSubmissionDetailView: FAILED to decode submissions from cache. Error: \(error)")
            return nil
        }
    }
    
    private func loadAttachmentPathMapFromCache() -> [String: String] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("form_attachment_paths_\(projectId).json")
        guard let data = try? Data(contentsOf: cacheURL) else {
            print("FormSubmissionDetailView: No attachment path map cache file found.")
            return [:]
        }
        do {
            let map = try JSONDecoder().decode([String: String].self, from: data)
            print("FormSubmissionDetailView: Loaded attachment path map with \(map.count) entries.")
            return map
        } catch {
            print("FormSubmissionDetailView: FAILED to decode attachment path map. Error: \(error)")
            return [:]
        }
    }
    
    private func handleSuccessfulFetch(_ submission: FormSubmission) async {
        await MainActor.run {
            self.submission = submission
            let initialResponses = submission.responses ?? [:]
            self.refreshedResponses = initialResponses
            refreshAttachmentURLs(fields: submission.fields, responses: initialResponses)
            self.isLoading = false
        }
    }
    
    private func handleFetchError(_ message: String) async {
        await MainActor.run {
            self.errorMessage = message
            self.isLoading = false
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
                        localUpdatedResponses[processedFieldId] = .string(newUrl)
                        print("[AttachmentRefresh] Field '\(processedFieldId)': Single key updated in localUpdatedResponses to: \(newUrl)")
                    }
                } else {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Skipping refresh for single key (already URL or no pattern match): \(fileKey)")
                }
                
            case .camera(let cameraData):
                if shouldRefreshToken(cameraData.image) {
                    hasPendingRefreshes = true
                    group.enter()
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Refreshing camera image key: \(cameraData.image)")
                    fetchAndReplaceToken(forKey: cameraData.image, fieldId: field.id, originalIndexInArray: nil, group: group) { (processedFieldId, newUrl, _) in
                        var updatedCameraData = cameraData
                        updatedCameraData.image = newUrl
                        localUpdatedResponses[processedFieldId] = .camera(updatedCameraData)
                        print("[AttachmentRefresh] Field '\(processedFieldId)': Camera image updated in localUpdatedResponses to: \(newUrl)")
                    }
                } else {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Skipping refresh for camera image (already URL or no pattern match): \(cameraData.image)")
                }

            case .stringArray(let fileKeys):
                print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Processing stringArray with \(fileKeys.count) keys.")
                var anItemInArrayNeededRefresh = false

                for (index, key) in fileKeys.enumerated() {
                    if shouldRefreshToken(key) {
                        hasPendingRefreshes = true
                        anItemInArrayNeededRefresh = true
                        group.enter()
                        print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)) [\(index)]: Refreshing array key: \(key)")
                        fetchAndReplaceToken(forKey: key, fieldId: field.id, originalIndexInArray: index, group: group) { (processedFieldId, newUrl, idxOptional) in
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

            case .closeout(let closeoutData):
                print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Closeout response. Processing photos and signature.")
                let closeoutKeys: [String] = (closeoutData.photos ?? []) + (closeoutData.signature.map { [$0] } ?? [])

                if closeoutKeys.isEmpty {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): No photos or signature in closeout data to refresh.")
                    break
                }
                
                var anItemInCloseoutNeededRefresh = false
                for (idx, key) in closeoutKeys.enumerated() {
                    if shouldRefreshToken(key) {
                        hasPendingRefreshes = true
                        anItemInCloseoutNeededRefresh = true
                        group.enter()
                        fetchAndReplaceToken(forKey: key, fieldId: field.id, originalIndexInArray: idx, group: group) { processedFieldId, newUrl, indexInArray in
                            guard let arrayIndex = indexInArray else { return }

                            if let existingResponse = localUpdatedResponses[processedFieldId], case .closeout(var updatedCloseoutData) = existingResponse {
                                if updatedCloseoutData.photos?.contains(key) == true, let photoIndex = updatedCloseoutData.photos?.firstIndex(of: key) {
                                    updatedCloseoutData.photos?[photoIndex] = newUrl
                                } else if updatedCloseoutData.signature == key {
                                    updatedCloseoutData.signature = newUrl
                                }
                                localUpdatedResponses[processedFieldId] = .closeout(updatedCloseoutData)
                                print("[AttachmentRefresh] Field '\(processedFieldId)' [\(arrayIndex)] CLOSEOUT: Updated to '\(newUrl)'.")
                            } else {
                                print("[AttachmentRefresh] Field '\(processedFieldId)' [\(arrayIndex)] CLOSEOUT: CRITICAL ERROR - Expected closeout in localUpdatedResponses but found something else or nil.")
                            }
                        }
                    }
                }
                if anItemInCloseoutNeededRefresh {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Closeout items were processed for potential refresh.")
                }
            case .cameraArray(let cameraValues):
                var newCameraValues = cameraValues
                var refreshNeededForArray = false

                for (index, value) in cameraValues.enumerated() {
                    if shouldRefreshToken(value.image) {
                        hasPendingRefreshes = true
                        refreshNeededForArray = true
                        group.enter()
                        fetchAndReplaceToken(forKey: value.image, fieldId: field.id, originalIndexInArray: index, group: group) { (processedFieldId, newUrl, originalIndex) in
                            if let idx = originalIndex {
                                newCameraValues[idx].image = newUrl
                                if localUpdatedResponses[processedFieldId]?.stringArrayValue.filter({ shouldRefreshToken($0) }).isEmpty ?? true {
                                    localUpdatedResponses[processedFieldId] = .cameraArray(newCameraValues)
                                }
                            }
                        }
                    }
                }
                if !refreshNeededForArray {
                    print("[AttachmentRefresh] Field '\(field.id)' (\(field.label)): Skipping refresh for camera array (all keys are URLs or no pattern match)")
                }
            case .int, .double, .repeater, .null:
                // These types do not contain refreshable attachment tokens, so we ignore them.
                break
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
                            PDFFieldResponseView(field: field, value: responseValue)
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
        case .int(let intValue):
            Text(String(intValue))
        case .double(let doubleValue):
            Text(String(doubleValue))
        case .repeater(let repeaterData):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(repeaterData.enumerated()), id: \.offset) { index, rowData in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Row \(index + 1):")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ForEach(Array(rowData.keys.sorted()), id: \.self) { key in
                            if let value = rowData[key] {
                                Text("  \(key): \(getDisplayValue(for: value))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        case .closeout(let closeoutData):
            CloseoutResponseDetailView(closeoutData: closeoutData)
        case .camera(_):
            Text("[Photo with location]")
                .foregroundColor(.gray)
                .font(.body)
        case .cameraArray(let cameraArray):
            Text("[\(cameraArray.count) photo(s) with location]")
                .foregroundColor(.gray)
                .font(.body)
        case .null, .none:
            Text("-") // Placeholder for not provided
        }
    }
    
    private func getDisplayValue(for value: FormResponseValue) -> String {
        switch value {
        case .string(let str): return str.isEmpty ? "-" : str
        case .stringArray(let arr): return arr.isEmpty ? "-" : arr.joined(separator: ", ")
        case .int(let intValue): return String(intValue)
        case .double(let doubleValue): return String(doubleValue)
        case .repeater(let repeaterData): return "Nested repeater (\(repeaterData.count) items)"
        case .closeout(_): return "Closeout data"
        case .camera(_): return "Photo with location"
        case .cameraArray(let cameraArray): return "\(cameraArray.count) photo(s) with location"
        case .null: return "-"
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
    let response: FormResponseValue?
    let refreshedResponses: [String: FormResponseValue]
    let attachmentPathMap: [String: String]
    let onImageTap: (_ urls: [URL], _ index: Int) -> Void
    let galleryStore: GalleryDataStore?
    @State private var isShowingFullResponse = false

    private var isImageField: Bool {
        ["image", "attachment", "camera", "signature"].contains(field.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldIcon(for: field.type)
                    .font(Font.headline)
                    .foregroundColor(Color.accentColor)
                Text(field.label)
                    .font(Font.headline)
                Spacer()
            }

            let responseText = getResponseText(from: response)

            Group {
                if isImageField || containsImageURL(responseText) {
                    if let response = response, let urls = getURLs(from: response), !urls.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if field.type.lowercased().contains("signature") || urls.count == 1 {
                                // Single image display (signatures or single photos)
                                Button(action: {
                                    self.onImageTap(urls, 0)
                                }) {
                                    AsyncImage(url: urls.first!) { image in
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(height: 100)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                }
                            } else {
                                // Multiple images display
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                                            Button(action: {
                                                self.onImageTap(urls, index)
                                            }) {
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
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Show location data for camera fields
                            if field.type == "camera", case .camera(let cameraData) = response, let location = cameraData.location {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Location: \(String(format: "%.6f", location.latitude)), \(String(format: "%.6f", location.longitude))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let accuracy = location.accuracy {
                                            Text("Accuracy: ±\(Int(accuracy))m")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(6)
                            }
                            
                            // Show location data for camera arrays
                            if field.type == "camera", case .cameraArray(let cameraArray) = response, !cameraArray.isEmpty {
                                VStack(spacing: 4) {
                                    ForEach(Array(cameraArray.enumerated()), id: \.offset) { index, cameraData in
                                        if let location = cameraData.location {
                                            HStack(spacing: 12) {
                                                Image(systemName: "location.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    if cameraArray.count > 1 {
                                                        Text("Photo \(index + 1) Location:")
                                                            .font(.caption2)
                                                            .fontWeight(.medium)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text("Location: \(String(format: "%.6f", location.latitude)), \(String(format: "%.6f", location.longitude))")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    if let accuracy = location.accuracy {
                                                        Text("Accuracy: ±\(Int(accuracy))m")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.05))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text("No image available")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                } else if field.type == "subheading" {
                    ModernSubheadingContent(field: field)
                } else if field.type == "repeater" {
                    ModernFormFieldContent(field: field, value: response, galleryStore: galleryStore)
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
        case .stringArray(let arr):
            return arr.isEmpty ? "No response" : arr.joined(separator: ", ")
        case .int(let intValue):
            return String(intValue)
        case .double(let doubleValue):
            return String(doubleValue)
        case .repeater(let repeaterData):
            return "Repeater data (\(repeaterData.count) items)"
        case .closeout(_):
            return "Closeout data"
        case .camera(let cameraData):
            if let location = cameraData.location {
                return "Photo with location (lat: \(String(format: "%.6f", location.latitude)), lon: \(String(format: "%.6f", location.longitude)))"
            } else {
                return "Photo"
            }
        case .cameraArray(let cameraArray):
            if cameraArray.count == 1 {
                let cameraData = cameraArray[0]
                if let location = cameraData.location {
                    return "Photo with location (lat: \(String(format: "%.6f", location.latitude)), lon: \(String(format: "%.6f", location.longitude)))"
                } else {
                    return "Photo"
                }
            } else {
                return "\(cameraArray.count) Photos"
            }
        case .null:
            return "No response"
        }
    }

    private func getSignatureURL(from response: FormResponseValue?) -> String? {
        guard let response = response else { return nil }
        if case .string(let urlString) = response {
            return urlString
        }
        return nil
    }
    
    private func getURLs(from value: FormResponseValue?) -> [URL]? {
        guard let value = value else { return nil }
        
        let isOffline = !NetworkStatusManager.shared.isNetworkAvailable
        let keys: [String] = {
            switch value {
            case .string(let str):
                return [str]
            case .stringArray(let arr):
                return arr
            case .camera(let cameraData):
                return [cameraData.image]
            case .cameraArray(let cameraArray):
                return cameraArray.map { $0.image }
            case .closeout(let closeoutData):
                return (closeoutData.photos ?? []) + (closeoutData.signature.map { [$0] } ?? [])
            default:
                return []
            }
        }()
        
        let urls = keys.compactMap { key -> URL? in
            if isOffline {
                if let localPath = attachmentPathMap[key] {
                    return URL(fileURLWithPath: localPath)
                } else {
                    return nil
                }
            } else {
                // First check if we have a refreshed response for this field
                if let refreshedValue = refreshedResponses[field.id] {
                    let refreshedKeys = refreshedValue.stringArrayValue
                    
                    // Try to find a matching refreshed URL
                    for refreshedKey in refreshedKeys {
                        if refreshedKey.contains(key) || key.contains(refreshedKey) {
                            if let url = URL(string: refreshedKey) {
                                return url
                            }
                        }
                    }
                    
                    // If no match found, use the refreshed keys in order
                    if let index = keys.firstIndex(of: key), index < refreshedKeys.count {
                        if let url = URL(string: refreshedKeys[index]) {
                            return url
                        }
                    }
                }
                
                // Fallback to original key if it's already a valid URL
                if let url = URL(string: key) {
                    return url
                }
                
                return nil
            }
        }
        
        return urls.isEmpty ? nil : urls
    }
    
    private func isImageField(type: String) -> Bool {
        let imageTypes = ["signature", "photo", "image", "camera", "attachment"]
        return imageTypes.contains { type.lowercased().contains($0) }
    }
    
    private func containsImageURL(_ text: String) -> Bool {
        // Check if the text contains URLs that might be images
        let lowercased = text.lowercased()
        return (lowercased.contains("http") || lowercased.contains("www.")) && 
               (lowercased.contains(".jpg") || lowercased.contains(".jpeg") || 
                lowercased.contains(".png") || lowercased.contains(".gif") || 
                lowercased.contains(".webp") || lowercased.contains("sites-inc") ||
                lowercased.contains("amazonaws") || lowercased.contains("blob"))
    }

    @ViewBuilder
    private func fieldIcon(for type: String) -> some View {
        switch type {
        case "text", "textarea":
            Image(systemName: "text.alignleft")
        case "yesNoNA":
            Image(systemName: "checkmark.circle")
        case "photo":
            Image(systemName: "photo.on.rectangle")
        case "attachment":
            Image(systemName: "paperclip")
        case "dropdown":
            Image(systemName: "chevron.down.square")
        case "checkbox":
            Image(systemName: "checkmark.square")
        case "radio":
            Image(systemName: "dot.square")
        case "signature":
            Image(systemName: "signature")
        case "input":
            Image(systemName: "keyboard")
        case "subheading":
            Image(systemName: "text.below.background")
        default:
            Image(systemName: "questionmark.circle")
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
    let galleryStore: GalleryDataStore?
    
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
        case "repeater":
            if case .repeater(let repeaterData) = value {
                ModernRepeaterContent(repeaterData: repeaterData, field: field, galleryStore: galleryStore)
            } else {
                EmptyResponseView()
            }
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
        case .int(let intValue):
            Text(String(intValue))
                .font(.body)
                .foregroundColor(.primary)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        case .double(let doubleValue):
            Text(String(doubleValue))
                .font(.body)
                .foregroundColor(.primary)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        case .repeater(_):
            EmptyResponseView()
        case .closeout(let closeoutData):
            CloseoutResponseDetailView(closeoutData: closeoutData)
        case .camera(let cameraData):
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo captured")
                    .font(.body)
                    .foregroundColor(.primary)
                if let location = cameraData.location {
                    Text("Location: \(location.latitude), \(location.longitude)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        case .cameraArray(let cameraArray):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(cameraArray.count) photo(s) captured")
                    .font(.body)
                    .foregroundColor(.primary)
                if let firstLocation = cameraArray.first?.location {
                    Text("First photo location: \(firstLocation.latitude), \(firstLocation.longitude)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if cameraArray.count > 1 {
                    Text("+ \(cameraArray.count - 1) more photo(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
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
        case .int(_):
            EmptyResponseView()
        case .double(_):
            EmptyResponseView()
        case .repeater(_):
            EmptyResponseView()
        case .closeout:
            EmptyResponseView()
        case .camera(_):
            EmptyResponseView()
        case .stringArray(_), .cameraArray(_):
            EmptyResponseView()
        case .null, .none:
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
        case .stringArray(_):
            EmptyResponseView()
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

// MARK: - Helper Extension for FormResponseValue removed (already defined in APIClient.swift)

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

// MARK: - Image Gallery View
struct ImageGalleryView: View {
    @Environment(\.dismiss) var dismiss
    let urls: [URL]
    let selectedIndex: Int
    @State private var currentIndex: Int
    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
    init(urls: [URL], selectedIndex: Int) {
        self.urls = urls
        self.selectedIndex = selectedIndex
        self.currentIndex = selectedIndex
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if urls.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                    Text("No Images Available")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("The image URLs could not be loaded")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        GeometryReader { geometry in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Loading...")
                                            .foregroundColor(.white)
                                            .padding(.top)
                                        Text("URL: \(url.absoluteString)")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                            .padding(.top, 4)
                                    }
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .scaleEffect(scale)
                                        .offset(dragOffset)
                                        .gesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    scale = value
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.spring()) {
                                                        if scale < 1 {
                                                            scale = 1
                                                        } else if scale > 3 {
                                                            scale = 3
                                                        }
                                                    }
                                                }
                                                .simultaneously(with:
                                                    DragGesture()
                                                        .onChanged { value in
                                                            dragOffset = value.translation
                                                        }
                                                        .onEnded { _ in
                                                            withAnimation(.spring()) {
                                                                dragOffset = .zero
                                                            }
                                                        }
                                                )
                                        )
                                case .failure(let error):
                                    VStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.largeTitle)
                                            .foregroundColor(.yellow)
                                        Text("Failed to load image")
                                            .foregroundColor(.white)
                                            .font(.headline)
                                        Text("Error: \(error.localizedDescription)")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                        Text("URL: \(url.absoluteString)")
                                            .foregroundColor(.white)
                                            .font(.caption2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding()
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        }
                        .tag(index)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                scale = scale == 1 ? 2 : 1
                                dragOffset = .zero
                            }
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            
            // Top overlay with close button and counter
            VStack {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.5).clipShape(Circle()))
                    }
                    
                    Spacer()
                    
                    if urls.count > 1 {
                        Text("\(currentIndex + 1) of \(urls.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(15)
                    }
                }
                .padding()
                
                Spacer()
            }
            
            // Bottom page indicator (only show if more than one image)
            if urls.count > 1 {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        ForEach(0..<urls.count, id: \.self) { index in
                            Circle()
                                .fill(currentIndex == index ? Color.white : Color.white.opacity(0.5))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut, value: currentIndex)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .statusBarHidden()
        .onTapGesture {
            // Single tap to toggle UI (you can implement this if needed)
        }
    }
}

struct ModernRepeaterContent: View {
    let repeaterData: [[String: FormResponseValue]]
    let field: FormField
    let galleryStore: GalleryDataStore?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(repeaterData.enumerated()), id: \.offset) { index, rowData in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Row \(index + 1)")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rowData.keys.sorted()), id: \.self) { fieldKey in
                            if let fieldValue = rowData[fieldKey] {
                                HStack(alignment: .top) {
                                    Text("\(getFieldLabel(for: fieldKey)):")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    
                                    if isImageField(fieldKey: fieldKey) && isImageValue(fieldValue) {
                                        imageDisplayView(for: fieldValue)
                                    } else {
                                        Text(getDisplayValue(for: fieldValue))
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
    }
    
    private func getFieldLabel(for fieldId: String) -> String {
        // Try to find the field label from subFields
        if let subFields = field.subFields {
            if let subField = subFields.first(where: { $0.id == fieldId }) {
                return subField.label
            }
        }
        // Fallback to field ID if no label found
        return fieldId
    }
    
    private func isImageField(fieldKey: String) -> Bool {
        // Check if this field is an image type based on the subFields
        if let subFields = field.subFields,
           let subField = subFields.first(where: { $0.id == fieldKey }) {
            let imageTypes = ["signature", "image", "camera", "attachment"]
            return imageTypes.contains { subField.type.lowercased().contains($0) }
        }
        return false
    }
    
    private func isImageValue(_ value: FormResponseValue) -> Bool {
        switch value {
        case .string(let str):
            return str.hasPrefix("data:image/") || str.contains("http") || str.contains("amazonaws") || str.contains("sitesinc")
        case .stringArray(let arr):
            return arr.contains { $0.hasPrefix("data:image/") || $0.contains("http") }
        default:
            return false
        }
    }
    
    @ViewBuilder
    private func imageDisplayView(for value: FormResponseValue) -> some View {
        if let urls = getImageURLs(from: value), !urls.isEmpty {
            if urls.count == 1 {
                singleImageView(urls: urls)
            } else {
                multipleImagesView(urls: urls)
            }
        } else {
            noImageView
        }
    }
    
    @ViewBuilder
    private func singleImageView(urls: [URL]) -> some View {
        Button(action: {
            galleryStore?.setData(urls: urls, selectedIndex: 0)
        }) {
            singleImageContent(url: urls.first!)
        }
    }
    
    @ViewBuilder 
    private func singleImageContent(url: URL) -> some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            ProgressView()
        }
        .frame(height: 60)
        .frame(maxWidth: 120)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    @ViewBuilder
    private func multipleImagesView(urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    multipleImageButton(url: url, index: index, urls: urls)
                }
            }
        }
    }
    
    @ViewBuilder
    private func multipleImageButton(url: URL, index: Int, urls: [URL]) -> some View {
        Button(action: {
            galleryStore?.setData(urls: urls, selectedIndex: index)
        }) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ProgressView()
                    .frame(width: 40, height: 40)
            }
            .frame(width: 40, height: 40)
            .cornerRadius(6)
            .clipped()
        }
    }
    
    @ViewBuilder
    private var noImageView: some View {
        Text("No image available")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    private func getImageURLs(from value: FormResponseValue) -> [URL]? {
        switch value {
        case .string(let str):
            if str.hasPrefix("data:image/") {
                // Handle base64 image
                return [URL(string: str)].compactMap { $0 }
            } else if let url = URL(string: str) {
                return [url]
            }
            return nil
        case .stringArray(let arr):
            return arr.compactMap { urlString in
                if urlString.hasPrefix("data:image/") {
                    return URL(string: urlString)
                } else {
                    return URL(string: urlString)
                }
            }
        default:
            return nil
        }
    }
    
    private func getDisplayValue(for value: FormResponseValue) -> String {
        switch value {
        case .string(let str): return str.isEmpty ? "-" : str
        case .stringArray(let arr): return arr.isEmpty ? "-" : arr.joined(separator: ", ")
        case .int(let intValue): return String(intValue)
        case .double(let doubleValue): return String(doubleValue)
        case .repeater(let repeaterData): return "Nested repeater (\(repeaterData.count) items)"
        case .closeout(_): return "Closeout data"
        case .camera(_): return "Photo with location"
        case .cameraArray(let cameraArray): return "\(cameraArray.count) photo(s) with location"
        case .null: return "-"
        }
    }
}
