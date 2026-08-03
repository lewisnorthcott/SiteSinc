import SwiftUI

struct ToolboxTalksListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @State private var talks: [ProjectToolboxTalk] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var deliverRoute: DeliverRoute?

    struct DeliverRoute: Identifiable, Hashable {
        let talkId: Int
        let sessionId: Int
        var id: String { "\(talkId)-\(sessionId)" }
    }

    private var filtered: [ProjectToolboxTalk] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return talks }
        return talks.filter { "\($0.reference) \($0.title)".lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading toolbox talks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if filtered.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Toolbox Talks")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by reference or title")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if ToolboxTalkPermissions.canAssign(user: sessionManager.user) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .refreshable { await load(showSpinner: false) }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateToolboxTalkWizardView(
                    projectId: projectId,
                    token: token,
                    projectName: projectName,
                    onFinished: { talk, session in
                        showCreate = false
                        Task { await load(showSpinner: false) }
                        if let session {
                            deliverRoute = DeliverRoute(talkId: talk.id, sessionId: session.id)
                        }
                    }
                )
                .environmentObject(sessionManager)
            }
        }
        .navigationDestination(item: $deliverRoute) { route in
            ToolboxTalkDeliverView(
                projectId: projectId,
                talkId: route.talkId,
                sessionId: route.sessionId,
                token: token
            )
            .environmentObject(sessionManager)
        }
        .trackPageView("/projects/\(projectId)/toolbox-talks", projectId: projectId)
        .onAppear {
            AnalyticsManager.shared.trackScreenView("Toolbox Talks", projectId: projectId)
        }
    }

    private var listContent: some View {
        List(filtered) { talk in
            NavigationLink {
                ToolboxTalkDetailView(
                    projectId: projectId,
                    talkId: talk.id,
                    token: token,
                    projectName: projectName
                )
                .environmentObject(sessionManager)
            } label: {
                talkRow(talk)
            }
        }
        .listStyle(.plain)
        .brandListChrome()
    }

    private func talkRow(_ talk: ProjectToolboxTalk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(talk.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(talk.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
                ToolboxTalkStatusPill(status: .from(talk))
            }

            if let sessions = talk.sessions, !sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sessions) { session in
                            ToolboxTalkSessionStatusChip(status: session.status ?? "SCHEDULED")
                        }
                    }
                }
            } else {
                Text("\(talk._count?.sessions ?? 0) session(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No toolbox talks yet")
                .font(.title3.weight(.semibold))
            Text("Create a talk from a template or blank content, then deliver and collect signatures on site.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if ToolboxTalkPermissions.canAssign(user: sessionManager.user) {
                Button("Create toolbox talk") { showCreate = true }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandChrome.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Error").font(.title2.weight(.semibold))
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(BrandChrome.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            talks = try await APIClient.fetchProjectToolboxTalks(projectId: projectId, token: token)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
