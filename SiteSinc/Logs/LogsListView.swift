import Foundation
import SwiftUI
import SwiftData

struct LogsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineLogManager.shared
    @State private var logs: [Log] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .number
    @State private var filterOption: FilterOption = .all
    @State private var showCreateLog = false
    @State private var isRefreshing = false
    @State private var isUsingCachedData = false
    @State private var cacheAge: Date?
    @State private var showPendingLogs = false

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
            
            if let errorMessage = errorMessage, !isUsingCachedData {
                errorView(errorMessage)
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search logs...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Pending logs indicator
                if offlineManager.pendingLogsCount > 0 {
                    Button {
                        showPendingLogs = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("\(offlineManager.pendingLogsCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.orange)
                    }
                }
                
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
        .sheet(isPresented: $showPendingLogs) {
            PendingLogsView()
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
            // Offline/Cache indicator banner
            if offlineManager.isOffline || isUsingCachedData {
                offlineBanner
            }
            
            // Pending sync banner
            if offlineManager.totalPendingCount > 0 && !offlineManager.isOffline {
                pendingSyncBanner
            }
            
            if logs.isEmpty && !isLoading {
                emptyStateView
            } else {
                logsList
            }
        }
    }
    
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: offlineManager.isOffline ? "wifi.slash" : "clock")
                .font(.caption)
            
            if offlineManager.isOffline {
                Text("Offline Mode")
                    .font(.caption)
                    .fontWeight(.medium)
                if isUsingCachedData, let age = cacheAge {
                    Text("• Showing cached data from \(formatCacheAge(age))")
                        .font(.caption)
                }
            } else if isUsingCachedData, let age = cacheAge {
                Text("Showing cached data from \(formatCacheAge(age))")
                    .font(.caption)
            }
            
            Spacer()
            
            if !offlineManager.isOffline && isUsingCachedData {
                Button("Refresh") {
                    loadLogs()
                }
                .font(.caption)
                .fontWeight(.medium)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(offlineManager.isOffline ? Color.orange : Color.blue)
    }
    
    private var pendingSyncBanner: some View {
        HStack(spacing: 8) {
            if offlineManager.syncInProgress {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text("Syncing \(offlineManager.totalPendingCount) item(s)...")
                    .font(.caption)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                Text("\(offlineManager.totalPendingCount) item(s) waiting to sync")
                    .font(.caption)
                
                Spacer()
                
                Button("Sync Now") {
                    offlineManager.manualSync()
                }
                .font(.caption)
                .fontWeight(.medium)
            }
            
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green)
    }
    
    private func formatCacheAge(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
                
                // Cache the logs for offline use
                offlineManager.cacheLogs(fetchedLogs, forProject: projectId)
                
                await MainActor.run {
                    self.logs = fetchedLogs
                    self.isLoading = false
                    self.isUsingCachedData = false
                    self.cacheAge = nil
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    
                    // Try to load from cache on network error
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .networkError:
                            loadFromCache()
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to view logs."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                self.errorMessage = "Logs feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Server error (\(statusCode)). Please try again."
                                loadFromCache()
                            }
                        case .decodingError(let decodingError):
                            self.errorMessage = "Data parsing error: \(decodingError.localizedDescription)"
                        }
                    } else {
                        // Generic error - try cache
                        loadFromCache()
                    }
                }
            }
        }
    }
    
    private func loadFromCache() {
        if let cachedLogs = offlineManager.getCachedLogs(forProject: projectId) {
            self.logs = cachedLogs
            self.isUsingCachedData = true
            self.cacheAge = offlineManager.getCacheAge(forProject: projectId)
            self.errorMessage = nil
            print("LogsListView: Loaded \(cachedLogs.count) logs from cache")
        } else {
            self.errorMessage = "No cached data available. Please connect to the internet."
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
            
            // Cache the logs for offline use
            offlineManager.cacheLogs(fetchedLogs, forProject: projectId)
            
            await MainActor.run {
                self.logs = fetchedLogs
                self.isUsingCachedData = false
                self.cacheAge = nil
            }
        } catch {
            await MainActor.run {
                if let apiError = error as? APIError {
                    switch apiError {
                    case .networkError:
                        // Don't show error if we have cached data
                        if !isUsingCachedData {
                            loadFromCache()
                        }
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

// MARK: - Pending Logs View

struct PendingLogsView: View {
    @StateObject private var offlineManager = OfflineLogManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if offlineManager.pendingLogs.isEmpty && offlineManager.pendingResponses.isEmpty {
                    ContentUnavailableView(
                        "No Pending Items",
                        systemImage: "checkmark.circle",
                        description: Text("All items have been synced")
                    )
                } else {
                    if !offlineManager.pendingLogs.isEmpty {
                        Section("Pending Logs") {
                            ForEach(offlineManager.pendingLogs) { log in
                                PendingLogRow(log: log)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    offlineManager.deletePendingLog(offlineManager.pendingLogs[index])
                                }
                            }
                        }
                    }
                    
                    if !offlineManager.pendingResponses.isEmpty {
                        Section("Pending Responses") {
                            ForEach(offlineManager.pendingResponses) { response in
                                PendingResponseRow(response: response)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    offlineManager.deletePendingResponse(offlineManager.pendingResponses[index])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pending Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if offlineManager.totalPendingCount > 0 {
                        Button {
                            offlineManager.manualSync()
                        } label: {
                            if offlineManager.syncInProgress {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(offlineManager.syncInProgress || offlineManager.isOffline)
                    }
                }
            }
            
            if let error = offlineManager.lastSyncError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
}

struct PendingLogRow: View {
    let log: OfflineLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(log.title)
                .font(.headline)
            
            if let description = log.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Created \(log.createdAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let attachments = log.attachments, !attachments.isEmpty {
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "paperclip")
                        Text("\(attachments.count)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PendingResponseRow: View {
    let response: OfflineLogResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Response for Log #\(response.logId)")
                    .font(.headline)
                
                if response.accepted {
                    Text("ACCEPTED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(4)
                }
            }
            
            Text(response.response)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Created \(response.createdAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if !response.photos.isEmpty {
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "photo")
                        Text("\(response.photos.count)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct LogRowView: View {
    let log: Log
    
    private var isOverdue: Bool {
        guard let dueDateString = log.dueDate else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let dueDate = formatter.date(from: dueDateString) else { return false }
        return dueDate < Date() && !(log.status?.name.lowercased().contains("closed") ?? false)
    }
    
    private var attachmentCount: Int {
        log.attachments?.count ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with number, title and status badges
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Log #\(log.number)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        // Attachment indicator
                        if attachmentCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                Text("\(attachmentCount)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                        }
                    }
                    
                    if let title = log.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.primary.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    if let status = log.status {
                        LogStatusBadge(status: status)
                    }
                    
                    if let priority = log.logPriority {
                        PriorityBadge(priority: priority)
                    }
                }
            }
            
            // Meta info row
            HStack(spacing: 12) {
                if let assignee = log.assignee {
                    DetailItem(icon: "person.fill", text: assignee.displayName, color: .blue)
                }
                
                if let type = log.type {
                    // Truncate long type names
                    let typeName = type.name.count > 20 ? String(type.name.prefix(18)) + "..." : type.name
                    DetailItem(icon: "tag.fill", text: typeName, color: .orange)
                }
                
                if let trade = log.trade {
                    DetailItem(icon: "hammer.fill", text: trade.name, color: .purple)
                }
            }
            
            // Due date and created date row
            HStack {
                if let dueDateString = log.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                            .font(.caption)
                            .foregroundColor(isOverdue ? .red : .secondary)
                        
                        Text("Due: \(formatDate(dueDateString))")
                            .font(.caption)
                            .fontWeight(isOverdue ? .semibold : .regular)
                            .foregroundColor(isOverdue ? .red : .secondary)
                    }
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isOverdue ? Color.red.opacity(0.3) : Color.clear, lineWidth: 2)
        )
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

