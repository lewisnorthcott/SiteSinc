import SwiftUI
import WebKit
import Foundation
import Network

enum DrawingSortOrder {
    case newestFirst
    case oldestFirst
    case alphabetical
}

enum DrawingDisplayMode {
    case list
    case grid
    case table
    case folder
}

// Token-based search helper function
// Splits search text into words and checks if all words appear in the target text
private func matchesTokenBased(searchText: String, text: String) -> Bool {
    let searchTokens = searchText.lowercased().split(separator: " ").map { String($0) }
    guard !searchTokens.isEmpty else { return false }
    
    let lowercasedText = text.lowercased()
    
    // All search tokens must appear in the text
    return searchTokens.allSatisfy { token in
        guard !token.isEmpty else { return true }
        
        // For single characters, enforce word boundary on BOTH sides to avoid partial matches
        // e.g. "C" should match "Block C" but NOT "C24" or "Concrete"
        if token.count == 1 {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
            return lowercasedText.range(of: pattern, options: .regularExpression) != nil
        }
        
        return lowercasedText.contains(token)
    }
}

struct DrawingListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @StateObject private var progressManager = DownloadProgressManager.shared
    @State private var drawings: [Drawing] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var filters: DrawingFilters = DrawingFilters()
    @State private var drawingFolders: [DrawingFolder] = []
    @State private var displayMode: DrawingDisplayMode = .list
    @State private var showCreateRFI = false
    @State private var isProjectOffline: Bool = false
    @State private var showFilters: Bool = false
    @State private var searchText: String = ""
    @State private var sortOrder: DrawingSortOrder = .newestFirst
    @State private var scrollToDrawingId: Int? = nil
    @State private var navigateToDrawingNumber: String? = nil
    @State private var showDrawingViewer: Drawing? = nil
    @State private var showFolderSettings: Bool = false

    var filteredDrawings: [Drawing] {
        drawings.filter { drawing in
            // Apply filter first
            let passesFilters = filters.matches(drawing)

            // Apply search if there's search text
            if !searchText.isEmpty {
                let matchesTitle = matchesTokenBased(searchText: searchText, text: drawing.title)
                let matchesNumber = matchesTokenBased(searchText: searchText, text: drawing.number)
                return passesFilters && (matchesTitle || matchesNumber)
            }

            return passesFilters
        }
        .sorted { (lhs: Drawing, rhs: Drawing) in
            switch sortOrder {
            case DrawingSortOrder.newestFirst:
                // Sort by most recent revision date (latest revision's uploadedAt or archivedAt)
                let lhsLatestRevision = lhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })
                let rhsLatestRevision = rhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })

                let lhsDate = lhsLatestRevision?.uploadedAt ?? lhsLatestRevision?.archivedAt ?? lhs.updatedAt ?? lhs.createdAt ?? ""
                let rhsDate = rhsLatestRevision?.uploadedAt ?? rhsLatestRevision?.archivedAt ?? rhs.updatedAt ?? rhs.createdAt ?? ""

                return lhsDate > rhsDate
            case DrawingSortOrder.oldestFirst:
                // Sort by oldest revision date
                let lhsLatestRevision = lhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })
                let rhsLatestRevision = rhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })

                let lhsDate = lhsLatestRevision?.uploadedAt ?? lhsLatestRevision?.archivedAt ?? lhs.updatedAt ?? lhs.createdAt ?? ""
                let rhsDate = rhsLatestRevision?.uploadedAt ?? rhsLatestRevision?.archivedAt ?? rhs.updatedAt ?? rhs.createdAt ?? ""

                return lhsDate < rhsDate
            case DrawingSortOrder.alphabetical:
                // Sort alphabetically by title
                return lhs.title.lowercased() < rhs.title.lowercased()
            }
        }
    }
    





    private var filterToolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { showFilters.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text("Filters")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                        if filters.hasActiveFilters {
                            Circle()
                                .fill(Color(hex: "#3B82F6"))
                                .frame(width: 6, height: 6)
                        }
                    }
                }

                if filters.hasActiveFilters {
                    Button(action: {
                        filters = DrawingFilters()
                    }) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#3B82F6"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#3B82F6").opacity(0.1))
                            .cornerRadius(6)
                    }
                }

                Spacer()

                Menu {
                    Button(action: {
                        sortOrder = DrawingSortOrder.newestFirst
                    }) {
                        HStack {
                            Text("Newest")
                            if sortOrder == DrawingSortOrder.newestFirst {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    Button(action: {
                        sortOrder = DrawingSortOrder.oldestFirst
                    }) {
                        HStack {
                            Text("Oldest")
                            if sortOrder == DrawingSortOrder.oldestFirst {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    Button(action: {
                        sortOrder = DrawingSortOrder.alphabetical
                    }) {
                        HStack {
                            Text("A-Z")
                            if sortOrder == DrawingSortOrder.alphabetical {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(hex: "#FFFFFF"))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var searchSection: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Color(hex: "#FFFFFF"))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var mainContent: some View {
        Group {
            if isLoading {
                ProgressView("Loading Drawings...")
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                    .padding()
                    .frame(maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.red)
                        .padding()
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        fetchDrawings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#3B82F6"))
                    .accessibilityLabel("Retry loading drawings")
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else if filteredDrawings.isEmpty {
                DrawingEmptyStateView(searchText: searchText, hasActiveFilters: filters.hasActiveFilters)
                    .frame(maxHeight: .infinity)
            } else {
                drawingsScrollView
            }
        }
    }

    private var drawingsScrollView: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                switch displayMode {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(filteredDrawings, id: \.id) { drawing in
                            NavigationLink(destination: DrawingGalleryView(
                                drawings: drawings,
                                initialDrawing: drawing,
                                isProjectOffline: isProjectOffline
                            ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                DrawingCard(drawing: drawing, token: token)
                            }
                            .id(drawing.id)
                            .simultaneousGesture(TapGesture().onEnded {
                                UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                            })
                        }
                    }
                    .padding()
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(filteredDrawings, id: \.id) { drawing in
                            NavigationLink(destination: DrawingGalleryView(
                                drawings: drawings,
                                initialDrawing: drawing,
                                isProjectOffline: isProjectOffline
                            ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                DrawingRow(
                                    drawing: drawing,
                                    token: token,
                                    searchText: searchText.isEmpty ? nil : searchText,
                                    isLastViewed: scrollToDrawingId == drawing.id
                                )
                            }
                            .id(drawing.id)
                            .simultaneousGesture(TapGesture().onEnded {
                                UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                            })
                        }
                    }
                    .padding()
                case .table:
                    DrawingTableView(drawings: filteredDrawings, token: token, projectId: projectId, isProjectOffline: isProjectOffline)
                        .environmentObject(sessionManager)
                        .environmentObject(networkStatusManager)
                        .frame(maxWidth: .infinity)
                case .folder:
                    DrawingFolderView(
                        drawings: filteredDrawings,
                        folders: drawingFolders,
                        token: token,
                        projectId: projectId,
                        projectName: projectName,
                        isProjectOffline: isProjectOffline,
                        searchText: searchText.isEmpty ? nil : searchText
                    )
                    .environmentObject(sessionManager)
                    .environmentObject(networkStatusManager)
                }
            }
            .onAppear {
                if let drawingId = scrollToDrawingId {
                    scrollViewProxy.scrollTo(drawingId, anchor: .center)
                }
            }
            .onChange(of: drawings.count) { _, _ in
                if let drawingId = scrollToDrawingId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollViewProxy.scrollTo(drawingId, anchor: .center)
                    }
                }
            }
        }
        .refreshable {
            fetchDrawings()
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                filterToolbar
                searchSection
                mainContent
            }
        }
        .navigationTitle("Drawings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Settings button when folder view is selected
            if displayMode == .folder {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFolderSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "#3B82F6"))
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { displayMode = .list }) {
                        HStack {
                            Text("List View")
                            if displayMode == .list {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    Button(action: { displayMode = .grid }) {
                        HStack {
                            Text("Grid View")
                            if displayMode == .grid {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button(action: { displayMode = .table }) {
                            HStack {
                                Text("Table View")
                                if displayMode == .table {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "#3B82F6"))
                                }
                            }
                        }
                    }
                    #endif
                    
                    Button(action: { displayMode = .folder }) {
                        HStack {
                            Text("Folder View")
                            if displayMode == .folder {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }
                } label: {
                    Image(systemName: {
                        switch displayMode {
                        case .list: return "list.bullet"
                        case .grid: return "square.grid.2x2.fill"
                        case .table: return "tablecells"
                        case .folder: return "folder.fill"
                        }
                    }())
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
            }
        }
        .onAppear {
            DrawingAccessLogger.shared.flushQueue()
            print("DrawingListView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
            fetchDrawings()
            fetchDrawingFolders()
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                displayMode = .table
            }
            #endif
            isProjectOffline = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
            print("DrawingListView: isProjectOffline set to \(isProjectOffline)")

            if let savedDrawingId = UserDefaults.standard.value(forKey: "lastViewedDrawing_\(projectId)") as? Int {
                scrollToDrawingId = savedDrawingId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDrawing"))) { notification in
            if let userInfo = notification.userInfo,
               let targetProjectId = userInfo["projectId"] as? Int,
               targetProjectId == projectId {
                // Handle navigation to specific drawing
                if let drawingId = userInfo["drawingId"] as? Int {
                    scrollToDrawingId = drawingId
                    // Find the drawing and open it
                    if let drawing = drawings.first(where: { $0.id == drawingId }) {
                        showDrawingViewer = drawing
                    } else {
                        // Drawing not loaded yet, wait for drawings to load
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let drawing = drawings.first(where: { $0.id == drawingId }) {
                                showDrawingViewer = drawing
                            }
                        }
                    }
                } else if let drawingNumber = userInfo["drawingNumber"] as? String {
                    navigateToDrawingNumber = drawingNumber
                    // Find drawing by number
                    if let drawing = drawings.first(where: { $0.number == drawingNumber }) {
                        scrollToDrawingId = drawing.id
                        showDrawingViewer = drawing
                    } else {
                        // Drawing not loaded yet, wait for drawings to load
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let drawing = drawings.first(where: { $0.number == drawingNumber }) {
                                scrollToDrawingId = drawing.id
                                showDrawingViewer = drawing
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: drawings.count) { oldCount, newCount in
            // Handle navigation after drawings are loaded
            // Only auto-open if we have a navigateToDrawingNumber (from notification)
            // Don't auto-open just because scrollToDrawingId exists (that's just for scrolling)
            if let drawingNumber = navigateToDrawingNumber,
               let drawing = drawings.first(where: { $0.number == drawingNumber }) {
                scrollToDrawingId = drawing.id
                showDrawingViewer = drawing
                navigateToDrawingNumber = nil
            }
            // Removed auto-opening on scrollToDrawingId - that should only scroll, not open
        }
        .sheet(isPresented: $showFolderSettings) {
            FolderViewSettingsView(
                settings: Binding(
                    get: { FolderViewSettings.load(for: projectId) },
                    set: { 
                        $0.save(for: projectId)
                        // Refresh folder view if needed
                    }
                ),
                isPresented: $showFolderSettings,
                projectId: projectId
            )
        }
        .sheet(item: $showDrawingViewer) { drawing in
            NavigationView {
                DrawingGalleryView(
                    drawings: drawings,
                    initialDrawing: drawing,
                    isProjectOffline: isProjectOffline
                )
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
            }
        }
        .sheet(isPresented: $showFilters) {
            DrawingFiltersView(
                filters: $filters,
                drawings: drawings,
                folders: drawingFolders,
                isPresented: $showFilters
            )
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
                showCreateRFI = false
            }, prefilledTitle: nil, prefilledAttachmentData: nil, prefilledDrawing: nil, sourceMarkup: nil)
        }
    }

    private func fetchDrawings() {
        isLoading = true
        errorMessage = nil
        Task {
            // Offline-first: try local first
            if let cached = loadDrawingsFromCache(), !cached.isEmpty {
                await MainActor.run {
                    drawings = cached.map { var d = $0; d.isOffline = checkOfflineStatus(for: d); return d }
                    isLoading = false
                    errorMessage = nil
                }
            }

            if networkStatusManager.isNetworkAvailable {
                do {
                    print("DrawingListView: Fetching drawings from API for project \(projectId)")
                    let d = try await APIClient.fetchDrawings(projectId: projectId, token: token)
                    print("DrawingListView: Successfully fetched \(d.count) drawings from API")
                    await MainActor.run {
                        drawings = d.map {
                            var drawing = $0
                            drawing.isOffline = checkOfflineStatus(for: drawing)
                            return drawing
                        }
                        saveDrawingsToCache(drawings)
                        #if os(iOS)
                        if UIDevice.current.userInterfaceIdiom == .pad && !drawings.isEmpty && displayMode != .grid {
                            // Auto-switch to grid view on iPad if not already in grid mode
                        }
                        #endif
                        isLoading = false
                    }
                } catch APIError.tokenExpired {
                    print("DrawingListView: Token expired error")
                    await MainActor.run {
                        sessionManager.handleTokenExpiration()
                    }
                } catch APIError.forbidden {
                    print("DrawingListView: Forbidden (treat as expired session)")
                    await MainActor.run {
                        sessionManager.handleTokenExpiration()
                    }
                } catch {
                    print("DrawingListView: Error fetching drawings from API: \(error.localizedDescription), code: \((error as NSError).code)")
                    await loadFromCacheOnError(error: error)
                }
            } else if drawings.isEmpty {
                print("DrawingListView: Device is offline, attempting to load cached drawings")
                await loadFromCacheOnError(error: NSError(domain: "", code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "Device is offline"]))
            }
        }
    }

    private func fetchDrawingFolders() {
        Task {
            if networkStatusManager.isNetworkAvailable {
                do {
                    let (_, folders) = try await APIClient.fetchDrawingFolders(projectId: projectId, token: token)
                    await MainActor.run {
                        drawingFolders = folders
                    }
                } catch {
                    print("DrawingListView: Error fetching drawing folders: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadFromCacheOnError(error: Error) async {
        await MainActor.run {
            isLoading = false
            if let cachedDrawings = loadDrawingsFromCache(), !cachedDrawings.isEmpty {
                print("DrawingListView: Loaded \(cachedDrawings.count) cached drawings: \(cachedDrawings.map { $0.title })")
                drawings = cachedDrawings.map {
                    var drawing = $0
                    drawing.isOffline = checkOfflineStatus(for: drawing)
                    return drawing
                }
                errorMessage = nil // Clear errorMessage to show the list
            } else {
                if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                    errorMessage = isProjectOffline
                        ? "Offline: No cached drawings available. Ensure the project was downloaded while online."
                        : "Offline: Offline mode not enabled. Please enable offline mode and download the project while online."
                } else {
                    errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                }
                print("DrawingListView: Failed to load cached drawings - errorMessage set to: \(errorMessage ?? "nil")")
            }
        }
    }

    private func checkOfflineStatus(for drawing: Drawing) -> Bool {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)/drawings")
        
        let pdfFiles = drawing.revisions.flatMap { $0.drawingFiles }.filter { $0.fileName.lowercased().hasSuffix(".pdf") }
        if pdfFiles.isEmpty { return false }
        
        return pdfFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(file.fileName).path)
        }
    }

    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(drawings)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let cacheURL = base.appendingPathComponent("drawings_project_\(projectId).json")
            try data.write(to: cacheURL)
            print("DrawingListView: Successfully saved \(drawings.count) drawings to cache at \(cacheURL.path)")
        } catch {
            print("DrawingListView: Failed to save drawings to cache: \(error.localizedDescription)")
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("drawings_project_\(projectId).json")
        do {
            if !FileManager.default.fileExists(atPath: cacheURL.path) {
                print("DrawingListView: Cache file does not exist at \(cacheURL.path)")
                return nil
            }
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let cachedDrawings = try decoder.decode([Drawing].self, from: data)
            print("DrawingListView: Successfully loaded \(cachedDrawings.count) drawings from cache at \(cacheURL.path)")
            return cachedDrawings
        } catch {
            print("DrawingListView: Failed to load drawings from cache: \(error.localizedDescription)")
            return nil
        }
    }
}





struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? Color(hex: "#3B82F6") : Color(hex: "#9CA3AF"))

            TextField("Search drawings by title or number...", text: $text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    isFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(hex: "#9CA3AF"))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isFocused ? Color.white : Color(hex: "#EFF2F7"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color(hex: "#3B82F6").opacity(0.7) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct FilteredDrawingsView: View {
    let drawings: [Drawing]
    let groupName: String
    let token: String
    let projectName: String
    let projectId: Int
    @Binding var displayMode: DrawingDisplayMode
    let onRefresh: () -> Void
    let isProjectOffline: Bool
    let folders: [DrawingFolder] // Add folders parameter
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    
    @State private var showCreateRFI = false
    @State private var searchText: String = "" // Add state for search text

    // Filter drawings based on search text
    private var filteredDrawings: [Drawing] {
        if searchText.isEmpty {
            return drawings.sorted { (lhs: Drawing, rhs: Drawing) in
                // Sort by most recent revision date (latest revision's uploadedAt or archivedAt)
                let lhsLatestRevision = lhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })
                let rhsLatestRevision = rhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })

                let lhsDate = lhsLatestRevision?.uploadedAt ?? lhsLatestRevision?.archivedAt ?? lhs.updatedAt ?? lhs.createdAt ?? ""
                let rhsDate = rhsLatestRevision?.uploadedAt ?? rhsLatestRevision?.archivedAt ?? rhs.updatedAt ?? rhs.createdAt ?? ""

                return lhsDate > rhsDate
            }
        } else {
            return drawings
                .filter {
                    matchesTokenBased(searchText: searchText, text: $0.title) ||
                    matchesTokenBased(searchText: searchText, text: $0.number)
                }
                .sorted { (lhs: Drawing, rhs: Drawing) in
                    // Sort by most recent revision date (latest revision's uploadedAt or archivedAt)
                    let lhsLatestRevision = lhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })
                    let rhsLatestRevision = rhs.revisions.max(by: { $0.versionNumber < $1.versionNumber })

                    let lhsDate = lhsLatestRevision?.uploadedAt ?? lhsLatestRevision?.archivedAt ?? lhs.updatedAt ?? lhs.createdAt ?? ""
                    let rhsDate = rhsLatestRevision?.uploadedAt ?? rhsLatestRevision?.archivedAt ?? rhs.updatedAt ?? rhs.createdAt ?? ""

                    return lhsDate > rhsDate
                }
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Add SearchBar below the navigation bar
                SearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#FFFFFF"))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                if filteredDrawings.isEmpty {
                    Text(searchText.isEmpty ? "No drawings found for \(groupName)" : "No drawings match your search in \(groupName).")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding()
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        switch displayMode {
                        case .grid:
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                                ForEach(filteredDrawings, id: \.id) { drawing in
                                    NavigationLink(destination: DrawingGalleryView(
                                        drawings: drawings,
                                        initialDrawing: drawing,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                        DrawingCard(drawing: drawing, token: token)
                                    }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                                    })
                                }
                            }
                            .padding()
                        case .list:
                            LazyVStack(spacing: 12) {
                                ForEach(filteredDrawings, id: \.id) { drawing in
                                    NavigationLink(destination: DrawingGalleryView(
                                        drawings: drawings,
                                        initialDrawing: drawing,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                        DrawingRow(
                                            drawing: drawing,
                                            token: token,
                                            searchText: searchText.isEmpty ? nil : searchText,
                                            isLastViewed: {
                                                if let lastViewedId = UserDefaults.standard.value(forKey: "lastViewedDrawing_\(projectId)") as? Int {
                                                    return lastViewedId == drawing.id
                                                }
                                                return false
                                            }()
                                        )
                                    }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                                    })
                                }
                            }
                            .padding()
                        case .table:
                            DrawingTableView(drawings: filteredDrawings, token: token, projectId: projectId, isProjectOffline: isProjectOffline)
                                .environmentObject(sessionManager)
                                .environmentObject(networkStatusManager)
                        case .folder:
                            DrawingFolderView(
                                drawings: filteredDrawings,
                                folders: folders,
                                token: token,
                                projectId: projectId,
                                projectName: projectName,
                                isProjectOffline: isProjectOffline,
                                searchText: searchText.isEmpty ? nil : searchText
                            )
                            .environmentObject(sessionManager)
                            .environmentObject(networkStatusManager)
                        }
                    }
                    .refreshable {
                        onRefresh()
                    }
                }
            }
            
