import SwiftUI

struct CreateToolboxTalkWizardView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onFinished: (ProjectToolboxTalk, ToolboxTalkSession?) -> Void

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    enum Step: Int {
        case source = 1
        case amend = 2
        case issue = 3
    }

    enum SourceMode {
        case template
        case ai
        case blank
        case reuse
    }

    enum IssueMode: String, CaseIterable, Identifiable {
        case deliverNow = "Deliver now"
        case schedule = "Schedule & notify"
        case saveLater = "Save for later"
        var id: String { rawValue }
    }

    @State private var step: Step = .source
    @State private var sourceMode: SourceMode?
    @State private var templates: [ToolboxTalkTemplate] = []
    @State private var existingTalks: [ProjectToolboxTalk] = []
    @State private var selectedTemplate: ToolboxTalkTemplate?
    @State private var reuseTalk: ProjectToolboxTalk?
    @State private var title = ""
    @State private var reference = ""
    @State private var content: ToolboxTalkContent = .empty
    @State private var aiContext = ""
    @State private var isGeneratingAI = false
    @State private var issueMode: IssueMode = .deliverNow
    @State private var scheduledDate = Date()
    @State private var location = ""
    @State private var projectUsers: [User] = []
    @State private var selectedAttendeeIds: Set<Int> = []
    @State private var notifyAttendees = true
    @State private var presenterUserId: Int?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var projectReference = ""
    @State private var isLoadingSource = false

    private var canGenerateAI: Bool { ToolboxTalkPermissions.canGenerateAI(user: sessionManager.user) }

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case .source: sourceStep
                    case .amend: amendStep
                    case .issue: issueStep
                    }
                }
                .padding()
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            footerBar
        }
        .navigationTitle("New toolbox talk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            await loadProjectMeta()
        }
    }

    private var stepHeader: some View {
        HStack(spacing: 8) {
            stepChip(1, title: "Source", active: step == .source)
            stepChip(2, title: "Amend", active: step == .amend)
            stepChip(3, title: "Issue", active: step == .issue)
        }
        .padding()
    }

    private func stepChip(_ number: Int, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(active ? Color.accentColor : Color.gray.opacity(0.3))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Circle())
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .foregroundColor(active ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How do you want to create this talk?")
                .font(.headline)

            sourceCard(
                title: "From template",
                subtitle: "Start from a published company template",
                icon: "doc.on.doc"
            ) {
                sourceMode = .template
                Task { await loadTemplates(); step = .amend }
            }

            if canGenerateAI {
                sourceCard(
                    title: "Generate with AI",
                    subtitle: "Draft topics from a title and context",
                    icon: "sparkles"
                ) {
                    sourceMode = .ai
                    content = .empty
                    step = .amend
                }
            }

            sourceCard(
                title: "Blank",
                subtitle: "Start with empty content",
                icon: "doc.badge.plus"
            ) {
                sourceMode = .blank
                content = .empty
                selectedTemplate = nil
                step = .amend
            }

            sourceCard(
                title: "Reuse existing",
                subtitle: "Schedule another session for an existing talk",
                icon: "arrow.triangle.2.circlepath"
            ) {
                sourceMode = .reuse
                Task { await loadExistingTalks(); step = .issue }
            }

            if isLoadingSource {
                ProgressView("Loading...")
            }
        }
    }

    private func sourceCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var amendStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sourceMode == .template {
                Text("Choose template")
                    .font(.headline)
                if templates.isEmpty {
                    Text("No published templates found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(templates) { template in
                        Button {
                            selectedTemplate = template
                            title = template.title
                            if let contentFromTemplate = template.currentRevision?.content {
                                content = contentFromTemplate
                            }
                            suggestReference()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(template.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                    if let ref = template.reference {
                                        Text(ref).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedTemplate?.id == template.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if sourceMode == .ai {
                Text("AI draft")
                    .font(.headline)
                TextField("Talk title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Extra context (optional)", text: $aiContext, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await generateAI() }
                } label: {
                    if isGeneratingAI {
                        ProgressView()
                    } else {
                        Label("Generate content", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingAI)
            }

            Text("Details")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Reference", text: $reference)
                .textFieldStyle(.roundedBorder)
                .onAppear { if reference.isEmpty { suggestReference() } }

            ToolboxTalkContentEditor(content: $content, token: token)
        }
    }

    private var issueStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sourceMode == .reuse {
                Text("Reuse existing talk")
                    .font(.headline)
                ForEach(existingTalks) { talk in
                    Button {
                        reuseTalk = talk
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(talk.reference).font(.caption).foregroundColor(.secondary)
                                Text(talk.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                            }
                            Spacer()
                            if reuseTalk?.id == talk.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Issue mode")
                .font(.headline)
            Picker("Issue mode", selection: $issueMode) {
                ForEach(availableIssueModes) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if issueMode != .saveLater {
                DatePicker("Scheduled for", selection: $scheduledDate)
                TextField("Location (optional)", text: $location)
                    .textFieldStyle(.roundedBorder)

                if !projectUsers.isEmpty {
                    Text("Presenter (optional)")
                        .font(.subheadline.weight(.semibold))
                    Picker("Presenter", selection: Binding(
                        get: { presenterUserId ?? -1 },
                        set: { presenterUserId = $0 == -1 ? nil : $0 }
                    )) {
                        Text("None").tag(-1)
                        ForEach(projectUsers, id: \.id) { user in
                            Text(displayName(user)).tag(user.id)
                        }
                    }

                    if issueMode == .schedule {
                        Toggle("Notify selected attendees", isOn: $notifyAttendees)
                        Text("Attendees")
                            .font(.subheadline.weight(.semibold))
                        ForEach(projectUsers, id: \.id) { user in
                            Toggle(isOn: Binding(
                                get: { selectedAttendeeIds.contains(user.id) },
                                set: { on in
                                    if on { selectedAttendeeIds.insert(user.id) }
                                    else { selectedAttendeeIds.remove(user.id) }
                                }
                            )) {
                                Text(displayName(user))
                            }
                        }
                    }
                }
            }
        }
        .task {
            if projectUsers.isEmpty {
                projectUsers = (try? await APIClient.fetchProjectUsers(projectId: projectId, token: token)) ?? []
            }
        }
    }

    private var availableIssueModes: [IssueMode] {
        if sourceMode == .reuse {
            return [.deliverNow, .schedule]
        }
        return IssueMode.allCases
    }

    private var footerBar: some View {
        HStack {
            if step != .source {
                Button("Back") {
                    switch step {
                    case .amend: step = .source
                    case .issue:
                        step = sourceMode == .reuse ? .source : .amend
                    case .source: break
                    }
                }
            }
            Spacer()
            if step == .amend {
                Button("Continue") {
                    guard canProceedFromAmend else { return }
                    step = .issue
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedFromAmend)
            } else if step == .issue {
                Button(isSubmitting ? "Working..." : "Finish") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || !canFinish)
            }
        }
        .padding()
    }

    private var canProceedFromAmend: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if sourceMode == .template {
            return hasTitle && selectedTemplate != nil
        }
        return hasTitle
    }

    private var canFinish: Bool {
        if sourceMode == .reuse {
            return reuseTalk != nil && issueMode != .saveLater
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sessionManager.user?.companyId != nil
    }

    private func loadProjectMeta() async {
        do {
            let projects = try await APIClient.fetchProjects(token: token)
            if let project = projects.first(where: { $0.id == projectId }) {
                projectReference = project.reference
                suggestReference()
            }
        } catch {
            // Non-fatal — reference can be typed manually
        }
    }

    private func loadTemplates() async {
        isLoadingSource = true
        defer { isLoadingSource = false }
        do {
            templates = try await APIClient.fetchToolboxTalkTemplates(token: token)
                .filter { $0.isArchived != true && $0.currentRevision != nil }
            suggestReference()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func loadExistingTalks() async {
        isLoadingSource = true
        defer { isLoadingSource = false }
        do {
            existingTalks = try await APIClient.fetchProjectToolboxTalks(projectId: projectId, token: token)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func suggestReference() {
        guard reference.isEmpty else { return }
        let prefix = projectReference.isEmpty ? "TBT" : "\(projectReference)-TBT"
        let next = (existingTalks.count > 0 ? existingTalks.count : templates.count) + 1
        // Prefer counting existing project talks when available
        Task {
            if existingTalks.isEmpty {
                existingTalks = (try? await APIClient.fetchProjectToolboxTalks(projectId: projectId, token: token)) ?? []
            }
            let n = existingTalks.count + 1
            if reference.isEmpty {
                reference = String(format: "%@-%03d", prefix, max(n, next))
            }
        }
    }

    private func generateAI() async {
        isGeneratingAI = true
        defer { isGeneratingAI = false }
        do {
            content = try await APIClient.generateAIToolboxTalkContent(
                title: title,
                description: aiContext.isEmpty ? nil : aiContext,
                reference: reference.isEmpty ? nil : reference,
                extraContext: aiContext.isEmpty ? nil : aiContext,
                token: token
            )
            suggestReference()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if sourceMode == .reuse {
                guard let reuseTalk else { return }
                let session = try await createSession(for: reuseTalk.id)
                onFinished(reuseTalk, session)
                return
            }

            guard let owningCompanyId = sessionManager.user?.companyId else {
                errorMessage = "Your user account has no company — cannot create a toolbox talk."
                return
            }

            let talk: ProjectToolboxTalk
            if sourceMode == .template, let selectedTemplate {
                talk = try await APIClient.createProjectToolboxTalkFromTemplate(
                    projectId: projectId,
                    templateId: selectedTemplate.id,
                    reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    owningCompanyId: owningCompanyId,
                    contentOverrides: content,
                    token: token
                )
            } else {
                talk = try await APIClient.createProjectToolboxTalk(
                    projectId: projectId,
                    reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    owningCompanyId: owningCompanyId,
                    content: content,
                    source: sourceMode == .ai ? "ai" : "ad_hoc",
                    token: token
                )
            }

            var session: ToolboxTalkSession?
            if issueMode != .saveLater {
                session = try await createSession(for: talk.id)
            }
            onFinished(talk, session)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func createSession(for talkId: Int) async throws -> ToolboxTalkSession {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let scheduledFor: String? = {
            switch issueMode {
            case .deliverNow: return iso.string(from: Date())
            case .schedule: return iso.string(from: scheduledDate)
            case .saveLater: return nil
            }
        }()
        let attendees: [Int]? = (issueMode == .schedule && notifyAttendees)
            ? Array(selectedAttendeeIds)
            : nil
        return try await APIClient.scheduleToolboxTalkSession(
            projectId: projectId,
            talkId: talkId,
            scheduledFor: scheduledFor,
            location: location.isEmpty ? nil : location,
            presenterUserId: presenterUserId,
            attendeeUserIds: attendees,
            token: token
        )
    }

    private func displayName(_ user: User) -> String {
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        return user.email ?? "User #\(user.id)"
    }
}
