import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MinuteLineCloseOutView: View {
    let meetingId: Int
    let line: MeetingMinuteLine
    let token: String
    let canCloseOut: Bool
    let canReopen: Bool
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var localLine: MeetingMinuteLine
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingFile: (Data, String, String)?

    init(
        meetingId: Int,
        line: MeetingMinuteLine,
        token: String,
        canCloseOut: Bool,
        canReopen: Bool,
        onFinished: @escaping () -> Void
    ) {
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
        defer { isWorking = false }
        do {
            let result = try await APIClient.addMeetingMinuteLineUpdate(
                meetingId: meetingId,
                lineId: localLine.id,
                content: commentText,
                fileData: pendingFile?.0,
                fileName: pendingFile?.1,
                mimeType: pendingFile?.2,
                token: token
            )
            if let updated = result.line {
                localLine = updated
            } else {
                // Refresh from server if response omitted the line payload
                localLine = try await APIClient.fetchMeeting(id: meetingId, token: token)
                    .minuteLines?
                    .first(where: { $0.id == localLine.id }) ?? localLine
            }
            commentText = ""
            pendingFile = nil
            photoItem = nil
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func complete() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let comment = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
            localLine = try await APIClient.completeMeetingMinuteLine(
                meetingId: meetingId,
                lineId: localLine.id,
                comment: comment.isEmpty ? nil : comment,
                token: token
            )
            commentText = ""
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func reopen() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            localLine = try await APIClient.reopenMeetingMinuteLine(
                meetingId: meetingId,
                lineId: localLine.id,
                token: token
            )
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
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
