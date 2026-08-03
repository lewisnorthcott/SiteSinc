import SwiftUI

// MARK: - HSE Observation detail + close-out workflow
// Actions mirror the server rules in hseInspectionRoutes.ts:
//   start / submit (assignee, raiser, or close_hse_observations)
//   approve / reject (raiser, approve_hse_observations, or close_hse_observations)

struct HseObservationDetailView: View {
    let projectId: Int
    let observationId: Int
    let token: String

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var observation: HseObservation?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isActing = false

    // Action sheets
    @State private var showCloseoutSheet = false
    @State private var showRejectSheet = false
    @State private var closeoutNotes = ""
    @State private var closeoutPhotos: [HsePendingPhoto] = []
    @State private var rejectNotes = ""
    @State private var approveNotes = ""
    @State private var showApproveConfirm = false

    // Comments / progress photos
    @State private var newComment = ""
    @State private var isPostingComment = false
    @State private var progressPhotos: [HsePendingPhoto] = []

    private var myId: Int? { sessionManager.user?.id }
    private var canManage: Bool { sessionManager.hasPermission("close_hse_observations") }
    private var canApprovePermission: Bool { sessionManager.hasPermission("approve_hse_observations") }
    private var isRaiser: Bool { observation?.raisedBy?.id == myId }
    private var isAssignee: Bool { observation?.assignedTo?.id == myId }

    private var canAction: Bool { isAssignee || isRaiser || canManage }
    private var canApprove: Bool { isRaiser || canApprovePermission || canManage }

