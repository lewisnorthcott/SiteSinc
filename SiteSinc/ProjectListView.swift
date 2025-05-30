import SwiftUI

struct ProjectListView: View {
    let token: String
    let tenantId: Int
    let onLogout: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var selectedStatus: ProjectStatusFilter = .all
    @State private var showFilterPicker = false
    @State private var isProfileTapped = false
    @State private var isProfileSidebarPresented = false
    @State private var lastUpdated: Date? = nil

    enum ProjectStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case planning = "Planning"
        case inProgress = "In Progress"
        case completed = "Completed"
        case onHold = "On Hold"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    // Main content
                    VStack(spacing: 20) {
                        // Header
                        HStack {
                            Text("Projects")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isProfileTapped = true
                                    isProfileSidebarPresented.toggle()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        isProfileTapped = false
                                    }
                                }
                            }) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(hex: "#635bff"))
                                    .accessibilityLabel("Profile")
                                    .scaleEffect(isProfileTapped ? 0.9 : 1.0)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)

                        // Search and Filter
                        HStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Search projects", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .accessibilityLabel("Search projects")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .frame(maxWidth: .infinity)

                            Picker("Status", selection: $selectedStatus) {
                                ForEach(ProjectStatusFilter.allCases) { status in
                                    Text(status.rawValue).tag(status)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 120)
                            .accessibilityLabel("Filter by status")
                        }
                        .padding(.horizontal, 4)

                        // Last updated
                        if let lastUpdated = lastUpdated {
                            Text("Last updated: \(lastUpdated, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.bottom, 2)
                        }

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
                                Image(systemName: "exclamationmark.circle")
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
                            VStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .resizable()
                                    .frame(width: 48, height: 48)
                                    .foregroundColor(.gray.opacity(0.3))
                                Text("No projects found")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Text("Try adjusting your search or filters.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .padding(.top, 40)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredProjects) { project in
                                        NavigationLink(destination: ProjectSummaryView(projectId: project.id, token: token, projectName: project.name)) {
                                            EnhancedProjectRow(project: project)
                                                .accessibilityElement(children: .combine)
                                                .accessibilityLabel("Project: \(project.name), Status: \(project.projectStatus ?? "Unknown")")
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
        }
    }

    private var filteredProjects: [Project] {
        var activeProjects = projects
        switch selectedStatus {
        case .planning:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "planning" }
        case .inProgress:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "in progress" }
        case .completed:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "completed" }
        case .onHold:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "on hold" }
        case .all:
            break
        }
        if searchText.isEmpty {
            return activeProjects
        } else {
            return activeProjects.filter {
                $0.name.lowercased().contains(searchText.lowercased()) ||
                ($0.location?.lowercased().contains(searchText.lowercased()) ?? false) ||
                $0.reference.lowercased().contains(searchText.lowercased())
            }
        }
    }

    // Enhanced Project Row
    private struct EnhancedProjectRow: View {
        let project: Project

        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(project.projectStatus?.lowercased() == "in_progress" ? Color.green : Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(project.name.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let location = project.location, !location.isEmpty {
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(project.projectStatus?.capitalized ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(project.reference)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .gray.opacity(0.08), radius: 4, x: 0, y: 2)
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
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("projects.json")
            try data.write(to: cacheURL)
            print("Successfully saved \(projects.count) projects to cache at \(cacheURL.path)")
        } catch {
            print("Failed to save projects to cache: \(error.localizedDescription)")
        }
    }

    private func loadProjectsFromCache() -> [Project]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("projects.json")
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

    private func refreshProjects() async {
        isLoading = true
        errorMessage = nil

        // Check network status first to avoid unnecessary network calls
        let isNetworkAvailable = await NetworkMonitor.shared.waitForInitialNetworkStatus()
        if isNetworkAvailable {
            do {
                let p = try await APIClient.fetchProjects(token: token)
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        projects = p
                    }
                    saveProjectsToCache(p)
                    isLoading = false
                    lastUpdated = Date()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Handle network errors specifically
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .networkError(let underlyingError):
                            if (underlyingError as NSError).code == NSURLErrorNotConnectedToInternet {
                                if let cachedProjects = loadProjectsFromCache() {
                                    projects = cachedProjects
                                    errorMessage = "Loaded cached projects (offline mode)"
                                } else {
                                    errorMessage = "No internet connection and no cached data available"
                                }
                            } else {
                                errorMessage = "Failed to load projects: \(underlyingError.localizedDescription)"
                            }
                        default:
                            errorMessage = "Failed to load projects: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Failed to load projects: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            // Network unavailable, load from cache immediately
            await MainActor.run {
                isLoading = false
                if let cachedProjects = loadProjectsFromCache() {
                    projects = cachedProjects
                    errorMessage = "Loaded cached projects (offline mode)"
                } else {
                    errorMessage = "No internet connection and no cached data available"
                }
            }
        }
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

#Preview {
    NavigationView {
        ProjectListView(token: "sample_token", tenantId: 1, onLogout: {})
            .environmentObject(SessionManager())
    }
}