//            VStack {
//                Spacer()
//                HStack {
//                    Spacer()
//                    Menu {
//                        Button(action: { showCreateRFI = true }) {
//                            Label("New RFI", systemImage: "doc.text.fill")
//                        }
//                    } label: {
//                        Image(systemName: "plus")
//                            .font(.system(size: 24, weight: .semibold))
//                            .foregroundColor(.white)
//                            .frame(width: 56, height: 56)
//                            .background(Color(hex: "#3B82F6"))
//                            .clipShape(Circle())
//                            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
//                            .contentShape(Circle())
//                    }
//                    .padding(.trailing, 20)
//                    .padding(.bottom, 20)
//                    .accessibilityLabel("Create new item")
//                }
//            }
        }
        .navigationTitle("\(groupName)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { displayMode = .list }) {
                        HStack {
                            Text("List View")
                            if displayMode == .list {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    Button(action: { displayMode = .grid }) {
                        HStack {
                            Text("Grid View")
                            if displayMode == .grid {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }

                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button(action: { displayMode = .table }) {
                            HStack {
                                Text("Table View")
                                if displayMode == .table {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "#3B82F6"))
                                }
                            }
                        }
                    }
                    #endif
                    
                    Button(action: { displayMode = .folder }) {
                        HStack {
                            Text("Folder View")
                            if displayMode == .folder {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                    }
                } label: {
                    Image(systemName: {
                        switch displayMode {
                        case .list: return "list.bullet"
                        case .grid: return "square.grid.2x2.fill"
                        case .table: return "tablecells"
                        case .folder: return "folder.fill"
                        }
                    }())
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
            }
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
                showCreateRFI = false
            }, prefilledTitle: nil, prefilledAttachmentData: nil, prefilledDrawing: nil, sourceMarkup: nil)
        }
        .onAppear {
            print("FilteredDrawingsView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
        }
    }
}


