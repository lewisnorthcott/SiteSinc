import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MinuteLineCloseOutView: View {
    let projectId: Int
    let meetingId: Int
    let line: MeetingMinuteLine
    let token: String
    let canCloseOut: Bool
    let canReopen: Bool
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var offlineManager = OfflineMeetingManager.shared
    @State private var commentText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var localLine: MeetingMinuteLine
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingFile: (Data, String, String)?
    @State private var statusNote: String?

    init(
        projectId: Int,
        meetingId: Int,
        line: MeetingMinuteLine,
        token: String,
        canCloseOut: Bool,
        canReopen: Bool,
        onFinished: @escaping () -> Void
    ) {
        self.projectId = projectId
        self.meetingId = meetingId
        self.line = line
        self.token = token
        self.canCloseOut = canCloseOut
        self.canReopen = canReopen
        self.onFinished = onFinished
        _localLine = State(initialValue: line)
    }

    private var isDone: Bool { (localLine.status ?? .open) == .done }

    var body: some View {
        List {
            if offlineManager.isOffline {
                Section {
                    Label("Offline — updates queue and sync when you're back online.", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section("Action") {
                Text(localLine.content)
                if let assignees = localLine.assignees, !assignees.isEmpty {
                    Text(assignees.compactMap { $0.user?.displayName }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let due = localLine.dueDate {
                    Text("Due \(MeetingDateFormatting.displayDay(due))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(isDone ? "Done" : "Open")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isDone ? .green : .orange)
            }

            Section("Updates") {
                ForEach(localLine.comments ?? []) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.user?.displayName ?? "User")
                            .font(.caption.weight(.semibold))
                        Text(comment.content)
                            .font(.subheadline)
                        if let created = comment.createdAt {
                            Text(MeetingDateFormatting.displayDateTime(created))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        ForEach(comment.attachments ?? []) { attachment in
                            Button(attachment.fileName) {
                                Task { await openAttachment(attachment) }
                            }
                            .font(.caption)
                            .disabled(offlineManager.isOffline)
                        }
                    }
                    .padding(.vertical, 2)
                }

                ForEach(localLine.attachments ?? []) { attachment in
                    Button {
                        Task { await openAttachment(attachment) }
                    } label: {
                        Label(attachment.fileName, systemImage: "paperclip")
                    }
                    .disabled(offlineManager.isOffline)
                }

                if canCloseOut && !isDone {
                    TextField("Add an update", text: $commentText, axis: .vertical)
                        .lineLimit(2...5)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Attach photo", systemImage: "photo")
                    }
                    .onChange(of: photoItem) { _, item in
                        Task { await loadPhoto(item) }
                    }
                    if let pendingFile {
                        Text(pendingFile.1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Post update") {
                        Task { await postUpdate() }
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingFile == nil)
                }
            }

            if let statusNote {
                Section {
                    Text(statusNote).foregroundColor(.orange).font(.caption)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                }
            }

            Section {
                if !isDone, canCloseOut {
                    Button {
                        Task { await complete() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Mark complete") }
                    }
                    .disabled(isWorking)
                }
                if isDone, canReopen {
                    Button {
                        Task { await reopen() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Reopen") }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle("Close out")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    onFinished()
                    dismiss()
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                pendingFile = (data, "update.jpg", "image/jpeg")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func postUpdate() async {
        isWorking = true
        errorMessage = nil
        statusNote = nil
        defer { isWorking = false }

        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if offlineManager.isOffline {
            offlineManager.queueMinuteLineUpdate(
                projectId: projectId,
                meetingId: meetingId,
                lineId: localLine.id,
                content: content.isEmpty ? nil : content,
                fileData: pendingFile?.0,
                fileName: pendingFile?.1,
                mimeType: pendingFile?.2,
                token: token
            )
            commentText = ""
            pendingFile = nil
            photoItem = nil
            statusNote = "Update saved offline — will sync when online."
            return
        }

        do {
            let result = try await APIClient.addMeetingMinuteLineUpdate(
                meetingId: meetingId,
                lineId: localLine.id,
                content: content,
                fileData: pendingFile?.0,
                fileName: pendingFile?.1,
                mimeType: pendingFile?.2,
                token: token
            )
            if let updated = result.line {
                localLine = updated
            } else {
                localLine = try await APIClient.fetchMeeting(id: meetingId, token: token)
                    .minuteLines?
                    .first(where: { $0.id == localLine.id }) ?? localLine
            }
            commentText = ""
            pendingFile = nil
            photoItem = nil
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueMinuteLineUpdate(
                    projectId: projectId,
                    meetingId: meetingId,
                    lineId: localLine.id,
                    content: content.isEmpty ? nil : content,
                    fileData: pendingFile?.0,
                    fileName: pendingFile?.1,
                    mimeType: pendingFile?.2,
                    token: token
                )
                commentText = ""
                pendingFile = nil
                photoItem = nil
                statusNote = "Update saved offline — will sync when online."
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func complete() async {
        isWorking = true
        errorMessage = nil
        statusNote = nil
        defer { isWorking = false }
        let comment = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if offlineManager.isOffline {
            offlineManager.queueCompleteMinuteLine(
                projectId: projectId,
                meetingId: meetingId,
                lineId: localLine.id,
                comment: comment.isEmpty ? nil : comment,
                token: token
            )
            // Optimistic local status
            localLine = MeetingMinuteLine(
                id: localLine.id,
                sortOrder: localLine.sortOrder,
                content: localLine.content,
                section: localLine.section,
                sourceMinuteLineId: localLine.sourceMinuteLineId,
                sourceMeetingId: localLine.sourceMeetingId,
                agendaItemId: localLine.agendaItemId,
                dueDate: localLine.dueDate,
                status: .done,
                completedAt: MeetingDateFormatting.isoString(from: Date()),
                completedBy: localLine.completedBy,
                createdById: localLine.createdById,
                assignees: localLine.assignees,
                comments: localLine.comments,
                attachments: localLine.attachments
            )
            commentText = ""
            statusNote = "Marked complete offline — will sync when online."
            return
        }

        do {
            localLine = try await APIClient.completeMeetingMinuteLine(
                meetingId: meetingId,
                lineId: localLine.id,
                comment: comment.isEmpty ? nil : comment,
                token: token
            )
            commentText = ""
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueCompleteMinuteLine(
                    projectId: projectId,
                    meetingId: meetingId,
                    lineId: localLine.id,
                    comment: comment.isEmpty ? nil : comment,
                    token: token
                )
                statusNote = "Marked complete offline — will sync when online."
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func reopen() async {
        isWorking = true
        errorMessage = nil
        statusNote = nil
        defer { isWorking = false }

        if offlineManager.isOffline {
            offlineManager.queueReopenMinuteLine(
                projectId: projectId,
                meetingId: meetingId,
                lineId: localLine.id,
                token: token
            )
            localLine = MeetingMinuteLine(
                id: localLine.id,
                sortOrder: localLine.sortOrder,
                content: localLine.content,
                section: localLine.section,
                sourceMinuteLineId: localLine.sourceMinuteLineId,
                sourceMeetingId: localLine.sourceMeetingId,
                agendaItemId: localLine.agendaItemId,
                dueDate: localLine.dueDate,
                status: .open,
                completedAt: nil,
                completedBy: nil,
                createdById: localLine.createdById,
                assignees: localLine.assignees,
                comments: localLine.comments,
                attachments: localLine.attachments
            )
            statusNote = "Reopened offline — will sync when online."
            return
        }

        do {
            localLine = try await APIClient.reopenMeetingMinuteLine(
                meetingId: meetingId,
                lineId: localLine.id,
                token: token
            )
        } catch {
            if OfflineMeetingManager.isConnectivityError(error) {
                offlineManager.queueReopenMinuteLine(
                    projectId: projectId,
                    meetingId: meetingId,
                    lineId: localLine.id,
                    token: token
                )
                statusNote = "Reopened offline — will sync when online."
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func openAttachment(_ attachment: MeetingMinuteLineAttachment) async {
        do {
            let result = try await APIClient.downloadMeetingMinuteLineAttachment(
                meetingId: meetingId,
                lineId: localLine.id,
                attachmentId: attachment.id,
                token: token
            )
            if let url = URL(string: result.url) {
                await UIApplication.shared.open(url)
            }
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
