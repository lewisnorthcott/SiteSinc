import Foundation
import SwiftUI
import SwiftData

struct LogsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var logs: [Log] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .number
    @State private var filterOption: FilterOption = .all
    @State private var showCreateLog = false
    @State private var isRefreshing = false

    enum SortOption: String, CaseIterable, Identifiable {
        case number = "Number"
        case date = "Date"
        case title = "Title"
        case status = "Status"
        case priority = "Priority"
        var id: String { rawValue }
    }
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case open = "Open"
        case closed = "Closed"
        case pending = "Pending"
        case assigned = "Assigned to Me"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            if isLoading && logs.isEmpty {
                loadingView
            } else {
                mainContent
            }
            
            if let errorMessage = errorMessage {
                errorView(errorMessage)
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search logs...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    
                    Picker("Filter", selection: $filterOption) {
                        ForEach(FilterOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.accentColor)
                }
                
                if canCreateLogs {
                    Button {
                        showCreateLog = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .refreshable {
            await refreshLogs()
        }
        .onAppear {
            loadLogs()
        }
        .sheet(isPresented: $showCreateLog) {
            CreateLogView(
                projectId: projectId,
                token: sessionManager.token ?? token,
                projectName: projectName,
                onSuccess: {
                    showCreateLog = false
                    loadLogs()
                }
            )
            .environmentObject(sessionManager)
        }
    }
    
    private var canCreateLogs: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("create_logs") || permissions.contains("manage_all_logs")
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            Text("Loading logs...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            if logs.isEmpty && !isLoading {
                emptyStateView
            } else {
                logsList
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No logs found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Create your first log to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if canCreateLogs {
                Button {
                    showCreateLog = true
                } label: {
                    Label("Create Log", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
        }
        .padding(40)
    }
    
    private var logsList: some View {
        List {
            ForEach(filteredAndSortedLogs) { log in
                NavigationLink(
                    destination: LogDetailView(
                        log: log,
                        token: sessionManager.token ?? token,
                        onRefresh: { loadLogs() }
                    )
                    .environmentObject(sessionManager)
                ) {
                    LogRowView(log: log)
                }
                .listRowBackground(Color(.systemBackground))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(PlainListStyle())
        .background(Color(.systemGroupedBackground))
    }
    
    private var filteredAndSortedLogs: [Log] {
        var filtered = logs
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { log in
                (log.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (log.description?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                String(log.number).contains(searchText) ||
                (log.assignee?.displayName.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (log.createdBy?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply status filter
        switch filterOption {
        case .all:
            break
        case .open:
            filtered = filtered.filter { log in
                guard let statusName = log.status?.name.lowercased() else { return true }
                return !["closed", "completed", "resolved"].contains(statusName)
            }
        case .closed:
            filtered = filtered.filter { log in
                guard let statusName = log.status?.name.lowercased() else { return false }
                return ["closed", "completed", "resolved"].contains(statusName)
            }
        case .pending:
            filtered = filtered.filter { log in
                log.status?.name.lowercased() == "pending"
            }
        case .assigned:
            let currentUserId = sessionManager.user?.id
            filtered = filtered.filter { log in
                log.assigneeId == currentUserId ||
                log.distributions?.contains(where: { $0.userId == currentUserId }) == true
            }
        }
        
        // Apply sorting
        switch sortOption {
        case .number:
            filtered.sort { $0.number > $1.number }
        case .date:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .title:
            filtered.sort { ($0.title ?? "") < ($1.title ?? "") }
        case .status:
            filtered.sort { ($0.status?.name ?? "") < ($1.status?.name ?? "") }
        case .priority:
            filtered.sort { ($0.logPriority?.order ?? 0) < ($1.logPriority?.order ?? 0) }
        }
        
        return filtered
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text(message)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                errorMessage = nil
                loadLogs()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
    }
    
    private func loadLogs() {
        guard !isRefreshing else { return }
        
        Task {
            await MainActor.run {
                if logs.isEmpty {
                    isLoading = true
                }
                errorMessage = nil
            }
            
            do {
                let fetchedLogs = try await APIClient.fetchLogs(
                    projectId: projectId,
                    token: sessionManager.token ?? token
                )
                
                await MainActor.run {
                    self.logs = fetchedLogs
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to view logs."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                self.errorMessage = "Logs feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Server error (\(statusCode)). Please try again."
                            }
                        case .networkError(let networkError):
                            self.errorMessage = "Network error: \(networkError.localizedDescription)"
                        case .decodingError(let decodingError):
                            self.errorMessage = "Data parsing error: \(decodingError.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Failed to load logs: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func refreshLogs() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let fetchedLogs = try await APIClient.fetchLogs(
                projectId: projectId,
                token: sessionManager.token ?? token
            )
            
            await MainActor.run {
                self.logs = fetchedLogs
            }
        } catch {
            await MainActor.run {
                if let apiError = error as? APIError {
                    switch apiError {
                    case .tokenExpired:
                        self.errorMessage = "Session expired. Please log in again."
                    case .forbidden:
                        self.errorMessage = "You don't have permission to view logs."
                    case .invalidResponse(let statusCode):
                        if statusCode == 404 {
                            self.errorMessage = "Logs feature is not yet available on the server."
                        } else {
                            self.errorMessage = "Failed to refresh logs: \(error.localizedDescription)"
                        }
                    default:
                        self.errorMessage = "Failed to refresh logs: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

struct LogRowView: View {
    let log: Log
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with number and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log #\(log.number)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let title = log.title {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let status = log.status {
                        LogStatusBadge(status: status)
                    }
                    
                    if let priority = log.logPriority {
                        PriorityBadge(priority: priority)
                    }
                }
            }
            
            // Details row
            HStack(spacing: 16) {
                if let assignee = log.assignee {
                    DetailItem(icon: "person.fill", text: assignee.displayName, color: .blue)
                }
                
                if let type = log.type {
                    DetailItem(icon: "tag.fill", text: type.name, color: .orange)
                }
                
                if let trade = log.trade {
                    DetailItem(icon: "hammer.fill", text: trade.name, color: .purple)
                }
                
                Spacer()
                
                Text(formatDate(log.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Safety indicators
            if log.hazard != nil || log.contributingCondition != nil || log.contributingBehaviour != nil {
                HStack(spacing: 8) {
                    if let hazard = log.hazard {
                        SafetyBadge(text: hazard.name, color: .red)
                    }
                    
                    if let condition = log.contributingCondition {
                        SafetyBadge(text: condition.name, color: .orange)
                    }
                    
                    if let behaviour = log.contributingBehaviour {
                        SafetyBadge(text: behaviour.name, color: .yellow)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, yyyy"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// LogStatusBadge and PriorityBadge are defined in LogDetailView.swift to be shared across log views.

struct SafetyBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
}

struct DetailItem: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