// Status badge component with color coding for drawings
struct DrawingStatusBadge: View {
    let status: String
    
    private var statusColor: Color {
        switch status.lowercased() {
        case "approved":
            return Color(hex: "#059669")
        case "draft":
            return Color(hex: "#D97706")
        case "for information":
            return Color(hex: "#3B82F6")
        case "superseded":
            return Color(hex: "#DC2626")
        default:
            return Color(hex: "#6B7280")
        }
    }
    
    private var backgroundColor: Color {
        switch status.lowercased() {
        case "approved":
            return Color(hex: "#D1FAE5")
        case "draft":
            return Color(hex: "#FED7AA")
        case "for information":
            return Color(hex: "#DBEAFE")
        case "superseded":
            return Color(hex: "#FEE2E2")
        default:
            return Color(hex: "#F3F4F6")
        }
    }
    
    var body: some View {
        Text(status)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// Text component with search highlighting
struct HighlightedText: View {
    let text: String
    let searchText: String
    
    var body: some View {
        if searchText.isEmpty {
            Text(text)
        } else {
            let tokens = searchText.lowercased().split(separator: " ").map { String($0) }
            let attributedString = createAttributedString(text: text, searchTokens: tokens)
            Text(AttributedString(attributedString))
        }
    }
    
    private func createAttributedString(text: String, searchTokens: [String]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let lowercasedText = text.lowercased()
        
        for token in searchTokens where !token.isEmpty {
            var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
            while let range = lowercasedText.range(of: token, range: searchRange) {
                let nsRange = NSRange(range, in: lowercasedText)
                // Use SwiftUI-compatible attributes
                if #available(iOS 15.0, *) {
                    attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: nsRange)
                } else {
                    attributedString.addAttribute(.backgroundColor, value: UIColor.yellow.withAlphaComponent(0.3), range: nsRange)
                }
                if range.upperBound < lowercasedText.endIndex {
                    searchRange = range.upperBound..<lowercasedText.endIndex
                } else {
                    break
                }
            }
        }
        
        return attributedString
    }
}

