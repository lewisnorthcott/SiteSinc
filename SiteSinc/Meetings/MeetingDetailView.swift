import SwiftUI
import UniformTypeIdentifiers

private enum MeetingSaveStatus: Equatable {
    case idle
    case pending
    case saving
    case saved
    case savedOffline
    case error(String)
}

struct MeetingDetailView: View {
    let projectId: Int
    let meetingId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var offlineManager = OfflineMeetingManager.shared

    @State private var meeting: MeetingDetail?
    @State private var projectUsers: [User] = []
    @State private var categories: [MeetingCategory] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?

    // Editable details
    @State private var title = ""
    @State private var meetingDate = Date()
    @State private var includeNextMeeting = false
    @State private var nextMeetingDate = Date()
    @State private var location = ""
    @State private var isPrivate = false
    @State private var categoryId: Int?
    @State private var presentIds: [Int] = []
    @State private var apologyIds: [Int] = []
    @State private var distributionIds: [Int] = []

    @State private var agendaDrafts: [AgendaDraftItem] = []
    @State private var minuteDrafts: [MinuteDraftLine] = []

    @State private var isHydrating = false
    @State private var hasLoaded = false
    @State private var saveStatus: MeetingSaveStatus = .idle
    @State private var detailsSaveTask: Task<Void, Never>?
    @State private var agendaSaveTask: Task<Void, Never>?
    @State private var minutesSaveTask: Task<Void, Never>?
    @State private var lastSavedDetailsSignature = ""
    @State private var lastSavedAgendaSignature = ""
    @State private var lastSavedMinutesSignature = ""
    @State private var showSavedIndicator = false

    @State private var isFinalizing = false
    @State private var pdfURL: URL?
    @State private var showSharePDF = false
    @State private var closeOutLine: MeetingMinuteLine?
    @State private var showFinalizeConfirm = false
    @State private var showDeleteConfirm = false
    @State private var agendaFileImporter = false

    private let autoSaveNanos: UInt64 = 700_000_000

    private var currentToken: String { sessionManager.token ?? token }
    private var canEdit: Bool {
        MeetingPermissions.canEdit(user: sessionManager.user) && (meeting?.isEditable ?? false)
    }
    private var canDelete: Bool {
        MeetingPermissions.canDelete(user: sessionManager.user) && (meeting?.isEditable ?? false)
    }

