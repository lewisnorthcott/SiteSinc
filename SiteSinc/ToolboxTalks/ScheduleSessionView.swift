import SwiftUI

struct ScheduleSessionView: View {
    let projectId: Int
    let talkId: Int
    let token: String
    let onCreated: (ToolboxTalkSession) -> Void

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var location = ""
    @State private var presenterUserId: Int?
    @State private var projectUsers: [User] = []
    @State private var selectedAttendeeIds: Set<Int> = []
    @State private var notifyAttendees = true
    @State private var isLoadingUsers = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("When & where") {
                DatePicker("Scheduled for", selection: $scheduledDate)
                TextField("Location", text: $location)
            }

            Section("Presenter") {
                if isLoadingUsers {
                    ProgressView()
                } else {
                    Picker("Presenter", selection: Binding(
                        get: { presenterUserId ?? -1 },
                        set: { presenterUserId = $0 == -1 ? nil : $0 }
                    )) {
                        Text("None").tag(-1)
                        ForEach(projectUsers, id: \.id) { user in
                            Text(displayName(user)).tag(user.id)
                        }
                    }
                }
            }

            Section {
                Toggle("Notify selected attendees", isOn: $notifyAttendees)
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
            } header: {
                Text("Attendees")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Schedule session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSubmitting ? "Saving..." : "Schedule") {
                    Task { await submit() }
                }
                .disabled(isSubmitting || !ToolboxTalkPermissions.canSchedule(user: sessionManager.user))
            }
        }
        .task { await loadUsers() }
    }

    private func loadUsers() async {
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            projectUsers = try await APIClient.fetchProjectUsers(projectId: projectId, token: token)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let session = try await APIClient.scheduleToolboxTalkSession(
                projectId: projectId,
                talkId: talkId,
                scheduledFor: iso.string(from: scheduledDate),
                location: location.isEmpty ? nil : location,
                presenterUserId: presenterUserId,
                attendeeUserIds: notifyAttendees ? Array(selectedAttendeeIds) : nil,
                token: token
            )
            onCreated(session)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func displayName(_ user: User) -> String {
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        return user.email ?? "User #\(user.id)"
    }
}
