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
    
    // State for Search and Filter
    @State private var searchText: String = ""
    @State private var selectedStatusFilter: SubmissionStatusFilter = .all
    @State private var selectedFormType: String = "All Types" // New form type filter

    // Simplified filtered submissions (no grouping by template)
    private var filteredSubmissions: [FormSubmission] {
        // 1. Filter by status
        let statusFilteredSubmissions: [FormSubmission]
        if selectedStatusFilter == .all {
            statusFilteredSubmissions = submissions
        } else {
            statusFilteredSubmissions = submissions.filter { $0.status.lowercased() == selectedStatusFilter.rawValue.lowercased() }
        }

        // 2. Filter by form type
        let formTypeFilteredSubmissions: [FormSubmission]
        if selectedFormType == "All Types" {
            formTypeFilteredSubmissions = statusFilteredSubmissions
        } else {
            formTypeFilteredSubmissions = statusFilteredSubmissions.filter { $0.templateTitle == selectedFormType }
        }

        // 3. Filter by search text
        let searchFilteredSubmissions: [FormSubmission]
        if searchText.isEmpty {
            searchFilteredSubmissions = formTypeFilteredSubmissions
        } else {
            let lowercasedSearchText = searchText.lowercased()
            searchFilteredSubmissions = formTypeFilteredSubmissions.filter { submission in
                return submission.templateTitle.lowercased().contains(lowercasedSearchText) ||
                       "\(submission.id)".contains(lowercasedSearchText) ||
                       submission.status.lowercased().contains(lowercasedSearchText) ||
                       submission.submittedBy.firstName.lowercased().contains(lowercasedSearchText) ||
                       submission.submittedBy.lastName.lowercased().contains(lowercasedSearchText)
            }
        }
        
        // 4. Sort by most recent first
        return searchFilteredSubmissions.sorted { $0.submittedAt > $1.submittedAt }
    }

    // Computed property to get unique form types from submissions
    private var availableFormTypes: [String] {
        let uniqueTypes = Array(Set(submissions.map { $0.templateTitle })).sorted()
        return ["All Types"] + uniqueTypes
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading forms...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        fetchSubmissions()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if submissions.isEmpty {
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
            } else if filteredSubmissions.isEmpty {
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
            } else {
                // Header
                FormListHeader()
                
                // List
                List {
                    ForEach(Array(filteredSubmissions.enumerated()), id: \.element.id) { index, submission in
                        FormSubmissionCard(
                            submission: submission,
                            projectId: projectId,
                            token: token,
                            projectName: projectName
                        )
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
        .navigationTitle("Forms - \(projectName)")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search forms...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    // Status Filter Section
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
                    
                    // Form Type Filter Section
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
                    
                    // Clear All Filters
                    Section {
                        Button(action: {
                            selectedStatusFilter = .all
                            selectedFormType = "All Types"
                        }) {
                            HStack {
                                Image(systemName: "clear")
                                Text("Clear All Filters")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                
                Button(action: {
                    showingFormTemplates = true
                }) {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .onAppear {
            if submissions.isEmpty {
                fetchSubmissions()
            }
        }
        .sheet(isPresented: $showingFormTemplates) {
            FormTemplateSelectionView(projectId: projectId, token: token) { formId in
                selectedFormId = FormID(id: formId)
                showingFormTemplates = false
            }
        }
        .sheet(item: $selectedFormId) { formIdItem in
            FormSubmissionCreateView(formId: formIdItem.id, projectId: projectId, token: token)
                .onDisappear {
                    selectedFormId = nil
                    fetchSubmissions()
                }
        }
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
            Text("Form Type")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Form #")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)
            
            Text("Status")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text("Date")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 90, alignment: .leading)
            
            Text("By")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text("")
                .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }
}

// Card-based design for each submission
struct FormSubmissionCard: View {
    let submission: FormSubmission
    let projectId: Int
    let token: String
    let projectName: String

    var body: some View {
        HStack(spacing: 12) {
            // Form Type
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.templateTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Form Number
            Text(submission.formNumber ?? "-")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
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
            
            // Action
            NavigationLink(destination: FormSubmissionDetailView(submissionId: submission.id, projectId: projectId, token: token, projectName: projectName)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 40, alignment: .center)
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

struct FormsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FormsView(projectId: 1, token: "sample_token", projectName: "Sample Project Name")
                .environmentObject(SessionManager.preview())
        }
    }
}

extension SessionManager {
    static func preview() -> SessionManager {
        let manager = SessionManager()
        return manager
    }
}
