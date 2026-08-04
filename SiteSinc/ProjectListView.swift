import SwiftUI
import LocalAuthentication

// MARK: - Enums
enum SortOption: String, CaseIterable {
    case name = "Name"
    case status = "Status"
    case reference = "Reference"
    case location = "Location"
}

enum ProjectSortOrder: String, CaseIterable {
    case ascending = "A-Z"
    case descending = "Z-A"
}

enum MainNavDestination: Hashable {
    case project(Int)
    case myTimesheets
    case assetCheckout(code: String? = nil)
}

struct ProjectListView: View {
    let token: String
    let tenantId: Int
    let onLogout: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedStatus: ProjectStatusFilter? = nil
    @State private var isProfileTapped = false
    @State private var isProfileSidebarPresented = false
    @State private var lastUpdated: Date? = nil
    @State private var showNotificationCenter = false
    @FocusState private var searchFocused: Bool
    @State private var showRecentOnly = false
    @State private var showOfflineOnly = false
    @State private var showSortOptions = false
    @State private var infoProject: Project?
    @State private var sortOption: SortOption = .name
    @State private var sortOrder: ProjectSortOrder = .ascending
    @State private var navigationPath = NavigationPath()

    private func triggerHapticFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func triggerSelectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    enum ProjectStatusFilter: String, CaseIterable, Identifiable {
        case planning = "PLANNING"
        case inProgress = "IN_PROGRESS"
        case completed = "COMPLETED"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .planning: return "Planning"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            }
        }

        var tint: Color {
            switch self {
            case .planning: return Color(hex: "#0891b2")
            case .inProgress: return Color(hex: "#16A34A")
            case .completed: return BrandChrome.accent
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || showRecentOnly || showOfflineOnly || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sortLabel: String {
        "\(sortOption.rawValue) · \(sortOrder.rawValue)"
    }

    // MARK: - Body Components
    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: BrandChrome.isMcPhillips ? 6 : 4) {
                if BrandChrome.isMcPhillips {
                    Text("WORKSPACE")
                        .font(.system(size: 11, weight: .semibold, design: BrandChrome.bodyDesign))
                        .foregroundColor(BrandChrome.mutedLabel)
                        .tracking(1.2)
                }

                HStack(spacing: 8) {
                    Text("Projects")
                        .font(
                            BrandChrome.isMcPhillips
                                ? .system(size: 30, weight: .regular, design: BrandChrome.displayDesign)
                                : .system(size: 28, weight: .bold, design: .rounded)
                        )
                        .foregroundColor(BrandChrome.isMcPhillips ? AppBrand.current.colors.deepestColor : .primary)
                        .accessibilityAddTraits(.isHeader)

                    if !isLoading && errorMessage == nil {
                        Text("\(filteredProjects.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(BrandChrome.subtleFill)
                            .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 6 : 20, style: .continuous))
                            .accessibilityLabel("\(filteredProjects.count) projects")
                    }
                }

                if AppBrand.current.features.showTenantIndicator,
                   let tenantName = getCurrentTenantName() {
                    Text(tenantName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("Current organisation")
                }

                if BrandChrome.isMcPhillips {
                    Rectangle()
                        .fill(BrandChrome.softBorder)
                        .frame(height: 1)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if AppBrand.current.features.showNavbarNotifications {
                Button {
                    showNotificationCenter = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(BrandChrome.subtleFill)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                            )

                        if notificationManager.currentBadgeCount > 0 {
                            Text(notificationManager.currentBadgeCount > 9 ? "9+" : "\(notificationManager.currentBadgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Notifications")
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isProfileTapped = true
                    isProfileSidebarPresented.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isProfileTapped = false }
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppBrand.current.primaryColor, AppBrand.current.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isProfileTapped ? 0.92 : 1.0)
            }
            .accessibilityLabel("Profile")
        }
    }

    private var offlineBanner: some View {
        Group {
            if !networkStatusManager.isNetworkAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("You're offline — showing available projects")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Color(hex: "#B45309"))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "#F59E0B").opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(searchFocused ? BrandChrome.accent : .secondary)
                .font(.system(size: 15, weight: .medium))

            TextField("Search by name, reference, or location", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($searchFocused)
                .accessibilityLabel("Search projects")
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(searchFocused ? BrandChrome.solidCardBackground : BrandChrome.searchFieldFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    searchFocused
                        ? BrandChrome.accent.opacity(0.45)
                        : BrandChrome.softBorder,
                    lineWidth: searchFocused ? 1.5 : (BrandChrome.isMcPhillips ? 1 : 0)
                )
        )
    }

    private var statusFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "All",
                    isSelected: selectedStatus == nil,
                    tint: BrandChrome.accent
                ) {
                    triggerSelectionHaptic()
                    selectedStatus = nil
                }

                ForEach(ProjectStatusFilter.allCases) { status in
                    filterChip(
                        title: status.displayName,
                        isSelected: selectedStatus == status,
                        tint: status.tint
                    ) {
                        triggerSelectionHaptic()
                        selectedStatus = selectedStatus == status ? nil : status
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: BrandChrome.bodyDesign))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? tint : BrandChrome.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous)
                        .stroke(isSelected ? Color.clear : BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var toolsRow: some View {
        HStack(spacing: 8) {
            Button {
                triggerSelectionHaptic()
                showSortOptions = true
            } label: {
                Label(sortLabel, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium, design: BrandChrome.bodyDesign))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(BrandChrome.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous)
                            .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort by \(sortLabel)")

            Button {
                triggerSelectionHaptic()
                withAnimation(.easeInOut(duration: 0.2)) { showRecentOnly.toggle() }
            } label: {
                Label("Recent", systemImage: "clock")
                    .font(.system(size: 12, weight: .medium, design: BrandChrome.bodyDesign))
                    .foregroundColor(showRecentOnly ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(showRecentOnly ? BrandChrome.accent : BrandChrome.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous)
                            .stroke(showRecentOnly ? Color.clear : BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showRecentOnly ? .isSelected : [])

            Button {
                triggerSelectionHaptic()
                withAnimation(.easeInOut(duration: 0.2)) { showOfflineOnly.toggle() }
            } label: {
                Label("Saved", systemImage: "checkmark.icloud")
                    .font(.system(size: 12, weight: .medium, design: BrandChrome.bodyDesign))
                    .foregroundColor(showOfflineOnly ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(showOfflineOnly ? BrandChrome.accent : BrandChrome.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 8 : 20, style: .continuous)
                            .stroke(showOfflineOnly ? Color.clear : BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showOfflineOnly ? .isSelected : [])

            Spacer(minLength: 0)

            if hasActiveFilters {
                Button("Clear") {
                    triggerSelectionHaptic()
                    clearAllFilters()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BrandChrome.accent)
            }
        }
    }

    private var permissionsBanner: some View {
        Group {
            if sessionManager.isLoadingPermissions {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BrandChrome.accent)
                    Text("Loading access permissions…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BrandChrome.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                )
            }
        }
    }

    private var softErrorBanner: some View {
        Group {
            if let errorMessage, !projects.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Retry") {
                            Task { await refreshProjects() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func mainContentView(geometry: GeometryProxy) -> some View {
        Group {
            if isLoading && projects.isEmpty {
                loadingView
            } else if let errorMessage, projects.isEmpty {
                errorView(errorMessage)
            } else if filteredProjects.isEmpty {
                emptyStateView
            } else {
                projectsListView
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonProjectRow()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func errorView(_ errorMessage: String) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Couldn't load projects")
                .font(.title3.weight(.semibold))
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try Again") {
                triggerHapticFeedback()
                Task { await refreshProjects() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandChrome.accent)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Image(systemName: emptyStateIcon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.7))

            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if hasActiveFilters {
                Button("Clear filters") {
                    triggerHapticFeedback()
                    clearAllFilters()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandChrome.accent)
            } else if networkStatusManager.isNetworkAvailable {
                Button("Refresh") {
                    triggerHapticFeedback()
                    Task { await refreshProjects() }
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        if hasActiveFilters { return "line.3.horizontal.decrease.circle" }
        if !networkStatusManager.isNetworkAvailable { return "icloud.slash" }
        return "folder"
    }

    private var emptyStateTitle: String {
        if hasActiveFilters { return "No matching projects" }
        if !networkStatusManager.isNetworkAvailable { return "No offline projects" }
        return "No projects yet"
    }

    private var emptyStateMessage: String {
        if hasActiveFilters {
            return "Try a different search or clear your filters to see more projects."
        }
        if !networkStatusManager.isNetworkAvailable {
            return "Projects you've saved for offline use will appear here."
        }
        return "Projects assigned to your account will show up here."
    }

    private var projectsListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredProjects) { project in
                    projectRowView(for: project)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await refreshProjects()
        }
    }

    private func projectRowView(for project: Project) -> some View {
        Group {
            if sessionManager.isLoadingPermissions {
                EnhancedProjectRow(project: project, isCached: isProjectCached(projectId: project.id))
                    .opacity(0.55)
                    .allowsHitTesting(false)
            } else {
                NavigationLink(value: MainNavDestination.project(project.id)) {
                    EnhancedProjectRow(project: project, isCached: isProjectCached(projectId: project.id))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(projectAccessibilityLabel(project))
                        .accessibilityHint("Opens project")
                }
                .buttonStyle(PlainButtonStyle())
                .contextMenu {
                    Button {
                        infoProject = project
                    } label: {
                        Label("Project Info", systemImage: "info.circle")
                    }
                    Button {
                        shareProject(project)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func projectAccessibilityLabel(_ project: Project) -> String {
        var parts = ["Project: \(project.name)"]
        if let status = project.projectStatus {
            parts.append("Status: \(status.replacingOccurrences(of: "_", with: " ").capitalized)")
        }
        if isProjectCached(projectId: project.id) {
            parts.append("Available offline")
        }
        return parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            searchText = ""
            selectedStatus = nil
            showRecentOnly = false
            showOfflineOnly = false
            searchFocused = false
        }
    }

    private func sidebarOverlayView(geometry: GeometryProxy) -> some View {
        Group {
            if isProfileSidebarPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isProfileSidebarPresented = false
                        }
                    }
            }
        }
    }

    private func sidebarView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Spacer()
            if isProfileSidebarPresented {
                ProfileView(
                    onLogout: {
                        // Close the sidebar first so its confirmation dialog / overlay
                        // doesn't linger over LoginView and block text entry.
                        isProfileSidebarPresented = false
                        onLogout()
                    },
                    onOpenTimesheets: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isProfileSidebarPresented = false
                        }
                        navigationPath.append(MainNavDestination.myTimesheets)
                    },
                    onOpenAssetCheckout: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isProfileSidebarPresented = false
                        }
                        navigationPath.append(MainNavDestination.assetCheckout(code: nil))
                    }
                )
                .environmentObject(sessionManager)
                .frame(width: min(geometry.size.width * 0.75, 340))
                .background(BrandChrome.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                )
                .shadow(color: BrandChrome.isMcPhillips ? .clear : Color.black.opacity(0.2), radius: BrandChrome.isMcPhillips ? 0 : 10)
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isProfileSidebarPresented)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    BrandChrome.groupedBackground
                        .ignoresSafeArea()

                    VStack(spacing: BrandChrome.isMcPhillips ? 12 : 14) {
                        headerView
                            .padding(.top, 4)

                        offlineBanner
                        softErrorBanner
                        permissionsBanner

                        searchBar
                        statusFilterChips
                        toolsRow

                        if let lastUpdated, !isLoading {
                            HStack {
                                Spacer()
                                Text("Updated \(relativeDateFormatter.localizedString(for: lastUpdated, relativeTo: Date()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        mainContentView(geometry: geometry)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .navigationTitle("")
                    .navigationBarHidden(true)
                    .blur(radius: isProfileSidebarPresented ? 2 : 0)
                    .disabled(isProfileSidebarPresented)

                    sidebarOverlayView(geometry: geometry)
                    sidebarView(geometry: geometry)
                }
            }
            // Keyed on the token so a silent re-auth after returning from background
            // (token rotation) automatically re-fetches and clears any stale error banner.
            .task(id: token) { await refreshProjects() }
            .onAppear {
                AnalyticsManager.shared.trackScreenView("Project List")
            }
            .trackPageView("/projects", projectId: nil)
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
            .sheet(item: $infoProject) { project in
                ProjectInfoSheet(
                    project: project,
                    isCached: isProjectCached(projectId: project.id)
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToProject"))) { notification in
                if let userInfo = notification.userInfo,
                   let projectId = userInfo["projectId"] as? Int,
                   projects.contains(where: { $0.id == projectId }) {
                    navigationPath.append(MainNavDestination.project(projectId))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDrawing"))) { notification in
                if let userInfo = notification.userInfo,
                   let projectId = userInfo["projectId"] as? Int,
                   projects.contains(where: { $0.id == projectId }) {
                    navigationPath.append(MainNavDestination.project(projectId))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDocument"))) { notification in
                if let userInfo = notification.userInfo,
                   let projectId = userInfo["projectId"] as? Int,
                   projects.contains(where: { $0.id == projectId }) {
                    navigationPath.append(MainNavDestination.project(projectId))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToRFI"))) { notification in
                if let userInfo = notification.userInfo,
                   let projectId = userInfo["projectId"] as? Int,
                   projects.contains(where: { $0.id == projectId }) {
                    navigationPath.append(MainNavDestination.project(projectId))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMyTimesheets"))) { _ in
                navigationPath.append(MainNavDestination.myTimesheets)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToRequisition"))) { notification in
                if let userInfo = notification.userInfo,
                   let projectId = userInfo["projectId"] as? Int,
                   projects.contains(where: { $0.id == projectId }) {
                    navigationPath.append(MainNavDestination.project(projectId))
                }
            }
            .navigationDestination(for: MainNavDestination.self) { destination in
                switch destination {
                case .project(let projectId):
                    if let project = projects.first(where: { $0.id == projectId }) {
                        ProjectSummaryView(projectId: projectId, token: token, projectName: project.name)
                            .onAppear {
                                trackProjectAccess(projectId: projectId)
                                AnalyticsManager.shared.trackProjectView(projectId: projectId, projectName: project.name)
                            }
                    }
                case .myTimesheets:
                    TimesheetsListView(isPresentedAsSheet: false)
                        .environmentObject(sessionManager)
                case .assetCheckout(let code):
                    AssetCheckoutView(initialCode: code)
                        .environmentObject(sessionManager)
                }
            }
        }
    }

    private var filteredProjects: [Project] {
        var activeProjects = projects

        if showOfflineOnly || !networkStatusManager.isNetworkAvailable {
            activeProjects = activeProjects.filter { isProjectCached(projectId: $0.id) }
        }

        if showRecentOnly {
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            activeProjects = activeProjects.filter { project in
                guard let accessTime = getProjectAccessTime(projectId: project.id) else { return false }
                return accessTime >= cutoff
            }
        }

        if let status = selectedStatus {
            activeProjects = activeProjects.filter { $0.projectStatus == status.rawValue }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            activeProjects = activeProjects.filter {
                $0.name.lowercased().contains(query) ||
                ($0.location?.lowercased().contains(query) ?? false) ||
                $0.reference.lowercased().contains(query)
            }
        }

        activeProjects.sort { project1, project2 in
            let accessTime1 = getProjectAccessTime(projectId: project1.id)
            let accessTime2 = getProjectAccessTime(projectId: project2.id)

            if showRecentOnly {
                let t1 = accessTime1 ?? .distantPast
                let t2 = accessTime2 ?? .distantPast
                if t1 != t2 { return t1 > t2 }
            } else if let time1 = accessTime1, let time2 = accessTime2, time1 != time2 {
                return time1 > time2
            } else if accessTime1 != nil && accessTime2 == nil {
                return true
            } else if accessTime1 == nil && accessTime2 != nil {
                return false
            }

            let result: Bool
            switch sortOption {
            case .name:
                result = project1.name.localizedCaseInsensitiveCompare(project2.name) == .orderedAscending
            case .status:
                result = (project1.projectStatus ?? "").localizedCaseInsensitiveCompare(project2.projectStatus ?? "") == .orderedAscending
            case .reference:
                result = project1.reference.localizedCaseInsensitiveCompare(project2.reference) == .orderedAscending
            case .location:
                result = (project1.location ?? "").localizedCaseInsensitiveCompare(project2.location ?? "") == .orderedAscending
            }
            return sortOrder == .ascending ? result : !result
        }

        return activeProjects
    }

    private struct EnhancedProjectRow: View {
        let project: Project
        let isCached: Bool

        var body: some View {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(statusColor)
                    .frame(width: 4)
                    .padding(.vertical, 10)

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 10 : 12, style: .continuous)
                            .fill(BrandChrome.isMcPhillips ? AppBrand.current.surfaces.accentSoftBgColor : statusColor.opacity(0.14))
                            .frame(width: 46, height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 10 : 12, style: .continuous)
                                    .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
                            )
                        Text(projectInitials)
                            .font(.system(size: 15, weight: .bold, design: BrandChrome.bodyDesign))
                            .foregroundColor(BrandChrome.isMcPhillips ? BrandChrome.accent : statusColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(project.name)
                                .font(.system(size: 16, weight: .semibold, design: BrandChrome.bodyDesign))
                                .foregroundColor(BrandChrome.isMcPhillips ? AppBrand.current.colors.deepestColor : .primary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            if isCached {
                                Image(systemName: "checkmark.icloud.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(BrandChrome.accent)
                                    .accessibilityLabel("Saved for offline")
                            }
                        }

                        HStack(spacing: 8) {
                            Text(statusDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(statusColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: BrandChrome.isMcPhillips ? 6 : 20, style: .continuous))

                            Text(project.reference)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let location = project.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .padding(.vertical, 12)
            }
            .brandCard(cornerRadius: 14)
        }

        private var projectInitials: String {
            let parts = project.name.split(separator: " ").prefix(2)
            let initials = parts.compactMap { $0.first.map(String.init) }.joined()
            return initials.isEmpty ? String(project.name.prefix(2)).uppercased() : initials.uppercased()
        }

        private var statusDisplayName: String {
            (project.projectStatus ?? "Unknown")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        private var statusColor: Color {
            switch project.projectStatus {
            case "IN_PROGRESS": return Color(hex: "#16A34A")
            case "COMPLETED": return BrandChrome.accent
            case "PLANNING": return Color(hex: "#0891b2")
            default: return .gray
            }
        }
    }

    private struct SkeletonProjectRow: View {
        var body: some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.18))
                        .frame(width: 140, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 90, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 110, height: 10)
                }
                Spacer()
            }
            .padding(14)
            .brandCard(cornerRadius: 14)
            .redacted(reason: .placeholder)
        }
    }

    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
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
        // Acquire the refresh flag, waiting briefly if another refresh holds it.
        // This matters after a silent re-auth: the token rotation restarts
        // `.task(id: token)`, and the replacement task can arrive before the
        // cancelled one has released the flag — skipping here would leave the
        // list stale and any error banner uncleared.
        while true {
            let acquired = await MainActor.run { () -> Bool in
                if isRefreshing { return false }
                isRefreshing = true
                if projects.isEmpty { isLoading = true }
                return true
            }
            if acquired { break }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        defer { Task { @MainActor in isRefreshing = false } }

        // Offline-first: load local first, then refresh from the network
        if let cachedProjects = loadProjectsFromCache(), !cachedProjects.isEmpty {
            await MainActor.run {
                projects = cachedProjects
                isLoading = false
                errorMessage = nil
                lastUpdated = getCacheFileLastModifiedDate()
            }
        }

        // Always attempt the fetch, even if the path monitor claims we're offline —
        // NWPathMonitor state can be stale right after returning from background,
        // which previously turned Retry into a silent no-op.
        do {
            let currentToken = await MainActor.run { sessionManager.token ?? token }
            let p = try await APIClient.fetchProjects(token: currentToken)
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
        } catch APIError.forbidden {
            // Treat forbidden as an invalid session in this context
            await MainActor.run {
                sessionManager.handleTokenExpiration()
            }
        } catch {
            // A token rotation mid-request restarts `.task(id: token)`, cancelling
            // this attempt. The replacement task re-fetches immediately, so a
            // cancelled fetch is not a failure — don't surface an error banner.
            if Task.isCancelled || isCancellationError(error) {
                print("refreshProjects: Fetch cancelled (superseded by a newer refresh); ignoring")
                return
            }
            let detail = (error as? APIError)?.displayMessage ?? error.localizedDescription
            await MainActor.run {
                isLoading = false
                let isOffline = !networkStatusManager.isNetworkAvailable
                if !projects.isEmpty {
                    if isOffline {
                        // The offline banner already explains the situation; an
                        // additional error banner here would just be noise.
                        errorMessage = nil
                    } else {
                        errorMessage = "Couldn't refresh — showing cached data. (\(detail))"
                    }
                    lastUpdated = getCacheFileLastModifiedDate()
                } else if isOffline {
                    errorMessage = "Offline: No internet connection and no cached data available."
                } else {
                    errorMessage = "Failed to load projects: \(detail)"
                }
                print("refreshProjects: Error fetching projects: \(error). Project count: \(projects.count)")
            }
        }
    }

    /// True when `error` represents a cancelled request, including a
    /// `URLError.cancelled`/`CancellationError` wrapped in `APIError.networkError`.
    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case APIError.networkError(let underlying) = error {
            return isCancellationError(underlying)
        }
        return false
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
    
    // MARK: - Project Access Tracking
    private func trackProjectAccess(projectId: Int) {
        let accessTime = Date()
        UserDefaults.standard.set(accessTime.timeIntervalSince1970, forKey: "projectAccessTime_\(projectId)")
        print("ProjectListView: Tracked access to project \(projectId) at \(accessTime)")
    }
    
    private func getProjectAccessTime(projectId: Int) -> Date? {
        let timeInterval = UserDefaults.standard.double(forKey: "projectAccessTime_\(projectId)")
        guard timeInterval > 0 else { return nil }
        return Date(timeIntervalSince1970: timeInterval)
    }
}

// MARK: - Supporting Views
struct ProjectInfoSheet: View {
    let project: Project
    let isCached: Bool
    @Environment(\.dismiss) private var dismiss

    private var statusName: String {
        (project.projectStatus ?? "Unknown")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var statusColor: Color {
        switch project.projectStatus {
        case "IN_PROGRESS": return Color(hex: "#16A34A")
        case "COMPLETED": return BrandChrome.accent
        case "PLANNING": return Color(hex: "#0891b2")
        default: return .gray
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.name)
                            .font(.title3.weight(.semibold))
                        Text(statusName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }

                Section("Details") {
                    LabeledContent("Reference", value: project.reference)
                    LabeledContent("Location", value: project.location?.isEmpty == false ? project.location! : "Not set")
                    LabeledContent("Offline", value: isCached ? "Saved on this device" : "Not saved")
                }
            }
            .navigationTitle("Project Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

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
    var onOpenTimesheets: (() -> Void)? = nil
    var onOpenAssetCheckout: (() -> Void)? = nil
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineSubmissionManager.shared
    @State private var isClearingCache = false
    @State private var cacheClearResult: (success: Bool, message: String)?
    @State private var showCacheClearAlert = false
    @State private var showQualifications = false
    @State private var showPendingSyncs = false
    @State private var activityMonitoringEnabled: Bool = true
    @State private var showSignOutConfirmation = false
    @State private var faceIDEnabled: Bool = KeychainHelper.hasStoredPassword()
    @State private var biometricsAvailable: Bool = false
    @State private var showEnableFaceIDSheet = false

    // Intercepts the toggle so switching it ON requires confirming the password first
    // (we don't have it in memory from the current session), while switching it OFF
    // can happen immediately.
    private var faceIDToggleBinding: Binding<Bool> {
        Binding(
            get: { faceIDEnabled },
            set: { newValue in
                if newValue {
                    showEnableFaceIDSheet = true
                } else {
                    _ = KeychainHelper.deleteCredentials()
                    faceIDEnabled = false
                }
            }
        )
    }

    var body: some View {
        ZStack {
            BrandChrome.cardBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header with Avatar
                    VStack(spacing: 12) {
                        // User Avatar
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppBrand.current.primaryColor, AppBrand.current.secondaryColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Text(userInitials)
                                .font(.system(size: 28, weight: .semibold, design: BrandChrome.bodyDesign))
                                .foregroundColor(.white)
                        }
                        .shadow(color: BrandChrome.accent.opacity(BrandChrome.isMcPhillips ? 0 : 0.3), radius: BrandChrome.isMcPhillips ? 0 : 8, x: 0, y: BrandChrome.isMcPhillips ? 0 : 4)
                        
                        // User Name
                        Text(userName)
                            .font(
                                BrandChrome.isMcPhillips
                                    ? .system(size: 22, weight: .regular, design: BrandChrome.displayDesign)
                                    : .system(size: 20, weight: .semibold, design: .rounded)
                            )
                            .foregroundColor(BrandChrome.isMcPhillips ? AppBrand.current.colors.deepestColor : .primary)
                        
                        // Email
                        if let email = sessionManager.user?.email {
                            Text(email)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                    
                    // Account Details Section
                    VStack(spacing: 0) {
                        profileInfoRow(
                            icon: "building.2.fill",
                            label: "Organisation",
                            value: currentTenantName ?? "Not selected",
                            iconColor: Color(hex: "#8B5CF6")
                        )
                        
                        Divider()
                            .padding(.leading, 60)
                        
                        profileInfoRow(
                            icon: "briefcase.fill",
                            label: "Company",
                            value: userCompanyName ?? "Not assigned",
                            iconColor: Color(hex: "#F59E0B")
                        )
                        
                        if let roles = sessionManager.user?.roles, !roles.isEmpty {
                            Divider()
                                .padding(.leading, 60)
                            
                            profileInfoRow(
                                icon: "person.badge.shield.checkmark.fill",
                                label: "Role",
                                value: roles.map { $0.name }.joined(separator: ", "),
                                iconColor: Color(hex: "#10B981")
                            )
                        }
                    }
                    .background(BrandChrome.secondaryCardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // Pending Syncs Button
                    Button(action: {
                        showPendingSyncs = true
                    }) {
                        HStack(spacing: 12) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "#F59E0B"))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: "#F59E0B").opacity(0.12))
                                    .cornerRadius(8)
                                if offlineManager.pendingSubmissionsCount > 0 {
                                    Text("\(offlineManager.pendingSubmissionsCount)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: "#EF4444"))
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: -6)
                                }
                            }
                            
                            Text("Pending Syncs")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(BrandChrome.secondaryCardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Qualifications Button
                    Button(action: {
                        showQualifications = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#10B981"))
                                .frame(width: 32, height: 32)
                                .background(Color(hex: "#10B981").opacity(0.12))
                                .cornerRadius(8)
                            
                            Text("My Qualifications")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(BrandChrome.secondaryCardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Assets (visible when user has view_assets or check_inandout_assets)
                    if hasAssetCheckoutPermission {
                        Button(action: {
                            onOpenAssetCheckout?()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "#6366F1"))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: "#6366F1").opacity(0.12))
                                    .cornerRadius(8)
                                
                                Text("Assets")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(BrandChrome.secondaryCardBackground)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }

                    // Timesheets Button
//                    Button(action: {
//                        onOpenTimesheets?()
//                    }) {
//                        HStack(spacing: 12) {
//                            Image(systemName: "clock.badge.checkmark.fill")
//                                .font(.system(size: 18))
//                                .foregroundColor(BrandChrome.accent)
//                                .frame(width: 32, height: 32)
//                                .background(BrandChrome.accent.opacity(0.12))
//                                .cornerRadius(8)
//                            
//                            Text("My Timesheets")
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.primary)
//                            
//                            Spacer()
//                            
//                            Image(systemName: "chevron.right")
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.secondary)
//                        }
//                        .padding(.horizontal, 16)
//                        .padding(.vertical, 14)
//                    }
//                    .background(BrandChrome.secondaryCardBackground)
//                    .cornerRadius(12)
//                    .padding(.horizontal, 20)
//                    .padding(.bottom, 16)
//
//                    // Activity monitoring (only when signed in)
//                    if sessionManager.token != nil {
//                        VStack(spacing: 0) {
//                            HStack(spacing: 12) {
//                                Image(systemName: "chart.bar.doc.horizontal.fill")
//                                    .font(.system(size: 18))
//                                    .foregroundColor(BrandChrome.accent)
//                                    .frame(width: 32, height: 32)
//                                    .background(BrandChrome.accent.opacity(0.12))
//                                    .cornerRadius(8)
//                                VStack(alignment: .leading, spacing: 2) {
//                                    Text("Activity monitoring")
//                                        .font(.system(size: 14, weight: .medium))
//                                        .foregroundColor(.primary)
//                                    Text("Helps improve the app; uses minimal battery.")
//                                        .font(.system(size: 12, weight: .regular))
//                                        .foregroundColor(.secondary)
//                                }
//                                Spacer()
//                                Toggle("", isOn: $activityMonitoringEnabled)
//                                    .labelsHidden()
//                                    .onChange(of: activityMonitoringEnabled) { _, newValue in
//                                        AnalyticsService.shared.isActivityMonitoringEnabled = newValue
//                                    }
//                            }
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 14)
//                        }
//                        .background(BrandChrome.secondaryCardBackground)
//                        .cornerRadius(12)
//                        .padding(.horizontal, 20)
//                        .padding(.bottom, 16)
//                    }

                    // Face ID Sign-In Section
                    if biometricsAvailable {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "faceid")
                                    .font(.system(size: 18))
                                    .foregroundColor(AppBrand.current.primaryColor)
                                    .frame(width: 32, height: 32)
                                    .background(AppBrand.current.primaryColor.opacity(0.12))
                                    .cornerRadius(8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Face ID Sign-In")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text("Sign in faster without typing your password.")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: faceIDToggleBinding)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(BrandChrome.secondaryCardBackground)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }

                    // Storage Section
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#6366F1"))
                                .frame(width: 32, height: 32)
                                .background(Color(hex: "#6366F1").opacity(0.12))
                                .cornerRadius(8)
                            
                            Text("Cache")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(CacheManager.shared.getCacheSize().formatted)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(BrandChrome.secondaryCardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Action Buttons
                    VStack(spacing: 12) {
                        // Clear Cache Button
                        Button(action: {
                            clearCache()
                        }) {
                            HStack(spacing: 8) {
                                if isClearingCache {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                Text(isClearingCache ? "Clearing..." : "Clear Cache")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BrandChrome.accent)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isClearingCache)
                        
                        // Logout Button
                        Button(action: {
                            showSignOutConfirmation = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 15, weight: .medium))
                                Text("Sign Out")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .foregroundColor(Color(hex: "#EF4444"))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .alert(isPresented: $showCacheClearAlert) {
            Alert(
                title: Text(cacheClearResult?.success ?? false ? "Cache Cleared" : "Clear Cache Failed"),
                message: Text(cacheClearResult?.message ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            AppBrand.current.signOutConfirmationTitle,
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                onLogout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your projects.")
        }
        .sheet(isPresented: $showQualifications) {
            UserQualificationsView()
                .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showPendingSyncs) {
            PendingSubmissionsView()
        }
        .sheet(isPresented: $showEnableFaceIDSheet) {
            EnableFaceIDSheet(
                email: sessionManager.user?.email ?? KeychainHelper.getEmail() ?? "",
                onSuccess: {
                    faceIDEnabled = true
                    showEnableFaceIDSheet = false
                },
                onCancel: {
                    showEnableFaceIDSheet = false
                }
            )
        }
        .onAppear {
            activityMonitoringEnabled = AnalyticsService.shared.isActivityMonitoringEnabled
            biometricsAvailable = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            faceIDEnabled = KeychainHelper.hasStoredPassword()
        }
    }
    
    // MARK: - Computed Properties
    
    private var userName: String {
        let firstName = sessionManager.user?.firstName ?? ""
        let lastName = sessionManager.user?.lastName ?? ""
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "User" : fullName
    }
    
    private var userInitials: String {
        let firstName = sessionManager.user?.firstName ?? ""
        let lastName = sessionManager.user?.lastName ?? ""
        let firstInitial = firstName.first.map { String($0).uppercased() } ?? ""
        let lastInitial = lastName.first.map { String($0).uppercased() } ?? ""
        let initials = "\(firstInitial)\(lastInitial)"
        return initials.isEmpty ? "U" : initials
    }
    
    private var currentTenantName: String? {
        guard let selectedTenantId = sessionManager.selectedTenantId,
              let tenants = sessionManager.tenants else {
            return nil
        }
        
        let currentTenant = tenants.first { userTenant in
            userTenant.tenant?.id == selectedTenantId || userTenant.tenantId == selectedTenantId
        }
        
        return currentTenant?.tenant?.name
    }
    
    private var userCompanyName: String? {
        // First try to get company from the current tenant's user info
        guard let selectedTenantId = sessionManager.selectedTenantId,
              let tenants = sessionManager.tenants else {
            return sessionManager.user?.company?.name
        }
        
        let currentTenant = tenants.first { userTenant in
            userTenant.tenant?.id == selectedTenantId || userTenant.tenantId == selectedTenantId
        }
        
        // Prefer the tenant-specific company, fallback to user's company
        return currentTenant?.company?.name ?? sessionManager.user?.company?.name
    }

    private var hasAssetCheckoutPermission: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_assets") || permissions.contains("check_inandout_assets")
    }
    
    // MARK: - Helper Views
    
    private func profileInfoRow(icon: String, label: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .cornerRadius(8)
            
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func clearCache() {
        isClearingCache = true

        // Run cache clearing on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CacheManager.shared.clearAllCaches()

            DispatchQueue.main.async {
                self.isClearingCache = false
                self.cacheClearResult = result
                self.showCacheClearAlert = true
            }
        }
    }
}

// MARK: - Enable Face ID Sheet
// Asks the user to re-enter their password before enabling Face ID sign-in from
// Settings. We don't have their password in memory outside of the login flow, so it's
// verified against the backend once here before being saved (biometric-gated) to Keychain.
private struct EnableFaceIDSheet: View {
    let email: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var error: String = ""
    @State private var isVerifying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 40))
                    .foregroundColor(AppBrand.current.primaryColor)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text("Enable Face ID Sign-In")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Confirm your password once to enable Face ID for \(email).")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                if !error.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .disabled(isVerifying)
                    .onSubmit { verify() }

                Button(action: verify) {
                    HStack {
                        if isVerifying {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.5)
                        }
                        Text(isVerifying ? "Verifying..." : "Enable Face ID")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppBrand.current.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isVerifying || password.isEmpty)

                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(isVerifying)
                }
            }
        }
    }

    private func verify() {
        guard !password.isEmpty else { return }
        isVerifying = true
        error = ""
        Task {
            do {
                _ = try await APIClient.login(email: email, password: password)
                await MainActor.run {
                    isVerifying = false
                    if KeychainHelper.enableFaceIDCredentials(email: email, password: password) {
                        onSuccess()
                    } else {
                        self.error = "Couldn't save your credentials securely. Please try again."
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = LoginView.loginErrorMessage(for: error)
                    isVerifying = false
                }
            }
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
                    .fill(isSelected ? BrandChrome.accent : BrandChrome.subtleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? BrandChrome.accent : BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips && !isSelected ? 1 : (isSelected ? 1 : 0))
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
            .background(active ? BrandChrome.accent : BrandChrome.subtleFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Options View
struct SortOptionsView: View {
    @Binding var sortOption: SortOption
    @Binding var sortOrder: ProjectSortOrder
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
                    ForEach(ProjectSortOrder.allCases, id: \.self) { order in
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
