import SwiftUI

// Wrapper for Int to conform to Identifiable
struct FormID: Identifiable {
    let id: Int
}

// Wrapper for draft editing data
struct DraftEditData: Identifiable {
    let id: Int
    let submission: FormSubmission
    let form: FormModel
    
    init(submission: FormSubmission, form: FormModel) {
        self.id = submission.id
        self.submission = submission
        self.form = form
    }
}

enum SubmissionStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case submitted = "Submitted"
    case awaitingCloseout = "Awaiting Closeout"
    case closeoutPending = "Closeout Pending"
    case closeoutSubmitted = "Closeout Submitted"
    case completed = "Completed"
    // Add other statuses if they exist and you want to filter by them

    var id: String { self.rawValue }
}

enum DisplayMode {
    case automatic
    case list
    case table
}

struct FormsView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineSubmissionManager.shared
    @State private var submissions: [FormSubmission] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFormTemplates = false
    @State private var selectedFormId: FormID?
    @State private var showCreateForm = false
    @State private var hasManageFormsPermission: Bool = false
    @State private var formToCreate: FormModel?
    /// Set when user selects a form from the template sheet; applied in onDismiss so the create cover presents after the sheet is gone.
    @State private var pendingFormToCreate: FormModel?
    @State private var draftToEdit: DraftEditData?
    @State private var showPendingSubmissions = false
    
    // State for Search and Filter
    @State private var searchText: String = ""
    @State private var selectedStatusFilter: SubmissionStatusFilter = .all
    @State private var selectedFormType: String = "All Types" // New form type filter
    @State private var selectedUser: String = "All Users"
    @State private var selectedFolder: String = "All Folders"
    @State private var displayMode: DisplayMode = .automatic
    @State private var shareSheetItem: ShareSheetItem?
    @State private var isPreparingPDF = false
    @State private var exportAlert: FormsExportAlert?
    @State private var isSelectionMode = false
    @State private var selectedSubmissionIds: Set<Int> = []
    @State private var availableProjectUsers: [User] = []
    @State private var showDistributionSheet = false
    @State private var isDistributingForms = false
    @State private var showDistributionToast = false
    @State private var distributionToastMessage = ""

    // Simplified filtered submissions (no grouping by template)
    private var filteredSubmissions: [FormSubmission] {
        var filtered = submissions

        // 1. Filter by status
        if selectedStatusFilter != .all {
            filtered = filtered.filter { $0.status.replacingOccurrences(of: "_", with: " ").lowercased() == selectedStatusFilter.rawValue.lowercased() }
        }

        // 2. Filter by form type
        if selectedFormType != "All Types" {
            filtered = filtered.filter { $0.templateTitle == selectedFormType }
        }

        // 3. Filter by user
        if selectedUser != "All Users" {
            filtered = filtered.filter { "\($0.submittedBy.firstName) \($0.submittedBy.lastName)" == selectedUser }
        }

        // 4. Filter by folder
        if selectedFolder != "All Folders" {
            filtered = filtered.filter { submission in
                let label: String = {
                    if let folder = submission.folder { return folder.name }
                    if let id = submission.folderId { return "Folder #\(id)" }
                    return "No Folder"
                }()
                return label == selectedFolder
            }
        }

        // 5. Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearchText = searchText.lowercased()
            var searchFiltered: [FormSubmission] = []
            for submission in filtered {
                if submission.templateTitle.lowercased().contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                } else if "\(submission.id)".contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                } else if submission.status.lowercased().contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                } else if submission.submittedBy.firstName.lowercased().contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                } else if submission.submittedBy.lastName.lowercased().contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                } else if let reference = submission.reference, !reference.isEmpty, reference.lowercased().contains(lowercasedSearchText) {
                    searchFiltered.append(submission)
                }
            }
            filtered = searchFiltered
        }
        
        // 6. Sort by most recent first
        return filtered.sorted { $0.submittedAt > $1.submittedAt }
    }

    // Computed property to get unique form types from submissions
    private var availableFormTypes: [String] {
        let uniqueTypes = Array(Set(submissions.map { $0.templateTitle })).sorted()
        return ["All Types"] + uniqueTypes
    }

    private var availableUsers: [String] {
        let uniqueUsers = Array(Set(submissions.map { "\($0.submittedBy.firstName) \($0.submittedBy.lastName)" })).sorted()
        return ["All Users"] + uniqueUsers
    }

    private var availableFolders: [String] {
        var labels: Set<String> = []
        for s in submissions {
            if let folder = s.folder {
                labels.insert(folder.name)
            } else if let id = s.folderId {
                labels.insert("Folder #\(id)")
            } else {
                labels.insert("No Folder")
            }
        }
        let sorted = Array(labels).sorted()
        return ["All Folders"] + sorted
    }

    private var currentDisplayMode: DisplayMode {
        if displayMode == .automatic {
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? .table : .list
            #else
            return .list
            #endif
        }
        return displayMode
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if offlineManager.pendingSubmissionsCount > 0 {
                    pendingSubmissionsBanner
                }
                contentView
            }

            // Floating Action Button
            if hasManageFormsPermission {
                Button(action: {
                    showingFormTemplates = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .padding(20)
                }
                .accessibilityLabel("Create new form")
            }
        }
        .navigationTitle("Forms")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search forms...")
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        exitSelectionMode()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        openDistributionSheet()
                    }) {
                        Text("Distribute (\(selectedSubmissionIds.count))")
                    }
                    .disabled(selectedSubmissionIds.isEmpty || isDistributingForms)
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showPendingSubmissions = true
                    }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 18))
                                .foregroundColor(offlineManager.pendingSubmissionsCount > 0 ? Color.orange : Color.secondary)
                            if offlineManager.pendingSubmissionsCount > 0 {
                                Text("\(offlineManager.pendingSubmissionsCount)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#EF4444"))
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                    .accessibilityLabel(offlineManager.pendingSubmissionsCount > 0 ? "\(offlineManager.pendingSubmissionsCount) pending syncs" : "Pending syncs")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        displayModeSection
                        Divider()
                        statusFilterSection
                        formTypeFilterSection
                        userFilterSection
                        folderFilterSection
                        clearFiltersSection
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showDistributionSheet) {
            FormDistributionSheet(
                users: availableProjectUsers,
                selectedCount: selectedSubmissionIds.count,
                isDistributing: isDistributingForms,
                onDistribute: { userIds, message in
                    distributeSelectedSubmissions(to: userIds, message: message)
                },
                onCancel: {
                    showDistributionSheet = false
                }
            )
        }
        .sheet(item: $shareSheetItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(item: $exportAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isPreparingPDF || isDistributingForms {
                ProgressView(isDistributingForms ? "Distributing forms..." : "Preparing PDF...")
                    .padding()
                    .background(Material.thin)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        .overlay(alignment: .top) {
            if showDistributionToast {
                ToastBanner(message: distributionToastMessage)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if submissions.isEmpty {
                fetchSubmissions()
            }
            checkPermissions()
            // Track screen view (GA4)
            AnalyticsManager.shared.trackScreenView("Forms", projectId: projectId)
        }
        .trackPageView("/projects/\(projectId)/forms", projectId: projectId)
        .sheet(isPresented: $showingFormTemplates, onDismiss: {
            // Present create view only after the template sheet has fully dismissed (matches web flow).
            if let form = pendingFormToCreate {
                pendingFormToCreate = nil
                DispatchQueue.main.async {
                    formToCreate = form
                }
            }
        }) {
            FormTemplateSelectionView(projectId: projectId, token: token) { form in
                pendingFormToCreate = form
                // Dismiss is called inside FormTemplateSelectionView; formToCreate is set in onDismiss above.
            }
        }
        .sheet(isPresented: $showPendingSubmissions) {
            PendingSubmissionsView()
        }
        .fullScreenCover(item: $formToCreate) { form in
            FormSubmissionCreateView(
                form: form,
                projectId: projectId,
                token: token,
                onSave: {
                    formToCreate = nil
                    fetchSubmissions() // Refresh list immediately after create
                }
            )
        }
        .fullScreenCover(item: $draftToEdit) { draftData in
            FormSubmissionEditView(
                submission: draftData.submission,
                form: draftData.form,
                projectId: projectId,
                token: token,
                onSave: {
                    draftToEdit = nil
                    fetchSubmissions() // Refresh the list
                }
            )
        }
    }

    // MARK: - Pending Submissions Banner
    private var pendingSubmissionsBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.orange)
                Text("\(offlineManager.pendingSubmissionsCount) form\(offlineManager.pendingSubmissionsCount == 1 ? "" : "s") waiting to sync")
                    .font(.footnote)
                Spacer()
                if offlineManager.syncInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Sync Now") {
                        offlineManager.manualSync()
                    }
                    .font(.footnote)
                    .foregroundColor(.blue)
                }
                Button(action: {
                    showPendingSubmissions = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            if let syncError = offlineManager.lastSyncError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(syncError)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    // MARK: - Menu Sections
    private var displayModeSection: some View {
        Section("Display Mode") {
            Button(action: { displayMode = .automatic }) {
                HStack {
                    Text("Automatic")
                    if displayMode == .automatic {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: { displayMode = .list }) {
                HStack {
                    Text("List")
                    if displayMode == .list {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button(action: { displayMode = .table }) {
                HStack {
                    Text("Table")
                    if displayMode == .table {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private var statusFilterSection: some View {
        Section("Filter by Status") {
            ForEach(SubmissionStatusFilter.allCases) { status in
                Button(action: {
                    selectedStatusFilter = status
                }) {
                    HStack {
                        Text(status.rawValue)
                        if selectedStatusFilter == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var formTypeFilterSection: some View {
        Section("Filter by Form Type") {
            ForEach(availableFormTypes, id: \.self) { formType in
                Button(action: {
                    selectedFormType = formType
                }) {
                    HStack {
                        Text(formType)
                        if selectedFormType == formType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var userFilterSection: some View {
        Section("Filter by User") {
            ForEach(availableUsers, id: \.self) { user in
                Button(action: {
                    selectedUser = user
                }) {
                    HStack {
                        Text(user)
                        if selectedUser == user {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var folderFilterSection: some View {
        Section("Filter by Folder") {
            ForEach(availableFolders, id: \.self) { folder in
                Button(action: { selectedFolder = folder }) {
                    HStack {
                        Text(folder)
                        if selectedFolder == folder { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }
    
    private var clearFiltersSection: some View {
        Section {
            Button(action: {
                selectedStatusFilter = .all
                selectedFormType = "All Types"
                selectedUser = "All Users"
                selectedFolder = "All Folders"
            }) {
                HStack {
                    Image(systemName: "clear")
                    Text("Clear All Filters")
                }
            }
        }
    }

    // MARK: - View Content
    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(projectName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if isLoading {
                ProgressView("Loading submissions...")
                    .frame(maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                .frame(maxHeight: .infinity)
            } else if submissions.isEmpty {
                emptySubmissionsView
            } else if filteredSubmissions.isEmpty {
                noFilteredSubmissionsView
            } else {
                if currentDisplayMode == .table {
                    submissionTableView
                } else {
                    submissionListView
                }
            }
        }
    }

    private var submissionListView: some View {
        List {
            ForEach(filteredSubmissions, id: \.id) { submission in
                submissionListRowContent(submission)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        exportSubmissionPDF(submission, action: .share)
                    } label: {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)

                    Button {
                        exportSubmissionPDF(submission, action: .download)
                    } label: {
                        Label("Download PDF", systemImage: "arrow.down.doc")
                    }
                    .tint(.teal)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            fetchSubmissions(force: true)
        }
    }

    private var submissionTableView: some View {
        VStack(spacing: 0) {
            // Table Header
            FormListHeader()

            // Table Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredSubmissions, id: \.id) { submission in
                        submissionTableRowContent(submission)

                        // Separator line
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .refreshable {
                fetchSubmissions(force: true)
            }
        }
        .background(Color(.systemBackground))
    }

    private var emptySubmissionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No Submissions Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap the '+' button to create your first form submission.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noFilteredSubmissionsView: some View {
        EmptyStateView(message: "No submissions match your filters.")
    }

    @ViewBuilder
    private func submissionListRowContent(_ submission: FormSubmission) -> some View {
        if isSelectionMode {
            Button(action: {
                toggleSubmissionSelection(submission.id)
            }) {
                HStack(spacing: 10) {
                    SelectionIndicator(isSelected: selectedSubmissionIds.contains(submission.id))
                    SubmissionRow(
                        submission: submission,
                        statusColor: statusColor(for: submission),
                        statusText: statusText(for: submission)
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if submission.status.lowercased() == "awaiting_closeout" || submission.status.lowercased() == "draft" {
            Button(action: {
                openSubmissionForEditing(submission)
            }) {
                HStack {
                    SubmissionRow(
                        submission: submission,
                        statusColor: statusColor(for: submission),
                        statusText: statusText(for: submission)
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0.5) {
                enterSelectionMode(with: submission.id)
            }
        } else {
            NavigationLink(destination: FormSubmissionDetailView(
                submissionId: submission.id,
                projectId: projectId,
                token: token,
                projectName: projectName
            )) {
                SubmissionRow(
                    submission: submission,
                    statusColor: statusColor(for: submission),
                    statusText: statusText(for: submission)
                )
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                enterSelectionMode(with: submission.id)
            })
        }
    }

    @ViewBuilder
    private func submissionTableRowContent(_ submission: FormSubmission) -> some View {
        if isSelectionMode {
            Button(action: {
                toggleSubmissionSelection(submission.id)
            }) {
                HStack(spacing: 10) {
                    SelectionIndicator(isSelected: selectedSubmissionIds.contains(submission.id))
                        .padding(.leading, 12)
                    FormTableRow(
                        submission: submission,
                        statusColor: statusColor(for: submission),
                        statusText: statusText(for: submission)
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if submission.status.lowercased() == "awaiting_closeout" || submission.status.lowercased() == "draft" {
            Button(action: {
                openSubmissionForEditing(submission)
            }) {
                FormTableRow(
                    submission: submission,
                    statusColor: statusColor(for: submission),
                    statusText: statusText(for: submission)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0.5) {
                enterSelectionMode(with: submission.id)
            }
        } else {
            NavigationLink(destination: FormSubmissionDetailView(
                submissionId: submission.id,
                projectId: projectId,
                token: token,
                projectName: projectName
            )) {
                FormTableRow(
                    submission: submission,
                    statusColor: statusColor(for: submission),
                    statusText: statusText(for: submission)
                )
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                enterSelectionMode(with: submission.id)
            })
        }
    }

    private func openSubmissionForEditing(_ submission: FormSubmission) {
        Task {
            do {
                let forms = try await APIClient.fetchForms(projectId: projectId, token: token)
                if let matchingForm = forms.first(where: { $0.id == submission.templateId }) {
                    await MainActor.run {
                        draftToEdit = DraftEditData(submission: submission, form: matchingForm)
                    }
                }
            } catch {
                print("Error fetching form for editing: \(error)")
            }
        }
    }

    private func openDraftForEditing(_ submission: FormSubmission) {
        // We need to fetch the form template to know the structure
        Task {
            do {
                let forms = try await APIClient.fetchForms(projectId: projectId, token: token)
                if let matchingForm = forms.first(where: { $0.id == submission.templateId }) {
                    await MainActor.run {
                        draftToEdit = DraftEditData(submission: submission, form: matchingForm)
                    }
                }
            } catch {
                print("Error fetching form for draft editing: \(error)")
            }
        }
    }
    
    private func checkPermissions() {
        hasManageFormsPermission = sessionManager.hasPermission("manage_forms")
    }

    private func fetchSubmissions(force: Bool = false) {
        isLoading = true
        errorMessage = nil
        Task {
            // Check if we're offline and have cached data
            let isOfflineMode = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
            if isOfflineMode && !NetworkStatusManager.shared.isNetworkAvailable {
                // Load from cache when offline
                if let cachedSubmissions = loadFormSubmissionsFromCache() {
                    await MainActor.run {
                        submissions = cachedSubmissions
                        isLoading = false
                        print("FormsView: Loaded \(cachedSubmissions.count) form submissions from cache while offline")
                    }
                    return
                } else {
                    await MainActor.run {
                        errorMessage = "Offline: No cached form submissions available. Please enable offline mode and download the project while online."
                        isLoading = false
                    }
                    return
                }
            }
            
            // Try to fetch from network
            do {
                let fetchedSubmissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
                await MainActor.run {
                    submissions = fetchedSubmissions
                    isLoading = false
                }
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
                // If network fails, try to load from cache as fallback
                if let cachedSubmissions = loadFormSubmissionsFromCache() {
                    await MainActor.run {
                        submissions = cachedSubmissions
                        isLoading = false
                        print("FormsView: Network failed, loaded \(cachedSubmissions.count) form submissions from cache as fallback")
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to load submissions: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func loadFormSubmissionsFromCache() -> [FormSubmission]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("form_submissions_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL),
           let submissions = try? JSONDecoder().decode([FormSubmission].self, from: data) {
            return submissions
        }
        return nil
    }

    private func statusColor(for submission: FormSubmission) -> Color {
        let status = submission.status
        
        switch status.lowercased() {
        case "draft":
            return .gray
        case "submitted":
            return .blue
        case "awaiting_closeout":
            return .orange
        case "closeout_pending":
            return .yellow
        case "closeout_submitted":
            return .purple
        case "completed":
            return .green
        default:
            return .gray
        }
    }
    
    private func statusText(for submission: FormSubmission) -> String {
        let status = submission.status
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func findForm(for submission: FormSubmission) -> FormModel? {
        // Implement the logic to find the corresponding form for a given submission
        // This is a placeholder and should be replaced with the actual implementation
        return nil
    }

    private func enterSelectionMode(with submissionId: Int) {
        isSelectionMode = true
        selectedSubmissionIds = [submissionId]
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedSubmissionIds.removeAll()
    }

    private func toggleSubmissionSelection(_ submissionId: Int) {
        if selectedSubmissionIds.contains(submissionId) {
            selectedSubmissionIds.remove(submissionId)
            if selectedSubmissionIds.isEmpty {
                exitSelectionMode()
            }
        } else {
            selectedSubmissionIds.insert(submissionId)
        }
    }

    private func openDistributionSheet() {
        guard !selectedSubmissionIds.isEmpty else { return }
        isDistributingForms = true
        Task {
            do {
                let users = try await APIClient.fetchProjectUsers(projectId: projectId, token: token)
                await MainActor.run {
                    availableProjectUsers = users.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                    isDistributingForms = false
                    showDistributionSheet = true
                }
            } catch {
                await MainActor.run {
                    isDistributingForms = false
                    exportAlert = FormsExportAlert(
                        title: "Unable to load users",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func distributeSelectedSubmissions(to userIds: [Int], message: String?) {
        guard !selectedSubmissionIds.isEmpty else { return }
        isDistributingForms = true
        Task {
            do {
                let response = try await APIClient.distributeFormSubmissions(
                    submissionIds: Array(selectedSubmissionIds).sorted(),
                    userIds: userIds,
                    message: message,
                    token: token
                )
                await MainActor.run {
                    isDistributingForms = false
                    showDistributionSheet = false
                    let summary = """
                    Forms: \(response.totalSubmissions)
                    Recipients: \(response.totalRecipients)
                    Sent: \(response.sent)
                    Failed: \(response.failed)
                    """
                    exportAlert = FormsExportAlert(
                        title: response.failed == 0 ? "Distribution successful" : "Distribution finished with issues",
                        message: summary
                    )
                    let toastSummary = response.failed == 0
                        ? "Distributed to \(response.totalRecipients) user\(response.totalRecipients == 1 ? "" : "s")."
                        : "Distributed with issues: \(response.sent) sent, \(response.failed) failed."
                    presentDistributionToast(message: toastSummary)
                    exitSelectionMode()
                }
            } catch {
                await MainActor.run {
                    isDistributingForms = false
                    exportAlert = FormsExportAlert(
                        title: "Distribution failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func presentDistributionToast(message: String) {
        distributionToastMessage = message
        withAnimation {
            showDistributionToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showDistributionToast = false
            }
        }
    }

    private func exportSubmissionPDF(_ submission: FormSubmission, action: FormPDFAction) {
        isPreparingPDF = true
        Task {
            do {
                let tempPDF = try await APIClient.fetchFormSubmissionPDF(submissionId: submission.id, token: token)
                let filename = "Form-\(submission.id)-\(Int(Date().timeIntervalSince1970)).pdf"
                let destination = try saveSubmissionPDFToDownloads(tempPDFURL: tempPDF, filename: filename)
                await MainActor.run {
                    isPreparingPDF = false
                    switch action {
                    case .share:
                        shareSheetItem = ShareSheetItem(url: destination)
                    case .download:
                        exportAlert = FormsExportAlert(
                            title: "Download complete",
                            message: "Saved to \(destination.lastPathComponent)"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    isPreparingPDF = false
                    exportAlert = FormsExportAlert(
                        title: "PDF export failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func saveSubmissionPDFToDownloads(tempPDFURL: URL, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadDirectory = documentsDirectory.appendingPathComponent("Project_\(projectId)/shared_downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let destinationURL = downloadDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: tempPDFURL, to: destinationURL)
        return destinationURL
    }
}

private enum FormPDFAction {
    case share
    case download
}

private struct FormsExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.95))
        .clipShape(Capsule())
        .shadow(radius: 6)
    }
}

private struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
    }
}

private struct FormDistributionSheet: View {
    let users: [User]
    let selectedCount: Int
    let isDistributing: Bool
    let onDistribute: (_ userIds: [Int], _ message: String?) -> Void
    let onCancel: () -> Void

    @State private var selectedUserIds: Set<Int> = []
    @State private var message: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if users.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No project users found")
                            .font(.headline)
                        Text("Add users to this project before distributing forms.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Select Users") {
                            ForEach(users, id: \.id) { user in
                                Button(action: {
                                    toggleSelection(for: user.id)
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                                .foregroundColor(.primary)
                                            if let email = user.email, !email.isEmpty {
                                                Text(email)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        SelectionIndicator(isSelected: selectedUserIds.contains(user.id))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Section("Message (Optional)") {
                            TextEditor(text: $message)
                                .frame(minHeight: 100)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Distribute \(selectedCount) Form\(selectedCount == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Distribute") {
                        onDistribute(Array(selectedUserIds).sorted(), message)
                    }
                    .disabled(selectedUserIds.isEmpty || isDistributing)
                }
            }
        }
    }

    private func toggleSelection(for id: Int) {
        if selectedUserIds.contains(id) {
            selectedUserIds.remove(id)
        } else {
            selectedUserIds.insert(id)
        }
    }
}

// Improved Header
struct FormListHeader: View {
    var body: some View {
        HStack {
            Text("Reference")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text("Form")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Folder")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text("Location")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text("Status")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text("Date")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text("Submitted By")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// Card-based design for each submission
struct FormSubmissionCard: View {
    let submission: FormSubmission
    let statusColor: Color
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Reference as primary
                    Text(submission.reference != nil && !submission.reference!.isEmpty ? submission.reference! : "—")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    // Form type as secondary (truncates when long)
                    Text(submission.templateTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text("Ref: #\(submission.formNumber ?? String(submission.id))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(submission.versionNumber != nil ? "v\(submission.versionNumber!)" : "Current")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.teal)
                    }
                }
                Spacer()
                statusView
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(submission.submittedAt.toShortDate())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName.prefix(1)).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let location = submission.projectLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private var statusView: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }

}

// Table row for form submissions
struct FormTableRow: View {
    let submission: FormSubmission
    let statusColor: Color
    let statusText: String

    var body: some View {
        HStack {
            // Reference (primary – fixed width so always visible)
            Text(submission.reference != nil && !submission.reference!.isEmpty ? submission.reference! : "—")
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 120, alignment: .leading)

            // Form type (secondary – takes remaining space, truncates when long)
            Text(submission.templateTitle)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Folder
            Text(submission.folder?.name ?? (submission.folderId != nil ? "Folder #\(submission.folderId!)" : "—"))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            // Location
            Text(submission.projectLocation?.name ?? "—")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            // Status
            Text(statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .foregroundColor(statusColor)
                .cornerRadius(6)
                .frame(width: 100, alignment: .leading)

            // Date
            Text(submission.submittedAt.toShortDate())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            // Submitted By
            Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// Improved status badge
struct StatusBadge: View {
    let status: String
    
    private var statusColor: Color {
        switch status.lowercased() {
        case "submitted": return .blue
        case "draft": return .orange
        case "approved": return .green
        case "rejected": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(6)
    }
}

//struct FormsView_Previews: PreviewProvider {
//    static var previews: some View {
//        NavigationView {
//            FormsView(projectId: 1, token: "sample_token", projectName: "Sample Project Name")
//                .environmentObject(SessionManager.preview())
//        }
//    }
//}

extension SessionManager {
    static func preview() -> SessionManager {
        let manager = SessionManager()
        return manager
    }
}

extension String {
    func toShortDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd/MM/yy"
            return displayFormatter.string(from: date)
        }
        return self
    }
}

// MARK: - Submission Row
private struct SubmissionRow: View {
    let submission: FormSubmission
    let statusColor: Color
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Reference as primary (always visible)
                    Text(submission.reference != nil && !submission.reference!.isEmpty ? submission.reference! : "—")
                        .font(.headline)
                        .lineLimit(1)
                    // Form type as secondary (truncates when long)
                    Text(submission.templateTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 6) {
                        if let folderName = submission.folder?.name ?? (submission.folderId != nil ? "Folder #\(submission.folderId!)" : nil) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            Text(folderName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("#\(submission.formNumber ?? String(submission.id))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(submission.versionNumber != nil ? "v\(submission.versionNumber!)" : "Current")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                statusView
            }

            // Submission info row
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(submission.submittedAt.toShortDate())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName.prefix(1)).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let location = submission.projectLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(location.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var statusView: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
