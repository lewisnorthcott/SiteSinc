import SwiftUI

struct ProjectSummaryView: View {
    let projectId: Int
    let token: String
    let projectName: String

    // MARK: - State Variables
    @State private var isLoading = false
    @State private var selectedTile: String?
    @State private var isAppearing = false
    @State private var isOfflineModeEnabled: Bool = false
    @State private var downloadProgress: Double = 0.0
    @State private var errorMessage: String? = nil
    @State private var documentCount: Int = 0
    @State private var drawingCount: Int = 0
    @State private var rfiCount: Int = 0
    @State private var formCount: Int = 0
    @State private var projectStatus: String? = nil
    @State private var initialSetupComplete: Bool = false
    @State private var hasViewDrawingsPermission: Bool = false // Track permission
    @State private var hasViewDocumentsPermission: Bool = false // Track permission
    @State private var hasManageFormsPermission: Bool = false // Track permission
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @EnvironmentObject var sessionManager: SessionManager // Assumed to hold user data

    var body: some View {
        ZStack {
            backgroundView
            mainContent
            errorView
        }
        .toolbar { toolbarContent }
        .onAppear {
            performInitialSetup()
        }
        .onChange(of: isOfflineModeEnabled) {
            Task {
                if isOfflineModeEnabled {
                    UserDefaults.standard.set(true, forKey: "offlineMode_\(projectId)")
                    // Only download if toggled ON
                    if networkStatusManager.isNetworkAvailable {
                        downloadAllResources()
                    } else {
                        // If offline, but toggle is enabled, try to load from cache.
                        // If cache fails, show error. This might happen if user enables, goes offline, then kills and reopens.
                        if await !loadSummaryDataFromCache() {
                            await MainActor.run {
                                self.errorMessage = "Network is offline and no cached data is available."
                                self.isOfflineModeEnabled = false // Revert toggle
                                UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            }
                        }
                    }
                } else {
                    // If toggled OFF, just clear the data.
                    UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                    clearOfflineData()
                }
            }
        }
    }

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
                if hasViewDocumentsPermission {
                    StatCard(
                        title: "Documents",
                        value: "\(documentCount)",
                        trend: "+5",
                        icon: "doc.fill",
                        destination: AnyView(DocumentListView(projectId: projectId, token: token, projectName: projectName))
                    )
                    .accessibilityLabel("Documents: \(documentCount)")
                }
                if hasViewDrawingsPermission {
                    StatCard(
                        title: "Drawings",
                        value: "\(drawingCount)",
                        trend: "+12",
                        icon: "square.and.pencil",
                        destination: AnyView(DrawingListView(projectId: projectId, token: token, projectName: projectName))
                    )
                    .accessibilityLabel("Drawings: \(drawingCount)")
                }
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
            if hasViewDrawingsPermission {
                navTile(drawingsTile, id: "Drawings")
            }
            if hasViewDocumentsPermission {
                navTile(documentsTile, id: "Documents")
            }
            navTile(formsTile, id: "Forms")
            
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
    
