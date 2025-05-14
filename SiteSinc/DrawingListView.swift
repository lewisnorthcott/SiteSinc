import SwiftUI
import WebKit

struct DrawingListView: View {
    let projectId: Int
    let token: String
    @State private var drawings: [Drawing] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var groupByOption: GroupByOption = .company

    enum GroupByOption: String, CaseIterable, Identifiable {
        case company = "Company"
        case folder = "Folder"
        case discipline = "Discipline"
        case type = "Type"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading Drawings...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .padding()
                } else if let errorMessage = errorMessage {
                    VStack {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                        Button("Retry") {
                            fetchDrawings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .accessibilityLabel("Retry loading drawings")
                    }
                } else if groupKeys.isEmpty {
                    Text("No drawings found for Project \(projectId)")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(groupKeys.sorted(), id: \.self) { groupKey in
                            NavigationLink(destination: FilteredDrawingsView(
                                drawings: filteredDrawings(for: groupKey),
                                groupName: groupKey,
                                token: token,
                                onRefresh: fetchDrawings
                            )) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text(groupKey)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(filteredDrawings(for: groupKey).count)")
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                        .foregroundColor(.blue)
                                        .accessibilityLabel("\(filteredDrawings(for: groupKey).count) drawings")
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        fetchDrawings()
                    }
                }
            }
        }
        .navigationTitle("Drawings for Project \(projectId)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Picker("Group By", selection: $groupByOption) {
                    ForEach(GroupByOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Group drawings by")
            }
        }
        .onAppear {
            fetchDrawings()
        }
    }

    private var groupedDrawings: [String: [Drawing]] {
        switch groupByOption {
        case .company:
            return Dictionary(grouping: drawings, by: { $0.company?.name ?? "Unknown Company" })
        case .folder:
            return Dictionary(grouping: drawings, by: { _ in "Project \(projectId)" })
        case .discipline:
            let hasDiscipline = drawings.contains { $0.projectDiscipline?.name != nil }
            let grouped = Dictionary(grouping: drawings, by: {
                $0.projectDiscipline?.name ?? (hasDiscipline ? "Unknown Discipline" : "No Discipline Available")
            })
            for (key, drawings) in grouped {
                if key == "Unknown Discipline" || key == "No Discipline Available" {
                    print("Drawings with \(key): \(drawings.map { "ID: \($0.id), Title: \($0.title)" }.joined(separator: "; "))")
                }
            }
            return grouped
        case .type:
            let hasType = drawings.contains { $0.projectDrawingType?.name != nil }
            let grouped = Dictionary(grouping: drawings, by: {
                $0.projectDrawingType?.name ?? (hasType ? "Unknown Type" : "No Type Available")
            })
            for (key, drawings) in grouped {
                if key == "Unknown Type" || key == "No Type Available" {
                    print("Drawings with \(key): \(drawings.map { "ID: \($0.id), Title: \($0.title)" }.joined(separator: "; "))")
                }
            }
            return grouped
        }
    }

    private var groupKeys: [String] {
        groupedDrawings.keys.sorted()
    }

    private func filteredDrawings(for groupKey: String) -> [Drawing] {
        drawings.filter { drawing in
            switch groupByOption {
            case .company:
                return drawing.company?.name == groupKey
            case .folder:
                return "Project \(projectId)" == groupKey
            case .discipline:
                return drawing.projectDiscipline?.name == groupKey || (groupKey == "No Discipline Available" && drawing.projectDiscipline?.name == nil)
            case .type:
                return drawing.projectDrawingType?.name == groupKey || (groupKey == "No Type Available" && drawing.projectDrawingType?.name == nil)
            }
        }
    }

    private func fetchDrawings() {
        isLoading = true
        errorMessage = nil
        APIClient.fetchDrawings(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let d):
                    let updatedDrawings = d.map { drawing in
                        var updatedDrawing = drawing
                        updatedDrawing.isOffline = checkOfflineStatus(for: drawing)
                        print("Drawing ID: \(drawing.id), Title: \(drawing.title), Discipline: \(drawing.projectDiscipline?.name ?? "nil"), Type: \(drawing.projectDrawingType?.name ?? "nil")")
                        return updatedDrawing
                    }
                    drawings = updatedDrawings
                    saveDrawingsToCache(updatedDrawings)
                    print("Fetched \(d.count) drawings for projectId: \(projectId)")
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        if let cachedDrawings = loadDrawingsFromCache() {
                            drawings = cachedDrawings.map { drawing in
                                var updatedDrawing = drawing
                                updatedDrawing.isOffline = checkOfflineStatus(for: drawing)
                                return updatedDrawing
                            }
                            errorMessage = "Loaded cached drawings (offline mode)"
                        } else {
                            errorMessage = "No internet connection and no cached data available"
                        }
                    } else {
                        errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                        print("Error fetching drawings: \(error)")
                    }
                }
            }
        }
    }

    private func checkOfflineStatus(for drawing: Drawing) -> Bool {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)/drawings", isDirectory: true)
        return drawing.revisions.flatMap { $0.drawingFiles }.allSatisfy { file in
            guard file.fileName.lowercased().hasSuffix(".pdf") else { return true }
            let fullPath = projectFolder.appendingPathComponent(file.fileName)
            return FileManager.default.fileExists(atPath: fullPath.path)
        }
    }

    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(drawings.count) drawings to cache for project \(projectId)")
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedDrawings = try? decoder.decode([Drawing].self, from: data) {
                print("Loaded \(cachedDrawings.count) drawings from cache for project \(projectId)")
                return cachedDrawings
            }
        }
        return nil
    }
}

