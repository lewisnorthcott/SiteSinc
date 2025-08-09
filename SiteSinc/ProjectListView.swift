import SwiftUI

// MARK: - Enums
enum SortOption: String, CaseIterable {
    case name = "Name"
    case status = "Status"
    case reference = "Reference"
    case location = "Location"
}

enum SortOrder: String, CaseIterable {
    case ascending = "A-Z"
    case descending = "Z-A"
}

struct ProjectListView: View {
    let token: String
    let tenantId: Int
    let onLogout: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var selectedStatus: ProjectStatusFilter? = nil // Use nullable for "All"
    @State private var showFilterPicker = false
    @State private var isProfileTapped = false
    @State private var isProfileSidebarPresented = false
    @State private var lastUpdated: Date? = nil
    @State private var showNotificationCenter = false
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showSearchSuggestions = false
    @State private var searchFocused = false
    @State private var recentSearches: [String] = []
    
    // Quick action states
    @State private var selectedQuickAction: QuickAction? = nil
    @State private var showSortOptions = false
    @State private var showMapView = false
    @State private var sortOption: SortOption = .name
    @State private var sortOrder: SortOrder = .ascending
    
    enum QuickAction: String, CaseIterable {
        case recent = "Recent"
        case offline = "Offline"
        case sort = "Sort"
        case mapView = "Map View"
    }
    
