import SwiftUI

struct MeetingsListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject private var offlineManager = OfflineMeetingManager.shared
    @State private var meetings: [MeetingListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var createdMeetingRoute: MeetingRoute?
    @State private var showingCached = false
    @State private var offlineCreateMessage: String?

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
        VStack(spacing: 0) {
            if offlineManager.isOffline {
                banner(
                    icon: "wifi.slash",
                    text: showingCached
                        ? "Offline — showing cached meetings."
                        : "You're offline.",
                    tint: .orange
                )
            } else if offlineManager.pendingCount(forProject: projectId) > 0 {
                banner(
                    icon: "arrow.triangle.2.circlepath",
                    text: "\(offlineManager.pendingCount(forProject: projectId)) meeting change(s) waiting to sync.",
                    tint: .green,
                    actionTitle: offlineManager.syncInProgress ? "Syncing…" : "Sync now",
                    actionEnabled: !offlineManager.syncInProgress
                ) {
                    offlineManager.manualSync()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await load(showSpinner: false)
                    }
                }
            }

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
                        if let meeting {
                            createdMeetingRoute = MeetingRoute(id: meeting.id)
                        } else {
                            offlineCreateMessage = "Meeting queued offline — it will appear after sync."
                        }
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
        .alert("Queued offline", isPresented: Binding(
            get: { offlineCreateMessage != nil },
            set: { if !$0 { offlineCreateMessage = nil } }
        )) {
            Button("OK", role: .cancel) { offlineCreateMessage = nil }
        } message: {
            Text(offlineCreateMessage ?? "")
        }
        .trackPageView("/projects/\(projectId)/meetings", projectId: projectId)
        .onAppear {
            AnalyticsManager.shared.trackScreenView("Meetings", projectId: projectId)
            if !offlineManager.isOffline {
                offlineManager.manualSync()
            }
        }
    }

    private func banner(
        icon: String,
        text: String,
        tint: Color,
        actionTitle: String? = nil,
        actionEnabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .disabled(!actionEnabled)
            }
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
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
        showingCached = false
        defer { isLoading = false }

        if offlineManager.isOffline {
            if let cached = offlineManager.getCachedMeetings(forProject: projectId) {
                meetings = cached
                showingCached = true
            } else {
                errorMessage = "No cached meetings available offline."
            }
            return
        }

        do {
            meetings = try await APIClient.fetchProjectMeetings(projectId: projectId, token: currentToken)
            offlineManager.cacheMeetings(meetings, forProject: projectId)
        } catch {
            if let cached = offlineManager.getCachedMeetings(forProject: projectId) {
                meetings = cached
                showingCached = true
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
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
