import SwiftUI
import WebKit
import SwiftData

struct RFIsView: View {
    let projectId: Int
    let token: String
    @State private var unifiedRFIs: [UnifiedRFI] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .title
    @Environment(\.modelContext) private var modelContext

    enum SortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case date = "Date"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("RFIs")
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundColor(.black)
                    .padding(.top, 16)

                HStack {
                    TextField("Search", text: $searchText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                    .padding(.leading, 8)
                                Spacer()
                            }
                        )
                }

                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 24)

                if isLoading {
                    ProgressView("Loading RFIs...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else if filteredUnifiedRFIs.isEmpty {
                    Text("No RFIs available")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredUnifiedRFIs) { unifiedRFI in
                                NavigationLink(destination: destinationView(for: unifiedRFI)) {
                                    RFIRow(unifiedRFI: unifiedRFI)
                                        .background(
                                            Color.white
                                                .cornerRadius(8)
                                                .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
                                        )
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(ScaleButtonStyle()) // Custom button style for visual feedback
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollIndicators(.visible)
                    .refreshable {
                        fetchRFIs()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchRFIs()
        }
    }

    private func destinationView(for unifiedRFI: UnifiedRFI) -> some View {
        if unifiedRFI.draftObject != nil {
            return AnyView(RFIDraftDetailView(draft: unifiedRFI.draftObject!, token: token, onSubmit: { draft in
                submitDraft(draft)
            }))
        } else {
            return AnyView(RFIDetailView(rfi: unifiedRFI.serverRFI!, token: token))
        }
    }

    private var filteredUnifiedRFIs: [UnifiedRFI] {
        var sortedRFIs = unifiedRFIs
        switch sortOption {
        case .title:
            sortedRFIs.sort(by: { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() })
        case .date:
            sortedRFIs.sort(by: { rfi1, rfi2 in
                let date1 = ISO8601DateFormatter().date(from: rfi1.createdAt ?? "") ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: rfi2.createdAt ?? "") ?? Date.distantPast
                return date1 > date2
            })
        }
        if searchText.isEmpty {
            return sortedRFIs
        } else {
            return sortedRFIs.filter {
                ($0.title ?? "").lowercased().contains(searchText.lowercased()) ||
                String($0.number).lowercased().contains(searchText.lowercased())
            }
        }
    }

    private struct RFIRow: View {
        let unifiedRFI: UnifiedRFI

        var body: some View {
            HStack {
                Circle()
                    .fill(unifiedRFI.status?.lowercased() == "open" ? Color.green : (unifiedRFI.status?.lowercased() == "draft" ? Color.orange : Color.blue.opacity(0.2)))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(unifiedRFI.title ?? "Untitled RFI")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    Text(unifiedRFI.number == 0 ? "Draft" : "RFI-\(unifiedRFI.number)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                .padding(.leading, 8)

                Spacer()

                Text(unifiedRFI.status?.uppercased() ?? "UNKNOWN")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(unifiedRFI.status?.lowercased() == "draft" ? .orange : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((unifiedRFI.status?.lowercased() == "draft" ? Color.orange : Color.blue).opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .accessibilityLabel("RFI \(unifiedRFI.number == 0 ? "Draft" : "Number \(unifiedRFI.number)"), Title: \(unifiedRFI.title ?? "Untitled RFI"), Status: \(unifiedRFI.status?.uppercased() ?? "UNKNOWN")")
        }
    }

    private func fetchRFIs() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        let drafts = (try? modelContext.fetch(fetchDescriptor)) ?? []
        let draftRFIs = drafts.map { UnifiedRFI.draft($0) }

        isLoading = true
        errorMessage = nil
        APIClient.fetchRFIs(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let r):
                    let serverRFIs = r.map { UnifiedRFI.server($0) }
                    unifiedRFIs = draftRFIs + serverRFIs
                    saveRFIsToCache(r)
                    if r.isEmpty {
                        print("No RFIs returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(r.count) RFIs for projectId: \(projectId)")
                    }
                    syncDrafts()
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        if let cachedRFIs = loadRFIsFromCache() {
                            unifiedRFIs = draftRFIs + cachedRFIs.map { UnifiedRFI.server($0) }
                            errorMessage = "Loaded cached RFIs (offline mode)"
                        } else {
                            unifiedRFIs = draftRFIs
                            errorMessage = "No internet connection and no cached data available"
                        }
                    } else {
                        unifiedRFIs = draftRFIs
                        errorMessage = "Failed to load RFIs: \(error.localizedDescription)"
                        print("Error fetching RFIs: \(error)")
                    }
                }
            }
        }
    }

    private func saveRFIsToCache(_ rfis: [RFI]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rfis) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }

    private func loadRFIsFromCache() -> [RFI]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedRFIs = try? decoder.decode([RFI].self, from: data) {
                print("Loaded \(cachedRFIs.count) RFIs from cache for project \(projectId)")
                return cachedRFIs
            }
        }
        return nil
    }

    private func syncDrafts() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        guard let drafts = try? modelContext.fetch(fetchDescriptor), !drafts.isEmpty else { return }
        
        for draft in drafts {
            submitDraft(draft)
        }
    }

    private func submitDraft(_ draft: RFIDraft) {
        var uploadedFiles: [[String: Any]] = []
        let group = DispatchGroup()
        var uploadError: String?

        let fileURLs = draft.selectedFiles.compactMap { URL(fileURLWithPath: $0) }
        for fileURL in fileURLs {
            group.enter()
            guard let data = try? Data(contentsOf: fileURL) else {
                uploadError = "Failed to read file data"
                group.leave()
                continue
            }
            let fileName = fileURL.lastPathComponent
            let url = URL(string: "\(APIClient.baseURL)/rfis/upload-file")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            let boundaryPrefix = "--\(boundary)\r\n"
            body.append(boundaryPrefix.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                if let error = error {
                    uploadError = "Failed to upload file: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let fileData: UploadedFileResponse = try? JSONDecoder().decode(UploadedFileResponse.self, from: data) else {
                    uploadError = "Failed to decode upload response"
                    return
                }
                uploadedFiles.append([
                    "fileUrl": fileData.fileUrl,
                    "fileName": fileData.fileName,
                    "fileType": fileData.fileType
                ])
            }.resume()
        }

        group.notify(queue: .main) {
            if let uploadError = uploadError {
                self.errorMessage = uploadError
                return
            }

            let body: [String: Any] = [
                "title": draft.title,
                "query": draft.query,
                "description": draft.query,
                "projectId": draft.projectId,
                "managerId": draft.managerId!,
                "assignedUserIds": draft.assignedUserIds,
                "returnDate": draft.returnDate?.ISO8601Format() ?? "",
                "attachments": uploadedFiles,
                "drawings": draft.selectedDrawings.map { ["drawingId": $0.drawingId, "revisionId": $0.revisionId] }
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                self.errorMessage = "Failed to encode request"
                return
            }

            let url = URL(string: "\(APIClient.baseURL)/rfis")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = "Failed to sync draft RFI: \(error.localizedDescription)"
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
                        self.errorMessage = "Failed to sync draft RFI: Invalid response"
                        return
                    }

                    self.modelContext.delete(draft)
                    try? self.modelContext.save()
                    fetchRFIs()
                }
            }.resume()
        }
    }
}

