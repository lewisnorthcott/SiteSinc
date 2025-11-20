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
    @State private var photoCount: Int = 0
    @State private var logCount: Int = 0
    @State private var projectStatus: String? = nil
    @State private var initialSetupComplete: Bool = false
    @State private var hasViewDrawingsPermission: Bool = false // Track permission
    @State private var hasViewDocumentsPermission: Bool = false // Track permission
    @State private var hasManageFormsPermission: Bool = false // Track permission
    @State private var hasViewRFIsPermission: Bool = false // Track permission
    @State private var hasViewPhotosPermission: Bool = false // Track permission
    @State private var hasViewLogsPermission: Bool = false // Track permission
    @State private var showNotificationSettings = false
    @State private var showSyncedToast: Bool = false
    @State private var showChat: Bool = false
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @EnvironmentObject var sessionManager: SessionManager // Assumed to hold user data
    @EnvironmentObject var notificationManager: NotificationManager
    @StateObject private var recentDrawingsManager = RecentDrawingsManager.shared

    var body: some View {
        ZStack {
            backgroundView
            if sessionManager.isLoadingPermissions {
                permissionLoadingView
            } else {
                mainContent
            }
            errorView
            
            // Chat Button - Bottom Right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    chatFloatingButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 20) // Position at bottom right
                }
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView(projectId: projectId, projectName: projectName)
        }
        .sheet(isPresented: $showChat) {
            ProjectChatView(projectId: projectId, token: token, projectName: projectName)
                .environmentObject(sessionManager)
        }
        .onAppear {
            performInitialSetup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDrawing"))) { notification in
            if let userInfo = notification.userInfo,
               let targetProjectId = userInfo["projectId"] as? Int,
               targetProjectId == projectId {
                // Navigation will be handled by DrawingListView
                // Just ensure we're on the drawings view
                selectedTile = "Drawings"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDocument"))) { notification in
            if let userInfo = notification.userInfo,
               let targetProjectId = userInfo["projectId"] as? Int,
               targetProjectId == projectId {
                // Navigation will be handled by DocumentListView
                // Just ensure we're on the documents view
                selectedTile = "Documents"
            }
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

    private var permissionLoadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                Text("Loading permissions...")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Please wait while we load your access permissions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerView
                recentDrawingsSection
                navigationGrid
            }
            .padding(.vertical, 8)
        }
        .refreshable {
            await refreshProjectData()
        }
        // Inline indicator is now shown within the cloud icon; remove blocking overlay
    }
    
    private func refreshProjectData() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Refresh project data
        await fetchSummaryCountsFromServer()
        
        await MainActor.run {
            isLoading = false
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(projectName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            // Inline status row
            HStack(spacing: 10) {
                if let status = projectStatus {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if isOfflineModeEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.fill").font(.system(size: 11, weight: .semibold))
                        Text("Offline")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }
                Text("Last updated: \(Date(), formatter: dateFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if showSyncedToast {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Synced")
                    }
                    .font(.caption2)
                    .foregroundColor(.green)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }
    
    private var recentDrawingsSection: some View {
        Group {
            if hasViewDrawingsPermission {
                let recentDrawings = recentDrawingsManager.getRecentDrawings(for: projectId)
                if !recentDrawings.isEmpty {
                    VStack(spacing: 16) {
                        // Section header
                        HStack {
                            Text("Recent Drawings")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                recentDrawingsManager.clearRecentDrawings(for: projectId)
                            }) {
                                Text("Clear")
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Horizontal scroll of recent drawings
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recentDrawings) { recentDrawing in
                                    RecentDrawingCard(
                                        recentDrawing: recentDrawing,
                                        projectName: projectName,
                                        token: token,
                                        isProjectOffline: isOfflineModeEnabled
                                    )
                                    .environmentObject(sessionManager)
                                    .environmentObject(networkStatusManager)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var navigationGrid: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Quick Access")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Customize entry removed by request
            }
            .padding(.horizontal, 16)
            
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
                if hasManageFormsPermission {
                    navTile(formsTile, id: "Forms")
                }
                if hasViewPhotosPermission {
                    navTile(photosTile, id: "Photos")
                }
                // if sessionManager.hasPermission("view_snags") || sessionManager.hasPermission("snag_manager") {
                //     navTile(snaggingTile, id: "Snagging")
                // }
                if hasViewRFIsPermission {
                    navTile(rfiTile, id: "RFI")
                }
                if hasViewLogsPermission {
                    navTile(logsTile, id: "Logs")
                }
                // navTile(settingsTile, id: "Settings")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
            .opacity(isAppearing ? 1 : 0)
            .offset(y: isAppearing ? 0 : 20)
        }
    }

    private func navTile<Content: View>(_ content: Content, id: String) -> some View {
        content
            .accessibilityAddTraits(.isButton)
            .scaleEffect(selectedTile == id ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTile)
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

    private var photosTile: some View {
        NavigationLink(
            destination: PhotoListView(projectId: projectId, token: token, projectName:projectName)
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
                .environmentObject(PhotoUploadManager.shared)
        ) {
            SummaryTile(
                title: "Photos",
                subtitle: "Access project photos",
                icon: "photo.on.rectangle.angled",
                color: Color.blue,
                isSelected: selectedTile == "Photos"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var rfiTile: some View {
        NavigationLink(
            destination: RFIsListView(projectId: projectId, token: token, projectName: projectName)
                .environmentObject(sessionManager)
        ) {
            SummaryTile(
                title: "RFI",
                subtitle: "Request for Information",
                icon: "questionmark.circle.fill",
                color: Color.red,
                isSelected: selectedTile == "RFI"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var logsTile: some View {
        NavigationLink(
            destination: LogsListView(projectId: projectId, token: token, projectName: projectName)
                .environmentObject(sessionManager)
        ) {
            SummaryTile(
                title: "Logs",
                subtitle: "Safety & Compliance Logs",
                icon: "doc.text.fill",
                color: Color.orange,
                isSelected: selectedTile == "Logs"
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // private var snaggingTile: some View {
    //     NavigationLink(
    //         destination: SnaggingListView(projectId: projectId, token: token, projectName: projectName)
    //             .environmentObject(sessionManager)
    //             .environmentObject(networkStatusManager)
    //     ) {
    //         SummaryTile(
    //             title: "Snagging",
    //             subtitle: "Log and track snags",
    //             icon: "mappin.and.ellipse",
    //             color: Color.purple,
    //             isSelected: selectedTile == "Snagging"
    //         )
    //     }
    //     .buttonStyle(PlainButtonStyle())
    // }
    
    // private var settingsTile: some View {
    //     NavigationLink(
    //         destination: NotificationSettingsView(projectId: projectId, projectName: projectName)
    //     ) {
    //         SummaryTile(
    //             title: "Settings",
    //             subtitle: "Project preferences",
    //             icon: "gearshape.fill",
    //             color: Color.gray,
    //             isSelected: selectedTile == "Settings"
    //         )
    //     }
    //     .buttonStyle(PlainButtonStyle())
    // }

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
            // Notification Settings Button
            Button(action: {
                showNotificationSettings = true
            }) {
                Image(systemName: "bell.badge")
                    .foregroundColor(Color(hex: "#3B82F6"))
            }
            .accessibilityLabel("Notification Settings")
            .accessibilityHint("Configure notification preferences for this project")
            
            Menu {
                if isLoading {
                    Button("Downloading… \(Int(downloadProgress * 100))%", action: {})
                        .disabled(true)
                }
                Button(isOfflineModeEnabled ? "Disable offline for this project" : "Enable offline for this project") {
                    isOfflineModeEnabled.toggle()
                }
                Button("Sync now") {
                    downloadAllResources()
                }
            } label: {
                CloudProgressIcon(
                    isLoading: isLoading,
                    progress: downloadProgress,
                    baseIcon: cloudStatusIcon,
                    tint: cloudStatusColor
                )
            }
            .accessibilityLabel(cloudStatusLabel)
        }
    }

    // MARK: - Cloud progress icon
    private struct CloudProgressIcon: View {
        let isLoading: Bool
        let progress: Double // 0.0 - 1.0
        let baseIcon: String
        let tint: Color

        @State private var rotation: Double = 0

        var body: some View {
            let clamped = max(0.01, min(0.999, progress))
            let ringSize: CGFloat = 26
            let line: CGFloat = 3
            ZStack {
                // Subtle background track for spacing reference
                if isLoading {
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: line)
                        .frame(width: ringSize, height: ringSize)
                }
                // Progress arc with smooth animation and slight rotation drift
                if isLoading {
                    Circle()
                        .trim(from: 0, to: CGFloat(clamped))
                        .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .foregroundColor(tint)
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(rotation - 90))
                        .animation(.easeInOut(duration: 0.25), value: progress)
                        .animation(isLoading ? .linear(duration: 1.4).repeatForever(autoreverses: false) : .default, value: rotation)
                        .onAppear { if isLoading { rotation = 360 } }
                }
                Image(systemName: baseIcon)
                    .foregroundColor(tint)
                    .font(.system(size: 17))
            }
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
        self.hasViewRFIsPermission = userPermissions.contains("view_rfis") || userPermissions.contains("view_all_rfis")
        self.hasViewPhotosPermission = userPermissions.contains("view_photos")
        self.hasViewLogsPermission = userPermissions.contains("view_logs") || userPermissions.contains("view_all_logs")
        print("ProjectSummaryView: Permissions - view_drawings: \(hasViewDrawingsPermission), view_documents: \(hasViewDocumentsPermission), manage_forms: \(hasManageFormsPermission), view_logs: \(hasViewLogsPermission)")

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
                            self.logCount = 0
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
        var photos: [PhotoItem] = []

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

        if hasViewPhotosPermission {
            do {
                // Fetch photos from all sources
                let results = try await withThrowingTaskGroup(of: [PhotoItem].self) { group in
                    group.addTask {
                        return try await APIClient.fetchProjectPhotos(projectId: projectId, token: token)
                    }
                    
                    group.addTask {
                        return try await APIClient.fetchFormPhotos(projectId: projectId, token: token)
                    }
                    
                    group.addTask {
                        return try await APIClient.fetchRFIPhotos(projectId: projectId, token: token)
                    }
                    
                    var allResults: [[PhotoItem]] = []
                    for try await result in group {
                        allResults.append(result)
                    }
                    return allResults
                }
                
                photos = results.flatMap { $0 }
            } catch {
                print("ProjectSummaryView: Error fetching photos: \(error.localizedDescription)")
                // Don't show error for photos as they're not critical
            }
        } else {
            print("ProjectSummaryView: Skipped fetching photos due to lack of view_photos permission.")
        }

        await MainActor.run {
            self.documentCount = documents.count
            self.drawingCount = drawings.count
            self.photoCount = photos.count
            if self.isOfflineModeEnabled {
                saveDrawingsToCache(drawings)
                saveDocumentsToCache(documents)
            }
            if self.errorMessage?.contains("Failed to load summary") == true || self.errorMessage?.contains("Network unavailable. Cannot fetch summary counts.") == true {
                self.errorMessage = nil
            }
            print("ProjectSummaryView: Successfully fetched summary counts. Documents: \(self.documentCount), Drawings: \(self.drawingCount), Photos: \(self.photoCount).")
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
        if hasManageFormsPermission, let cachedFormSubmissions = loadFormSubmissionsFromCache() {
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
                
                var rfisData: [RFI] = []
                if hasViewRFIsPermission {
                    let rfisResult = await fetchRFIs()
                    switch rfisResult {
                    case .success(let data):
                        rfisData = data
                    case .failure(let error):
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch RFIs: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                        return
                    }
                } else {
                    print("ProjectSummaryView: Skipped fetching RFIs due to lack of view_rfis permission.")
                }

                var formsData: [FormModel] = []
                if hasManageFormsPermission {
                    let formsResult = await fetchForms()
                    switch formsResult {
                    case .success(let data):
                        formsData = data
                    case .failure(let error):
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch forms: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                        return
                    }
                } else {
                    print("ProjectSummaryView: Skipped fetching forms due to lack of manage_forms permission.")
                }

                var formSubmissionsData: [FormSubmission] = []
                if hasManageFormsPermission {
                    let formSubmissionsResult = await fetchFormSubmissions()
                    switch formSubmissionsResult {
                    case .success(let data):
                        formSubmissionsData = data
                    case .failure(let error):
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch form submissions: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                        return
                    }
                } else {
                    print("ProjectSummaryView: Skipped fetching form submissions due to lack of manage_forms permission.")
                }

                var allPhotos: [PhotoItem] = []
                if hasViewPhotosPermission {
                    let photosResult = await fetchAllPhotos()
                    switch photosResult {
                    case .success(let data):
                        allPhotos = data
                    case .failure(let error):
                        await MainActor.run {
                            self.errorMessage = "Failed to fetch photos: \(error.localizedDescription)"
                            self.isLoading = false
                            UserDefaults.standard.set(false, forKey: "offlineMode_\(projectId)")
                            self.isOfflineModeEnabled = false
                        }
                        return
                    }
                } else {
                    print("ProjectSummaryView: Skipped fetching photos due to lack of view_photos permission.")
                }

                var documentsData: [Document] = []
                if hasViewDocumentsPermission {
                    let documentsResult = await fetchDocuments()
                    switch documentsResult {
                    case .success(let data):
                        documentsData = data
                        print("ProjectSummaryView: Successfully fetched \(data.count) documents")
                    case .failure(let error):
                        print("ProjectSummaryView: Failed to fetch documents: \(error)")
                        // Don't fail the entire process if documents can't be fetched
                        documentsData = []
                        print("ProjectSummaryView: Continuing download process without documents")
                    }
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

                var formAttachmentFiles: [(key: String, localPath: URL)] = []
                if hasManageFormsPermission {
                    let attachmentKeys = formSubmissionsData.flatMap { submission -> [String] in
                        return submission.fields.flatMap { field -> [String] in
                            if ["image", "attachment", "camera", "signature"].contains(field.type) {
                                return submission.responses?[field.id]?.stringArrayValue ?? []
                            }
                            return []
                        }
                    }
                    
                    let uniqueKeys = Array(Set(attachmentKeys.filter { !$0.isEmpty }))
                    
                    formAttachmentFiles = uniqueKeys.map { key in
                        let fileName = (key as NSString).lastPathComponent
                        let localPath = projectFolder.appendingPathComponent("form_attachments/\(fileName)")
                        return (key: key, localPath: localPath)
                    }
                }
                
                let photoFiles = allPhotos.map { photo -> (photo: PhotoItem, localPath: URL)? in
                    let safeFileName = photo.fileName.replacingOccurrences(of: "/", with: "_")
                    let finalFileName = "\(photo.id)_\(safeFileName)"
                    return (photo: photo, localPath: projectFolder.appendingPathComponent("photos/\(finalFileName)"))
                }.compactMap { $0 }
                
                let totalFiles = drawingFiles.count + rfiFiles.count + documentFiles.count + formAttachmentFiles.count + photoFiles.count
                
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
                        self.photoCount = allPhotos.count
                        withAnimation { self.showSyncedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { self.showSyncedToast = false } }
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
                            print("ProjectSummaryView: Skipped document file with no download URL for project \(projectId)")
                        }
                        continue
                    }
                    
                    print("ProjectSummaryView: Attempting to download document: \(file.fileName) from: \(downloadUrl)")
                    let result = await downloadFile(from: downloadUrl, to: localPath)
                    await MainActor.run {
                        switch result {
                        case .success:
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            print("ProjectSummaryView: Successfully downloaded document: \(file.fileName)")
                        case .failure(let error):
                            print("ProjectSummaryView: Failed to download document \(file.fileName) from \(downloadUrl): \(error)")
                            // Don't fail the entire download for individual document failures
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        }
                    }
                }
                
                var attachmentPathMap: [String: String] = [:]
                var attachmentDownloadSupported = true
                
                for (key, localPath) in formAttachmentFiles {
                    if !attachmentDownloadSupported {
                        // Skip remaining attachments if API doesn't support it
                        await MainActor.run {
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        }
                        continue
                    }
                    
                    do {
                        try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("form_attachments"), withIntermediateDirectories: true, attributes: nil)
                        
                        let downloadUrlString = try await APIClient.getPresignedUrl(forKey: key, token: token)
                        let result = await downloadFile(from: downloadUrlString, to: localPath)
                        
                        await MainActor.run {
                            if case .success = result {
                                attachmentPathMap[key] = localPath.path
                                completedDownloads += 1
                                self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            } else {
                                print("ProjectSummaryView: Failed to download form attachment \(key), but continuing download process")
                                completedDownloads += 1
                                self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            }
                        }
                    } catch {
                        // If it's a decoding error (API doesn't support form attachments), disable further attempts
                        if let apiError = error as? APIError, case .decodingError = apiError {
                            print("ProjectSummaryView: Form attachment download not supported by API, skipping remaining attachments")
                            attachmentDownloadSupported = false
                        } else {
                            print("ProjectSummaryView: Failed to get download URL for attachment \(key): \(error.localizedDescription)")
                        }
                        
                        await MainActor.run {
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        }
                    }
                }
                
                var photoPathMap: [String: String] = [:]
                for (photo, localPath) in photoFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("photos"), withIntermediateDirectories: true)
                    let result = await downloadFile(from: photo.url, to: localPath)
                    await MainActor.run {
                        switch result {
                        case .success:
                            photoPathMap[photo.id] = localPath.path
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
                        case .failure(let error):
                            print("ProjectSummaryView: Failed to download photo file \(photo.fileName): \(error.localizedDescription)")
                            completedDownloads += 1
                            self.downloadProgress = Double(completedDownloads) / Double(totalFiles)
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
                        saveAttachmentPathMapToCache(attachmentPathMap)
                        savePhotoPathMapToCache(photoPathMap)
                        print("ProjectSummaryView: All files downloaded and metadata cached successfully for project \(projectId).")
                        self.documentCount = documentsData.count
                        self.drawingCount = drawingsData.count
                        self.rfiCount = rfisData.count
                        self.photoCount = allPhotos.count
                        withAnimation { self.showSyncedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { self.showSyncedToast = false } }
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
    
    private func fetchAllPhotos() async -> Result<[PhotoItem], Error> {
        do {
            let results = try await withThrowingTaskGroup(of: [PhotoItem].self) { group in
                group.addTask { return try await APIClient.fetchProjectPhotos(projectId: projectId, token: token) }
                group.addTask { return try await APIClient.fetchFormPhotos(projectId: projectId, token: token) }
                group.addTask { return try await APIClient.fetchRFIPhotos(projectId: projectId, token: token) }
                
                var allResults: [[PhotoItem]] = []
                for try await result in group {
                    allResults.append(result)
                }
                return allResults
            }
            let allPhotos = results.flatMap { $0 }
            return .success(allPhotos)
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
        let attachmentMapCacheURL = cachesDirectory.appendingPathComponent("form_attachment_paths_\(projectId).json")
        let photoMapCacheURL = cachesDirectory.appendingPathComponent("photo_paths_project_\(projectId).json")
        
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
            if FileManager.default.fileExists(atPath: attachmentMapCacheURL.path) {
                try FileManager.default.removeItem(at: attachmentMapCacheURL)
            }
            if FileManager.default.fileExists(atPath: photoMapCacheURL.path) {
                try FileManager.default.removeItem(at: photoMapCacheURL)
            }
            print("ProjectSummaryView: Offline data cleared for project \(projectId)")
            Task { await MainActor.run {
                self.documentCount = 0
                self.drawingCount = 0
                self.rfiCount = 0
                self.formCount = 0
                self.photoCount = 0
                self.logCount = 0
            }}
        } catch {
            print("ProjectSummaryView: Error clearing offline data: \(error)")
        }
    }
    
    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(drawings.count) drawings to cache for project \(projectId)")
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("drawings_project_\(projectId).json")
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
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }
    
    private func saveFormsToCache(_ forms: [FormModel]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(forms) {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("forms_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(forms.count) forms to cache for project \(projectId)")
        } else {
            print("ProjectSummaryView: FAILED to encode forms to cache for project \(projectId)")
        }
    }
    
    private func saveFormSubmissionsToCache(_ submissions: [FormSubmission]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(submissions) {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("form_submissions_project_\(projectId).json")
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
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("documents_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(documents.count) documents to cache for project \(projectId)")
        }
    }

    private func loadDocumentsFromCache() -> [Document]? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("documents_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let documents = try? JSONDecoder().decode([Document].self, from: data) {
            print("ProjectSummaryView: Loaded \(documents.count) documents from cache for project \(projectId)")
            return documents
        }
        print("ProjectSummaryView: Failed to load documents from cache or cache file does not exist for project \(projectId)")
        return nil
    }

    private func saveAttachmentPathMapToCache(_ map: [String: String]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(map)
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("form_attachment_paths_\(projectId).json")
            try data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(map.count) attachment paths to cache.")
        } catch {
            print("ProjectSummaryView: FAILED to encode or save attachment path map. Error: \(error)")
        }
    }

    private func savePhotoPathMapToCache(_ map: [String: String]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(map)
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("photo_paths_project_\(projectId).json")
            try data.write(to: cacheURL)
            print("ProjectSummaryView: Saved \(map.count) photo paths to cache.")
        } catch {
            print("ProjectSummaryView: FAILED to encode or save photo path map. Error: \(error)")
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

    struct EnhancedStatCard: View {
        let title: String
        let value: String
        let trend: String
        let icon: String
        let color: Color
        let destination: AnyView

        var body: some View {
            NavigationLink(destination: destination) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(color)
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                    
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if !trend.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: trend.first == "+" ? "arrow.up.right.and.arrow.down.left" : "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12))
                                .foregroundColor(trend.first == "+" ? .green : .red)
                            Text(trend)
                                .font(.caption2)
                                .foregroundColor(trend.first == "+" ? .green : .red)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
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
        @State private var isPressed = false
        
        var body: some View {
            VStack(spacing: 12) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [color, color.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
                
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
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(isSelected ? 0.4 : 0), color.opacity(isSelected ? 0.2 : 0)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.02 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
    }
    
    private var statusColor: Color {
        guard let status = projectStatus else { return .gray }
        switch status.lowercased() {
        case "in_progress": return .green
        case "planning": return Color(hex: "#0891b2")
        case "completed": return .purple
        default: return .gray
        }
    }
    
    // MARK: - Chat Floating Button
    private var chatFloatingButton: some View {
        Button(action: {
            showChat = true
        }) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#3B82F6"))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Image(systemName: "ellipsis.bubble")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(showChat ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showChat)
        .accessibilityLabel("Open AI Chat")
        .accessibilityHint("Start a conversation with AI about your project")
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

struct RecentDrawingCard: View {
    let recentDrawing: RecentDrawingsManager.RecentDrawing
    let projectName: String
    let token: String
    let isProjectOffline: Bool
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @State private var drawings: [Drawing] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationLink(destination: destinationView) {
            if let drawing = drawings.first(where: { $0.id == recentDrawing.id }) {
                // Use DrawingRow style for consistency
                DrawingRow(
                    drawing: drawing,
                    token: token,
                    searchText: nil,
                    isLastViewed: false
                )
                .frame(width: 320) // Fixed width for horizontal scroll
            } else if isLoading {
                // Loading state
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 320, height: 120)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                // Fallback for when drawing not loaded yet
            VStack(alignment: .leading, spacing: 8) {
                // Drawing icon with background
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#3B82F6").opacity(0.1))
                        .frame(height: 60)
                    
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(recentDrawing.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text("No: \(recentDrawing.number)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(timeAgoString)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
                .frame(width: 320, height: 120)
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadDrawings()
        }
    }
    
    @ViewBuilder
    private var destinationView: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let drawing = drawings.first(where: { $0.id == recentDrawing.id }) {
            DrawingGalleryView(
                drawings: drawings,
                initialDrawing: drawing,
                isProjectOffline: isProjectOffline
            )
            .environmentObject(sessionManager)
            .environmentObject(networkStatusManager)
        } else {
            Text("Drawing not found")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: recentDrawing.lastAccessedAt, relativeTo: Date())
    }
    
    private func loadDrawings() {
        guard drawings.isEmpty else { return }
        
        isLoading = true
        Task {
            do {
                let fetchedDrawings = try await APIClient.fetchDrawings(projectId: recentDrawing.projectId, token: token)
                await MainActor.run {
                    self.drawings = fetchedDrawings
                    self.isLoading = false
                }
            } catch {
                print("RecentDrawingCard: Error loading drawings: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