    private var formsTile: some View {
        NavigationLink(
            destination: FormsView(projectId: projectId, token: token, projectName: projectName)
                .environmentObject(sessionManager)
        ) {
            SummaryTile(
                title: "Forms",
                subtitle: "Access project forms",
                icon: "list.clipboard.fill",
                color: Color.orange,
                isSelected: selectedTile == "Forms"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var errorView: some View {
        Group {
            if errorMessage != nil {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { withAnimation { errorMessage = nil } }
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        Text(errorMessage!)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            print("Retry button tapped. isOfflineModeEnabled: \(isOfflineModeEnabled)")
                            if isOfflineModeEnabled {
                                downloadAllResources()
                            } else {
                                Task {
                                    await MainActor.run { self.isLoading = true; self.errorMessage = nil }
                                    await fetchSummaryCountsFromServer()
                                    await MainActor.run { self.isLoading = false }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .padding(.horizontal)
                        
                        Button("Dismiss") {
                            withAnimation { errorMessage = nil }
                        }
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal)
                    .background(.thinMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .frame(maxWidth: 350)
                }
                .animation(.default, value: errorMessage)
            }
        }
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: {
                isOfflineModeEnabled.toggle()
            }) {
                Image(systemName: cloudStatusIcon)
                    .foregroundColor(cloudStatusColor)
            }
            .accessibilityLabel(cloudStatusLabel)
        }
    }

    private var hasDownloadError: Bool {
        if let error = errorMessage {
            return error.contains("Failed to fetch drawings") ||
                   error.contains("Failed to fetch RFIs") ||
                   error.contains("Failed to fetch forms") ||
                   error.contains("Failed to download drawing file") ||
                   error.contains("Failed to download RFI file") ||
                   error.contains("Failed during offline data setup") ||
                   error.contains("Internet connection is offline")
        }
        return false
    }

    private var cloudStatusIcon: String {
        if hasDownloadError {
            return "exclamationmark.triangle.fill"
        } else if isOfflineModeEnabled {
            return "icloud.fill"
        } else {
            return "icloud"
        }
    }

    private var cloudStatusColor: Color {
        if hasDownloadError {
            return Color.red
        } else if isOfflineModeEnabled {
            return Color.green
        } else {
            return Color.gray
        }
    }

    private var cloudStatusLabel: String {
        if hasDownloadError {
            return "Error downloading project data, tap to toggle offline mode"
        } else if isOfflineModeEnabled {
            return "Project available offline, tap to disable offline mode"
        } else {
            return "Project not downloaded, tap to enable offline mode"
        }
    }

    private func fetchAndCacheProjectInformation() async {
        downloadAllResources()
    }
    
    private func performInitialSetup() {
        // Check permissions
        let userPermissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        self.hasViewDrawingsPermission = userPermissions.contains("view_drawings")
        self.hasViewDocumentsPermission = userPermissions.contains("view_documents")
        self.hasManageFormsPermission = userPermissions.contains("manage_forms")
        print("ProjectSummaryView: Permissions - view_drawings: \(hasViewDrawingsPermission), view_documents: \(hasViewDocumentsPermission), manage_forms: \(hasManageFormsPermission)")

        let initiallyEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        self.isOfflineModeEnabled = initiallyEnabled

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            self.isAppearing = true
        }

        Task {
            if initiallyEnabled {
                print("ProjectSummaryView: Initial setup - Offline mode is ON for project \(projectId).")
                if networkStatusManager.isNetworkAvailable {
                    print("ProjectSummaryView: Internet is available. Fetching fresh project information and caching.")
                    await fetchAndCacheProjectInformation()
                } else {
                    print("ProjectSummaryView: No internet available. Loading summary from cache.")
                    if await !loadSummaryDataFromCache() {
                        print("ProjectSummaryView: Initial setup - Failed to load summary data from cache or cache is empty.")
                        await MainActor.run {
                            self.documentCount = 0
                            self.drawingCount = 0
                            self.rfiCount = 0
                            self.formCount = 0
                        }
                    }
                }
            } else {
                print("ProjectSummaryView: Initial setup - Offline mode is OFF for project \(projectId). Fetching summary counts from server.")
                await fetchSummaryCountsFromServer()
            }

            await MainActor.run {
                self.initialSetupComplete = true
                print("ProjectSummaryView: Initial setup complete. Ready for user interactions with the offline toggle. isOfflineModeEnabled: \(self.isOfflineModeEnabled)")
            }
        }
    }

    private func fetchSummaryCountsFromServer() async {
        print("ProjectSummaryView: Fetching summary counts from server for project \(projectId)...")
        var documents: [Document] = []
        var drawings: [Drawing] = []

        do {
            // Fetch documents only if user has view_documents permission
            if hasViewDocumentsPermission {
                documents = try await APIClient.fetchDocuments(projectId: projectId, token: token)
            } else {
                print("ProjectSummaryView: Skipped fetching documents due to lack of view_documents permission.")
            }
        } catch {
            await MainActor.run {
                if !self.isLoading && self.errorMessage?.contains("Cannot download project data") != true {
                    self.errorMessage = "Failed to load documents: \(error.localizedDescription)"
                }
                print("ProjectSummaryView: Error fetching documents: \(error.localizedDescription). Current errorMessage: \(self.errorMessage ?? "nil")")
            }
        }

        do {
            // Fetch drawings only if user has view_drawings permission
            if hasViewDrawingsPermission {
                drawings = try await APIClient.fetchDrawings(projectId: projectId, token: token)
            } else {
                print("ProjectSummaryView: Skipped fetching drawings due to lack of view_drawings permission.")
            }
        } catch {
            await MainActor.run {
                if !self.isLoading && self.errorMessage?.contains("Cannot download project data") != true {
                    self.errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                }
                print("ProjectSummaryView: Error fetching drawings: \(error.localizedDescription). Current errorMessage: \(self.errorMessage ?? "nil")")
            }
        }

        await MainActor.run {
            self.documentCount = documents.count
            self.drawingCount = drawings.count
            if self.isOfflineModeEnabled {
                saveDrawingsToCache(drawings)
                saveDocumentsToCache(documents)
            }
            if self.errorMessage?.contains("Failed to load summary") == true || self.errorMessage?.contains("Network unavailable. Cannot fetch summary counts.") == true {
                self.errorMessage = nil
            }
            print("ProjectSummaryView: Successfully fetched summary counts. Documents: \(self.documentCount), Drawings: \(self.drawingCount).")
        }
    }
    
    private func loadSummaryDataFromCache() async -> Bool {
        print("ProjectSummaryView: Loading summary data from cache for project \(projectId)...")
        var success = false
        if hasViewDrawingsPermission, let cachedDrawings = loadDrawingsFromCache() {
            await MainActor.run { self.drawingCount = cachedDrawings.count }
            success = true
        }
        if hasViewDocumentsPermission, let cachedDocuments = loadDocumentsFromCache() {
            await MainActor.run { self.documentCount = cachedDocuments.count }
            success = true
        }
        if let cachedFormSubmissions = loadFormSubmissionsFromCache() {
            await MainActor.run { self.formCount = cachedFormSubmissions.count }
            success = true
        }

        if success {
            await MainActor.run {
                if self.errorMessage?.contains("Failed to load summary") == true || self.errorMessage == nil {
                    self.errorMessage = nil
                }
                print("ProjectSummaryView: Summary data (partially or fully) loaded from cache. Drawings: \(self.drawingCount), Documents: \(self.documentCount), Forms: \(self.formCount).")
            }
        } else {
            print("ProjectSummaryView: No summary data found in cache or cache load failed for project \(projectId).")
        }
        return success
    }

    private func downloadAllResources() {
        Task {
            print("ProjectSummaryView: downloadAllResources called for project \(projectId).")
            guard networkStatusManager.isNetworkAvailable else {
                await MainActor.run {
                    self.errorMessage = "Internet connection is offline. Cannot download project data at this time."
                    self.isLoading = false
                    print("ProjectSummaryView: downloadAllResources - Network check failed (offline).")
                }
                return
            }

            await MainActor.run {
                self.isLoading = true
                self.errorMessage = nil
                self.downloadProgress = 0.0
                print("ProjectSummaryView: downloadAllResources - Network check passed. Starting download process.")
            }
            
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true, attributes: nil)
                
                var drawingsData: [Drawing] = []
                if hasViewDrawingsPermission {
                    let drawingsResult = await fetchDrawings()
                    guard case .success(let data) = drawingsResult else {
                        if case .failure(let error) = drawingsResult {
                            await MainActor.run {
                                self.errorMessage = "Failed to fetch drawings: \(error.localizedDescription)"
                                self.isLoading = false
                                UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                                self.isOfflineModeEnabled = false
                            }
                        }
                        return
                    }
                    drawingsData = data
                } else {
                    print("ProjectSummaryView: Skipped fetching drawings due to lack of view_drawings permission.")
                }
                
                let rfisResult = await fetchRFIs()
                guard case .success(let rfisData) = rfisResult else {
                    if case .failure(let error) = rfisResult {
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch RFIs: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                    }
                    return
                }

                let formsResult = await fetchForms()
                guard case .success(let formsData) = formsResult else {
                    if case .failure(let error) = formsResult {
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch forms: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                    }
                    return
                }

                let formSubmissionsResult = await fetchFormSubmissions()
                guard case .success(let formSubmissionsData) = formSubmissionsResult else {
                    if case .failure(let error) = formSubmissionsResult {
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch form submissions: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                    }
                    return
                }

                var documentsData: [Document] = []
                if hasViewDocumentsPermission {
                    let documentsResult = await fetchDocuments()
                    guard case .success(let data) = documentsResult else {
                        if case .failure(let error) = documentsResult {
                            await MainActor.run {
                                self.errorMessage = "Failed to fetch documents: \(error.localizedDescription)"
                                self.isLoading = false
                                UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                                self.isOfflineModeEnabled = false
                            }
                        }
                        return
                    }
                    documentsData = data
                } else {
                    print("ProjectSummaryView: Skipped fetching documents due to lack of view_documents permission.")
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

                let documentFiles = documentsData.flatMap { document in
                    document.revisions.compactMap { revision in
                        if let documentFiles = revision.documentFiles {
                            return documentFiles.filter { $0.fileName.lowercased().hasSuffix(".pdf") }.map { file in
                                (file: file, localPath: projectFolder.appendingPathComponent("documents/\(file.fileName)"))
                            }
                        } else {
                            guard !revision.fileUrl.isEmpty else { return nil }
                            let fileName = revision.fileUrl.split(separator: "/").last?.removingPercentEncoding ?? "document.pdf"
                            let file = DocumentFile(id: revision.id, fileName: fileName, fileUrl: revision.fileUrl, downloadUrl: revision.downloadUrl)
                            return [(file: file, localPath: projectFolder.appendingPathComponent("documents/\(file.fileName)"))]
                        }
                    }.flatMap { $0 }
                }

                let totalFiles = drawingFiles.count + rfiFiles.count + documentFiles.count
                
                guard totalFiles > 0 else {
                    await MainActor.run {
                        self.isLoading = false
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        saveFormSubmissionsToCache(formSubmissionsData)
                        saveDocumentsToCache(documentsData)
                        print("ProjectSummaryView: No files to download for project \(projectId). Metadata cached.")
                        self.documentCount = documentsData.count
                        self.drawingCount = drawingsData.count
                        self.rfiCount = rfisData.count
                    }
                    return
                }
                
                var completedDownloads = 0

                for (file, localPath) in drawingFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("drawings"), withIntermediateDirectories: true)
                    guard let downloadUrl = file.downloadUrl else {
                        await MainActor.run {
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            print("Skipped drawing file with no download URL for project \(projectId)")
                        }
                        continue
                    }
                    let result = await downloadFile(from: downloadUrl, to: localPath)
                    await MainActor.run {
                        switch result {
                        case .success:
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        case .failure(let error):
                            self.errorMessage = "Failed to download drawing file: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                            return
                        }
                    }
                }
                
                for (file, localPath) in rfiFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("rfis"), withIntermediateDirectories: true)
                    let downloadUrl = file.downloadUrl ?? file.fileUrl
                    guard !downloadUrl.isEmpty else {
                        await MainActor.run {
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            print("Skipped RFI file with no download URL for project \(projectId)")
                        }
                        continue
                    }
                    let result = await downloadFile(from: downloadUrl, to: localPath)
                    await MainActor.run {
                        switch result {
                        case .success:
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        case .failure(let error):
                            self.errorMessage = "Failed to download RFI file: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                            return
                        }
                    }
                }

                for (file, localPath) in documentFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("documents"), withIntermediateDirectories: true)
                    guard let downloadUrl = file.downloadUrl else {
                        await MainActor.run {
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            print("Skipped document file with no download URL for project \(projectId)")
                        }
                        continue
                    }
                    let result = await downloadFile(from: downloadUrl, to: localPath)
                    await MainActor.run {
                        switch result {
                        case .success:
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        case .failure(let error):
                            self.errorMessage = "Failed to download document file: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                            return
                        }
                    }
                }
                
                await MainActor.run {
                    self.isLoading = false
                    if self.errorMessage == nil {
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        saveFormSubmissionsToCache(formSubmissionsData)
                        saveDocumentsToCache(documentsData)
                        print("ProjectSummaryView: All files downloaded and metadata cached successfully for project \(projectId).")
                        self.documentCount = documentsData.count
                        self.drawingCount = drawingsData.count
                        self.rfiCount = rfisData.count
                    } else {
                        print("ProjectSummaryView: Download process completed with an error: \(self.errorMessage ?? "Unknown error")")
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed during offline data setup: \(error.localizedDescription)"
                    self.isLoading = false
                    UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                    self.isOfflineModeEnabled = false
                    print("ProjectSummaryView: downloadAllResources - Error during data setup: \(error.localizedDescription)")
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
    
    private func fetchFormSubmissions() async -> Result<[FormSubmission], Error> {
        do {
            let submissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
            return .success(submissions)
        } catch {
            return .failure(error)
        }
    }
    
    private func fetchDocuments() async -> Result<[Document], Error> {
        do {
            let documents = try await APIClient.fetchDocuments(projectId: projectId, token: token)
            return .success(documents)
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
        let formSubmissionsCacheURL = cachesDirectory.appendingPathComponent("form_submissions_project_\(projectId).json")
        let documentsCacheURL = cachesDirectory.appendingPathComponent("documents_project_\(projectId).json")
        
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
            if FileManager.default.fileExists(atPath: formSubmissionsCacheURL.path) {
                try FileManager.default.removeItem(at: formSubmissionsCacheURL)
            }
            if FileManager.default.fileExists(atPath: documentsCacheURL.path) {
                try FileManager.default.removeItem(at: documentsCacheURL)
            }
            print("ProjectSummaryView: Offline data cleared for project \(projectId)")
            Task { await MainActor.run {
                self.documentCount = 0
                self.drawingCount = 0
                self.rfiCount = 0
                self.formCount = 0
            }}
        } catch {
            print("ProjectSummaryView: Error clearing offline data: \(error)")
        }
    }
    
    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(drawings.count) drawings to cache for project \(projectId)")
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let drawings = try? JSONDecoder().decode([Drawing].self, from: data) {
            print("ProjectSummaryView: Loaded \(drawings.count) drawings from cache for project \(projectId)")
            return drawings
        }
        print("ProjectSummaryView: Failed to load drawings from cache or cache file does not exist for project \(projectId)")
        return nil
    }
    
    private func saveRFIsToCache(_ rfis: [RFI]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rfis) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }
    
    private func saveFormsToCache(_ forms: [FormModel]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(forms) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("forms_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(forms.count) forms to cache for project \(projectId)")
        } else {
            print("ProjectSummaryView: FAILED to encode forms to cache for project \(projectId)")
        }
    }
    
    private func saveFormSubmissionsToCache(_ submissions: [FormSubmission]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(submissions) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("form_submissions_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(submissions.count) form submissions to cache for project \(projectId)")
        } else {
            print("ProjectSummaryView: FAILED to encode form submissions to cache for project \(projectId)")
        }
    }
    
    private func loadFormSubmissionsFromCache() -> [FormSubmission]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("form_submissions_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let submissions = try? JSONDecoder().decode([FormSubmission].self, from: data) {
            print("ProjectSummaryView: Loaded \(submissions.count) form submissions from cache for project \(projectId)")
            return submissions
        }
        print("ProjectSummaryView: Failed to load form submissions from cache or cache file does not exist for project \(projectId)")
        return nil
    }
    
    private func saveDocumentsToCache(_ documents: [Document]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(documents) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("documents_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(documents.count) documents to cache for project \(projectId)")
        }
    }

    private func loadDocumentsFromCache() -> [Document]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("documents_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let documents = try? JSONDecoder().decode([Document].self, from: data) {
            print("ProjectSummaryView: Loaded \(documents.count) documents from cache for project \(projectId)")
            return documents
        }
        print("ProjectSummaryView: Failed to load documents from cache or cache file does not exist for project \(projectId)")
        return nil
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
}
