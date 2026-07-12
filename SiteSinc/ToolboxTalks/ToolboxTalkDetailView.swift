import SwiftUI

struct ToolboxTalkDetailView: View {
    let projectId: Int
    let talkId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @State private var talk: ProjectToolboxTalk?
    @State private var content: ToolboxTalkContent = .empty
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showSchedule = false
    @State private var ramsIdText = ""
    @State private var dossierURL: URL?
    @State private var isGeneratingDossier = false

    private var canAmend: Bool { ToolboxTalkPermissions.canAmend(user: sessionManager.user) }
    private var canSchedule: Bool { ToolboxTalkPermissions.canSchedule(user: sessionManager.user) }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, talk == nil {
                errorView(errorMessage)
            } else if let talk {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(talk)
                        contentSection
                        ramsSection(talk)
                        revisionsSection(talk)
                        sessionsSection(talk)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(talk?.reference ?? "Toolbox Talk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if canSchedule {
                    Button { showSchedule = true } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showSchedule) {
            NavigationStack {
                ScheduleSessionView(
                    projectId: projectId,
                    talkId: talkId,
                    token: token,
                    onCreated: { _ in
                        showSchedule = false
                        Task { await load() }
                    }
                )
                .environmentObject(sessionManager)
            }
        }
        .refreshable { await load(showSpinner: false) }
        .task { await load() }
        .trackPageView("/projects/\(projectId)/toolbox-talks/\(talkId)", projectId: projectId)
        .alert("Notice", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func header(_ talk: ProjectToolboxTalk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(talk.title)
                    .font(.title2.weight(.bold))
                Spacer()
                ToolboxTalkStatusPill(status: .from(talk))
            }
            if let company = talk.owningCompany?.name {
                Text(company)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text(projectName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content")
                    .font(.title3.weight(.semibold))
                Spacer()
                if canAmend {
                    Button(isSaving ? "Saving..." : "Save amendment") {
                        Task { await saveAmendment() }
                    }
                    .disabled(isSaving)
                    .buttonStyle(.borderedProminent)
                }
            }
            ToolboxTalkContentEditor(
                content: $content,
                readOnly: !canAmend,
                token: token
            )
        }
    }

    private func ramsSection(_ talk: ProjectToolboxTalk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked RAMS")
                .font(.title3.weight(.semibold))
            let links = talk.ramsLinks ?? []
            if links.isEmpty {
                Text("No RAMS linked.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(links, id: \.stableId) { link in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(link.projectRams?.reference ?? "RAMS #\(link.projectRamsId ?? 0)")
                                .font(.subheadline.weight(.semibold))
                            if let title = link.projectRams?.title {
                                Text(title).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if let status = link.projectRams?.status {
                            Text(status).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            if canAmend {
                HStack {
                    TextField("Project RAMS ID", text: $ramsIdText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Link") {
                        Task { await linkRams() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(Int(ramsIdText) == nil)
                }
            }
        }
    }

    private func revisionsSection(_ talk: ProjectToolboxTalk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revision history")
                .font(.title3.weight(.semibold))
            let revisions = talk.revisions ?? []
            if revisions.isEmpty {
                Text("No revisions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(revisions) { revision in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("v\(revision.versionNumber ?? 0) · \(revision.status ?? "")")
                                .font(.subheadline.weight(.semibold))
                            if let email = revision.createdBy?.email {
                                Text(email).font(.caption).foregroundColor(.secondary)
                            }
                            if let createdAt = revision.createdAt {
                                Text(createdAt).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if canAmend, let revContent = revision.content {
                            Button("Restore") {
                                content = revContent
                                statusMessage = "Revision loaded into editor. Save to publish as a new amendment."
                            }
                            .font(.caption)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func sessionsSection(_ talk: ProjectToolboxTalk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sessions")
                    .font(.title3.weight(.semibold))
                Spacer()
                if canSchedule {
                    Button("Schedule") { showSchedule = true }
                        .font(.subheadline)
                }
            }
            let sessions = talk.sessions ?? []
            if sessions.isEmpty {
                Text("No sessions scheduled.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ToolboxTalkSessionStatusChip(status: session.status ?? "SCHEDULED")
                            Spacer()
                            if let scheduled = session.scheduledFor {
                                Text(formatDate(scheduled))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let location = session.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("\(session._count?.attendees ?? 0) attendees · \(session._count?.signatures ?? 0) signatures")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            NavigationLink {
                                ToolboxTalkDeliverView(
                                    projectId: projectId,
                                    talkId: talkId,
                                    sessionId: session.id,
                                    token: token
                                )
                                .environmentObject(sessionManager)
                            } label: {
                                Label("Deliver / sign", systemImage: "play.circle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await generateDossier(sessionId: session.id) }
                            } label: {
                                if isGeneratingDossier {
                                    ProgressView()
                                } else {
                                    Label("Dossier", systemImage: "doc.richtext")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
        }
        .sheet(item: Binding(
            get: { dossierURL.map { IdentifiableURL(url: $0) } },
            set: { dossierURL = $0?.url }
        )) { item in
            ToolboxTalkDossierPreview(url: item.url)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message).foregroundColor(.secondary)
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
            let fetched = try await APIClient.fetchProjectToolboxTalk(
                projectId: projectId,
                id: talkId,
                token: token
            )
            talk = fetched
            content = fetched.currentRevision?.content ?? .empty
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func saveAmendment() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.createToolboxTalkRevision(
                projectId: projectId,
                talkId: talkId,
                content: content,
                token: token
            )
            statusMessage = "Amendment saved."
            await load(showSpinner: false)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func linkRams() async {
        guard let ramsId = Int(ramsIdText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        do {
            _ = try await APIClient.linkToolboxTalkRams(
                projectId: projectId,
                talkId: talkId,
                projectRamsId: ramsId,
                token: token
            )
            ramsIdText = ""
            statusMessage = "RAMS linked."
            await load(showSpinner: false)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func generateDossier(sessionId: Int) async {
        isGeneratingDossier = true
        defer { isGeneratingDossier = false }
        do {
            let result = try await APIClient.generateToolboxTalkDossier(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                token: token
            )
            if let urlString = result.presignedUrl, let url = URL(string: urlString) {
                dossierURL = url
            } else {
                statusMessage = "Dossier generated but no download URL was returned."
            }
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func formatDate(_ iso: String) -> String {
        let parsers = [iso8601Frac, iso8601]
        for parser in parsers {
            if let date = parser.date(from: iso) {
                return Self.displayFormatter.string(from: date)
            }
        }
        return iso
    }

    private var iso8601Frac: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private var iso8601: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct ToolboxTalkDossierPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Dossier ready")
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Link("Open dossier PDF", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