struct FilteredDrawingsView: View {
    let drawings: [Drawing]
    let groupName: String
    let token: String
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)

            if drawings.isEmpty {
                Text("No drawings found for \(groupName)")
                    .foregroundColor(.gray)
                    .padding()
                    .accessibilityLabel("No drawings available")
            } else {
                ScrollViewReader { proxy in
                    List(drawings.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }, id: \.id) { drawing in
                        NavigationLink(destination: DrawingGalleryView(drawings: drawings, initialDrawing: drawing)) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(drawing.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(drawing.number)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                                        Text("Rev \(latestRevision.revisionNumber ?? "N/A")")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Image(systemName: drawing.isOffline ?? false ? "cloud.fill" : "cloud")
                                    .foregroundColor(drawing.isOffline ?? false ? .green : .gray)
                                    .accessibilityLabel(drawing.isOffline ?? false ? "Available offline" : "Not available offline")
                                Text("\(drawing.revisions.count)")
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Circle())
                                    .foregroundColor(.blue)
                                    .accessibilityLabel("\(drawing.revisions.count) revisions")
                            }
                            .padding(.vertical, 8)
                            .id(drawing.id)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        onRefresh()
                    }
                }
                .onAppear {
                    print("FilteredDrawingsView appeared with \(drawings.count) drawings for \(groupName)")
                }
            }
        }
        .navigationTitle("\(groupName) Drawings")
        .accessibilityLabel("\(groupName) drawings list")
    }
}

struct DrawingViewer: View {
    let drawing: Drawing
    @State private var selectedRevision: Revision?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    if let pdfFile = revision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) {
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let fullPath = documentsDirectory.appendingPathComponent("Project_\(drawing.projectId)/drawings/\(pdfFile.fileName)")
                        if FileManager.default.fileExists(atPath: fullPath.path) {
                            WebView(url: fullPath)
                                .accessibilityLabel("PDF view of drawing \(drawing.title), revision \(revision.versionNumber)")
                        } else {
                            WebView(url: URL(string: pdfFile.downloadUrl)!)
                                .accessibilityLabel("PDF view of drawing \(drawing.title), revision \(revision.versionNumber)")
                        }
                    } else {
                        VStack {
                            Text("Unsupported file format: \(revision.drawingFiles.first?.fileName ?? "Unknown")")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text("This drawing has no PDF version available.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("Please use an external app (e.g., AutoCAD Mobile) to view DWG files.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    Text("No drawing files available")
                        .foregroundColor(.gray)
                        .accessibilityLabel("No files available for drawing \(drawing.title)")
                }

                if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                   let current = selectedRevision,
                   current.versionNumber != latest.versionNumber {
                    VStack {
                        Text("Not the Latest Revision (Current: \(current.versionNumber), Latest: \(latest.versionNumber))")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .accessibilityLabel("Not the latest revision, current \(current.versionNumber), latest \(latest.versionNumber)")
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        guard !drawing.revisions.isEmpty else { return }
                        let sortedRevisions = drawing.revisions.sorted { $0.versionNumber > $1.versionNumber }
                        let current = selectedRevision ?? sortedRevisions.first!
                        guard let index = sortedRevisions.firstIndex(where: { $0.id == current.id }) else { return }

                        if value.translation.height < -50 {
                            if index > 0 {
                                withAnimation(.easeInOut) {
                                    selectedRevision = sortedRevisions[index - 1]
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }
                        } else if value.translation.height > 50 {
                            if index < sortedRevisions.count - 1 {
                                withAnimation(.easeInOut) {
                                    selectedRevision = sortedRevisions[index + 1]
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }
                        }
                    }
            )

            if !drawing.revisions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(drawing.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    selectedRevision = revision
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }) {
                                VStack {
                                    Text("Rev \(revision.versionNumber)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Text(revision.status)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    (selectedRevision?.id == revision.id ||
                                     (selectedRevision == nil && revision.versionNumber == drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber))
                                    ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
                                )
                                .cornerRadius(8)
                            }
                            .accessibilityLabel("Select revision \(revision.versionNumber), status \(revision.status)")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
                .shadow(radius: 2)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Revision selector")
            }
        }
        .navigationTitle(drawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(drawing.title)
                        .font(.headline)
                    Text(drawing.number)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Drawing title: \(drawing.title), number: \(drawing.number)")
            }
        }
        .onAppear {
            print("DrawingViewer appeared for drawing \(drawing.id), revisions: \(drawing.revisions.count)")
        }
    }
}

//struct WebView: UIViewRepresentable {
//    let url: URL
//
//    func makeUIView(context: Context) -> WKWebView {
//        let configuration = WKWebViewConfiguration()
//        let webView = WKWebView(frame: .zero, configuration: configuration)
//        webView.navigationDelegate = context.coordinator
//        webView.scrollView.minimumZoomScale = 1.0
//        webView.scrollView.maximumZoomScale = 5.0
//        webView.scrollView.bouncesZoom = true
//        webView.scrollView.isScrollEnabled = true
//        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
//        webView.isUserInteractionEnabled = true
//        webView.configuration.suppressesIncrementalRendering = false
//        return webView
//    }
//
//    func updateUIView(_ uiView: WKWebView, context: Context) {
//        let request = URLRequest(url: url)
//        uiView.load(request)
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    class Coordinator: NSObject, WKNavigationDelegate {
//        let parent: WebView
//
//        init(_ parent: WebView) {
//            self.parent = parent
//        }
//
//        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
//            print("Failed to load content: \(error)")
//        }
//
//        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
//            print("Failed to start loading content: \(error)")
//        }
//
//        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//            print("Successfully loaded content")
//        }
//    }
//}

#Preview {
    DrawingListView(projectId: 2, token: "sample-token")
}