    // Haptic feedback
    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func triggerSuccessHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    private func triggerSelectionHaptic() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }

    enum ProjectStatusFilter: String, CaseIterable, Identifiable {
        case planning = "PLANNING"
        case inProgress = "IN_PROGRESS"
        case completed = "COMPLETED"
        var id: String { rawValue }

        // Display-friendly name for UI
        var displayName: String {
            switch self {
            case .planning: return "Planning"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    VStack(spacing: 20) {
                        // Header
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text("Projects")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .accessibilityAddTraits(.isHeader)
                                    if !filteredProjects.isEmpty {
                                        Text("\(filteredProjects.count)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                                if let tenantName = getCurrentTenantName() {
                                    Text(tenantName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .accessibilityLabel("Current tenant")
                                }
                            }
                            Spacer(minLength: 0)
                            Button(action: { showNotificationCenter = true }) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color(hex: "#3B82F6"))
                            }
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isProfileTapped = true
                                    isProfileSidebarPresented.toggle()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isProfileTapped = false }
                                }
                            }) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(hex: "#635bff"))
                                    .scaleEffect(isProfileTapped ? 0.92 : 1.0)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 8)

                        // Search and Filter
                        HStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(searchFocused ? Color.blue : .gray)
                                    .font(.system(size: 16, weight: .medium))
                                TextField("Search projects", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .accessibilityLabel("Search projects")
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            searchFocused = true
                                            showSearchSuggestions = true
                                        }
                                    }
                                    .onSubmit {
                                        if !searchText.isEmpty && !recentSearches.contains(searchText) {
                                            recentSearches.insert(searchText, at: 0)
                                            if recentSearches.count > 5 {
                                                recentSearches.removeLast()
                                            }
                                        }
                                        searchFocused = false
                                        showSearchSuggestions = false
                                    }
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                        searchFocused = false
                                        showSearchSuggestions = false
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 16))
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(searchFocused ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(searchFocused ? Color.blue : Color.clear, lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity)
                            .animation(.easeInOut(duration: 0.2), value: searchFocused)
                            .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
                            .overlay(
                                // Search suggestions
                                VStack(alignment: .leading, spacing: 0) {
                                    if showSearchSuggestions && !recentSearches.isEmpty {
                                        VStack(alignment: .leading, spacing: 0) {
                                            ForEach(recentSearches.prefix(3), id: \.self) { search in
                                                Button(action: {
                                                    searchText = search
                                                    searchFocused = false
                                                    showSearchSuggestions = false
                                                }) {
                                                    HStack {
                                                        Image(systemName: "clock")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.gray)
                                                        Text(search)
                                                            .font(.subheadline)
                                                            .foregroundColor(.primary)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                
                                                if search != recentSearches.prefix(3).last {
                                                    Divider()
                                                        .padding(.leading, 32)
                                                }
                                            }
                                        }
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                        .offset(y: 50)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.2), value: showSearchSuggestions)
                            )

                            Picker("Status", selection: $selectedStatus) {
                                Text("All").tag(ProjectStatusFilter?.none)
                                ForEach(ProjectStatusFilter.allCases) { status in
                                    Text(status.displayName).tag(ProjectStatusFilter?.some(status))
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 120)
                            .accessibilityLabel("Filter by status")
                        }
                        .padding(.horizontal, 4)

                        // Minimal Filters Row
                        HStack {
                            Button(action: { showSortOptions = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Filters")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                            }
                            Spacer()
                            if let lastUpdated = lastUpdated {
                                Text("Last updated: \(lastUpdated, formatter: dateFormatter)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)

                        // (last updated shown above)

                        // Project Statistics
//                        if !filteredProjects.isEmpty {
//                            HStack(spacing: 16) {
//                                StatCard(title: "Total", value: "\(filteredProjects.count)", color: .blue)
//                                StatCard(title: "In Progress", value: "\(filteredProjects.filter { $0.projectStatus == "IN_PROGRESS" }.count)", color: .green)
//                                StatCard(title: "Planning", value: "\(filteredProjects.filter { $0.projectStatus == "PLANNING" }.count)", color: Color(hex: "#0891b2"))
//                                StatCard(title: "Completed", value: "\(filteredProjects.filter { $0.projectStatus == "COMPLETED" }.count)", color: .purple)
//                            }
//                            .padding(.horizontal, 4)
//                            .padding(.bottom, 8)
//                        }

                        // Main content
                        if isLoading {
                            VStack(spacing: 16) {
                                ForEach(0..<3) { _ in
                                    SkeletonProjectRow()
                                }
                            }
                            .padding(.top, 32)
                        } else if let errorMessage = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button("Retry") {
                                    Task { await refreshProjects() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        } else if filteredProjects.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .foregroundColor(.gray.opacity(0.3))
                                    .animation(.easeInOut(duration: 0.3), value: searchText.isEmpty)
                                
                                VStack(spacing: 8) {
                                    Text(searchText.isEmpty ? 
                                        (networkStatusManager.isNetworkAvailable ? "No projects found" : "No offline projects available") :
                                        "No matching projects")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    
                                    Text(searchText.isEmpty ? 
                                        (networkStatusManager.isNetworkAvailable ? "Projects will appear here once they're added to your account." : "Projects available offline will appear here.") :
                                        "Try adjusting your search terms or filters.")
                                        .font(.subheadline)
                                        .foregroundColor(.gray.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                }
                                
                                if searchText.isEmpty && networkStatusManager.isNetworkAvailable {
                                    Button("Refresh") {
                                        triggerHapticFeedback()
                                        Task { await refreshProjects() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                }
                            }
                            .padding(.top, 60)
                            .padding(.horizontal, 20)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredProjects) { project in
                                        NavigationLink(destination: ProjectSummaryView(projectId: project.id, token: token, projectName: project.name)) {
                                            EnhancedProjectRow(project: project, isCached: isProjectCached(projectId: project.id))
                                                .accessibilityElement(children: .combine)
                                                .accessibilityLabel("Project: \(project.name), Status: \(project.projectStatus ?? "Unknown")\(isProjectCached(projectId: project.id) ? ", Available Offline" : "")")
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .background(Color.clear)
                                        .contentShape(Rectangle())
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button("Share") {
                                                shareProject(project)
                                            }
                                            .tint(.green)
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button("Info") {
                                                showProjectInfo(project)
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .scrollIndicators(.visible)
                            .refreshable {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isRefreshing = true
                                }
                                await refreshProjects()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isRefreshing = false
                                }
                            }
                            .overlay(
                                // Refresh indicator
                                Group {
                                    if isRefreshing {
                                        VStack {
                                            ProgressView()
                                                .scaleEffect(1.2)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                            Text("Refreshing...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.top, 4)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground).opacity(0.9))
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                        .transition(.opacity.combined(with: .scale))
                                    }
                                }
                                .animation(.easeInOut(duration: 0.3), value: isRefreshing)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .navigationTitle("")
                    .blur(radius: isProfileSidebarPresented ? 2 : 0)
                    .disabled(isProfileSidebarPresented)

                    // Sidebar overlay
                    if isProfileSidebarPresented {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isProfileSidebarPresented = false
                                }
                            }
                    }

                    // Sidebar itself
                    HStack(spacing: 0) {
                        Spacer()
                        if isProfileSidebarPresented {
                            ProfileView(onLogout: {
                                onLogout()
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isProfileSidebarPresented = false
                                }
                            })
                            .frame(width: min(geometry.size.width * 0.4, 320))
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(radius: 10)
                            .transition(.move(edge: .trailing))
                            .zIndex(2)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: isProfileSidebarPresented)
                }
            }
            .task { await refreshProjects() }
            .onChange(of: sessionManager.errorMessage) {
                if let error = sessionManager.errorMessage {
                    errorMessage = error
                }
            }
            .sheet(isPresented: $showNotificationCenter) {
                NotificationCenterView()
            }
            .sheet(isPresented: $showSortOptions) {
                SortOptionsView(
                    sortOption: $sortOption,
                    sortOrder: $sortOrder,
                    isPresented: $showSortOptions
                )
            }
            .sheet(isPresented: $showMapView) {
                MapViewSheet(projects: filteredProjects)
            }
        }
    }

    private var filteredProjects: [Project] {
        var activeProjects = projects
        
        // Apply quick action filters
        if let quickAction = selectedQuickAction {
            switch quickAction {
            case .recent:
                // Show projects that have been accessed recently (last 7 days)
                _ = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                // For now, we'll show all projects since we don't track access times
                // TODO: Implement actual recent access tracking
                break
            case .offline:
                // Show only cached projects
                activeProjects = activeProjects.filter { isProjectCached(projectId: $0.id) }
            case .sort, .mapView:
                // These don't filter, they just change the view
                break
            }
        }
        
        // If offline, only show projects that are cached
        if !networkStatusManager.isNetworkAvailable {
            activeProjects = activeProjects.filter { isProjectCached(projectId: $0.id) }
        }
        
        // Apply status filter
        if let status = selectedStatus {
            activeProjects = activeProjects.filter { $0.projectStatus == status.rawValue }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            activeProjects = activeProjects.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                ($0.location?.lowercased().contains(searchText.lowercased()) ?? false) ||
                $0.reference.lowercased().contains(searchText.lowercased())
            }
        }
        
        // Apply sorting
        activeProjects.sort { project1, project2 in
            let result: Bool
            switch sortOption {
            case .name:
                result = project1.name.localizedCaseInsensitiveCompare(project2.name) == .orderedAscending
            case .status:
                result = (project1.projectStatus ?? "").localizedCaseInsensitiveCompare(project2.projectStatus ?? "") == .orderedAscending
            case .reference:
                result = project1.reference.localizedCaseInsensitiveCompare(project2.reference) == .orderedAscending
            case .location:
                let loc1 = project1.location ?? ""
                let loc2 = project2.location ?? ""
                result = loc1.localizedCaseInsensitiveCompare(loc2) == .orderedAscending
            }
            return sortOrder == .ascending ? result : !result
        }
        
        return activeProjects
    }

    // Enhanced Project Row with Cached Indicator
    private struct EnhancedProjectRow: View {
        let project: Project
        let isCached: Bool
        @State private var isPressed = false

        var body: some View {
            HStack(spacing: 16) {
                // Project Avatar with Status
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: statusColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Text(project.name.prefix(2).uppercased())
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Status indicator
                    if project.projectStatus == "IN_PROGRESS" {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .offset(x: 18, y: -18)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(project.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Offline indicator
                        if isCached {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 12))
                                Text("Offline")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    if let location = project.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(location)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    HStack {
                        Text(project.projectStatus?.capitalized.replacingOccurrences(of: "_", with: " ") ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.1))
                            .cornerRadius(6)
                        
                        Spacer()
                        
                        Text(project.reference)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Navigation indicator
                VStack {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .gray.opacity(0.08), radius: 6, x: 0, y: 3)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        
        private var statusColor: Color {
            switch project.projectStatus {
            case "IN_PROGRESS":
                return .green
            case "COMPLETED":
                return .blue
            case "PLANNING":
                return Color(hex: "#0891b2") // Teal instead of orange
            default:
                return .gray
            }
        }
    }

    // Skeleton Loader Row
    private struct SkeletonProjectRow: View {
        var body: some View {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 12)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 60, height: 16)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .redacted(reason: .placeholder)
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    private func saveProjectsToCache(_ projects: [Project]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(projects)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let base = appSupport.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("projects.json")
            try data.write(to: cacheURL)
            print("Successfully saved \(projects.count) projects to cache at \(cacheURL.path)")
        } catch {
            print("Failed to save projects to cache: \(error.localizedDescription)")
        }
    }

    private func loadProjectsFromCache() -> [Project]? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("projects.json")
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let cachedProjects = try decoder.decode([Project].self, from: data)
            print("Successfully loaded \(cachedProjects.count) projects from cache")
            return cachedProjects
        } catch {
            print("Failed to load projects from cache: \(error.localizedDescription)")
            return nil
        }
    }

    private func isProjectCached(projectId: Int) -> Bool {
        let isOfflineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        if !isOfflineModeEnabled {
            print("ProjectListView: Project \(projectId) is not cached (offline mode not enabled).")
            return false
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("drawings_project_\(projectId).json")
        let cacheExists = FileManager.default.fileExists(atPath: cacheURL.path)
        print("ProjectListView: Project \(projectId) - Offline mode enabled: \(isOfflineModeEnabled), Cache exists: \(cacheExists)")
        return cacheExists
    }

    private func refreshProjects() async {
        await MainActor.run {
            isLoading = true
        }

        // Offline-first: load local first, then refresh network in background
        if let cachedProjects = loadProjectsFromCache(), !cachedProjects.isEmpty {
            await MainActor.run {
                projects = cachedProjects
                isLoading = false
                errorMessage = nil
                lastUpdated = getCacheFileLastModifiedDate()
            }
        }

        if networkStatusManager.isNetworkAvailable {
            do {
                let p = try await APIClient.fetchProjects(token: token)
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        projects = p
                    }
                    saveProjectsToCache(p)
                    isLoading = false
                    errorMessage = nil
                    lastUpdated = Date()
                    print("refreshProjects: Successfully fetched \(p.count) projects: \(p.map { $0.name })")
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if let cachedProjects = loadProjectsFromCache(), !cachedProjects.isEmpty {
                        projects = cachedProjects
                        errorMessage = "Failed to refresh. Displaying cached data."
                        lastUpdated = getCacheFileLastModifiedDate()
                    } else {
                        projects = []
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .networkError(let underlyingError):
                                errorMessage = "Network error: \((underlyingError as NSError).localizedDescription). No cached data."
                            default:
                                errorMessage = "Failed to load projects: \(error.localizedDescription). No cached data."
                            }
                        } else {
                            errorMessage = "Failed to load projects: \(error.localizedDescription). No cached data."
                        }
                    }
                    print("refreshProjects: Error fetching projects: \(error.localizedDescription). Project count: \(projects.count)")
                }
            }
        } else if projects.isEmpty {
            await MainActor.run {
                isLoading = false
                if let cachedProjects = loadProjectsFromCache() {
                    projects = cachedProjects
                    if !cachedProjects.isEmpty {
                        errorMessage = nil
                    } else {
                        errorMessage = "Offline: No projects found in cache."
                    }
                    lastUpdated = getCacheFileLastModifiedDate()
                    print("refreshProjects: Loaded \(projects.count) projects from cache while offline.")
                } else {
                    projects = []
                    errorMessage = "Offline: No internet connection and no cached data available."
                    print("refreshProjects: Failed to load projects from cache while offline.")
                }
            }
        }
    }

    private func getCacheFileLastModifiedDate() -> Date? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("projects.json")
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            return attributes[.modificationDate] as? Date
        } catch {
            print("Could not get cache file modification date: \(error)")
            return nil
        }
    }

    private func shareProject(_ project: Project) {
        let activityViewController = UIActivityViewController(activityItems: [
            "Project: \(project.name)",
            "Status: \(project.projectStatus?.capitalized.replacingOccurrences(of: "_", with: " ") ?? "Unknown")",
            "Reference: \(project.reference)",
            "Location: \(project.location ?? "N/A")"
        ], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityViewController, animated: true)
        }
    }

    private func showProjectInfo(_ project: Project) {
        let alert = UIAlertController(title: "Project Info", message: """
            Name: \(project.name)
            Status: \(project.projectStatus?.capitalized.replacingOccurrences(of: "_", with: " ") ?? "Unknown")
            Reference: \(project.reference)
            Location: \(project.location ?? "N/A")
            """, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }

    private func getCurrentTenantName() -> String? {
        guard let selectedTenantId = sessionManager.selectedTenantId,
              let tenants = sessionManager.tenants else {
            return nil
        }
        
        // Find the current tenant by matching the selectedTenantId
        let currentTenant = tenants.first { userTenant in
            userTenant.tenant?.id == selectedTenantId || userTenant.tenantId == selectedTenantId
        }
        
        return currentTenant?.tenant?.name
    }

    private func handleQuickAction(_ action: QuickAction) {
        triggerSelectionHaptic()
        
        // If the same action is tapped again, deselect it
        if selectedQuickAction == action {
            selectedQuickAction = nil
            return
        }
        
        selectedQuickAction = action
        
        switch action {
        case .recent:
            // Show projects that have been accessed recently
            // For now, we'll show all projects since we don't track access times
            // TODO: Implement actual recent access tracking
            print("Recent filter selected - showing all projects")
            
        case .offline:
            // Show only cached projects
            print("Offline filter selected - showing cached projects only")
            
        case .sort:
            showSortOptions.toggle()
            // Don't keep sort selected as a filter
            selectedQuickAction = nil
            
        case .mapView:
            showMapView.toggle()
            // Don't keep map view selected as a filter
            selectedQuickAction = nil
        }
    }
}