    var body: some View {
        ZStack {
            BrandChrome.groupedBackground.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading observation...")
            } else if let observation {
                content(observation)
            } else {
                Text("Observation not found").foregroundColor(.secondary)
            }
        }
        .navigationTitle("Observation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .trackPageView("/projects/\(projectId)/hse-inspections/observations/\(observationId)", projectId: projectId)
        .sheet(isPresented: $showCloseoutSheet) { closeoutSheet }
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        .alert("Approve close-out?", isPresented: $showApproveConfirm) {
            Button("Approve") { Task { await performStatus(action: "approve", notes: approveNotes.isEmpty ? nil : approveNotes) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close the observation.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: Content

    private func content(_ observation: HseObservation) -> some View {
        List {
            // Summary
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HseObservationStatusBadge(status: observation.status)
                        Spacer()
                        if let number = observation.inspection?.inspectionNumber {
                            Text(number).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text(observation.description)
                        .font(.body)
                }
                .padding(.vertical, 4)

                if let template = observation.inspection?.template {
                    detailRow("Inspection", template.title)
                }
                if let sectionTitle = sectionTitle(for: observation) {
                    detailRow("Section", sectionTitle)
                }
                if let category = observation.category {
                    detailRow("Category", category.name)
                }
                ForEach(categoryAnswers(for: observation), id: \.0) { label, value in
                    detailRow(label, value)
                }
                if let location = observation.location {
                    detailRow("Location", location.name)
                }
            }

            // People & dates
            Section("People & Dates") {
                if let raisedBy = observation.raisedBy {
                    detailRow("Raised by", raisedBy.displayName)
                }
                if let assignedTo = observation.assignedTo {
                    detailRow("Assigned to", assignedTo.displayName)
                } else {
                    detailRow("Assigned to", "Unassigned")
                }
                if let due = observation.dueDate {
                    HStack {
                        Text("Due date").foregroundColor(.secondary)
                        Spacer()
                        Text(due.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(observation.isOverdue ? .red : .primary)
                            .fontWeight(observation.isOverdue ? .semibold : .regular)
                    }
                    .font(.subheadline)
                }
                detailRow("Raised", observation.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let closedAt = observation.closedAt {
                    detailRow("Closed", closedAt.formatted(date: .abbreviated, time: .shortened))
                    if let closedBy = observation.closedBy {
                        detailRow("Closed by", closedBy.displayName)
                    }
                }
            }

            // Close-out notes
            if let notes = observation.closeoutNotes, !notes.isEmpty {
                Section("Close-out Notes") {
                    Text(notes).font(.subheadline)
                }
            }
            if let notes = observation.rejectionNotes, !notes.isEmpty, observation.status != .closed {
                Section {
                    Label(notes, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.red)
                } header: {
                    Text("Close-out Rejected")
                }
            }

            // Photos grouped by type
            photoSections(observation)

            // Add progress photos while open
            if observation.status == .open || observation.status == .inProgress, canAction {
                Section("Add Progress Photos") {
                    HsePhotoPickerSection(photos: $progressPhotos, title: "Progress Photos")
                    if !progressPhotos.isEmpty {
                        Button {
                            Task { await uploadProgressPhotos() }
                        } label: {
                            if isActing {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Upload \(progressPhotos.count) Photo(s)")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isActing)
                    }
                }
            }

            // Activity / comments
            Section("Activity") {
                if let comments = observation.comments, !comments.isEmpty {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                } else {
                    Text("No activity yet").font(.caption).foregroundColor(.secondary)
                }
                HStack {
                    TextField("Add a comment...", text: $newComment, axis: .vertical)
                        .lineLimit(1...4)
                    Button {
                        Task { await postComment() }
                    } label: {
                        if isPostingComment {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(newComment.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : BrandChrome.accent)
                        }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || isPostingComment)
                }
            }

            // Workflow actions
            if !availableActions(observation).isEmpty {
                Section {
                    ForEach(availableActions(observation), id: \.title) { action in
                        Button {
                            action.handler()
                        } label: {
                            HStack {
                                Spacer()
                                if isActing {
                                    ProgressView()
                                } else {
                                    Label(action.title, systemImage: action.icon)
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .foregroundColor(action.destructive ? .red : BrandChrome.accent)
                        .disabled(isActing)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func photoSections(_ observation: HseObservation) -> some View {
        let photos = (observation.photos ?? []).filter { $0.isImage }
        let grouped = Dictionary(grouping: photos) { $0.photoType ?? .observation }
        ForEach([HsePhotoType.observation, .progress, .closeout], id: \.self) { type in
            if let items = grouped[type], !items.isEmpty {
                Section("\(type.label) Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items) { photo in
                                VStack(alignment: .leading, spacing: 2) {
                                    HseRemotePhotoThumb(photo: photo, projectId: projectId, token: token, size: 110)
                                    if let stamp = photoStamp(photo) {
                                        Text(stamp)
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .frame(width: 110, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
    }

    private func photoStamp(_ photo: HseObservationPhoto) -> String? {
        var parts: [String] = []
        if let when = photo.capturedAt ?? photo.uploadedAt {
            parts.append(when.formatted(date: .abbreviated, time: .shortened))
        }
        if let lat = photo.latitude, let lon = photo.longitude {
            parts.append(String(format: "%.5f, %.5f", lat, lon))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func commentRow(_ comment: HseObservationComment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(comment.author?.displayName ?? "System")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(comment.comment)
                .font(.subheadline)
                .foregroundColor(comment.type == "comment" ? .primary : .secondary)
                .italic(comment.type != "comment")
        }
        .padding(.vertical, 2)
    }

    // MARK: Field helpers

    private func sectionTitle(for observation: HseObservation) -> String? {
        observation.inspection?.revision?.sections?.first { $0.id == observation.sectionId }?.title
    }

    private func categoryAnswers(for observation: HseObservation) -> [(String, String)] {
        let fields = observation.inspection?.revision?.observationFields ?? []
        let data = observation.categoryData ?? [:]
        return fields.compactMap { field in
            guard let value = data[field.id]?.displayString, !value.isEmpty else { return nil }
            return (field.label, value)
        }
    }

    // MARK: Actions

    private struct WorkflowAction {
        let title: String
        let icon: String
        let destructive: Bool
        let handler: () -> Void
    }

    private func availableActions(_ observation: HseObservation) -> [WorkflowAction] {
        var actions: [WorkflowAction] = []
        switch observation.status {
        case .open:
            if canAction {
                actions.append(WorkflowAction(title: "Start Work", icon: "play.circle", destructive: false) {
                    Task { await performStatus(action: "start", notes: nil) }
                })
                actions.append(WorkflowAction(title: "Submit Close-out", icon: "checkmark.seal", destructive: false) {
                    showCloseoutSheet = true
                })
            }
        case .inProgress:
            if canAction {
                actions.append(WorkflowAction(title: "Submit Close-out", icon: "checkmark.seal", destructive: false) {
                    showCloseoutSheet = true
                })
            }
        case .pendingApproval:
            if canApprove {
                actions.append(WorkflowAction(title: "Approve Close-out", icon: "checkmark.circle", destructive: false) {
                    showApproveConfirm = true
                })
                actions.append(WorkflowAction(title: "Reject Close-out", icon: "xmark.circle", destructive: true) {
                    showRejectSheet = true
                })
            }
        case .closed:
            break
        }
        return actions
    }

    // MARK: Close-out sheet

    private var closeoutSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe how this was resolved...", text: $closeoutNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Close-out Notes (required)")
                }
                Section {
                    HsePhotoPickerSection(photos: $closeoutPhotos, title: "Close-out Photos")
                } footer: {
                    Text("Evidence photos are stamped and attached before the close-out is submitted for approval.")
                }
            }
            .navigationTitle("Submit Close-out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showCloseoutSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await submitCloseout() }
                    } label: {
                        if isActing { ProgressView() } else { Text("Submit").fontWeight(.semibold) }
                    }
                    .disabled(closeoutNotes.trimmingCharacters(in: .whitespaces).isEmpty || isActing)
                }
            }
        }
    }

    private var rejectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Explain why the close-out is rejected...", text: $rejectNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Rejection Notes (required)")
                }
            }
            .navigationTitle("Reject Close-out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showRejectSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await performReject() }
                    } label: {
                        if isActing { ProgressView() } else { Text("Reject").fontWeight(.semibold) }
                    }
                    .disabled(rejectNotes.trimmingCharacters(in: .whitespaces).isEmpty || isActing)
                }
            }
        }
    }

    // MARK: Networking

    private func load() async {
        do {
            observation = try await APIClient.fetchHseObservation(projectId: projectId, observationId: observationId, token: token)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isLoading = false
    }

    private func performStatus(action: String, notes: String?) async {
        isActing = true
        defer { isActing = false }
        do {
            _ = try await APIClient.postHseObservationStatus(
                projectId: projectId,
                observationId: observationId,
                action: action,
                notes: notes,
                token: token
            )
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func submitCloseout() async {
        isActing = true
        defer { isActing = false }
        do {
            // Upload evidence first — the server blocks uploads on closed
            // observations, so photos must land before any approval.
            for photo in closeoutPhotos {
                _ = try await APIClient.uploadHseObservationPhotos(
                    projectId: projectId,
                    observationId: observationId,
                    images: [(data: photo.data, fileName: "closeout_\(photo.id).jpg")],
                    photoType: .closeout,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    accuracy: photo.accuracy,
                    capturedAt: photo.capturedAt,
                    token: token
                )
            }
            _ = try await APIClient.postHseObservationStatus(
                projectId: projectId,
                observationId: observationId,
                action: "submit",
                notes: closeoutNotes.trimmingCharacters(in: .whitespaces),
                token: token
            )
            showCloseoutSheet = false
            closeoutNotes = ""
            closeoutPhotos = []
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func performReject() async {
        isActing = true
        defer { isActing = false }
        do {
            _ = try await APIClient.postHseObservationStatus(
                projectId: projectId,
                observationId: observationId,
                action: "reject",
                notes: rejectNotes.trimmingCharacters(in: .whitespaces),
                token: token
            )
            showRejectSheet = false
            rejectNotes = ""
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func uploadProgressPhotos() async {
        isActing = true
        defer { isActing = false }
        do {
            for photo in progressPhotos {
                _ = try await APIClient.uploadHseObservationPhotos(
                    projectId: projectId,
                    observationId: observationId,
                    images: [(data: photo.data, fileName: "progress_\(photo.id).jpg")],
                    photoType: .progress,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    accuracy: photo.accuracy,
                    capturedAt: photo.capturedAt,
                    token: token
                )
            }
            progressPhotos = []
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func postComment() async {
        let trimmed = newComment.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isPostingComment = true
        defer { isPostingComment = false }
        do {
            _ = try await APIClient.addHseObservationComment(projectId: projectId, observationId: observationId, comment: trimmed, token: token)
            newComment = ""
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
