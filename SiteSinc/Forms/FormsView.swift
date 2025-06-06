import SwiftUI

// Wrapper for Int to conform to Identifiable
struct FormID: Identifiable {
    let id: Int
}

enum SubmissionStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case submitted = "Submitted"
    // Add other statuses if they exist and you want to filter by them

    var id: String { self.rawValue }
}

struct FormsView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var submissions: [FormSubmission] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFormTemplates = false
    @State private var selectedFormId: FormID?
    @State private var showCreateForm = false
    @State private var hasManageFormsPermission: Bool = false
    @State private var formToCreate: FormModel?
    
    // State for Search and Filter
    @State private var searchText: String = ""
    @State private var selectedStatusFilter: SubmissionStatusFilter = .all
    @State private var selectedFormType: String = "All Types" // New form type filter
    @State private var selectedUser: String = "All Users"

    // Simplified filtered submissions (no grouping by template)
    private var filteredSubmissions: [FormSubmission] {
        var filtered = submissions

        // 1. Filter by status
        if selectedStatusFilter != .all {
            filtered = filtered.filter { $0.status.lowercased() == selectedStatusFilter.rawValue.lowercased() }
        }

        // 2. Filter by form type
        if selectedFormType != "All Types" {
            filtered = filtered.filter { $0.templateTitle == selectedFormType }
        }

        // 3. Filter by user
        if selectedUser != "All Users" {
            filtered = filtered.filter { "\($0.submittedBy.firstName) \($0.submittedBy.lastName)" == selectedUser }
        }

        // 4. Filter by search text
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
                }
            }
            filtered = searchFiltered
        }
        
        // 5. Sort by most recent first
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

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .navigationTitle("Forms - \(projectName)")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search forms...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    statusFilterSection
                    formTypeFilterSection
                    userFilterSection
                    clearFiltersSection
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                
                if hasManageFormsPermission {
                    Button(action: {
                        showingFormTemplates = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .onAppear {
            if submissions.isEmpty {
                fetchSubmissions()
            }
            checkPermissions()
        }
        .sheet(isPresented: $showingFormTemplates) {
            FormTemplateSelectionView(projectId: projectId, token: token) { form in
                self.formToCreate = form
            }
        }
        .fullScreenCover(item: $formToCreate) { form in
            FormSubmissionCreateView(
                form: form,
                projectId: projectId,
                token: token
            )
        }
    }

    // MARK: - Menu Sections
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
    
    private var clearFiltersSection: some View {
        Section {
            Button(action: {
                selectedStatusFilter = .all
                selectedFormType = "All Types"
                selectedUser = "All Users"
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
        if isLoading {
            loadingView
        } else if let errorMessage = errorMessage {
            errorView(for: errorMessage)
        } else if submissions.isEmpty {
            emptySubmissionsView
        } else if filteredSubmissions.isEmpty {
            noFilteredSubmissionsView
        } else {
            submissionListView
        }
    }

    // MARK: - View Components
    private var loadingView: some View {
        ProgressView("Loading forms...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(for message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                fetchSubmissions()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySubmissionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No form submissions found")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Create your first form submission to get started")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noFilteredSubmissionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No submissions match your filters")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Try adjusting your search or filter criteria")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var submissionListView: some View {
        VStack(spacing: 0) {
            FormListHeader()
            
            List {
                ForEach(filteredSubmissions) { submission in
                    NavigationLink(destination: FormSubmissionDetailView(submissionId: submission.id, projectId: projectId, token: token, projectName: projectName)) {
                        FormSubmissionCard(submission: submission)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .refreshable {
                fetchSubmissions()
            }
        }
    }

    private func checkPermissions() {
        hasManageFormsPermission = sessionManager.hasPermission("manage_forms")
    }

    private func fetchSubmissions() {
        isLoading = true
        errorMessage = nil
        Task {
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
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load submissions: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// Improved Header
struct FormListHeader: View {
    var body: some View {
        HStack {
            Text("Form")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Status")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text("Date")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text("By")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// Card-based design for each submission
struct FormSubmissionCard: View {
    let submission: FormSubmission

    var body: some View {
        HStack(spacing: 12) {
            // Form Type & Number
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.templateTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let formNumber = submission.formNumber, !formNumber.isEmpty {
                    Text("#\(formNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status
            StatusBadge(status: submission.status)
                .frame(width: 80, alignment: .leading)
            
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(submission.submittedAt))
                    .font(.callout)
                    .foregroundColor(.primary)
            }
            .frame(width: 90, alignment: .leading)
            
            // Submitted By
            VStack(alignment: .leading, spacing: 2) {
                Text("\(submission.submittedBy.firstName)")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("\(submission.submittedBy.lastName.prefix(1)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd/MM/yy"
            return displayFormatter.string(from: date)
        }
        return dateString
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
