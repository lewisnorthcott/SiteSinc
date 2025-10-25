import SwiftUI
import WebKit

struct LogDetailView: View {
    let log: Log
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentLog: Log
    @State private var responseText = ""
    @State private var isSubmittingResponse = false
    @State private var responses: [Log.ResponseItem] = []
    @State private var isLoadingResponses = false
    @State private var errorMessage: String?
    @State private var showEditLog = false
    
    // Use current token from session manager to avoid stale token issues
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    // Permission checks
    private var canEditLog: Bool {
        // Add your edit permission logic here
        return true // For now, allow editing
    }
    
    private var canRespondToLog: Bool {
        // User can respond if they are assigned OR have manage_all_logs permission
        guard let currentUser = sessionManager.user else { return false }
        let isAssignee = currentLog.assignee?.id == currentUser.id
        let hasManageAllLogs = currentUser.permissions?.contains { $0.name == "manage_all_logs" } ?? false
        return isAssignee || hasManageAllLogs
    }
    
    private var canAcceptResponse: Bool {
        // Creator or users with manage_all_logs permission can accept responses
        guard let currentUser = sessionManager.user else { return false }
        let isLogCreator = currentLog.createdById == currentUser.id
        let hasManageAllLogs = currentUser.permissions?.contains { $0.name == "manage_all_logs" } ?? false
        return isLogCreator || hasManageAllLogs
    }
    
