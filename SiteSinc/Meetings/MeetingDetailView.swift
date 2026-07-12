import SwiftUI
import UniformTypeIdentifiers

struct MeetingDetailView: View {
    let projectId: Int
    let meetingId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

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
    @State private var isSavingDetails = false
    @State private var isSavingAgenda = false
    @State private var isSavingMinutes = false
    @State private var isFinalizing = false
    @State private var pdfURL: URL?
    @State private var showSharePDF = false
    @State private var closeOutLine: MeetingMinuteLine?
    @State private var showFinalizeConfirm = false
    @State private var showDeleteConfirm = false
    @State private var agendaFileImporter = false

    private var currentToken: String { sessionManager.token ?? token }
    private var canEdit: Bool {
        MeetingPermissions.canEdit(user: sessionManager.user) && (meeting?.isEditable ?? false)
    }
    private var canDelete: Bool {
        MeetingPermissions.canDelete(user: sessionManager.user) && (meeting?.isEditable ?? false)
    }

    var body: some View {
        Group {
            if isLoading && meeting == nil {
                ProgressView("Loading meeting...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, meeting == nil {
                errorState(errorMessage)
            } else if let meeting {
                content(meeting)
            }
        }
        .navigationTitle(meeting?.reference ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await load() }
        .refreshable { await load(showSpinner: false) }
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
            NavigationStack {
                MinuteLineCloseOutView(
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                }
                if canDelete {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func content(_ meeting: MeetingDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                if isFinalizing || isSavingDetails {
                    ProgressView()
                }
            }
            Text(meeting.title)
                .font(.title2.weight(.bold))
            Text(MeetingDateFormatting.displayDateTime(meeting.meetingDate))
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let location = meeting.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
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
                Button {
                    Task { await saveDetails() }
                } label: {
                    if isSavingDetails {
                        ProgressView()
                    } else {
                        Text("Save details")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingDetails)
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
            if canEdit {
                Button {
                    Task { await saveDetails() }
                } label: {
                    Text("Save attendees")
                }
                .buttonStyle(.bordered)
            }
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
                Button {
                    Task { await saveAgenda() }
                } label: {
                    if isSavingAgenda { ProgressView() } else { Text("Save agenda") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingAgenda)

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
                    if canEdit {
                        Button(role: .destructive) {
                            Task { await deleteAgendaAttachment(attachment) }
                        } label: {
                            Image(systemName: "trash")
                        }
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
                Button {
                    Task { await saveMinutes() }
                } label: {
                    if isSavingMinutes { ProgressView() } else { Text("Save minutes") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingMinutes)
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

    // MARK: - Data

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let meetingTask = APIClient.fetchMeeting(id: meetingId, token: currentToken)
            async let usersTask = APIClient.fetchProjectUsers(projectId: projectId, token: currentToken)
            async let categoriesTask = APIClient.fetchMeetingCategories(token: currentToken)
            let (fetched, users, cats) = try await (meetingTask, usersTask, categoriesTask)
            meeting = fetched
            projectUsers = users.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            categories = cats
            hydrate(from: fetched)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func hydrate(from meeting: MeetingDetail) {
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

    private func saveDetails() async {
        isSavingDetails = true
        actionError = nil
        defer { isSavingDetails = false }
        let attendees: [MeetingAttendeeInput] =
            presentIds.map { MeetingAttendeeInput(userId: $0, role: .present) }
            + apologyIds.map { MeetingAttendeeInput(userId: $0, role: .apologies) }
            + distributionIds.map { MeetingAttendeeInput(userId: $0, role: .distribution) }
        let body = UpdateMeetingRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingDate: MeetingDateFormatting.isoString(from: meetingDate),
            nextMeetingDate: includeNextMeeting ? MeetingDateFormatting.isoString(from: nextMeetingDate) : nil,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
            notes: nil,
            isPrivate: isPrivate,
            categoryId: categoryId,
            attendees: attendees
        )
        do {
            let updated = try await APIClient.updateMeeting(id: meetingId, body: body, token: currentToken)
            meeting = updated
            hydrate(from: updated)
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func saveAgenda() async {
        isSavingAgenda = true
        actionError = nil
        defer { isSavingAgenda = false }
        let payload: [AgendaItemInput] = agendaDrafts.enumerated().compactMap { index, draft in
            let t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return draft.toInput(sortOrder: index)
        }
        do {
            let updated = try await APIClient.replaceMeetingAgendaItems(
                meetingId: meetingId,
                items: payload,
                token: currentToken
            )
            meeting = updated
            hydrate(from: updated)
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func saveMinutes() async {
        isSavingMinutes = true
        actionError = nil
        defer { isSavingMinutes = false }
        let payload: [MinuteLineInput] = minuteDrafts.enumerated().compactMap { index, draft in
            let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return draft.toInput(sortOrder: index)
        }
        do {
            let updated = try await APIClient.replaceMeetingMinuteLines(
                meetingId: meetingId,
                lines: payload,
                token: currentToken
            )
            meeting = updated
            hydrate(from: updated)
        } catch {
            actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func finalize() async {
        isFinalizing = true
        actionError = nil
        defer { isFinalizing = false }
        do {
            let updated = try await APIClient.finalizeMeeting(id: meetingId, token: currentToken)
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
            _ = try await APIClient.uploadMeetingAgendaFile(
                meetingId: meetingId,
                fileData: data,
                fileName: url.lastPathComponent,
                mimeType: mime,
                token: currentToken
            )
            await load(showSpinner: false)
        } catch {
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

/// Simple wrapping HStack for chips without a third-party layout.
private struct FlexibleChipWrap<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        // LazyVGrid with adaptive columns gives a wrap-like chip layout.
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
