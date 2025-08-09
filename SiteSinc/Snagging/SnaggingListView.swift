import SwiftUI

struct SnaggingListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selections: [APIClient.SnagSelectedDrawing] = []
    @State private var showRefreshHint: Bool = false

    var canViewSnags: Bool {
        sessionManager.hasPermission("snag_manager") ||
        sessionManager.hasPermission("view_all_snags") ||
        sessionManager.hasPermission("view_snags")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading {
                    ProgressView("Loading snagging drawings…")
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .padding(.top, 24)
                } else if let error = errorMessage {
                    errorBanner(error)
                } else if selections.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(selections, id: \.id) { selection in
                            NavigationLink(
                                destination: SnaggingViewer(
                                    projectId: projectId,
                                    token: token,
                                    drawing: selection.drawing,
                                    drawingFileId: selection.drawingFileId
                                )
                                .environmentObject(sessionManager)
                                .environmentObject(networkStatusManager)
                            ) {
                                SnaggingDrawingCard(selection: selection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Snagging")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoading {
                    ProgressView()
                } else {
                    Button(action: { Task { await refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh selected drawings")
                }
            }
        }
        .onAppear {
            Task { await refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(projectName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Selected drawings available for snagging")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44)).foregroundColor(.gray.opacity(0.5))
            Text("No drawings selected for snagging")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Use the web app to select drawings (PDF files) for snagging, then pull to refresh here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Failed to load").font(.headline)
                Text(message).font(.subheadline)
                Button("Retry") { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func refresh() async {
        guard canViewSnags else {
            await MainActor.run { self.errorMessage = "You don't have permission to view snags." }
            return
        }
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let loaded = try await APIClient.fetchSelectedSnagDrawings(projectId: projectId, token: token)
            await MainActor.run { self.selections = loaded; self.isLoading = false }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

private struct SnaggingDrawingCard: View {
    let selection: APIClient.SnagSelectedDrawing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 140)
                VStack(spacing: 4) {
                    Image(systemName: "doc.text").font(.system(size: 28)).foregroundColor(.blue)
                    Text("PDF File #\(selection.drawingFileId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("\(selection.drawing.number) – \(selection.drawing.title)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
            Text("Selected \(formatted(dateString: selection.selectedAt))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1))
        .contentShape(Rectangle())
    }

    private func formatted(dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        if let d = iso.date(from: dateString) { return out.string(from: d) }
        return dateString
    }
}


