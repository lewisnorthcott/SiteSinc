import SwiftUI
import WebKit

struct DrawingListView: View {
    let projectId: Int
    let token: String
    @State private var drawings: [Drawing] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    @State private var isOfflineModeEnabled: Bool = false

    enum SortOption { case name, date, revisionCount }

    var body: some View {
        ZStack {
            mainContent
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Companies for Project \(projectId)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section {
                        Button("Sort by Name") { sortOption = .name }
                        Button("Sort by Latest Revision") { sortOption = .date }
                        Button("Sort by Revision Count") { sortOption = .revisionCount }
                    }
                    Section {
                        Toggle("Offline Mode", isOn: $isOfflineModeEnabled)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            fetchDrawings()
            isOfflineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        }
        .onChange(of: isOfflineModeEnabled) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "offlineMode_\(projectId)")
            if newValue {
                downloadAllDrawings()
            } else {
                clearOfflineData()
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack {
                if isLoading {
                    ProgressView("Loading Drawings...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if filteredCompanies.isEmpty {
                    Text("No companies found for Project ID \(projectId)")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(filteredCompanies, id: \.self) { companyName in
                        NavigationLink(destination: CompanyDrawingsView(
                            companyName: companyName,
                            drawings: drawings.filter { $0.company?.name == companyName },
                            token: token,
                            onRefresh: fetchDrawings
                        )) {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.blue)
                                Text(companyName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                // Offline status icon for the company (based on any drawing's offline status)
                                if let anyDrawing = drawings.first(where: { $0.company?.name == companyName }),
                                   checkOfflineStatus(for: anyDrawing) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .imageScale(.small)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                        .imageScale(.small)
                                }
                                Text("\(drawings.filter { $0.company?.name == companyName }.count) drawings")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        fetchDrawings()
                    }
                }
            }
        }
    }

    private var groupedDrawings: [String: [Drawing]] {
        Dictionary(grouping: drawings, by: { $0.company?.name ?? "Unknown Company" })
    }

    private var filteredCompanies: [String] {
        let sortedKeys = groupedDrawings.keys.sorted { (a, b) in
            switch sortOption {
            case .name:
                return a < b
            case .date:
                let aLatest = groupedDrawings[a]?.flatMap { $0.revisions }.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber ?? 0
                let bLatest = groupedDrawings[b]?.flatMap { $0.revisions }.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber ?? 0
                return aLatest > bLatest
            case .revisionCount:
                return (groupedDrawings[a]?.count ?? 0) > (groupedDrawings[b]?.count ?? 0)
            }
        }
        if searchText.isEmpty {
            return sortedKeys
        } else {
            return sortedKeys.filter { companyName in
                companyName.lowercased().contains(searchText.lowercased()) ||
                groupedDrawings[companyName]?.contains(where: {
                    $0.title.lowercased().contains(searchText.lowercased()) ||
                    $0.number.lowercased().contains(searchText.lowercased())
                }) ?? false
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
                    drawings = d.map { drawing in
                        var updatedDrawing = drawing
                        updatedDrawing.isOffline = checkOfflineStatus(for: drawing)
                        return updatedDrawing
                    }
                    if d.isEmpty {
                        print("No drawings returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(d.count) drawings for projectId: \(projectId)")
                    }
                case .failure(let error):
                    errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                    print("Error fetching drawings: \(error)")
                }
            }
        }
    }

    private func downloadAllDrawings() {
        isLoading = true
        errorMessage = nil
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true, attributes: nil)
            var completedDownloads = 0
            let totalFiles = drawings.flatMap { $0.revisions.flatMap { $0.drawingFiles } }.count

            for (drawingIndex, drawing) in drawings.enumerated() {
                for (revisionIndex, revision) in drawing.revisions.enumerated() {
                    for (fileIndex, _) in revision.drawingFiles.enumerated() {
                        let localPath = projectFolder.appendingPathComponent(drawing.revisions[revisionIndex].drawingFiles[fileIndex].fileName)
                        APIClient.downloadFile(from: drawing.revisions[revisionIndex].drawingFiles[fileIndex].downloadUrl, to: localPath) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    completedDownloads += 1
                                    if completedDownloads == totalFiles {
                                        isLoading = false
                                        var updatedDrawings = drawings
                                        let updatedDrawing = Drawing(
                                            id: drawing.id,
                                            title: drawing.title,
                                            number: drawing.number,
                                            projectId: drawing.projectId,
                                            status: drawing.status,
                                            createdAt: drawing.createdAt,
                                            updatedAt: drawing.updatedAt,
                                            revisions: drawing.revisions.enumerated().map { (index, rev) in
                                                if index == revisionIndex {
                                                    return Revision(
                                                        id: rev.id,
                                                        versionNumber: rev.versionNumber,
                                                        status: rev.status,
                                                        drawingFiles: rev.drawingFiles.enumerated().map { (fileIdx, file) in
                                                            if fileIdx == fileIndex {
                                                                var updatedFile = file
                                                                updatedFile.localPath = localPath
                                                                return updatedFile
                                                            }
                                                            return file
                                                        },
                                                        createdAt: rev.createdAt,
                                                        revisionNumber: rev.revisionNumber
                                                    )
                                                }
                                                return rev
                                            },
                                            company: drawing.company,
                                            discipline: drawing.discipline,
                                            projectDiscipline: drawing.projectDiscipline,
                                            projectDrawingType: drawing.projectDrawingType,
                                            isOffline: true
                                        )
                                        updatedDrawings[drawingIndex] = updatedDrawing
                                        drawings = updatedDrawings
                                        print("All drawings downloaded for project \(projectId)")
                                    }
                                case .failure(let error):
                                    errorMessage = "Failed to download file: \(error.localizedDescription)"
                                    isLoading = false
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                errorMessage = "Failed to create directory: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func clearOfflineData() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: projectFolder.path) {
                try FileManager.default.removeItem(at: projectFolder)
                drawings = drawings.map { drawing in
                    var updatedDrawing = drawing
                    updatedDrawing.isOffline = false
                    return updatedDrawing
                }
                print("Offline data cleared for project \(projectId)")
            }
        } catch {
            print("Error clearing offline data: \(error)")
        }
    }