struct RFIDetailView: View {
    let rfi: RFI
    let token: String

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text(rfi.title ?? "Untitled RFI")
                        .font(.title2)
                        .fontWeight(.regular)
                        .foregroundColor(.black)

                    Text("RFI-\(rfi.number)")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Status: \(rfi.status?.uppercased() ?? "UNKNOWN")")
                        .font(.subheadline)
                        .foregroundColor(rfi.status?.lowercased() == "open" ? .green : .blue)

                    if let createdAt = rfi.createdAt {
                        Text("Created: \(ISO8601DateFormatter().date(from: createdAt)?.formatted() ?? createdAt)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Created: Unknown")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    if let description = rfi.description {
                        Text("Description: \(description)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Description: Not provided")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    if let query = rfi.query {
                        Text("Query: \(query)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Query: Not provided")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    if let attachments = rfi.attachments, !attachments.isEmpty {
                        Text("Attachments")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.top, 8)

                        ForEach(attachments, id: \.id) { attachment in
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let fullPath = documentsDirectory.appendingPathComponent("Project_\(rfi.projectId)/rfis/\(attachment.fileName)")
                            VStack(alignment: .leading) {
                                if FileManager.default.fileExists(atPath: fullPath.path) {
                                    WebView(url: fullPath)
                                        .frame(height: 300)
                                        .cornerRadius(8)
                                        .accessibilityLabel("Attachment \(attachment.fileName)")
                                } else if let url = URL(string: attachment.downloadUrl ?? attachment.fileUrl) {
                                    WebView(url: url)
                                        .frame(height: 300)
                                        .cornerRadius(8)
                                        .accessibilityLabel("Attachment \(attachment.fileName)")
                                } else {
                                    Text("Attachment unavailable: \(attachment.fileName)")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Spacer()
                }
                .padding(24)
            }
        }
        .navigationTitle("RFI Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RFIDraftDetailView: View {
    let draft: RFIDraft
    let token: String
    let onSubmit: (RFIDraft) -> Void

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text(draft.title)
                        .font(.title2)
                        .fontWeight(.regular)
                        .foregroundColor(.black)

                    Text("Draft RFI")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Status: Draft")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                    Text("Created: \(ISO8601DateFormatter().date(from: ISO8601DateFormatter().string(from: draft.createdAt))?.formatted() ?? ISO8601DateFormatter().string(from: draft.createdAt))")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Description: \(draft.query)")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Query: \(draft.query)")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if !draft.selectedDrawings.isEmpty {
                        Text("Selected Drawings")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.top, 8)

                        ForEach(draft.selectedDrawings) { drawing in
                            Text("\(drawing.number) - Rev \(drawing.revisionNumber)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.vertical, 2)
                        }
                    }

                    if !draft.selectedFiles.isEmpty {
                        Text("Attachments")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.top, 8)

                        ForEach(draft.selectedFiles, id: \.self) { filePath in
                            let fileURL = URL(fileURLWithPath: filePath)
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let fullPath = documentsDirectory.appendingPathComponent("Project_\(draft.projectId)/rfis/\(fileURL.lastPathComponent)")
                            VStack(alignment: .leading) {
                                if FileManager.default.fileExists(atPath: fullPath.path) {
                                    WebView(url: fullPath)
                                        .frame(height: 300)
                                        .cornerRadius(8)
                                        .accessibilityLabel("Attachment \(fileURL.lastPathComponent)")
                                } else if FileManager.default.fileExists(atPath: fileURL.path) {
                                    WebView(url: fileURL)
                                        .frame(height: 300)
                                        .cornerRadius(8)
                                        .accessibilityLabel("Attachment \(fileURL.lastPathComponent)")
                                } else {
                                    Text("Attachment unavailable: \(fileURL.lastPathComponent)")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button("Submit Draft") {
                        onSubmit(draft)
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)

                    Spacer()
                }
                .padding(24)
            }
        }
        .navigationTitle("Draft RFI Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0
        webView.scrollView.bouncesZoom = true
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        webView.isUserInteractionEnabled = true
        webView.configuration.suppressesIncrementalRendering = false
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Failed to load content: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Failed to start loading content: \(error)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Successfully loaded content")
        }
    }
}

// Custom button style for visual feedback on tap
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        RFIsView(projectId: 1, token: "sample_token")
    }
}

