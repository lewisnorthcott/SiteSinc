import SwiftUI

struct ProjectListView: View {
    let token: String
    let tenantId: Int
    let onLogout: () -> Void
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var selectedStatus: ProjectStatusFilter = .all
    @State private var showFilterPicker = false
    @State private var isProfileTapped = false
    @State private var isProfileSidebarPresented = false // Controls sidebar visibility

    enum ProjectStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In Progress"
        case completed = "Completed"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .trailing) {
                // Main Content
                VStack(spacing: 16) {
                    // Projects Title
                    Text("Projects")
                        .font(.title2)
                        .fontWeight(.regular)
                        .foregroundColor(.black)
                        .padding(.top, 16)

                    // Search Bar with Filter Icon
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

                        Button(action: {
                            withAnimation(.easeInOut) {
                                showFilterPicker.toggle()
                            }
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#635bff"))
                                .padding(6)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(Circle())
                        }
                    }

                    // Status Filter Picker (shown conditionally)
                    if showFilterPicker {
                        Picker("Filter by Status", selection: $selectedStatus) {
                            ForEach(ProjectStatusFilter.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 16)
                    }

                    if isLoading {
                        ProgressView("Loading Projects...")
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
                    } else if filteredProjects.isEmpty {
                        Text("No projects available")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredProjects) { project in
                                    NavigationLink(destination: ProjectSummaryView(projectId: project.id, token: token)) {
                                        ProjectRow(project: project)
                                            .background(
                                                Color.white
                                                    .cornerRadius(8)
                                                    .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
                                            )
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 4)
                                            .scaleEffect(isRefreshing ? 0.98 : 1.0)
                                    }
                                }
                            }
                            .padding(.vertical, 10)
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
                    Spacer()
                }
                .padding(.horizontal, 24)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isProfileTapped = true
                                isProfileSidebarPresented.toggle() // Toggle sidebar
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isProfileTapped = false
                                }
                            }
                        }) {
                            Image(systemName: "person")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#635bff"))
                                .padding(8)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(Circle())
                                .scaleEffect(isProfileTapped ? 0.9 : 1.0)
                        }
                    }
                }
                .offset(x: isProfileSidebarPresented ? -UIScreen.main.bounds.width * 0.6 : 0) // Shift main content when sidebar is open
                .animation(.easeInOut(duration: 0.3), value: isProfileSidebarPresented)

                // Sidebar
                ProfileView(onLogout: {
                    onLogout()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isProfileSidebarPresented = false // Close sidebar on logout
                    }
                })
                .frame(width: UIScreen.main.bounds.width * 0.6) // Sidebar width
                .offset(x: isProfileSidebarPresented ? 0 : UIScreen.main.bounds.width * 0.6) // Slide in/out
                .animation(.easeInOut(duration: 0.3), value: isProfileSidebarPresented)
                .ignoresSafeArea()
            }
            .task {
                await refreshProjects()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var filteredProjects: [Project] {
        var activeProjects = projects
        switch selectedStatus {
        case .inProgress:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "in_progress" }
        case .completed:
            activeProjects = activeProjects.filter { $0.projectStatus?.lowercased() == "completed" }
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

    private struct ProjectRow: View {
        let project: Project

        var body: some View {
            HStack {
                Circle()
                    .fill(project.projectStatus?.lowercased() == "in_progress" ? Color.green : Color.blue.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if let location = project.location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)

                Spacer()

                Text(project.reference)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.3), value: project.name)
        }
    }
    
    private func saveProjectsToCache(_ projects: [Project]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(projects) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("projects.json")
            try? data.write(to: cacheURL)
        }
    }

    private func loadProjectsFromCache() -> [Project]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("projects.json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            return try? decoder.decode([Project].self, from: data)
        }
        return nil
    }

    private func refreshProjects() async {
        isLoading = true
        errorMessage = nil
        APIClient.fetchProjects(token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let p):
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        projects = p
                    }
                    saveProjectsToCache(p)
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        if let cachedProjects = loadProjectsFromCache() {
                            projects = cachedProjects
                            errorMessage = "Loaded cached projects (offline mode)"
                        } else {
                            errorMessage = "No internet connection and no cached data available"
                        }
                    } else {
                        errorMessage = "Failed to load projects: \(error.localizedDescription)"
                    }
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
                // Profile Header
                Image(systemName: "person")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "#635bff"))
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .clipShape(Circle())

                Text("Profile")
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundColor(.black)

                // Logout Button
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
    }
}