    private func checkOfflineStatus(for drawing: Drawing) -> Bool {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)
        return drawing.revisions.flatMap { $0.drawingFiles }.allSatisfy { file in
            guard let localPath = file.localPath else { return false }
            let fullPath = projectFolder.appendingPathComponent(localPath.lastPathComponent)
            return FileManager.default.fileExists(atPath: fullPath.path)
        }
    }
}

// View for a specific company's drawings
struct CompanyDrawingsView: View {
    let companyName: String
    let drawings: [Drawing]
    let token: String
    let onRefresh: () -> Void
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)

            if drawings.isEmpty {
                Text("No drawings found for \(companyName)")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollViewReader { proxy in
                    List(filteredDrawings, id: \.id) { drawing in
                        NavigationLink(destination: PDFView(drawing: drawing)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(drawing.title)
                                        .font(.headline)
                                    Text(drawing.number)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                                        Text("Latest Revision: \(latestRevision.revisionNumber ?? "N/A")")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                // Offline status icon for the drawing
                                if drawing.isOffline! {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .imageScale(.small)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                        .imageScale(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .id(drawing.id)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        onRefresh()
                    }
                }
                .onAppear {
                    print("Drawings count: \(drawings.count)")
                    let dateFormatter = ISO8601DateFormatter()
                    filteredDrawings.forEach { drawing in
                        let latestFile = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })?
                            .drawingFiles.max(by: {
                                let date0 = dateFormatter.date(from: $0.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                                let date1 = dateFormatter.date(from: $1.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                                return date0 < date1
                            })
                        print("Drawing \(drawing.title): \(latestFile?.createdAt ?? "N/A")")
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("\(companyName) Drawings")
    }

    private var filteredDrawings: [Drawing] {
        let dateFormatter = ISO8601DateFormatter()
        let sortedDrawings = drawings.sorted { (drawing1: Drawing, drawing2: Drawing) in
            let latestRev1 = drawing1.revisions.max(by: { $0.versionNumber < $1.versionNumber })
            let latestRev2 = drawing2.revisions.max(by: { $0.versionNumber < $1.versionNumber })
            let latestFile1 = latestRev1?.drawingFiles.max(by: {
                let date0 = dateFormatter.date(from: $0.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                let date1 = dateFormatter.date(from: $1.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                return date0 < date1
            })
            let latestFile2 = latestRev2?.drawingFiles.max(by: {
                let date0 = dateFormatter.date(from: $0.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                let date1 = dateFormatter.date(from: $1.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
                return date0 < date1
            })
            let date1 = dateFormatter.date(from: latestFile1?.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
            let date2 = dateFormatter.date(from: latestFile2?.createdAt ?? "1970-01-01T00:00:00Z") ?? Date.distantPast
            print("Comparing \(drawing1.title): \(date1) vs \(drawing2.title): \(date2)")
            return date1 > date2
        }
        
        if searchText.isEmpty {
            return sortedDrawings
        } else {
            return sortedDrawings.filter {
                $0.title.lowercased().contains(searchText.lowercased()) ||
                $0.number.lowercased().contains(searchText.lowercased())
            }
        }
    }
}
// PDF View to display the latest revision with swipe-up revisions
struct PDFView: View {
    let drawing: Drawing
    @State private var selectedRevision: Revision?

    var body: some View {
        VStack {
            ZStack {
                if let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                   let latestFile = revision.drawingFiles.first {
                    WebView(url: URL(string: latestFile.downloadUrl)!)
                        .onAppear {
                            print("Loading PDF for drawing \(drawing.id), Revision \(revision.versionNumber), URL: \(latestFile.downloadUrl)")
                        }
                } else {
                    Text("No PDF available for this drawing")
                        .onAppear {
                            print("No revisions or files for drawing \(drawing.id). Revisions: \(drawing.revisions.count)")
                        }
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
                }
            }

            if !drawing.revisions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(drawing.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                            Button(action: {
                                withAnimation {
                                    selectedRevision = revision
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
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
                .shadow(radius: 2)
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
            }
        }
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
            print("Failed to load PDF: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Failed to start loading PDF: \(error)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Successfully loaded PDF")
        }
    }
}

#Preview {
    DrawingListView(projectId: 2, token: "sample-token")
}