// Drawing thumbnail view component
struct DrawingThumbnailView: View {
    let fileId: Int?
    let token: String
    var width: CGFloat = 80
    var height: CGFloat = 60
    @State private var thumbnailURL: String?
    @State private var isLoading: Bool = false
    @State private var hasError: Bool = false
    
    var body: some View {
        Group {
            if let urlString = thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: width, height: height)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: width, height: height)
                            .background(Color.white)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    case .failure:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
            } else {
                fallbackIcon
            }
        }
        .onAppear {
            if let fileId = fileId, thumbnailURL == nil && !isLoading {
                loadThumbnail(fileId: fileId)
            }
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
                .frame(width: width, height: height)
            
            Image(systemName: "doc.text.fill")
                .font(.system(size: min(width, height) * 0.3))
                .foregroundColor(Color.gray.opacity(0.5))
        }
    }
    
    private func loadThumbnail(fileId: Int) {
        isLoading = true
        hasError = false
        
        Task {
            do {
                let response = try await APIClient.fetchDrawingThumbnail(fileId: fileId, token: token)
                await MainActor.run {
                    thumbnailURL = response.url
                    isLoading = false
                    hasError = response.url == nil
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    hasError = true
                }
            }
        }
    }
}

struct DrawingRow: View {
    let drawing: Drawing
    let token: String
    let searchText: String? // Optional search text for highlighting
    let isLastViewed: Bool // Indicates if this is the last viewed drawing
    @State private var isFavourite: Bool
    @State private var isLoading: Bool = false
    