// MARK: - Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ProfileView: View {
    let onLogout: () -> Void

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Profile")
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundColor(.black)

                Button(action: {
                    onLogout()
                }) {
                    Text("Logout")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .tracking(1)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.05 : 1.0))
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Segmented Pill (new compact style)
struct SegmentedPill: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(active ? .white : .primary)
            .background(active ? Color.accentColor : Color(.systemGray6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Options View
struct SortOptionsView: View {
    @Binding var sortOption: SortOption
    @Binding var sortOrder: SortOrder
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                Section("Sort By") {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        HStack {
                            Text(option.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            sortOption = option
                            triggerSelectionHaptic()
                        }
                    }
                }
                
                Section("Order") {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        HStack {
                            Text(order.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            sortOrder = order
                            triggerSelectionHaptic()
                        }
                    }
                }
            }
            .navigationTitle("Sort Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func triggerSelectionHaptic() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
}

// MARK: - Map View Sheet
struct MapViewSheet: View {
    let projects: [Project]
    
    var body: some View {
        NavigationView {
            VStack {
                // Placeholder for map view
                VStack(spacing: 20) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Map View")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(projects.count) projects")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Map view functionality coming soon!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Project list for now
                List(projects) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        if let location = project.location {
                            Text(location)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text(project.reference)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Map View")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

//#Preview {
//    NavigationView {
//        ProjectListView(token: "sample_token", tenantId: 1, onLogout: {})
//            .environmentObject(SessionManager())
//    }
//}
