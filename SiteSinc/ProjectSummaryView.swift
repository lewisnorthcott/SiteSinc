import SwiftUI

struct ProjectSummaryView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @State private var isLoading = false
    @State private var selectedTile: String?
    @State private var isAppearing = false
    @State private var showCreateRFI = false
    @State private var isOfflineModeEnabled: Bool = false
    @State private var downloadProgress: Double = 0.0
    @State private var errorMessage: String?
    @State private var documentCount: Int = 0
    @State private var drawingCount: Int = 0
    @State private var rfiCount: Int = 0
    @State private var projectStatus: String? = nil

    var body: some View {
        ZStack {
            backgroundView
            mainContent
//            FloatingActionButton(showCreateRFI: $showCreateRFI) {
//                Group {
////                    Button(action: { showCreateRFI = true }) {
////                        Label("New RFI", systemImage: "doc.text")
////                    }
//                    Button(action: {
//                        print("Another action for Project Summary page")
//                    }) {
//                        Label("Project Action", systemImage: "gear")
//                    }
//                }
//            }
            loadingView
            errorView
        }
        .toolbar { toolbarContent }
        .onAppear { handleOnAppear() }
        .onChange(of: isOfflineModeEnabled) { handleOfflineModeChange($1) }
//        .sheet(isPresented: $showCreateRFI) { createRFIView }
    }

    // View Components
    private var backgroundView: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerView
                statsOverview
                navigationGrid
            }
            .padding(.vertical, 8)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(projectName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
            if let status = projectStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }
            Text("Project Summary")
                .font(.subheadline)
                .foregroundColor(Color.secondary)
            if isOfflineModeEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                    Text("Offline Mode Enabled")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
    }

    private var statsOverview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                StatCard(
                    title: "Documents",
                    value: "\(documentCount)",
                    trend: "+5",
                    icon: "doc.fill",
                    destination: AnyView(DocumentListView(projectId: projectId, token: token, projectName: projectName))
                )
                .accessibilityLabel("Documents: \(documentCount)")
                StatCard(
                    title: "Drawings",
                    value: "\(drawingCount)",
                    trend: "+12",
                    icon: "square.and.pencil",
                    destination: AnyView(DrawingListView(projectId: projectId, token: token, projectName: projectName))
                )
                .accessibilityLabel("Drawings: \(drawingCount)")
