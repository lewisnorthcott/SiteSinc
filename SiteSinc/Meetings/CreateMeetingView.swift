import SwiftUI

struct CreateMeetingView: View {
    let projectId: Int
    let token: String
    let existingMeetings: [MeetingListItem]
    let onCreated: (MeetingDetail) -> Void

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var meetingDate = Date()
    @State private var includeNextMeeting = false
    @State private var nextMeetingDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var isPrivate = false
    @State private var categoryId: Int?
    @State private var categories: [MeetingCategory] = []
    @State private var includePreviousReview = false
    @State private var copyFromMeetingId: Int?
    @State private var copyActionsFilter: CopyActionsFilter = .outstanding
    @State private var copyPreviewCount: Int?
    @State private var copyPreviewLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var newCategoryName = ""
    @State private var showNewCategory = false

    private var currentToken: String { sessionManager.token ?? token }
    private var canManageCategories: Bool { MeetingPermissions.canEdit(user: sessionManager.user) }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!includePreviousReview || (copyFromMeetingId != nil && (copyPreviewCount ?? 0) > 0))
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Title", text: $title)
                DatePicker("Date & time", selection: $meetingDate)
                Toggle("Next meeting", isOn: $includeNextMeeting)
                if includeNextMeeting {
                    DatePicker("Next meeting date", selection: $nextMeetingDate)
                }
                TextField("Location (optional)", text: $location)
                Toggle("Private meeting", isOn: $isPrivate)
            }

            Section("Category") {
                Picker("Category", selection: $categoryId) {
                    Text("None").tag(Optional<Int>.none)
                    ForEach(categories.filter { $0.active != false }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                if canManageCategories {
                    Button("Add category") { showNewCategory = true }
                }
            }

            if !existingMeetings.isEmpty {
                Section {
                    Toggle("Review previous minutes", isOn: $includePreviousReview)
                    if includePreviousReview {
                        Picker("Copy from", selection: $copyFromMeetingId) {
                            ForEach(existingMeetings) { meeting in
                                Text("\(meeting.reference) — \(meeting.title)").tag(Optional(meeting.id))
                            }
                        }
                        Picker("Actions to copy", selection: $copyActionsFilter) {
                            Text("Outstanding only").tag(CopyActionsFilter.outstanding)
                            Text("All actions").tag(CopyActionsFilter.all)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: copyActionsFilter) { _, _ in
                            Task { await refreshCopyPreview() }
                        }
                        .onChange(of: copyFromMeetingId) { _, _ in
                            Task { await refreshCopyPreview() }
                        }

                        if copyPreviewLoading {
                            ProgressView("Checking actions...")
                        } else if let copyPreviewCount {
                            Text("\(copyPreviewCount) action\(copyPreviewCount == 1 ? "" : "s") will be carried forward")
                                .font(.caption)
                                .foregroundColor(copyPreviewCount == 0 ? .red : .secondary)
                        }
                    }
                } header: {
                    Text("Previous actions")
                } footer: {
                    Text("Carries action items into a review section on the new meeting.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("New meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button("Create") { Task { await submit() } }
                        .disabled(!canSubmit)
                }
            }
        }
        .task {
            await loadCategories()
            if copyFromMeetingId == nil {
                copyFromMeetingId = existingMeetings.first?.id
            }
        }
        .onChange(of: includePreviousReview) { _, enabled in
            if enabled {
                if copyFromMeetingId == nil {
                    copyFromMeetingId = existingMeetings.first?.id
                }
                Task { await refreshCopyPreview() }
            } else {
                copyPreviewCount = nil
            }
        }
        .alert("New category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryName = "" }
            Button("Create") {
                Task { await createCategory() }
            }
        } message: {
            Text("Categories are shared across your organisation.")
        }
    }

    private func loadCategories() async {
        do {
            categories = try await APIClient.fetchMeetingCategories(token: currentToken)
        } catch {
            // Non-fatal — category is optional
        }
    }

    private func createCategory() async {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let category = try await APIClient.createMeetingCategory(name: name, token: currentToken)
            categories.append(category)
            categories.sort { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            categoryId = category.id
            newCategoryName = ""
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func refreshCopyPreview() async {
        guard includePreviousReview, let copyFromMeetingId else {
            copyPreviewCount = nil
            return
        }
        copyPreviewLoading = true
        defer { copyPreviewLoading = false }
        do {
            let result = try await APIClient.fetchCopyableMeetingActions(
                meetingId: copyFromMeetingId,
                filter: copyActionsFilter,
                token: currentToken
            )
            copyPreviewCount = result.actions.count
        } catch {
            copyPreviewCount = nil
        }
    }

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let body = CreateMeetingRequest(
            title: trimmedTitle,
            meetingDate: MeetingDateFormatting.isoString(from: meetingDate),
            nextMeetingDate: includeNextMeeting ? MeetingDateFormatting.isoString(from: nextMeetingDate) : nil,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: nil,
            isPrivate: isPrivate,
            categoryId: categoryId,
            attendees: nil,
            copyFromMeetingId: includePreviousReview ? copyFromMeetingId : nil,
            copyActionsFilter: includePreviousReview ? copyActionsFilter : nil
        )

        do {
            let meeting = try await APIClient.createMeeting(projectId: projectId, body: body, token: currentToken)
            onCreated(meeting)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
