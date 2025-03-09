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

    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.2), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)

                // Main content
                VStack {
                    if isLoading {
                        ProgressView("Loading Projects...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(10)
                            .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    } else if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(10)
                            .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    } else if filteredProjects.isEmpty {
                        Text("No active projects available")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(10)
                            .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredProjects) { project in
                                    NavigationLink(destination: DrawingListView(projectId: project.id, token: token)) {
                                        ProjectRow(project: project)
                                            .background(
                                                Color.white
                                                    .cornerRadius(15)
                                                    .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 3)
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
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle("Projects")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    onLogout()
                                }
                            }) {
                                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)
                            }
                        } label: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Circle())
                                .shadow(color: .gray.opacity(0.2), radius: 3, x: 0, y: 2)
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
                    .fill(project.projectStatus?.lowercased() == "in_progress" ? Color.green : Color.blue.opacity(0.2))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if let location = project.location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)

                Spacer()

                Text(project.reference)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.3), value: project.name)
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        projects = p
                    }
                case .failure(let error):
                    errorMessage = "Failed to load projects: \(error.localizedDescription)"
                }
            }
        }
    }
}