//                StatCard(
//                    title: "RFIs",
//                    value: "\(rfiCount)",
//                    trend: "+2",
//                    icon: "questionmark.circle.fill",
//                    destination: AnyView(RFIsListView(projectId: projectId, token: token, projectName: projectName))
//                )
//                .accessibilityLabel("RFIs: \(rfiCount)")
            }
            .padding(.horizontal, 16)
        }
    }

    private var navigationGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 16
        ) {
            navTile(drawingsTile, id: "Drawings")
            navTile(documentsTile, id: "Documents")
//            navTile(rfisTile, id: "RFIs")
//            navTile(formsTile, id: "Forms")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
    }

    private func navTile<Content: View>(_ content: Content, id: String) -> some View {
        content
            .accessibilityAddTraits(.isButton)
            .scaleEffect(selectedTile == id ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTile)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTile = id
                }
            }
    }

    private var drawingsTile: some View {
        NavigationLink(
            destination: DrawingListView(projectId: projectId, token: token, projectName: projectName)
        ) {
            SummaryTile(
                title: "Drawings",
                subtitle: "Access project drawings",
                icon: "square.and.pencil",
                color: Color.accentColor,
                isSelected: selectedTile == "Drawings"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var documentsTile: some View {
        NavigationLink(
            destination: DocumentListView(projectId: projectId, token: token, projectName: projectName)
        ) {
            SummaryTile(
                title: "Documents",
                subtitle: "Access project documents",
                icon: "doc.fill",
                color: Color.accentColor,
                isSelected: selectedTile == "Documents"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

//    private var rfisTile: some View {
//        NavigationLink(
//            destination: RFIsListView(projectId: projectId, token: token, projectName: projectName)
//        ) {
//            SummaryTile(
//                title: "RFIs",
//                subtitle: "Manage information requests",
//                icon: "questionmark.circle.fill",
//                color: Color.accentColor,
//                isSelected: selectedTile == "RFIs"
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//
//    private var formsTile: some View {
//        NavigationLink(
//            destination: FormsView(projectId: projectId, token: token, projectName: projectName)
//        ) {
//            SummaryTile(
//                title: "Forms",
//                subtitle: "View and submit forms",
//                icon: "doc.text.fill",
//                color: Color.accentColor,
//                isSelected: selectedTile == "Forms"
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }

    private var loadingView: some View {
        Group {
            if isLoading && downloadProgress > 0 && downloadProgress < 1 {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView("Downloading Data", value: downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color.accentColor))
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                }
            }
        }
    }

    private var errorView: some View {
        Group {
            if let errorMessage = errorMessage {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            if isOfflineModeEnabled { downloadAllResources() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 8)
                }
            }
        }
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Toggle(isOn: $isOfflineModeEnabled) {
                Image(systemName: isOfflineModeEnabled ? "cloud.fill" : "cloud")
                    .foregroundColor(isOfflineModeEnabled ? Color.green : Color.secondary)
            }
            .accessibilityLabel("Toggle offline mode")
        }
    }

//    private var createRFIView: some View {
//        CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
//            showCreateRFI = false
//        })
//    }

    // Actions
    private func handleOnAppear() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isAppearing = true
        }
        isOfflineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)") //

        Task {
            if isOfflineModeEnabled { //
                // Attempt to load from cache first
                let loadedFromCache = await loadSummaryDataFromCache()
                if loadedFromCache {
                    // Optionally, you could try a silent background update here if network is available
                    // but the UI is already populated.
                    // For now, we'll just rely on the cache when offline.
                    // If you want to try to update, make sure to handle errors gracefully
                    // and not overwrite the errorMessage if cache loading was successful.
                    print("Successfully loaded summary data from cache.")
                    // Potentially try to refresh in background without blocking UI or showing errors over cached data
                    // await refreshDataFromNetworkGracefully()
                    return // Exit if cache load was sufficient for offline display
                } else {
                    // Cache loading failed, or no cache found, set an appropriate message or proceed to network
                    print("Could not load summary data from cache or cache is empty.")
                    // If you expect data to be there, this could be an error state
                }
            }

            // If not offline, or if cache loading failed and want to try network
            do {
                // These API calls are for the summary counts.
                // The full lists for offline use are fetched in downloadAllResources.
                let documents = try await APIClient.fetchDocuments(projectId: projectId, token: token)
                let drawings = try await APIClient.fetchDrawings(projectId: projectId, token: token)
                // let rfis = try await APIClient.fetchRFIs(projectId: projectId, token: token)
                await MainActor.run {
                    documentCount = documents.count //
                    drawingCount = drawings.count //
                    // rfiCount = rfis.count
                    errorMessage = nil // Clear previous errors if network call succeeds
                }
            } catch {
                await MainActor.run {
                    // Only show this error if not in offline mode OR if cache loading also failed
                    if !isOfflineModeEnabled { // Or if you determined cache should have existed but didn't
                        errorMessage = "Failed to load summary: \(error.localizedDescription)" //
                    } else {
                        // If offline and network fails, rely on the (potentially empty) cache state
                        // or a specific "could not refresh offline data" message.
                        // For now, if cache load failed, this error will be masked if we don't set it.
                        // The key is that counts should reflect cached data if available.
                        print("Network fetch in onAppear failed while offline: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // You'll need to implement these cache loading functions
    private func loadSummaryDataFromCache() async -> Bool {
        // Example for drawings:
        if let cachedDrawings = loadDrawingsFromCache() { // Assuming loadDocumentsFromCache exists
            await MainActor.run {
                self.drawingCount = cachedDrawings.count
                // Load other counts (RFIs, etc.)
                self.errorMessage = nil // Clear errors if cache is successfully loaded
            }
            return true
        }
        return false
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let drawings = try? JSONDecoder().decode([Drawing].self, from: data) {
            print("Loaded \(drawings.count) drawings from cache for project \(projectId)")
            return drawings
        }
        print("Failed to load drawings from cache or cache file does not exist for project \(projectId)")
        return nil
    }

    private func handleOfflineModeChange(_ newValue: Bool) {
        UserDefaults.standard.set(newValue, forKey: "offlineMode_\(projectId)")
        if newValue {
            downloadAllResources()
        } else {
            clearOfflineData()
        }
    }

    // Helpers
    private func downloadAllResources() {
        isLoading = true
        errorMessage = nil
        downloadProgress = 0.0
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)
        
        Task {
            do {
                try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true, attributes: nil)
                
                let drawingsResult = await fetchDrawings()
                guard case .success(let drawingsData) = drawingsResult else {
                    switch drawingsResult {
                    case .failure(let error):
                        await MainActor.run {
                            errorMessage = "Failed to fetch drawings: \(error.localizedDescription)"
                            isLoading = false
                        }
                    case .success:
                        break
                    }
                    return
                }
                
                let rfisResult = await fetchRFIs()
                guard case .success(let rfisData) = rfisResult else {
                    switch rfisResult {
                    case .failure(let error):
                        await MainActor.run {
                            errorMessage = "Failed to fetch RFIs: \(error.localizedDescription)"
                            isLoading = false
                        }
                    case .success:
                        break
                    }
                    return
                }
                
                let formsResult = await fetchForms()
                guard case .success(let formsData) = formsResult else {
                    switch formsResult {
                    case .failure(let error):
                        await MainActor.run {
                            errorMessage = "Failed to fetch forms: \(error.localizedDescription)"
                            isLoading = false
                        }
                    case .success:
                        break
                    }
                    return
                }
                
                let drawingFiles = drawingsData.flatMap { drawing in
                    drawing.revisions.flatMap { revision in
                        revision.drawingFiles.filter { $0.fileName.lowercased().hasSuffix(".pdf") }.map { file in
                            (file: file, localPath: projectFolder.appendingPathComponent("drawings/\(file.fileName)"))
                        }
                    }
                }
                
                let rfiFiles = rfisData.flatMap { rfi in
                    (rfi.attachments ?? []).map { attachment in
                        (file: attachment, localPath: projectFolder.appendingPathComponent("rfis/\(attachment.fileName)"))
                    }
                }
                
                let totalFiles = drawingFiles.count + rfiFiles.count
                guard totalFiles > 0 else {
                    await MainActor.run {
                        isLoading = false
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        print("No files to download for project \(projectId)")
                    }
                    return
                }
                
                var completedDownloads = 0
                
                for (file, localPath) in drawingFiles {
                    do {
                        try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("drawings"), withIntermediateDirectories: true)
                        guard let downloadUrl = file.downloadUrl else {
                            await MainActor.run {
                                completedDownloads += 1
                                downloadProgress = Double(completedDownloads) / Double(totalFiles)
                                if completedDownloads == totalFiles {
                                    isLoading = false
                                    saveDrawingsToCache(drawingsData)
                                    saveRFIsToCache(rfisData)
                                    saveFormsToCache(formsData)
                                    print("Skipped drawing file with no download URL for project \(projectId)")
                                }
                            }
                            continue
                        }
                        let result = await downloadFile(from: downloadUrl, to: localPath)
                        await MainActor.run {
                            switch result {
                            case .success:
                                completedDownloads += 1
                                downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            case .failure(let error):
                                errorMessage = "Failed to download drawing file: \(error.localizedDescription)"
                                isLoading = false
                            }
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to create drawings directory: \(error.localizedDescription)"
                            isLoading = false
                        }
                        return
                    }
                }
                
                for (file, localPath) in rfiFiles {
                    do {
                        try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("rfis"), withIntermediateDirectories: true)
                        let result = await downloadFile(from: file.downloadUrl ?? file.fileUrl, to: localPath)
                        await MainActor.run {
                            switch result {
                            case .success:
                                completedDownloads += 1
                                downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            case .failure(let error):
                                errorMessage = "Failed to download RFI file: \(error.localizedDescription)"
                                isLoading = false
                            }
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to create RFIs directory: \(error.localizedDescription)"
                            isLoading = false
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    if completedDownloads == totalFiles {
                        isLoading = false
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        print("All files downloaded for project \(projectId)")
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create directory: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func fetchDrawings() async -> Result<[Drawing], Error> {
        do {
            let drawings = try await APIClient.fetchDrawings(projectId: projectId, token: token)
            return .success(drawings)
        } catch {
            return .failure(error)
        }
    }

    private func fetchRFIs() async -> Result<[RFI], Error> {
        do {
            let rfis = try await APIClient.fetchRFIs(projectId: projectId, token: token)
            return .success(rfis)
        } catch {
            return .failure(error)
        }
    }

    private func fetchForms() async -> Result<[FormModel], Error> {
        do {
            let forms = try await APIClient.fetchForms(projectId: projectId, token: token)
            return .success(forms)
        } catch {
            return .failure(error)
        }
    }

    private func downloadFile(from urlString: String, to localPath: URL) async -> Result<Void, Error> {
        do {
            try await APIClient.downloadFile(from: urlString, to: localPath)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    private func clearOfflineData() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let drawingsCacheURL = cachesDirectory.appendingPathComponent("drawings_project_\(projectId).json")
        let rfisCacheURL = cachesDirectory.appendingPathComponent("rfis_project_\(projectId).json")
        let formsCacheURL = cachesDirectory.appendingPathComponent("forms_project_\(projectId).json")
        
        do {
            if FileManager.default.fileExists(atPath: projectFolder.path) {
                try FileManager.default.removeItem(at: projectFolder)
            }
            if FileManager.default.fileExists(atPath: drawingsCacheURL.path) {
                try FileManager.default.removeItem(at: drawingsCacheURL)
            }
            if FileManager.default.fileExists(atPath: rfisCacheURL.path) {
                try FileManager.default.removeItem(at: rfisCacheURL)
            }
            if FileManager.default.fileExists(atPath: formsCacheURL.path) {
                try FileManager.default.removeItem(at: formsCacheURL)
            }
            print("Offline data cleared for project \(projectId)")
        } catch {
            print("Error clearing offline data: \(error)")
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
    
    private func saveRFIsToCache(_ rfis: [RFI]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rfis) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }
    
    private func saveFormsToCache(_ forms: [FormModel]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(forms) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("forms_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(forms.count) forms to cache for project \(projectId)")
        }
    }

    struct StatCard: View {
        let title: String
        let value: String
        let trend: String
        let icon: String
        let destination: AnyView

        var body: some View {
            NavigationLink(destination: destination) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(value)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    if !trend.isEmpty {
                        Text(trend)
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(0.98, anchor: .center)
            .animation(.spring(), value: value)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(value), \(trend)")
        }
    }

    struct SummaryTile: View {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        var isSelected: Bool
        
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(color)
                            .shadow(color: color.opacity(0.3), radius: 3, x: 0, y: 1)
                    )
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isSelected ? 0.3 : 0), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
    
    struct ProjectSummaryView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                ProjectSummaryView(projectId: 1, token: "sample_token", projectName: "Sample Project")
            }
        }
    }
}
