import SwiftUI

struct MeetingsListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @State private var meetings: [MeetingListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var createdMeetingRoute: MeetingRoute?

    private struct MeetingRoute: Identifiable, Hashable {
        let id: Int
    }

    private var currentToken: String { sessionManager.token ?? token }

    private var filtered: [MeetingListItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return meetings }
        return meetings.filter {
            "\($0.reference) \($0.title) \($0.category?.name ?? "") \($0.location ?? "")"
                .lowercased()
                .contains(q)
        }
    }

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading meetings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if filtered.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Meetings")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search meetings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if MeetingPermissions.canCreate(user: sessionManager.user) {
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
                CreateMeetingView(
                    projectId: projectId,
                    token: currentToken,
                    existingMeetings: meetings,
                    onCreated: { meeting in
                        showCreate = false
                        createdMeetingRoute = MeetingRoute(id: meeting.id)
                        Task { await load(showSpinner: false) }
                    }
                )
                .environmentObject(sessionManager)
            }
        }
        .navigationDestination(item: $createdMeetingRoute) { route in
            MeetingDetailView(
                projectId: projectId,
                meetingId: route.id,
                token: currentToken,
                projectName: projectName
            )
            .environmentObject(sessionManager)
        }
        .trackPageView("/projects/\(projectId)/meetings", projectId: projectId)
        .onAppear {
            AnalyticsManager.shared.trackScreenView("Meetings", projectId: projectId)
        }
    }

    private var listContent: some View {
        List(filtered) { meeting in
            NavigationLink {
                MeetingDetailView(
                    projectId: projectId,
                    meetingId: meeting.id,
                    token: currentToken,
                    projectName: projectName
                )
                .environmentObject(sessionManager)
            } label: {
                meetingRow(meeting)
            }
        }
        .listStyle(.plain)
    }

    private func meetingRow(_ meeting: MeetingListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(meeting.reference)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        if meeting.isPrivate == true {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(meeting.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
                MeetingStatusPill(status: meeting.status)
            }

            HStack(spacing: 12) {
                Label(MeetingDateFormatting.displayDateTime(meeting.meetingDate), systemImage: "calendar")
                if let category = meeting.category?.name {
                    Label(category, systemImage: "tag")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: 12) {
                if meeting.openActionsCount > 0 {
                    Label("\(meeting.openActionsCount) open action\(meeting.openActionsCount == 1 ? "" : "s")", systemImage: "checklist")
                        .foregroundColor(.orange)
                }
                if meeting.agendaItemsCount > 0 {
                    Label("\(meeting.agendaItemsCount) agenda", systemImage: "list.bullet")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No meetings yet" : "No matching meetings")
                .font(.title3.weight(.semibold))
            Text("Record meeting notes, agendas, and action items for this project.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if searchText.isEmpty, MeetingPermissions.canCreate(user: sessionManager.user) {
                Button("New meeting") { showCreate = true }
                    .buttonStyle(.borderedProminent)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            meetings = try await APIClient.fetchProjectMeetings(projectId: projectId, token: currentToken)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}

struct MeetingStatusPill: View {
    let status: MeetingStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(status == .final ? .white : .primary)
            .background(status == .final ? Color.green : Color(.systemGray5))
            .clipShape(Capsule())
    }
}