enum UnifiedRFI: Identifiable {
    case server(RFI)
    case draft(RFIDraft)

    var id: Int {
        switch self {
        case .server(let rfi):
            return rfi.id
        case .draft(let draft):
            return draft.id.uuidString.hashValue // Convert UUID to Int using hashValue
        }
    }

    var title: String? {
        switch self {
        case .server(let rfi):
            return rfi.title
        case .draft(let draft):
            return draft.title
        }
    }

    var number: Int {
        switch self {
        case .server(let rfi):
            return rfi.number
        case .draft:
            return 0
        }
    }

    var status: String? {
        switch self {
        case .server(let rfi):
            return rfi.status
        case .draft:
            return "Draft"
        }
    }

    var createdAt: String? {
        switch self {
        case .server(let rfi):
            return rfi.createdAt
        case .draft(let draft):
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: draft.createdAt)
        }
    }

    var query: String? {
        switch self {
        case .server(let rfi):
            return rfi.query
        case .draft(let draft):
            return draft.query
        }
    }

    var description: String? {
        switch self {
        case .server(let rfi):
            return rfi.description
        case .draft(let draft):
            return draft.query
        }
    }

    var attachments: [RFI.RFIAttachment]? {
        switch self {
        case .server(let rfi):
            return rfi.attachments
        case .draft:
            return nil
        }
    }

    var projectId: Int {
        switch self {
        case .server(let rfi):
            return rfi.projectId
        case .draft(let draft):
            return draft.projectId
        }
    }

    var draftObject: RFIDraft? {
        switch self {
        case .server:
            return nil
        case .draft(let draft):
            return draft
        }
    }

    var serverRFI: RFI? {
        switch self {
        case .server(let rfi):
            return rfi
        case .draft:
            return nil
        }
    }

    var selectedDrawings: [SelectedDrawing] {
        switch self {
        case .server:
            return []
        case .draft(let draft):
            return draft.selectedDrawings
        }
    }
}
