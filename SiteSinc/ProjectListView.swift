//
//  ProjectListView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import SwiftUI

struct ProjectListView: View {
    let token: String
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                    } else if projects.isEmpty {
                        Text("No projects available")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ScrollView { // Explicit ScrollView for custom control
                            LazyVStack(spacing: 0) {
                                ForEach(projects) { project in
                                    NavigationLink(destination: DrawingListView(projectId: project.id, token: token)) {
                                        ProjectRow(project: project)
                                    }
                                    .listRowBackground(Color.white.opacity(0.9))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            }
                            .background(Color.white.opacity(0.95)) // Subtle background for scroll area
                        }
                        .scrollIndicators(.visible) // Show scroll indicators
                        .refreshable {
                            await refreshProjects()
                        }
                    }
                }
                .navigationTitle("Projects")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task {
                                await refreshProjects()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .task {
                await refreshProjects()
            }
        }.navigationViewStyle(StackNavigationViewStyle())
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

#Preview {
    ProjectListView(token: "sample-token")
}