    var body: some View {
        rootContent
            .navigationTitle(meeting?.reference ?? "Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await load() }
            .refreshable { await load(showSpinner: false) }
            .onDisappear { flushPendingSaves() }
            .modifier(MeetingAutosaveChangeModifier(
                onDetailsChange: scheduleDetailsAutoSave,
                onAgendaChange: scheduleAgendaAutoSave,
                onMinutesChange: scheduleMinutesAutoSave,
                title: title,
                meetingDate: meetingDate,
                includeNextMeeting: includeNextMeeting,
                nextMeetingDate: nextMeetingDate,
                location: location,
                isPrivate: isPrivate,
                categoryId: categoryId,
                presentIds: presentIds,
                apologyIds: apologyIds,
                distributionIds: distributionIds,
                agendaDrafts: agendaDrafts,
                minuteDrafts: minuteDrafts
            ))
            .alert("Finalize meeting?", isPresented: $showFinalizeConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Finalize") { Task { await finalize() } }
            } message: {
                Text("Finalizing locks the meeting. Agenda and minutes will become read-only.")
            }
            .alert("Delete draft meeting?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await deleteMeeting() } }
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(item: $closeOutLine) { line in
                closeOutSheet(line)
            }
            .sheet(isPresented: $showSharePDF) {
                if let pdfURL {
                    MeetingShareSheet(items: [pdfURL])
                }
            }
            .fileImporter(
                isPresented: $agendaFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleAgendaFileImport(result) }
            }
            .trackPageView("/projects/\(projectId)/meetings/\(meetingId)", projectId: projectId)
    }

    @ViewBuilder
    private var rootContent: some View {
        if isLoading && meeting == nil {
            ProgressView("Loading meeting...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, meeting == nil {
            errorState(errorMessage)
        } else if let meeting {
            content(meeting)
        }
    }

    private func closeOutSheet(_ line: MeetingMinuteLine) -> some View {
        NavigationStack {
            MinuteLineCloseOutView(
                projectId: projectId,
                meetingId: meetingId,
                line: line,
                token: currentToken,
                canCloseOut: MeetingPermissions.canCloseOut(
                    user: sessionManager.user,
                    line: line,
                    meetingCreatedById: meeting?.createdById
                ),
                canReopen: MeetingPermissions.canReopen(
                    user: sessionManager.user,
                    meetingCreatedById: meeting?.createdById
                ),
                onFinished: {
                    closeOutLine = nil
                    Task { await load(showSpinner: false) }
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            saveStatusView
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    Task { await downloadPDF() }
                } label: {
                    Label("Download PDF", systemImage: "arrow.down.doc")
                }
                if canEdit {
                    Button {
                        showFinalizeConfirm = true
                    } label: {
                        Label("Finalize", systemImage: "checkmark.seal")
                    }
                    .disabled(offlineManager.isOffline)
                }
                if canDelete {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(offlineManager.isOffline)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var saveStatusView: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .pending, .saving:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Saving…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .saved:
            if showSavedIndicator {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        case .savedOffline:
            HStack(spacing: 4) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.caption)
                Text("Saved offline")
                    .font(.caption)
            }
            .foregroundColor(.orange)
        case .error(let message):
            Text(message)
                .font(.caption2)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    private func content(_ meeting: MeetingDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if offlineManager.isOffline {
                    offlineBanner(text: "You're offline — changes autosave locally and sync when you're back online.")
                } else if offlineManager.pendingCount(forProject: projectId) > 0 {
                    offlineBanner(
                        text: "\(offlineManager.pendingCount(forProject: projectId)) meeting change(s) waiting to sync.",
                        tint: .green,
                        actionTitle: offlineManager.syncInProgress ? nil : "Sync now"
                    ) {
                        offlineManager.manualSync()
                    }
                }

                header(meeting)

                if let actionError {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                detailsCard
                attendeesCard

                if !meeting.previousActionLines.isEmpty {
                    previousActionsCard(meeting.previousActionLines)
                }

                agendaCard(meeting)
                minutesCard(meeting)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func offlineBanner(
        text: String,
        tint: Color = .orange,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tint == .orange ? "wifi.slash" : "arrow.triangle.2.circlepath")
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundColor(tint == .orange ? .orange : .green)
        .padding(12)
        .background((tint == .orange ? Color.orange : Color.green).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private func header(_ meeting: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MeetingStatusPill(status: meeting.status)
                if meeting.isPrivate == true {
                    Label("Private", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isFinalizing {
                    ProgressView()
                }
            }
            Text(title.isEmpty ? meeting.title : title)
                .font(.title2.weight(.bold))
            Text(MeetingDateFormatting.displayDateTime(MeetingDateFormatting.isoString(from: meetingDate)))
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if canEdit {
                Text("Autosaves as you type")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var detailsCard: some View {
        MeetingSectionCard(title: "Meeting details") {
            if canEdit {
                TextField("Title", text: $title)
                DatePicker("Date & time", selection: $meetingDate)
                Toggle("Next meeting", isOn: $includeNextMeeting)
                if includeNextMeeting {
                    DatePicker("Next meeting", selection: $nextMeetingDate)
                }
                TextField("Location", text: $location)
                Toggle("Private", isOn: $isPrivate)
                Picker("Category", selection: $categoryId) {
                    Text("None").tag(Optional<Int>.none)
                    ForEach(categories.filter { $0.active != false }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            } else {
                detailRow("Title", title)
                detailRow("Date", MeetingDateFormatting.displayDateTime(MeetingDateFormatting.isoString(from: meetingDate)))
                if includeNextMeeting {
                    detailRow("Next meeting", MeetingDateFormatting.displayDateTime(MeetingDateFormatting.isoString(from: nextMeetingDate)))
                }
                if !location.isEmpty {
                    detailRow("Location", location)
                }
                if let category = categories.first(where: { $0.id == categoryId })?.name
                    ?? meeting?.category?.name {
                    detailRow("Category", category)
                }
                detailRow("Private", isPrivate ? "Yes" : "No")
            }
        }
    }

    private var attendeesCard: some View {
        MeetingSectionCard(title: "Attendees") {
            attendeeGroup(title: "Present", ids: $presentIds)
            attendeeGroup(title: "Apologies", ids: $apologyIds)
            attendeeGroup(title: "Distribution", ids: $distributionIds)
        }
    }

    private func previousActionsCard(_ lines: [MeetingMinuteLine]) -> some View {
        MeetingSectionCard(title: "Review of previous minutes") {
            if let source = meeting?.reviewSourceMeeting {
                Text("From \(source.reference ?? "") — \(source.title ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(lines) { line in
                previousActionRow(line)
            }
        }
    }

    private func agendaCard(_ meeting: MeetingDetail) -> some View {
        MeetingSectionCard(title: "Agenda") {
            if canEdit {
                ForEach($agendaDrafts) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Topic", text: $item.title)
                        TextField("Talking points", text: $item.notes, axis: .vertical)
                            .lineLimit(2...4)
                        HStack {
                            TextField("Mins", value: $item.durationMinutes, format: .number)
                                .keyboardType(.numberPad)
                                .frame(width: 64)
                            Picker("Presenter", selection: $item.presenterUserId) {
                                Text("None").tag(Optional<Int>.none)
                                ForEach(projectUsers, id: \.id) { user in
                                    Text(user.displayName).tag(Optional(user.id))
                                }
                            }
                            Button(role: .destructive) {
                                agendaDrafts.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button {
                    agendaDrafts.append(AgendaDraftItem())
                } label: {
                    Label("Add agenda item", systemImage: "plus")
                }

                Divider()
                Button {
                    agendaFileImporter = true
                } label: {
                    Label("Upload agenda file", systemImage: "paperclip")
                }
            } else if agendaDrafts.isEmpty && (meeting.agendaAttachments ?? []).isEmpty {
                Text("No agenda items")
                    .foregroundColor(.secondary)
            } else {
                ForEach(agendaDrafts) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                            if let mins = item.durationMinutes {
                                Text("\(mins) min").font(.caption2).foregroundColor(.secondary)
                            }
                            if let presenterId = item.presenterUserId,
                               let user = projectUsers.first(where: { $0.id == presenterId }) {
                                Text(user.displayName).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ForEach(meeting.agendaAttachments ?? []) { attachment in
                HStack {
                    Image(systemName: "doc")
                    Text(attachment.fileName)
                        .font(.subheadline)
                    Spacer()
                    Button("Open") {
                        Task { await openAgendaAttachment(attachment) }
                    }
                    .font(.caption)
                    .disabled(offlineManager.isOffline)
                    if canEdit {
                        Button(role: .destructive) {
                            Task { await deleteAgendaAttachment(attachment) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(offlineManager.isOffline)
                    }
                }
            }
        }
    }

    private func minutesCard(_ meeting: MeetingDetail) -> some View {
        MeetingSectionCard(title: "Minutes") {
            if canEdit {
                ForEach($minuteDrafts) { $draft in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Minute / note", text: $draft.content, axis: .vertical)
                            .lineLimit(2...6)
                        HStack {
                            DatePicker(
                                "Due",
                                selection: Binding(
                                    get: { draft.dueDate ?? Date() },
                                    set: { draft.dueDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            Toggle("Due date", isOn: Binding(
                                get: { draft.dueDate != nil },
                                set: { draft.dueDate = $0 ? (draft.dueDate ?? Date()) : nil }
                            ))
                            .labelsHidden()
                        }
                        Picker("Agenda topic", selection: $draft.agendaItemId) {
                            Text("None").tag(Optional<Int>.none)
                            ForEach(meeting.agendaItems ?? []) { item in
                                Text(item.title).tag(Optional(item.id))
                            }
                        }
                        assigneePicker(for: $draft)
                        HStack {
                            if !draft.assigneeUserIds.isEmpty {
                                Text("Action")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if let serverId = draft.serverId,
                               let line = meeting.minuteSectionLines.first(where: { $0.id == serverId }),
                               line.isAction {
                                Button("Close out") { closeOutLine = line }
                                    .font(.caption)
                            }
                            Button(role: .destructive) {
                                minuteDrafts.removeAll { $0.id == draft.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button {
                    minuteDrafts.append(MinuteDraftLine())
                } label: {
                    Label("Add minute line", systemImage: "plus")
                }
            } else {
                let lines = meeting.minuteSectionLines
                if lines.isEmpty {
                    Text("No minutes yet").foregroundColor(.secondary)
                } else {
                    ForEach(lines) { line in
                        minuteReadRow(line)
                    }
                }
            }
        }
    }

    private func previousActionRow(_ line: MeetingMinuteLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.content)
                .font(.subheadline)
            HStack {
                statusChip(for: line)
                if let due = line.dueDate {
                    Text("Due \(MeetingDateFormatting.displayDay(due))")
                        .font(.caption2)
                        .foregroundColor(dueColor(for: line))
                }
                Spacer()
                if line.isAction {
                    Button("Close out") { closeOutLine = line }
                        .font(.caption)
                }
            }
            if let assignees = line.assignees, !assignees.isEmpty {
                Text(assignees.compactMap { $0.user?.displayName }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func minuteReadRow(_ line: MeetingMinuteLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.content).font(.subheadline)
            HStack {
                if line.isAction {
                    Text("Action")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                    statusChip(for: line)
                }
                if let due = line.dueDate {
                    Text("Due \(MeetingDateFormatting.displayDay(due))")
                        .font(.caption2)
                        .foregroundColor(dueColor(for: line))
                }
                Spacer()
                if line.isAction {
                    Button("Close out") { closeOutLine = line }
                        .font(.caption)
                }
            }
            if let assignees = line.assignees, !assignees.isEmpty {
                Text(assignees.compactMap { $0.user?.displayName }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func attendeeGroup(title: String, ids: Binding<[Int]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if ids.wrappedValue.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                FlowUserChips(userIds: ids.wrappedValue, users: projectUsers) { userId in
                    if canEdit {
                        ids.wrappedValue.removeAll { $0 == userId }
                    }
                }
            }
            if canEdit {
                Menu {
                    ForEach(availableUsers(excluding: Set(presentIds + apologyIds + distributionIds)), id: \.id) { user in
                        Button(user.displayName) {
                            ids.wrappedValue.append(user.id)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func assigneePicker(for draft: Binding<MinuteDraftLine>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assignees").font(.caption.weight(.semibold))
            FlowUserChips(userIds: draft.wrappedValue.assigneeUserIds, users: projectUsers) { userId in
                draft.wrappedValue.assigneeUserIds.removeAll { $0 == userId }
            }
            Menu {
                ForEach(projectUsers.filter { !draft.wrappedValue.assigneeUserIds.contains($0.id) }, id: \.id) { user in
                    Button(user.displayName) {
                        draft.wrappedValue.assigneeUserIds.append(user.id)
                    }
                }
            } label: {
                Label("Add assignee", systemImage: "person.badge.plus")
                    .font(.caption)
            }
        }
    }

    private func statusChip(for line: MeetingMinuteLine) -> some View {
        let done = (line.status ?? .open) == .done
        return Text(done ? "Done" : "Open")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(done ? .white : .primary)
            .background(done ? Color.green : Color(.systemGray5))
            .clipShape(Capsule())
    }

    private func dueColor(for line: MeetingMinuteLine) -> Color {
        guard let due = line.dueDate, let date = MeetingDateFormatting.parseISO(due) else {
            return .secondary
        }
        if (line.status ?? .open) == .done { return .green }
        if Calendar.current.isDateInToday(date) { return .orange }
        if date < Date() { return .red }
        return .secondary
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func availableUsers(excluding: Set<Int>) -> [User] {
        projectUsers.filter { !excluding.contains($0.id) }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Autosave scheduling

    private func scheduleDetailsAutoSave() {
        guard hasLoaded, !isHydrating, canEdit else { return }
        guard detailsSignature() != lastSavedDetailsSignature else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveStatus = .pending
        detailsSaveTask?.cancel()
        detailsSaveTask = Task {
            try? await Task.sleep(nanoseconds: autoSaveNanos)
            guard !Task.isCancelled else { return }
            await saveDetails(triggeredByAutosave: true)
        }
    }

    private func scheduleAgendaAutoSave() {
        guard hasLoaded, !isHydrating, canEdit else { return }
        guard agendaSignature() != lastSavedAgendaSignature else { return }
        saveStatus = .pending
        agendaSaveTask?.cancel()
        agendaSaveTask = Task {
            try? await Task.sleep(nanoseconds: autoSaveNanos)
            guard !Task.isCancelled else { return }
            await saveAgenda(triggeredByAutosave: true)
        }
    }

    private func scheduleMinutesAutoSave() {
        guard hasLoaded, !isHydrating, canEdit else { return }
        guard minutesSignature() != lastSavedMinutesSignature else { return }
        saveStatus = .pending
        minutesSaveTask?.cancel()
        minutesSaveTask = Task {
            try? await Task.sleep(nanoseconds: autoSaveNanos)
            guard !Task.isCancelled else { return }
            await saveMinutes(triggeredByAutosave: true)
        }
    }

    private func flushPendingSaves() {
        detailsSaveTask?.cancel()
        agendaSaveTask?.cancel()
        minutesSaveTask?.cancel()
        guard canEdit, hasLoaded else { return }
        Task {
            if detailsSignature() != lastSavedDetailsSignature,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await saveDetails(triggeredByAutosave: true)
            }
            if agendaSignature() != lastSavedAgendaSignature {
                await saveAgenda(triggeredByAutosave: true)
            }
            if minutesSignature() != lastSavedMinutesSignature {
                await saveMinutes(triggeredByAutosave: true)
            }
        }
    }

    private func markSaved(_ status: MeetingSaveStatus = .saved) {
        saveStatus = status
        showSavedIndicator = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .saved = saveStatus {
                showSavedIndicator = false
                saveStatus = .idle
            } else if case .savedOffline = saveStatus {
                // Keep offline indicator visible briefly longer
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if case .savedOffline = saveStatus {
                    showSavedIndicator = false
                    saveStatus = .idle
                }
            }
        }
    }

    // MARK: - Signatures

    private func detailsSignature() -> String {
        let attendees = (
            presentIds.sorted().map { "P\($0)" }
                + apologyIds.sorted().map { "A\($0)" }
                + distributionIds.sorted().map { "D\($0)" }
        ).joined(separator: ",")
        return [
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            MeetingDateFormatting.isoString(from: meetingDate),
            includeNextMeeting ? MeetingDateFormatting.isoString(from: nextMeetingDate) : "",
            location.trimmingCharacters(in: .whitespacesAndNewlines),
            isPrivate ? "1" : "0",
            categoryId.map(String.init) ?? "",
            attendees
        ].joined(separator: "|")
    }

    private func agendaSignature() -> String {
        let payload = agendaPayload()
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return "\(agendaDrafts.count)"
        }
        return string
    }

    private func minutesSignature() -> String {
        let payload = minutesPayload()
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return "\(minuteDrafts.count)"
        }
        return string
    }

    private func agendaPayload() -> [AgendaItemInput] {
        agendaDrafts.enumerated().compactMap { index, draft in
            let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return draft.toInput(sortOrder: index)
        }
    }

    private func minutesPayload() -> [MinuteLineInput] {
        minuteDrafts.enumerated().compactMap { index, draft in
            let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return draft.toInput(sortOrder: index)
        }
    }

    private func detailsBody() -> UpdateMeetingRequest {
        let attendees: [MeetingAttendeeInput] =
            presentIds.map { MeetingAttendeeInput(userId: $0, role: .present) }
            + apologyIds.map { MeetingAttendeeInput(userId: $0, role: .apologies) }
            + distributionIds.map { MeetingAttendeeInput(userId: $0, role: .distribution) }
        return UpdateMeetingRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingDate: MeetingDateFormatting.isoString(from: meetingDate),
            nextMeetingDate: includeNextMeeting ? MeetingDateFormatting.isoString(from: nextMeetingDate) : nil,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
            notes: nil,
            isPrivate: isPrivate,
            categoryId: categoryId,
            attendees: attendees
        )
    }

    // MARK: - Data

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        if offlineManager.isOffline, let cached = offlineManager.getCachedMeetingDetail(id: meetingId) {
            applyLoadedMeeting(cached, users: projectUsers, categories: categories)
            return
        }

        do {
            async let meetingTask = APIClient.fetchMeeting(id: meetingId, token: currentToken)
            async let usersTask = APIClient.fetchProjectUsers(projectId: projectId, token: currentToken)
            async let categoriesTask = APIClient.fetchMeetingCategories(token: currentToken)
            let (fetched, users, cats) = try await (meetingTask, usersTask, categoriesTask)
            offlineManager.cacheMeetingDetail(fetched)
            applyLoadedMeeting(
                fetched,
                users: users.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
                categories: cats
            )
        } catch {
            if let cached = offlineManager.getCachedMeetingDetail(id: meetingId) {
                applyLoadedMeeting(cached, users: projectUsers, categories: categories)
                actionError = "Showing cached meeting — \( (error as? APIError)?.displayMessage ?? error.localizedDescription )"
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func applyLoadedMeeting(_ fetched: MeetingDetail, users: [User], categories cats: [MeetingCategory]) {
        meeting = fetched
        if !users.isEmpty { projectUsers = users }
        if !cats.isEmpty { categories = cats }
        hydrate(from: fetched)
        hasLoaded = true
    }

    private func hydrate(from meeting: MeetingDetail) {
        isHydrating = true
        defer {
            lastSavedDetailsSignature = detailsSignature()
            lastSavedAgendaSignature = agendaSignature()
            lastSavedMinutesSignature = minutesSignature()
            isHydrating = false
        }
        title = meeting.title
        meetingDate = MeetingDateFormatting.parseISO(meeting.meetingDate) ?? Date()
        if let next = meeting.nextMeetingDate, let date = MeetingDateFormatting.parseISO(next) {
            includeNextMeeting = true
            nextMeetingDate = date
        } else {
            includeNextMeeting = false
        }
        location = meeting.location ?? ""
        isPrivate = meeting.isPrivate ?? false
        categoryId = meeting.categoryId ?? meeting.category?.id
        let attendees = meeting.attendees ?? []
        presentIds = attendees
            .filter { $0.role == nil || $0.role == .present || $0.role == .chair }
            .map(\.userId)
        apologyIds = attendees.filter { $0.role == .apologies }.map(\.userId)
        distributionIds = attendees.filter { $0.role == .distribution }.map(\.userId)
        agendaDrafts = (meeting.agendaItems ?? []).map(AgendaDraftItem.from)
        minuteDrafts = meeting.minuteSectionLines.map(MinuteDraftLine.from)
    }

    private func saveDetails(triggeredByAutosave: Bool) async {
        let signature = detailsSignature()
        guard signature != lastSavedDetailsSignature else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        saveStatus = .saving
        actionError = nil
        let body = detailsBody()

        if offlineManager.isOffline {
            offlineManager.queueUpdateDetails(
                projectId: projectId,
                meetingId: meetingId,
                body: body,
                token: currentToken
            )
            lastSavedDetailsSignature = signature
            persistLocalDetailSnapshot()
            markSaved(.savedOffline)
            return
        }

        do {
            let updated = try await APIClient.updateMeeting(id: meetingId, body: body, token: currentToken)
            offlineManager.cacheMeetingDetail(updated)
            if detailsSignature() == signature {
                meeting = updated
                lastSavedDetailsSignature = signature
            }
            markSaved(.saved)
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueUpdateDetails(
                    projectId: projectId,
                    meetingId: meetingId,
                    body: body,
                    token: currentToken
                )
                lastSavedDetailsSignature = signature
                persistLocalDetailSnapshot()
                markSaved(.savedOffline)
            } else {
                let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
                saveStatus = .error(message)
                if !triggeredByAutosave { actionError = message }
            }
        }
    }

    private func saveAgenda(triggeredByAutosave: Bool) async {
        let signature = agendaSignature()
        guard signature != lastSavedAgendaSignature else { return }
        saveStatus = .saving
        actionError = nil
        let payload = agendaPayload()

        if offlineManager.isOffline {
            offlineManager.queueReplaceAgenda(
                projectId: projectId,
                meetingId: meetingId,
                items: payload,
                token: currentToken
            )
            lastSavedAgendaSignature = signature
            persistLocalDetailSnapshot()
            markSaved(.savedOffline)
            return
        }

        do {
            let updated = try await APIClient.replaceMeetingAgendaItems(
                meetingId: meetingId,
                items: payload,
                token: currentToken
            )
            offlineManager.cacheMeetingDetail(updated)
            if agendaSignature() == signature {
                meeting = updated
                mergeAgendaServerIds(from: updated)
                lastSavedAgendaSignature = agendaSignature()
            } else {
                mergeAgendaServerIds(from: updated)
            }
            markSaved(.saved)
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueReplaceAgenda(
                    projectId: projectId,
                    meetingId: meetingId,
                    items: payload,
                    token: currentToken
                )
                lastSavedAgendaSignature = signature
                persistLocalDetailSnapshot()
                markSaved(.savedOffline)
            } else {
                let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
                saveStatus = .error(message)
                if !triggeredByAutosave { actionError = message }
            }
        }
    }

    private func saveMinutes(triggeredByAutosave: Bool) async {
        let signature = minutesSignature()
        guard signature != lastSavedMinutesSignature else { return }
        saveStatus = .saving
        actionError = nil
        let payload = minutesPayload()

        if offlineManager.isOffline {
            offlineManager.queueReplaceMinutes(
                projectId: projectId,
                meetingId: meetingId,
                lines: payload,
                token: currentToken
            )
            lastSavedMinutesSignature = signature
            persistLocalDetailSnapshot()
            markSaved(.savedOffline)
            return
        }

        do {
            let updated = try await APIClient.replaceMeetingMinuteLines(
                meetingId: meetingId,
                lines: payload,
                token: currentToken
            )
            offlineManager.cacheMeetingDetail(updated)
            if minutesSignature() == signature {
                meeting = updated
                mergeMinuteServerIds(from: updated)
                lastSavedMinutesSignature = minutesSignature()
            } else {
                mergeMinuteServerIds(from: updated)
            }
            markSaved(.saved)
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueReplaceMinutes(
                    projectId: projectId,
                    meetingId: meetingId,
                    lines: payload,
                    token: currentToken
                )
                lastSavedMinutesSignature = signature
                persistLocalDetailSnapshot()
                markSaved(.savedOffline)
            } else {
                let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
                saveStatus = .error(message)
                if !triggeredByAutosave { actionError = message }
            }
        }
    }

    private func mergeAgendaServerIds(from updated: MeetingDetail) {
        let serverItems = updated.agendaItems ?? []
        var used = Set<Int>()
        isHydrating = true
        defer { isHydrating = false }
        for index in agendaDrafts.indices {
            if let existing = agendaDrafts[index].serverId {
                used.insert(existing)
                continue
            }
            let title = agendaDrafts[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if let match = serverItems.first(where: { !used.contains($0.id) && $0.title == title })
                ?? serverItems.first(where: { !used.contains($0.id) && $0.sortOrder == index }) {
                agendaDrafts[index].serverId = match.id
                used.insert(match.id)
            }
        }
    }

    private func mergeMinuteServerIds(from updated: MeetingDetail) {
        let serverLines = updated.minuteSectionLines
        var used = Set<Int>()
        isHydrating = true
        defer { isHydrating = false }
        for index in minuteDrafts.indices {
            if let existing = minuteDrafts[index].serverId {
                used.insert(existing)
                continue
            }
            let content = minuteDrafts[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if let match = serverLines.first(where: { !used.contains($0.id) && $0.content == content })
                ?? serverLines.first(where: { !used.contains($0.id) && ($0.sortOrder ?? index) == index }) {
                minuteDrafts[index].serverId = match.id
                used.insert(match.id)
            }
        }
        // Refresh close-out source lines without clobbering drafts
        meeting = updated
    }

    /// Keep a local snapshot so offline reload reflects the latest edits.
    private func persistLocalDetailSnapshot() {
        guard var snapshot = meeting else { return }
        // Store current editable fields into a lightweight cache update via re-fetch shape.
        // We only have MeetingDetail from server; cache the last known server meeting and
        // rely on pending mutations for truth after sync. Still useful for title/date display.
        offlineManager.cacheMeetingDetail(snapshot)
        _ = snapshot
    }

    private func finalize() async {
        flushPendingSaves()
        isFinalizing = true
        actionError = nil
        defer { isFinalizing = false }
        do {
            let updated = try await APIClient.finalizeMeeting(id: meetingId, token: currentToken)
            offlineManager.cacheMeetingDetail(updated)
            meeting = updated
            hydrate(from: updated)
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func deleteMeeting() async {
        do {
            try await APIClient.deleteMeeting(id: meetingId, token: currentToken)
            dismiss()
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func downloadPDF() async {
        do {
            pdfURL = try await APIClient.fetchMeetingPDF(id: meetingId, token: currentToken)
            showSharePDF = true
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func openAgendaAttachment(_ attachment: MeetingAgendaAttachment) async {
        do {
            let result = try await APIClient.downloadMeetingAgendaFile(
                meetingId: meetingId,
                attachmentId: attachment.id,
                token: currentToken
            )
            if let url = URL(string: result.url) {
                await UIApplication.shared.open(url)
            }
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func deleteAgendaAttachment(_ attachment: MeetingAgendaAttachment) async {
        do {
            try await APIClient.deleteMeetingAgendaFile(
                meetingId: meetingId,
                attachmentId: attachment.id,
                token: currentToken
            )
            await load(showSpinner: false)
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func handleAgendaFileImport(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let fileName = url.lastPathComponent

            if offlineManager.isOffline {
                offlineManager.queueAgendaFileUpload(
                    projectId: projectId,
                    meetingId: meetingId,
                    fileData: data,
                    fileName: fileName,
                    mimeType: mime,
                    token: currentToken
                )
                markSaved(.savedOffline)
                return
            }

            _ = try await APIClient.uploadMeetingAgendaFile(
                meetingId: meetingId,
                fileData: data,
                fileName: fileName,
                mimeType: mime,
                token: currentToken
            )
            await load(showSpinner: false)
            markSaved(.saved)
        } catch {
            if OfflineMeetingManager.isConnectivityError(error),
               let url = try? result.get().first,
               url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    offlineManager.queueAgendaFileUpload(
                        projectId: projectId,
                        meetingId: meetingId,
                        fileData: data,
                        fileName: url.lastPathComponent,
                        mimeType: mime,
                        token: currentToken
                    )
                    markSaved(.savedOffline)
                    return
                }
            }
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}

// MARK: - Supporting UI

private struct MeetingSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }
}

private struct FlowUserChips: View {
    let userIds: [Int]
    let users: [User]
    let onRemove: (Int) -> Void

    var body: some View {
        FlexibleChipWrap {
            ForEach(userIds, id: \.self) { userId in
                let name = users.first(where: { $0.id == userId })?.displayName ?? "User #\(userId)"
                HStack(spacing: 4) {
                    Text(name).font(.caption)
                    Button {
                        onRemove(userId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
            }
        }
    }
}

private struct FlexibleChipWrap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

private struct MeetingShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Breaks up onChange observers so the detail view type-checks.
private struct MeetingAutosaveChangeModifier: ViewModifier {
    let onDetailsChange: () -> Void
    let onAgendaChange: () -> Void
    let onMinutesChange: () -> Void

    let title: String
    let meetingDate: Date
    let includeNextMeeting: Bool
    let nextMeetingDate: Date
    let location: String
    let isPrivate: Bool
    let categoryId: Int?
    let presentIds: [Int]
    let apologyIds: [Int]
    let distributionIds: [Int]
    let agendaDrafts: [AgendaDraftItem]
    let minuteDrafts: [MinuteDraftLine]

    func body(content: Content) -> some View {
        content
            .onChange(of: title) { _, _ in onDetailsChange() }
            .onChange(of: meetingDate) { _, _ in onDetailsChange() }
            .onChange(of: includeNextMeeting) { _, _ in onDetailsChange() }
            .onChange(of: nextMeetingDate) { _, _ in onDetailsChange() }
            .onChange(of: location) { _, _ in onDetailsChange() }
            .onChange(of: isPrivate) { _, _ in onDetailsChange() }
            .onChange(of: categoryId) { _, _ in onDetailsChange() }
            .onChange(of: presentIds) { _, _ in onDetailsChange() }
            .onChange(of: apologyIds) { _, _ in onDetailsChange() }
            .onChange(of: distributionIds) { _, _ in onDetailsChange() }
            .onChange(of: agendaDrafts) { _, _ in onAgendaChange() }
            .onChange(of: minuteDrafts) { _, _ in onMinutesChange() }
    }
}