    init(log: Log, token: String, onRefresh: (() -> Void)?) {
        self.log = log
        self.token = token
        self.onRefresh = onRefresh
        self._currentLog = State(initialValue: log)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                
                if let description = currentLog.description {
                    descriptionSection(description)
                }
                
                detailsSection
                
                if !safetyItems.isEmpty {
                    safetySection
                }
                
                if let assignee = currentLog.assignee {
                    assignmentSection(assignee)
                }
                
                if let distributions = currentLog.distributions, !distributions.isEmpty {
                    distributionSection(distributions)
                }
                
                if let attachments = currentLog.attachments, !attachments.isEmpty {
                    attachmentsSection(attachments)
                }
                
                responsesSection
                
                if canRespondToLog {
                    responseInputSection
                }
            }
            .padding(16)
        }
        .navigationTitle("Log #\(currentLog.number)")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Edit button temporarily hidden
                // if canEditLog {
                //     Button("Edit") {
                //         showEditLog = true
                //     }
                //     .foregroundColor(.accentColor)
                // }
            }
        }
        .onAppear {
            loadResponses()
        }
        .sheet(isPresented: $showEditLog) {
            CreateLogView(
                projectId: currentLog.projectId,
                token: currentToken,
                projectName: "",
                editingLog: currentLog,
                onSuccess: {
                    showEditLog = false
                    refreshLogData()
                }
            )
            .environmentObject(sessionManager)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = currentLog.title {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    if let createdBy = currentLog.createdBy {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.secondary)
                            Text("Created by \(createdBy.displayName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Created: \(formatDate(currentLog.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    if let status = currentLog.status {
                        LogStatusBadge(status: status)
                    }
                    
                    if let priority = currentLog.logPriority {
                        PriorityBadge(priority: priority)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if let type = currentLog.type {
                    DetailRow(label: "Type", value: type.name, icon: "tag.fill")
                }
                
                if let trade = currentLog.trade {
                    DetailRow(label: "Trade", value: trade.name, icon: "hammer.fill")
                }
                
                if let location = currentLog.location {
                    DetailRow(label: "Location", value: location, icon: "location.fill")
                }
                
                if let specification = currentLog.specification {
                    DetailRow(label: "Specification", value: specification, icon: "doc.text.fill")
                }
                
                if let dueDate = currentLog.dueDate {
                    DetailRow(label: "Due Date", value: formatDate(dueDate), icon: "calendar.fill")
                }
                
                DetailRow(label: "Private", value: currentLog.isPrivate ? "Yes" : "No", icon: "eye.slash.fill")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var safetyItems: [(String, String, Color)] {
        var items: [(String, String, Color)] = []
        
        if let hazard = currentLog.hazard {
            items.append(("Hazard", hazard.name, .red))
        }
        
        if let condition = currentLog.contributingCondition {
            items.append(("Contributing Condition", condition.name, .orange))
        }
        
        if let behaviour = currentLog.contributingBehaviour {
            items.append(("Contributing Behaviour", behaviour.name, .yellow))
        }
        
        return items
    }
    
    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(safetyItems, id: \.0) { item in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(item.2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.1)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func assignmentSection(_ assignee: Log.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assigned To")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignee.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let companyName = assignee.companyName {
                        Text(companyName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func distributionSection(_ distributions: [Log.LogDistribution]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribution List")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                // Use a stable composite key since distribution.id can be missing in some payloads
                ForEach(distributions, id: \.userId) { distribution in
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(distribution.user.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            if let companyName = distribution.user.companyName {
                                Text(companyName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func attachmentsSection(_ attachments: [Log.LogAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments, id: \.id) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: fileIcon(for: attachment.fileType))
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Text(attachment.fileType.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Download") {
                            // TODO: Implement download functionality
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    
    private func fileIcon(for fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return "photo.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        default:
            return "paperclip"
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func loadResponses() {
        guard !isLoadingResponses else { return }
        
        Task {
            await MainActor.run {
                isLoadingResponses = true
            }
            
            do {
                let fetchedResponses = try await APIClient.fetchLogResponses(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responses = fetchedResponses.sorted { $0.createdAt > $1.createdAt }
                    self.isLoadingResponses = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingResponses = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to view responses."
                        default:
                            self.errorMessage = "Failed to load responses: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func submitResponse() {
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await MainActor.run {
                isSubmittingResponse = true
            }
            
            do {
                try await APIClient.submitLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    response: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responseText = ""
                    self.isSubmittingResponse = false
                    self.loadResponses()
                }
            } catch {
                await MainActor.run {
                    self.isSubmittingResponse = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to respond to this log."
                        default:
                            self.errorMessage = "Failed to submit response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func refreshLogData() {
        onRefresh?()
    }
    
    // MARK: - Response Sections
    
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Responses")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !responses.isEmpty {
                    Text("\(responses.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Spacer()
            }
            
            if isLoadingResponses {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading responses...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if responses.isEmpty {
                Text("No responses yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(responses, id: \.id) { response in
                        ResponseRowView(
                            response: response,
                            canAccept: canAcceptResponse && !response.accepted,
                            onAccept: {
                                acceptResponse(response.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var responseInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Submit Response")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Response")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextEditor(text: $responseText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                
                HStack(spacing: 12) {
                    Button(action: {
                        submitResponse(accepted: true)
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Accept & Close Log")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingResponse)
                    
                    Button(action: {
                        submitResponse(accepted: false)
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Submit Response Only")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                    }
                    .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingResponse)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func submitResponse(accepted: Bool) {
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await MainActor.run {
                isSubmittingResponse = true
            }
            
            do {
                try await APIClient.submitLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    response: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                    accepted: accepted,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responseText = ""
                    self.isSubmittingResponse = false
                    self.loadResponses()
                    self.refreshLogData()
                }
            } catch {
                await MainActor.run {
                    self.isSubmittingResponse = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to respond to this log."
                        default:
                            self.errorMessage = "Failed to submit response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func acceptResponse(_ responseId: Int) {
        Task {
            do {
                try await APIClient.acceptLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    responseId: responseId,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.loadResponses()
                    self.refreshLogData()
                }
            } catch {
                await MainActor.run {
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to accept responses."
                        default:
                            self.errorMessage = "Failed to accept response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ResponseRowView: View {
    let response: Log.ResponseItem
    let canAccept: Bool
    let onAccept: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(response.user.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let companyName = response.user.companyName {
                        Text(companyName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatResponseDate(response.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if response.accepted {
                        Text("ACCEPTED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if canAccept {
                        Button(action: onAccept) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("Accept")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            Text(response.response)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatResponseDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct LogStatusBadge: View {
    let status: Log.LogStatus
    
    var body: some View {
        Text(status.name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: status.color ?? "#64748B"))
            .cornerRadius(6)
    }
}

struct PriorityBadge: View {
    let priority: Log.LogPriority
    
    var body: some View {
        Text(priority.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: priority.color ?? "#64748B"))
            .cornerRadius(4)
    }
}

// Color(hex:) extension lives elsewhere in the project; avoid redefining here to prevent ambiguity.
