import SwiftUI

struct ProjectListView: View {
    let token: String
    let tenantId: Int // Add this back
    let onLogout: () -> Void
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.1), Color.white]), startPoint: .top, endPoint: .bottom)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    if isLoading {
                        ProgressView("Loading Projects...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding()
                    } else if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    } else if filteredProjects.isEmpty {
                        Text("No active projects available")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredProjects) { project in
                                    NavigationLink(destination: DrawingListView(projectId: project.id, token: token)) {
                                        ProjectRow(project: project)
                                    }
                                    .listRowBackground(Color.white.opacity(0.9))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            }
                            .background(Color.white.opacity(0.95))
                        }
                        .scrollIndicators(.visible)
                        .refreshable {
                            await refreshProjects()
                        }
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle("Projects")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            Task {
                                await refreshProjects()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            onLogout() // Trigger logout
                        }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .task {
                await refreshProjects()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var filteredProjects: [Project] {
        let activeProjects = projects.filter { $0.projectStatus?.lowercased() == "in_progress" || $0.projectStatus == nil }
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
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let location = project.location, !location.isEmpty {
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(project.reference)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .animation(.easeInOut, value: project.name)
        }
    }

    private func refreshProjects() async {
        isLoading = true
        errorMessage = nil
        APIClient.fetchProjects(token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let p):
                    withAnimation {
                        projects = p
                    }
                case .failure(let error):
                    errorMessage = "Failed to load projects: \(error.localizedDescription)"
                }
            }
        }
    }
}