    // Get latest PDF file ID for thumbnail
    private var latestPDFFileId: Int? {
        guard let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
              let pdfFile = latestRevision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) else {
            return nil
        }
        return pdfFile.id
    }

    init(drawing: Drawing, token: String, searchText: String? = nil, isLastViewed: Bool = false) {
        self.drawing = drawing
        self.token = token
        self.searchText = searchText
        self.isLastViewed = isLastViewed
        self._isFavourite = State(initialValue: drawing.isFavourite ?? false)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status indicator bar (left border)
            statusIndicatorBar
            
            VStack(alignment: .leading, spacing: 4) {
                // Title at the top - spans FULL WIDTH over the thumbnail area
                HStack(spacing: 6) {
                    if let searchText = searchText, !searchText.isEmpty {
                        HighlightedText(text: drawing.title, searchText: searchText)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(drawing.title)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Archived indicator
                    if drawing.archived == true {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7280"))
                            .padding(4)
                            .background(Color(hex: "#6B7280").opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                
                // Bottom row - thumbnail on left, content on right
                HStack(alignment: .top, spacing: 8) {
                    // Thumbnail
                    DrawingThumbnailView(fileId: latestPDFFileId, token: token)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Drawing number with search highlighting
                        if let searchText = searchText, !searchText.isEmpty {
                            HighlightedText(text: "No: \(drawing.number)", searchText: searchText)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(hex: "#6B7280"))
                                .lineLimit(1)
                        } else {
                            Text("No: \(drawing.number)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(hex: "#6B7280"))
                                .lineLimit(1)
                        }
                        
                        // Revision, Category, and Discipline stacked vertically
                        VStack(alignment: .leading, spacing: 3) {
                            // Revision (without "Rev: " prefix)
                            if let rev = latestRevisionText(drawing: drawing) {
                                Text(rev)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7280"))
                            }
                            
                            // Category (Type)
                            if let typeName = drawing.projectDrawingType?.name, !typeName.isEmpty {
                                Text(typeName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7280"))
                            }
                            
                            // Discipline
                            if let disciplineName = drawing.projectDiscipline?.name, !disciplineName.isEmpty {
                                Text(disciplineName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7280"))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Right side: Revs badge, Status badge, and icons
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(drawing.revisions.count) Revs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#3B82F6").opacity(0.8))
                            .clipShape(Capsule())
                        
                        // Status badge underneath Revs badge
                        if let status = latestStatusText(drawing: drawing), !status.isEmpty {
                            DrawingStatusBadge(status: status)
                        }
                        
                        Spacer()
                        
                        // Favorite and Cloud icons at bottom right
                        HStack(spacing: 8) {
                            Button(action: {
                                Task {
                                    await toggleFavorite()
                                }
                            }) {
                                Image(systemName: isFavourite ? "star.fill" : "star")
                                    .font(.system(size: 16))
                                    .foregroundColor(isFavourite ? Color(hex: "#F59E0B") : Color(hex: "#9CA3AF"))
                            }
                            .disabled(isLoading)
                            .buttonStyle(.plain)

                            Image(systemName: drawing.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                                .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                                .font(.system(size: 18))
                        }
                    }
                }
            }
            .padding(.leading, 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
    
    // Status indicator bar on the left
    private var statusIndicatorBar: some View {
        Rectangle()
            .fill(statusColor)
            .frame(width: 3)
            .opacity(0.6)
    }
    
    // Background color based on status
    private var backgroundColor: Color {
        if isLastViewed {
            return Color(hex: "#3B82F6").opacity(0.03)
        }
        return Color(hex: "#FFFFFF")
    }
    
    // Border color and width
    private var borderColor: Color {
        if isLastViewed {
            return Color(hex: "#3B82F6").opacity(0.3)
        }
        return Color.clear
    }
    
    private var borderWidth: CGFloat {
        isLastViewed ? 1 : 0
    }
    
    // Status color based on latest revision status
    private var statusColor: Color {
        if let status = latestStatusText(drawing: drawing) {
            return statusColor(for: status)
        }
        return Color(hex: "#3B82F6")
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "approved":
            return Color(hex: "#059669")
        case "draft":
            return Color(hex: "#D97706")
        case "for information":
            return Color(hex: "#3B82F6")
        case "superseded":
            return Color(hex: "#DC2626")
        default:
            return Color(hex: "#6B7280")
        }
    }

    private func toggleFavorite() async {
        guard !isLoading else { return }

        isLoading = true

        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        do {
            let newStatus = try await APIClient.toggleDrawingFavorite(drawingId: drawing.id, token: token)
            await MainActor.run {
                isFavourite = newStatus.isFavourite
                isLoading = false

                // Success haptic feedback
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
            }
        } catch {
            print("Error toggling favorite: \(error)")
            await MainActor.run {
                isLoading = false

                // Error haptic feedback
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
            }
        }
    }

    private func latestRevisionText(drawing: Drawing) -> String? {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            return latest.revisionNumber ?? String(latest.versionNumber)
        }
        return nil
    }

    private func latestStatusText(drawing: Drawing) -> String? {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            return latest.status
        }
        return drawing.status
    }

    private func compactMetadata(for drawing: Drawing) -> [String] {
        var items: [String] = []
        if let disciplineName = drawing.projectDiscipline?.name, !disciplineName.isEmpty {
            items.append(compactText(disciplineName))
        }
        if let typeName = drawing.projectDrawingType?.name, !typeName.isEmpty {
            items.append(compactText(typeName))
        }
        if let status = latestStatusText(drawing: drawing), !status.isEmpty {
            items.append(compactText(status))
        }
        if let rev = latestRevisionText(drawing: drawing) {
            items.append("Rev: \(rev)")
        }
        return items
    }
    
    // Metadata without status (status is shown separately as a badge)
    private func compactMetadataWithoutStatus(for drawing: Drawing) -> [String] {
        var items: [String] = []
        if let disciplineName = drawing.projectDiscipline?.name, !disciplineName.isEmpty {
            items.append(compactText(disciplineName))
        }
        if let typeName = drawing.projectDrawingType?.name, !typeName.isEmpty {
            items.append(compactText(typeName))
        }
        if let rev = latestRevisionText(drawing: drawing) {
            items.append("Rev: \(rev)")
        }
        return items
    }

    private func compactText(_ text: String, maxLength: Int = 12) -> String {
        var t = text
        t = t.replacingOccurrences(of: "Engineer", with: "")
        t = t.replacingOccurrences(of: "Engineering", with: "")
        t = t.replacingOccurrences(of: "Services", with: "")
        t = t.replacingOccurrences(of: "Plans", with: "")
        t = t.trimmingCharacters(in: .whitespaces)
        if t.count > maxLength {
            let idx = t.index(t.startIndex, offsetBy: maxLength)
            return String(t[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return t
    }
}

struct DrawingCard: View {
    let drawing: Drawing
    let token: String
    @State private var isFavourite: Bool
    @State private var isLoading: Bool = false

    init(drawing: Drawing, token: String) {
        self.drawing = drawing
        self.token = token
        self._isFavourite = State(initialValue: drawing.isFavourite ?? false)
    }

    // Get latest PDF file ID for thumbnail
    private var latestPDFFileId: Int? {
        guard let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
              let pdfFile = latestRevision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) else {
            return nil
        }
        return pdfFile.id
    }
    
    private func latestRevisionText(drawing: Drawing) -> String? {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            return latest.revisionNumber ?? String(latest.versionNumber)
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            GeometryReader { geometry in
                DrawingThumbnailView(fileId: latestPDFFileId, token: token, width: geometry.size.width, height: 120)
            }
            .frame(height: 120)
            .clipped()

            HStack {
                Text(drawing.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded)) // Increased font size, semibold for clarity
                    .foregroundColor(Color(hex: "#1F2A44"))
                    .lineLimit(2) // Allow wrapping to 2 lines
                    .minimumScaleFactor(0.8) // Scale down if needed
                
                // Archived indicator
                if drawing.archived == true {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(hex: "#6B7280").opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Text("No: \(drawing.number)")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(hex: "#6B7280"))
            
            // Revision, Category, and Discipline
            HStack(spacing: 6) {
                // Revision
                if let rev = latestRevisionText(drawing: drawing) {
                    Text("Rev: \(rev)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                
                // Category (Type)
                if let typeName = drawing.projectDrawingType?.name, !typeName.isEmpty {
                    Text("•")
                        .foregroundColor(Color(hex: "#9CA3AF"))
                    Text(typeName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .lineLimit(1)
                }
                
                // Discipline
                if let disciplineName = drawing.projectDiscipline?.name, !disciplineName.isEmpty {
                    Text("•")
                        .foregroundColor(Color(hex: "#9CA3AF"))
                    Text(disciplineName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .lineLimit(1)
                }
            }
            
            Spacer()

            HStack {
                Image(systemName: drawing.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                    .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                    .font(.system(size: 16))

                Spacer()

                Button(action: {
                    Task {
                        await toggleFavorite()
                    }
                }) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(isFavourite ? Color(hex: "#F59E0B") : Color(hex: "#9CA3AF"))
                }
                .disabled(isLoading)
                .buttonStyle(.plain)

                Text("\(drawing.revisions.count) Revs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#4B5563"))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, idealHeight: 160, maxHeight: 170)
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private func toggleFavorite() async {
        guard !isLoading else { return }

        isLoading = true

        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        do {
            let newStatus = try await APIClient.toggleDrawingFavorite(drawingId: drawing.id, token: token)
            await MainActor.run {
                isFavourite = newStatus.isFavourite
                isLoading = false

                // Success haptic feedback
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
            }
        } catch {
            print("Error toggling favorite: \(error)")
            await MainActor.run {
                isLoading = false

                // Error haptic feedback
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
            }
        }
    }
}

struct DrawingEmptyStateView: View {
    let searchText: String
    let hasActiveFilters: Bool

    private var message: String {
        let hasActiveSearch = !searchText.isEmpty

        if hasActiveSearch && hasActiveFilters {
            return "No drawings match your search and filters."
        } else if hasActiveSearch {
            return "No drawings match your search."
        } else if hasActiveFilters {
            return "No drawings match your filters."
        } else {
            return "No drawings found for this project."
        }
    }

    var body: some View {
        Text(message)
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundColor(Color(hex: "#6B7280"))
            .padding()
    }
}

struct DrawingTableView: View {
    let drawings: [Drawing]
    let token: String
    let projectId: Int
    let isProjectOffline: Bool
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    

    private func latestRevisionText(for drawing: Drawing) -> String? {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            return latest.revisionNumber ?? String(latest.versionNumber)
        }
        return nil
    }

    private func latestStatusText(for drawing: Drawing) -> String? {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            return latest.status
        }
        return drawing.status
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "approved":
            return Color(hex: "#059669")
        case "draft":
            return Color(hex: "#D97706")
        case "for information":
            return Color(hex: "#3B82F6")
        case "superseded":
            return Color(hex: "#DC2626")
        default:
            return Color(hex: "#6B7280")
        }
    }

    private func statusBackgroundColor(for status: String) -> Color {
        switch status.lowercased() {
        case "approved":
            return Color(hex: "#D1FAE5")
        case "draft":
            return Color(hex: "#FED7AA")
        case "for information":
            return Color(hex: "#DBEAFE")
        case "superseded":
            return Color(hex: "#FEE2E2")
        default:
            return Color(hex: "#F3F4F6")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Table Header
            HStack(spacing: 0) {
                Text("Title")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                Text("Number")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 130, alignment: .leading)
                    .padding(.vertical, 16)

                Text("Discipline")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 140, alignment: .leading)
                    .padding(.vertical, 16)

                Text("Type")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 120, alignment: .leading)
                    .padding(.vertical, 16)

                Text("Status")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 100, alignment: .center)
                    .padding(.vertical, 16)

                Text("Rev")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 70, alignment: .center)
                    .padding(.vertical, 16)

                Text("Offline")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 80, alignment: .center)
                    .padding(.vertical, 16)

                Text("Actions")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .frame(width: 100, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "#F8FAFC"), Color(hex: "#F1F5F9")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color(hex: "#E2E8F0"))
                    .frame(height: 1),
                alignment: .bottom
            )

            // Scrollable Table Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(drawings.enumerated()), id: \.element.id) { index, drawing in
                        NavigationLink(destination: DrawingGalleryView(
                            drawings: drawings,
                            initialDrawing: drawing,
                            isProjectOffline: isProjectOffline
                        ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                            HStack(spacing: 0) {
                                // Title Column
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(drawing.title)
                                            .font(.system(size: 16, weight: .medium, design: .rounded))
                                            .foregroundColor(Color(hex: "#1F2937"))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        if drawing.archived == true {
                                            Image(systemName: "archivebox.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(hex: "#F59E0B"))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color(hex: "#FEF3C7"))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)

                                // Number Column
                                Text(drawing.number)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(hex: "#6B7280"))
                                    .frame(width: 130, alignment: .leading)
                                    .padding(.vertical, 16)
                                    .lineLimit(1)

                                // Discipline Column
                                Text(drawing.projectDiscipline?.name ?? "-")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(Color(hex: "#6B7280"))
                                    .frame(width: 140, alignment: .leading)
                                    .padding(.vertical, 16)
                                    .lineLimit(1)

                                // Type Column
                                Text(drawing.projectDrawingType?.name ?? "-")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(Color(hex: "#6B7280"))
                                    .frame(width: 120, alignment: .leading)
                                    .padding(.vertical, 16)
                                    .lineLimit(1)

                                // Status Column
                                HStack {
                                    if let status = latestStatusText(for: drawing), !status.isEmpty {
                                        Text(status)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(statusColor(for: status))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(statusBackgroundColor(for: status))
                                            .clipShape(Capsule())
                                    } else {
                                        Text("-")
                                            .font(.system(size: 14, weight: .regular, design: .rounded))
                                            .foregroundColor(Color(hex: "#9CA3AF"))
                                    }
                                }
                                .frame(width: 100, alignment: .center)
                                .padding(.vertical, 16)

                                // Revision Column
                                Text(latestRevisionText(for: drawing) ?? "-")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#3B82F6"))
                                    .frame(width: 70, alignment: .center)
                                    .padding(.vertical, 16)

                                // Offline Column
                                Image(systemName: drawing.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                                    .font(.system(size: 18))
                                    .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#D1D5DB"))
                                    .frame(width: 80, alignment: .center)
                                    .padding(.vertical, 16)

                                // Actions Column
                                HStack(spacing: 12) {
                                    Text("\(drawing.revisions.count)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .clipShape(Capsule())
                                        .shadow(color: Color(hex: "#3B82F6").opacity(0.3), radius: 2, x: 0, y: 1)

                                    DrawingTableFavoriteButton(drawing: drawing, token: token)
                                }
                                .frame(width: 100, alignment: .trailing)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .background(Color.white)
                            .contentShape(Rectangle())
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                        })

                        if index < drawings.count - 1 {
                            Divider()
                                .background(Color(hex: "#E5E7EB"))
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#E5E7EB"), lineWidth: 1)
        )
    }
}

struct DrawingTableFavoriteButton: View {
    let drawing: Drawing
    let token: String
    @State private var isFavourite: Bool
    @State private var isLoading: Bool = false

    init(drawing: Drawing, token: String) {
        self.drawing = drawing
        self.token = token
        self._isFavourite = State(initialValue: drawing.isFavourite ?? false)
    }

    var body: some View {
        Button(action: {
            Task {
                await toggleFavorite()
            }
        }) {
            Image(systemName: isFavourite ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isFavourite ? Color(hex: "#F59E0B") : Color(hex: "#D1D5DB"))
                .scaleEffect(isLoading ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isLoading)
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
        .contentShape(Circle())
        .frame(width: 32, height: 32)
        .background(
            Circle()
                .fill(isFavourite ? Color(hex: "#FEF3C7") : Color.clear)
                .opacity(isFavourite ? 1.0 : 0.0)
        )
        .scaleEffect(isFavourite ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFavourite)
    }

    private func toggleFavorite() async {
        guard !isLoading else { return }

        isLoading = true

        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        do {
            let newStatus = try await APIClient.toggleDrawingFavorite(drawingId: drawing.id, token: token)
            await MainActor.run {
                isFavourite = newStatus.isFavourite
                isLoading = false

                // Success haptic feedback
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
            }
        } catch {
            print("Error toggling favorite: \(error)")
            await MainActor.run {
                isLoading = false

                // Error haptic feedback
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
            }
        }
    }
}

// Folder view hierarchy settings
struct FolderViewSettings: Codable {
    var enabledLevels: [FolderLevel] = [.company, .folder, .discipline, .category]
    
    enum FolderLevel: String, Codable, CaseIterable {
        case company = "Company"
        case folder = "Folder"
        case discipline = "Discipline"
        case category = "Category"
    }
    
    static func load(for projectId: Int) -> FolderViewSettings {
        if let data = UserDefaults.standard.data(forKey: "folderViewSettings_\(projectId)"),
           let settings = try? JSONDecoder().decode(FolderViewSettings.self, from: data) {
            return settings
        }
        return FolderViewSettings() // Default
    }
    
    func save(for projectId: Int) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "folderViewSettings_\(projectId)")
        }
    }
}

// Folder view component that groups drawings by folder
struct DrawingFolderView: View {
    let drawings: [Drawing]
    let folders: [DrawingFolder]
    let token: String
    let projectId: Int
    let projectName: String
    let isProjectOffline: Bool
    let searchText: String?
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @State private var folderSettings: FolderViewSettings
    
    init(drawings: [Drawing], folders: [DrawingFolder], token: String, projectId: Int, projectName: String, isProjectOffline: Bool, searchText: String?) {
        self.drawings = drawings
        self.folders = folders
        self.token = token
        self.projectId = projectId
        self.projectName = projectName
        self.isProjectOffline = isProjectOffline
        self.searchText = searchText
        self._folderSettings = State(initialValue: FolderViewSettings.load(for: projectId))
    }
    
    // Group drawings by folder
    private var drawingsByFolder: [Int: [Drawing]] {
        var grouped: [Int: [Drawing]] = [:]
        var noFolder: [Drawing] = []
        
        for drawing in drawings {
            if let folderId = drawing.folderId {
                if grouped[folderId] == nil {
                    grouped[folderId] = []
                }
                grouped[folderId]?.append(drawing)
            } else {
                noFolder.append(drawing)
            }
        }
        
        // Add drawings without folders to a special key
        if !noFolder.isEmpty {
            grouped[-1] = noFolder
        }
        
        return grouped
    }
    
    // Get all folder IDs including subfolders
    private func getAllFolderIds(_ folder: DrawingFolder) -> [Int] {
        var ids = [folder.id]
        if let subfolders = folder.subfolders {
            for subfolder in subfolders {
                ids.append(contentsOf: getAllFolderIds(subfolder))
            }
        }
        return ids
    }
    
    // Get drawings for a folder (including subfolders)
    private func getDrawingsForFolder(_ folder: DrawingFolder) -> [Drawing] {
        let allFolderIds = getAllFolderIds(folder)
        return drawings.filter { drawing in
            if let folderId = drawing.folderId {
                return allFolderIds.contains(folderId)
            }
            return false
        }
    }
    
    // Build hierarchical tree structure
    private var hierarchicalGroups: [HierarchicalGroup] {
        buildHierarchy(drawings: drawings, levels: folderSettings.enabledLevels, currentIndex: 0)
    }
    
    private func buildHierarchy(drawings: [Drawing], levels: [FolderViewSettings.FolderLevel], currentIndex: Int) -> [HierarchicalGroup] {
        guard currentIndex < levels.count else { return [] }
        
        let currentLevel = levels[currentIndex]
        var groupedDrawings: [String: [Drawing]] = [:]
        
        // Group drawings by current level
        for drawing in drawings {
            let key: String
            switch currentLevel {
            case .company:
                key = drawing.company?.name ?? "No Company"
            case .folder:
                key = drawing.folder?.name ?? "No Folder"
            case .discipline:
                key = drawing.projectDiscipline?.name ?? "No Discipline"
            case .category:
                key = drawing.projectDrawingType?.name ?? "No Category"
            }
            
            if groupedDrawings[key] == nil {
                groupedDrawings[key] = []
            }
            groupedDrawings[key]?.append(drawing)
        }
        
        // Create hierarchical groups
        var groups: [HierarchicalGroup] = []
        for (key, groupDrawings) in groupedDrawings.sorted(by: { $0.key < $1.key }) {
            let isLastLevel = currentIndex == levels.count - 1
            let subgroups = isLastLevel ? [] : buildHierarchy(drawings: groupDrawings, levels: levels, currentIndex: currentIndex + 1)
            
            groups.append(HierarchicalGroup(
                name: key,
                level: currentLevel,
                drawings: isLastLevel ? groupDrawings : [],
                subgroups: subgroups,
                isLastLevel: isLastLevel
            ))
        }
        
        return groups
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hierarchicalGroups, id: \.id) { group in
                    HierarchicalFolderRow(
                        group: group,
                        token: token,
                        projectId: projectId,
                        projectName: projectName,
                        isProjectOffline: isProjectOffline,
                        searchText: searchText,
                        level: 0
                    )
                    .environmentObject(sessionManager)
                    .environmentObject(networkStatusManager)
                }
            }
            .padding()
        }
    }
    
    // Hierarchical group structure
    struct HierarchicalGroup: Identifiable {
        let id = UUID()
        let name: String
        let level: FolderViewSettings.FolderLevel
        let drawings: [Drawing]
        let subgroups: [HierarchicalGroup]
        let isLastLevel: Bool
    }
    
    // Hierarchical folder row that can be nested
    struct HierarchicalFolderRow: View {
        let group: HierarchicalGroup
        let token: String
        let projectId: Int
        let projectName: String
        let isProjectOffline: Bool
        let searchText: String?
        let level: Int
        @EnvironmentObject var sessionManager: SessionManager
        @EnvironmentObject var networkStatusManager: NetworkStatusManager
        @State private var isExpanded: Bool = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Folder header
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 8) {
                        // Indentation based on level
                        if level > 0 {
                            Spacer()
                                .frame(width: CGFloat(level * 20))
                        }
                        
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#6B7280"))
                            .frame(width: 16)
                        
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#3B82F6"))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#1F2A44"))
                            
                            Text(group.level.rawValue + (group.isLastLevel ? "" : " • \(totalDrawingCount) drawings"))
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#6B7280"))
                        }
                        
                        Spacer()
                        
                        if group.isLastLevel {
                            Text("\(group.drawings.count)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7280"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#F3F4F6"))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(hex: "#FFFFFF"))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Expanded content
                if isExpanded {
                    if group.isLastLevel {
                        // Show drawings at the last level
                        LazyVStack(spacing: 0) {
                            ForEach(group.drawings, id: \.id) { drawing in
                                NavigationLink(destination: DrawingGalleryView(
                                    drawings: group.drawings,
                                    initialDrawing: drawing,
                                    isProjectOffline: isProjectOffline
                                ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                    DrawingRow(
                                        drawing: drawing,
                                        token: token,
                                        searchText: searchText,
                                        isLastViewed: {
                                            if let lastViewedId = UserDefaults.standard.value(forKey: "lastViewedDrawing_\(projectId)") as? Int {
                                                return lastViewedId == drawing.id
                                            }
                                            return false
                                        }()
                                    )
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                                })
                                .padding(.leading, CGFloat((level + 1) * 20))
                            }
                        }
                    } else {
                        // Show subgroups
                        ForEach(group.subgroups, id: \.id) { subgroup in
                            HierarchicalFolderRow(
                                group: subgroup,
                                token: token,
                                projectId: projectId,
                                projectName: projectName,
                                isProjectOffline: isProjectOffline,
                                searchText: searchText,
                                level: level + 1
                            )
                            .environmentObject(sessionManager)
                            .environmentObject(networkStatusManager)
                        }
                    }
                }
            }
            .background(level == 0 ? Color(hex: "#FFFFFF") : Color.clear)
            .cornerRadius(level == 0 ? 12 : 0)
            .overlay(
                level == 0 ? RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "#E5E7EB"), lineWidth: 1) : nil
            )
            .padding(.bottom, level == 0 ? 12 : 0)
        }
        
        private var totalDrawingCount: Int {
            if group.isLastLevel {
                return group.drawings.count
            } else {
                return group.subgroups.reduce(0) { $0 + countDrawings(in: $1) }
            }
        }
        
        private func countDrawings(in group: HierarchicalGroup) -> Int {
            if group.isLastLevel {
                return group.drawings.count
            } else {
                return group.subgroups.reduce(0) { $0 + countDrawings(in: $1) }
            }
        }
    }
    
    
    // Folder section view that displays a folder header and its drawings
    struct FolderSectionView: View {
        let folderName: String
        let drawings: [Drawing]
        let token: String
        let projectId: Int
        let projectName: String
        let isProjectOffline: Bool
        let searchText: String?
        let subfolders: [DrawingFolder]?
        @EnvironmentObject var sessionManager: SessionManager
        @EnvironmentObject var networkStatusManager: NetworkStatusManager
        @State private var isExpanded: Bool = false
        
        init(folderName: String, drawings: [Drawing], token: String, projectId: Int, projectName: String, isProjectOffline: Bool, searchText: String?, subfolders: [DrawingFolder]? = nil) {
            self.folderName = folderName
            self.drawings = drawings
            self.token = token
            self.projectId = projectId
            self.projectName = projectName
            self.isProjectOffline = isProjectOffline
            self.searchText = searchText
            self.subfolders = subfolders
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Folder header
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#6B7280"))
                            .frame(width: 16)
                        
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#3B82F6"))
                        
                        Text(folderName)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                        
                        Spacer()
                        
                        Text("\(drawings.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#6B7280"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#F3F4F6"))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Drawings in this folder
                if isExpanded {
                    LazyVStack(spacing: 12) {
                        ForEach(drawings, id: \.id) { drawing in
                            NavigationLink(destination: DrawingGalleryView(
                                drawings: drawings,
                                initialDrawing: drawing,
                                isProjectOffline: isProjectOffline
                            ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                DrawingRow(
                                    drawing: drawing,
                                    token: token,
                                    searchText: searchText,
                                    isLastViewed: {
                                        if let lastViewedId = UserDefaults.standard.value(forKey: "lastViewedDrawing_\(projectId)") as? Int {
                                            return lastViewedId == drawing.id
                                        }
                                        return false
                                    }()
                                )
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                UserDefaults.standard.set(drawing.id, forKey: "lastViewedDrawing_\(projectId)")
                            })
                        }
                    }
                    .padding(.leading, 32)
                }
            }
            .padding()
            .background(Color(hex: "#FFFFFF"))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
    }
    
    #Preview {
        DrawingListView(projectId: 2, token: "sample-token", projectName: "Sample Project")
            .environmentObject(SessionManager())
            .environmentObject(NetworkStatusManager.shared)
    }
}
