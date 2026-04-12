import SwiftUI

struct PermitsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var eventManager = PermitEventManager.shared
    @State private var permits: [Permit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .date
    @State private var filterOption: FilterOption = .all
    @State private var isRefreshing = false
    @State private var selectedPermit: Permit?
    @State private var showCreatePermit = false
    /// When set, after create we show the permit's form in-app (seamless flow like web).
    @State private var permitFormFlow: PermitFormFlow?
    /// When set, show the "New Permit" step first for this draft, then continue to form.
    @State private var draftPermitStep1: DraftPermitStep1?
    /// permitTypeId -> formTemplateId for opening draft permit form workflow.
    @State private var permitTypeFormTemplateIds: [Int: Int] = [:]

    struct DraftPermitStep1: Identifiable {
        let permit: Permit
        let formTemplateId: Int
        var id: Int { permit.id }
    }

    struct PermitFormFlow: Identifiable {
        let permit: Permit
        let formTemplateId: Int
        var id: Int { permit.id }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case number = "Number"
        case date = "Date"
        case status = "Status"
        var id: String { rawValue }
    }

    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case underReview = "Under Review"
        case approved = "Approved"
        case active = "Active"
        case rejected = "Rejected"
        case suspended = "Suspended"
        case closeoutReview = "Closeout Review"
        case closed = "Closed"
        var id: String { rawValue }
    }

    private static let statusMap: [String: String] = [
        "DRAFT": "Draft",
        "UNDER_REVIEW": "Under Review",
        "APPROVED": "Approved",
        "ACTIVE": "Active",
        "REJECTED": "Rejected",
        "SUSPENDED": "Suspended",
        "CLOSEOUT_REVIEW": "Closeout Review",
        "CLOSED": "Closed"
    ]

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading permits...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        fetchPermits()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if permits.isEmpty {
                emptyStateView
            } else {
                permitsList
            }
        }
        .navigationTitle("Permits")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search permits...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if eventManager.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Live")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if sessionManager.hasPermission("create_permits") {
                    Button(action: { showCreatePermit = true }) {
                        Image(systemName: "plus")
                    }
                }
                Menu {
                    Section("Sort By") {
                        ForEach(SortOption.allCases) { option in
                            Button(action: { sortOption = option }) {
                                HStack {
                                    Text(option.rawValue)
                                    if sortOption == option { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Filter By Status") {
                        ForEach(FilterOption.allCases) { option in
                            Button(action: { filterOption = option }) {
                                HStack {
                                    Text(option.rawValue)
                                    if filterOption == option { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onAppear {
            if permits.isEmpty {
                fetchPermits()
            }
            loadPermitTypeFormTemplateIds()
            let currentToken = sessionManager.token ?? token
            eventManager.connect(projectId: projectId, token: currentToken)
        }
        .onDisappear {
            eventManager.disconnect()
        }
        .refreshable {
            await refreshPermits()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PermitCreated"))) { notification in
            if let userInfo = notification.userInfo,
               let eventProjectId = userInfo["projectId"] as? Int,
               eventProjectId == projectId,
               let newPermit = userInfo["permit"] as? Permit {
                if !permits.contains(where: { $0.id == newPermit.id }) {
                    permits.insert(newPermit, at: 0)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PermitUpdated"))) { notification in
            if let userInfo = notification.userInfo,
               let eventProjectId = userInfo["projectId"] as? Int,
               eventProjectId == projectId,
               let updatedPermit = userInfo["permit"] as? Permit {
                if let index = permits.firstIndex(where: { $0.id == updatedPermit.id }) {
                    permits[index] = updatedPermit
                }
                if selectedPermit?.id == updatedPermit.id {
                    selectedPermit = updatedPermit
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PermitDeleted"))) { notification in
            if let userInfo = notification.userInfo,
               let eventProjectId = userInfo["projectId"] as? Int,
               eventProjectId == projectId,
               let deletedId = userInfo["permitId"] as? Int {
                permits.removeAll { $0.id == deletedId }
                if selectedPermit?.id == deletedId {
                    selectedPermit = nil
                }
            }
        }
        .sheet(item: $selectedPermit) { permit in
            NavigationView {
                PermitDetailPlaceholderView(permit: permit, projectId: projectId)
            }
        }
        .fullScreenCover(isPresented: $showCreatePermit) {
            CreatePermitView(
                projectId: projectId,
                token: token,
                projectName: projectName,
                onSuccess: { createdPermit, formTemplateId in
                    showCreatePermit = false
                    if let formId = formTemplateId {
                        permitFormFlow = PermitFormFlow(permit: createdPermit, formTemplateId: formId)
                    } else {
                        selectedPermit = createdPermit
                    }
                    fetchPermits()
                },
                onCancel: { showCreatePermit = false }
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: $permitFormFlow) { flow in
            PermitFormView(
                permit: flow.permit,
                formTemplateId: flow.formTemplateId,
                projectId: projectId,
                token: token,
                onDone: {
                    permitFormFlow = nil
                    fetchPermits()
                }
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: $draftPermitStep1) { step in
            CreatePermitView(
                projectId: projectId,
                token: token,
                projectName: projectName,
                existingDraftPermit: step.permit,
                formTemplateIdForDraft: step.formTemplateId,
                onSuccess: { completedPermit, formTemplateId in
                    draftPermitStep1 = nil
                    if let formId = formTemplateId {
                        permitFormFlow = PermitFormFlow(permit: completedPermit, formTemplateId: formId)
                    }
                    fetchPermits()
                },
                onCancel: { draftPermitStep1 = nil }
            )
            .environmentObject(sessionManager)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                Text("No Permits")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Permits for this project will appear here.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if sessionManager.hasPermission("create_permits") {
                Button(action: { showCreatePermit = true }) {
                    Label("Create Permit", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permitsList: some View {
        List {
            ForEach(filteredAndSortedPermits) { permit in
                Button(action: {
                    if permit.status.uppercased() == "DRAFT",
                       let formTemplateId = permitTypeFormTemplateIds[permit.permitTypeId] {
                        draftPermitStep1 = DraftPermitStep1(permit: permit, formTemplateId: formTemplateId)
                    } else {
                        selectedPermit = permit
                    }
                }) {
                    PermitRowView(permit: permit)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    private var filteredAndSortedPermits: [Permit] {
        var filtered = permits

        if filterOption != .all {
            let statusValue: String = {
                switch filterOption {
                case .all: return ""
                case .draft: return "DRAFT"
                case .underReview: return "UNDER_REVIEW"
                case .approved: return "APPROVED"
                case .active: return "ACTIVE"
                case .rejected: return "REJECTED"
                case .suspended: return "SUSPENDED"
                case .closeoutReview: return "CLOSEOUT_REVIEW"
                case .closed: return "CLOSED"
                }
            }()
            filtered = filtered.filter { $0.status.uppercased() == statusValue }
        }

        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            filtered = filtered.filter {
                $0.permitNumber.lowercased().contains(lower) ||
                ($0.permitType?.name.lowercased().contains(lower) ?? false) ||
                ($0.submittedBy?.email?.lowercased().contains(lower) ?? false)
            }
        }

        switch sortOption {
        case .number:
            filtered.sort { $0.permitNumber.localizedStandardCompare($1.permitNumber) == .orderedDescending }
        case .date:
            filtered.sort { (p1, p2) in
                let d1 = p1.submittedAt ?? p1.createdAt ?? Date.distantPast
                let d2 = p2.submittedAt ?? p2.createdAt ?? Date.distantPast
                return d1 > d2
            }
        case .status:
            filtered.sort { $0.status.localizedCaseInsensitiveCompare($1.status) == .orderedAscending }
        }

        return filtered
    }

    private func fetchPermits() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await APIClient.fetchPermits(projectId: projectId, token: token)
                await MainActor.run {
                    permits = fetched
                    isLoading = false
                }
                await MainActor.run { loadPermitTypeFormTemplateIds() }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                    isLoading = false
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func loadPermitTypeFormTemplateIds() {
        Task {
            do {
                let types = try await APIClient.fetchPermitTypes(projectId: projectId, token: token)
                await MainActor.run {
                    permitTypeFormTemplateIds = Dictionary(uniqueKeysWithValues: types.compactMap { type -> (Int, Int)? in
                        guard let formId = type.formTemplateId else { return nil }
                        return (type.id, formId)
                    })
                }
            } catch {
                // Non-fatal; draft form flow will fall back to detail view if map is empty
            }
        }
    }

    private func refreshPermits() async {
        isRefreshing = true
        do {
            let fetched = try await APIClient.fetchPermits(projectId: projectId, token: token)
            await MainActor.run {
                permits = fetched
                isRefreshing = false
            }
            await MainActor.run { loadPermitTypeFormTemplateIds() }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isRefreshing = false
            }
        }
    }
}

struct PermitRowView: View {
    let permit: Permit

    private static let statusMap: [String: String] = [
        "DRAFT": "Draft",
        "UNDER_REVIEW": "Under Review",
        "APPROVED": "Approved",
        "ACTIVE": "Active",
        "REJECTED": "Rejected",
        "SUSPENDED": "Suspended",
        "CLOSEOUT_REVIEW": "Closeout Review",
        "CLOSED": "Closed"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(permit.permitNumber)
                        .font(.headline)
                        .lineLimit(1)
                    if let typeName = permit.permitType?.name {
                        Text(typeName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(Self.statusMap[permit.status.uppercased()] ?? permit.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(6)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if let date = permit.submittedAt ?? permit.createdAt {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let email = permit.submittedBy?.email {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(email)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
    }

    private var statusColor: Color {
        switch permit.status.uppercased() {
        case "DRAFT": return .gray
        case "UNDER_REVIEW": return .orange
        case "APPROVED", "ACTIVE": return .green
        case "REJECTED": return .red
        case "SUSPENDED": return .orange
        case "CLOSEOUT_REVIEW": return .blue
        case "CLOSED": return .purple
        default: return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct PermitDetailPlaceholderView: View {
    let permit: Permit
    let projectId: Int
    @Environment(\.dismiss) private var dismiss

    private static let statusMap: [String: String] = [
        "DRAFT": "Draft",
        "UNDER_REVIEW": "Under Review",
        "APPROVED": "Approved",
        "ACTIVE": "Active",
        "REJECTED": "Rejected",
        "SUSPENDED": "Suspended",
        "CLOSEOUT_REVIEW": "Closeout Review",
        "CLOSED": "Closed"
    ]

    var body: some View {
        List {
            Section("Permit") {
                LabeledContent("Number", value: permit.permitNumber)
                LabeledContent("Type", value: permit.permitType?.name ?? "—")
                LabeledContent("Status", value: Self.statusMap[permit.status.uppercased()] ?? permit.status)
            }
            Section("Dates") {
                if let d = permit.submittedAt {
                    LabeledContent("Submitted", value: formatDate(d))
                }
                if let d = permit.validUntil {
                    LabeledContent("Valid until", value: formatDate(d))
                }
                if let d = permit.createdAt {
                    LabeledContent("Created", value: formatDate(d))
                }
            }
            if let email = permit.submittedBy?.email {
                Section("Submitted by") {
                    Text(email)
                }
            }
        }
        .navigationTitle(permit.permitNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Loads the form for a permit type and presents it in-app (seamless permit → form flow like web).
/// If the permit already has a form submission (e.g. draft saved), loads that so existing text/data is shown.
///
/// Photo markup (draw/text on images before submit) is provided by `FormSubmissionCreateView` / `FormSubmissionEditView` for camera and image fields.
struct PermitFormView: View {
    let permit: Permit
    let formTemplateId: Int
    let projectId: Int
    let token: String
    let onDone: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var form: FormModel?
    @State private var existingSubmission: FormSubmission?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading form…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Close") { onDone() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let form = form, let submission = existingSubmission {
                FormSubmissionEditView(
                    submission: submission,
                    form: form,
                    projectId: projectId,
                    token: token,
                    onSave: onDone
                )
            } else if let form = form {
                FormSubmissionCreateView(
                    form: form,
                    projectId: projectId,
                    token: token,
                    permitId: permit.id,
                    navigationTitleOverride: permit.permitNumber,
                    onSave: onDone
                )
            }
        }
        .navigationTitle(permit.permitNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard form == nil, loadError == nil else { return }
            do {
                let loadedForm = try await APIClient.fetchFormDetails(formId: formTemplateId, token: token)
                await MainActor.run { form = loadedForm }

                if let submissionId = permit.formSubmissionId {
                    let submissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
                    let match = submissions.first { $0.id == submissionId }
                    await MainActor.run { existingSubmission = match }
                }

                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

struct CreatePermitView: View {
    let projectId: Int
    let token: String
    let projectName: String
    /// When set, we're continuing a draft: show permit details then "Continue to form".
    let existingDraftPermit: Permit?
    /// Required when existingDraftPermit is set, so we can open the form after "Continue".
    let formTemplateIdForDraft: Int?
    let onSuccess: (Permit, Int?) -> Void
    let onCancel: () -> Void

    init(projectId: Int, token: String, projectName: String, existingDraftPermit: Permit? = nil, formTemplateIdForDraft: Int? = nil, onSuccess: @escaping (Permit, Int?) -> Void, onCancel: @escaping () -> Void) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.existingDraftPermit = existingDraftPermit
        self.formTemplateIdForDraft = formTemplateIdForDraft
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var permitTypes: [PermitTypeListItem] = []
    @State private var selectedTypeId: Int?
    @State private var worksDate: Date = Date()
    @State private var validUntil: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var useWorksDate = false
    @State private var useValidUntil = false
    @State private var isLoadingTypes = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var isDraftMode: Bool { existingDraftPermit != nil }

    var body: some View {
        NavigationView {
            Group {
                if isLoadingTypes {
                    ProgressView("Loading permit types...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = errorMessage, !isSubmitting {
                    VStack(spacing: 16) {
                        Text(message)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            errorMessage = nil
                            loadPermitTypes()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            if isDraftMode {
                                LabeledContent("Permit type", value: existingDraftPermit?.permitType?.name ?? "—")
                            } else {
                                Picker("Permit type", selection: $selectedTypeId) {
                                    Text("Select type…").tag(nil as Int?)
                                    ForEach(permitTypes) { type in
                                        Text(type.name).tag(type.id as Int?)
                                    }
                                }
                                .disabled(isSubmitting)
                            }
                        } header: {
                            Text("Permit type")
                        } footer: {
                            if permitTypes.isEmpty && !isLoadingTypes {
                                Text("No permit types are available for this project.")
                            }
                        }

                        Section("Optional dates") {
                            Toggle("Set works date", isOn: $useWorksDate)
                                .disabled(isSubmitting || isDraftMode)
                            if useWorksDate {
                                DatePicker("Works date", selection: $worksDate, displayedComponents: [.date, .hourAndMinute])
                                    .disabled(isSubmitting || isDraftMode)
                            }
                            Toggle("Set valid until", isOn: $useValidUntil)
                                .disabled(isSubmitting || isDraftMode)
                            if useValidUntil {
                                DatePicker("Valid until", selection: $validUntil, displayedComponents: [.date, .hourAndMinute])
                                    .disabled(isSubmitting || isDraftMode)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isDraftMode ? (existingDraftPermit?.permitNumber ?? "Complete permit") : "New Permit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isDraftMode {
                        Button("Continue to form") { continueToForm() }
                            .disabled(formTemplateIdForDraft == nil)
                    } else {
                        Button("Create") { submitCreate() }
                            .disabled(isSubmitting || selectedTypeId == nil || permitTypes.isEmpty)
                    }
                }
            }
            .onAppear { loadPermitTypes() }
        }
    }

    private func loadPermitTypes() {
        isLoadingTypes = true
        errorMessage = nil
        Task {
            do {
                let types = try await APIClient.fetchPermitTypes(projectId: projectId, token: token)
                await MainActor.run {
                    permitTypes = types
                    if let existing = existingDraftPermit {
                        selectedTypeId = existing.permitTypeId
                        useWorksDate = existing.worksDate != nil
                        worksDate = existing.worksDate ?? Date()
                        useValidUntil = existing.validUntil != nil
                        validUntil = existing.validUntil ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    } else {
                        selectedTypeId = types.first?.id
                    }
                    isLoadingTypes = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingTypes = false
                }
            }
        }
    }

    private func continueToForm() {
        guard let permit = existingDraftPermit, let formId = formTemplateIdForDraft else { return }
        onSuccess(permit, formId)
    }

    private func submitCreate() {
        guard let permitTypeId = selectedTypeId else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let created = try await APIClient.createPermit(
                    projectId: projectId,
                    permitTypeId: permitTypeId,
                    token: token,
                    worksDate: useWorksDate ? worksDate : nil,
                    validUntil: useValidUntil ? validUntil : nil
                )
                await MainActor.run {
                    isSubmitting = false
                    let formTemplateId = permitTypes.first(where: { $0.id == permitTypeId })?.formTemplateId
                    onSuccess(created, formTemplateId)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
