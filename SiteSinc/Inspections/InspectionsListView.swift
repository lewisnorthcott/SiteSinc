import Foundation
import SwiftUI

struct InspectionsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineInspectionManager.shared
    @State private var inspections: [Inspection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .number
    @State private var filterOption: FilterOption = .all
    @State private var showCreateInspection = false
    @State private var isRefreshing = false
    @State private var isUsingCachedData = false
    @State private var cacheAge: Date?
    @State private var showPendingInspections = false
    @State private var isReauthInProgress = false

    enum SortOption: String, CaseIterable, Identifiable {
        case number = "Number"
        case date = "Date"
        case status = "Status"
        case location = "Location"
        var id: String { rawValue }
    }
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case notStarted = "Not Started"
        case inProgress = "In Progress"
        case completed = "Completed"
        case failed = "Failed"
        case assigned = "Assigned to Me"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            BrandChrome.groupedBackground.ignoresSafeArea()
            
            if isLoading && inspections.isEmpty {
                loadingView
            } else {
                mainContent
            }
            
            if let errorMessage = errorMessage, !isUsingCachedData {
                errorView(errorMessage)
            }
        }
        .navigationTitle("Inspections")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search inspections...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Pending inspections indicator
                if offlineManager.pendingInspectionsCount > 0 {
                    Button {
                        showPendingInspections = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("\(offlineManager.pendingInspectionsCount)")
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
                        .foregroundColor(BrandChrome.accent)
                }
                
                if canCreateInspections {
                    Button {
                        showCreateInspection = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(BrandChrome.accent)
                    }
                }
            }
        }
        .refreshable {
            await refreshInspections()
        }
        .onAppear {
            loadInspections()
            // Track screen view (GA4)
            AnalyticsManager.shared.trackScreenView("Inspections", projectId: projectId)
        }
        .trackPageView("/projects/\(projectId)/inspections", projectId: projectId)
        .sheet(isPresented: $showCreateInspection) {
            CreateInspectionView(
                projectId: projectId,
                token: sessionManager.token ?? token,
                projectName: projectName,
                onSuccess: {
                    showCreateInspection = false
                    loadInspections()
                }
            )
            .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showPendingInspections) {
            PendingInspectionsView()
        }
    }
    
    private var canCreateInspections: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("manage_project_inspections")
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: BrandChrome.accent))
            Text("Loading inspections...")
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
            
            if inspections.isEmpty && !isLoading {
                emptyStateView
            } else {
                inspectionsList
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
                    loadInspections()
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
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No inspections found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Create your first inspection to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if canCreateInspections {
                Button {
                    showCreateInspection = true
                } label: {
                    Label("Create Inspection", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(BrandChrome.accent)
                        .cornerRadius(12)
                }
            }
        }
        .padding(40)
    }
    
    private var inspectionsList: some View {
        List {
            ForEach(filteredAndSortedInspections) { inspection in
                NavigationLink(
                    destination: InspectionDetailView(
                        inspection: inspection,
                        projectId: projectId,
                        token: sessionManager.token ?? token,
                        onRefresh: { loadInspections() }
                    )
                    .environmentObject(sessionManager)
                ) {
                    InspectionRowView(inspection: inspection)
                }
                .listRowBackground(BrandChrome.groupedBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(PlainListStyle())
        .brandListChrome()
    }
    
    private var filteredAndSortedInspections: [Inspection] {
        var filtered = inspections
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { inspection in
                (inspection.location?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                String(inspection.inspectionNumber).contains(searchText) ||
                inspection.projectInspectionTemplate.template.name.localizedCaseInsensitiveContains(searchText) ||
                (inspection.assignedTo?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply status filter
        switch filterOption {
        case .all:
            break
        case .notStarted:
            filtered = filtered.filter { $0.status == "NOT_STARTED" }
        case .inProgress:
            filtered = filtered.filter { $0.status == "IN_PROGRESS" }
        case .completed:
            filtered = filtered.filter { $0.status == "COMPLETED" }
        case .failed:
            filtered = filtered.filter { $0.status == "FAILED" }
        case .assigned:
            let currentUserId = sessionManager.user?.id
            filtered = filtered.filter { $0.assignedToId == currentUserId }
        }
        
        // Apply sorting
        switch sortOption {
        case .number:
            filtered.sort { $0.inspectionNumber > $1.inspectionNumber }
        case .date:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .status:
            filtered.sort { $0.status < $1.status }
        case .location:
            filtered.sort { ($0.location?.name ?? "") < ($1.location?.name ?? "") }
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
                loadInspections()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
    }
    
    private func loadInspections() {
        guard !isRefreshing else { return }
        
        Task {
            await MainActor.run {
                if inspections.isEmpty {
                    isLoading = true
                }
                errorMessage = nil
            }
            
            do {
                let fetchedInspections = try await APIClient.fetchInspections(
                    projectId: projectId,
                    token: sessionManager.token ?? token
                )
                
                // Cache the inspections for offline use
                offlineManager.cacheInspections(fetchedInspections, forProject: projectId)
                
                await MainActor.run {
                    self.inspections = fetchedInspections
                    self.isLoading = false
                    self.isUsingCachedData = false
                    self.cacheAge = nil
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                
                // Try to load from cache on network error
                if let apiError = error as? APIError {
                    switch apiError {
                    case .networkError:
                        await MainActor.run {
                            loadFromCache()
                        }
                    case .tokenExpired:
                        await handleAuthIssueAndRetry(fallbackMessage: "Session expired. Please log in again.")
                    case .forbidden:
                        await handleAuthIssueAndRetry(fallbackMessage: "You don't have permission to view inspections.")
                    case .invalidResponse(let statusCode):
                        await MainActor.run {
                            if statusCode == 404 {
                                self.errorMessage = "Inspections feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Server error (\(statusCode)). Please try again."
                                loadFromCache()
                            }
                        }
                    case .badRequest(let message):
                        await MainActor.run { self.errorMessage = message }
                    case .closureGate(let gate):
                        await MainActor.run { self.errorMessage = gate.message }
                    case .decodingError(let decodingError):
                        await MainActor.run {
                            self.errorMessage = "Data parsing error: \(decodingError.localizedDescription)"
                        }
                    }
                } else {
                    // Generic error - try cache
                    await MainActor.run {
                        loadFromCache()
                    }
                }
            }
        }
    }
    
    private func loadFromCache() {
        if let cachedInspections = offlineManager.getCachedInspections(forProject: projectId) {
            self.inspections = cachedInspections
            self.isUsingCachedData = true
            self.cacheAge = offlineManager.getCacheAge(forProject: projectId)
            self.errorMessage = nil
            print("InspectionsListView: Loaded \(cachedInspections.count) inspections from cache")
        } else {
            self.errorMessage = "No cached data available. Please connect to the internet."
        }
    }
    
    private func refreshInspections() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let fetchedInspections = try await APIClient.fetchInspections(
                projectId: projectId,
                token: sessionManager.token ?? token
            )
            
            // Cache the inspections for offline use
            offlineManager.cacheInspections(fetchedInspections, forProject: projectId)
            
            await MainActor.run {
                self.inspections = fetchedInspections
                self.isUsingCachedData = false
                self.cacheAge = nil
            }
        } catch {
            if let apiError = error as? APIError {
                switch apiError {
                case .networkError:
                    // Don't show error if we have cached data
                    await MainActor.run {
                        if !isUsingCachedData {
                            loadFromCache()
                        }
                    }
                case .tokenExpired:
                    await handleAuthIssueAndRetry(fallbackMessage: "Session expired. Please log in again.")
                case .forbidden:
                    await handleAuthIssueAndRetry(fallbackMessage: "You don't have permission to view inspections.")
                case .invalidResponse(let statusCode):
                    await MainActor.run {
                        if statusCode == 404 {
                            self.errorMessage = "Inspections feature is not yet available on the server."
                        } else {
                            self.errorMessage = "Failed to refresh inspections: \(error.localizedDescription)"
                        }
                    }
                default:
                    await MainActor.run {
                        self.errorMessage = "Failed to refresh inspections: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func handleAuthIssueAndRetry(fallbackMessage: String) async {
        if isReauthInProgress {
            await MainActor.run {
                self.errorMessage = fallbackMessage
            }
            return
        }
        
        await MainActor.run {
            self.isReauthInProgress = true
        }
        defer { Task { @MainActor in self.isReauthInProgress = false } }
        
        let reauthed = await sessionManager.attemptSilentReauth()
        if reauthed {
            await MainActor.run {
                self.errorMessage = nil
            }
            loadInspections()
        } else {
            await MainActor.run {
                self.errorMessage = fallbackMessage
            }
        }
    }
}

// MARK: - Pending Inspections View

struct PendingInspectionsView: View {
    @StateObject private var offlineManager = OfflineInspectionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if offlineManager.pendingInspections.isEmpty {
                    ContentUnavailableView(
                        "No Pending Items",
                        systemImage: "checkmark.circle",
                        description: Text("All items have been synced")
                    )
                } else {
                    Section("Pending Inspections") {
                        ForEach(offlineManager.pendingInspections) { inspection in
                            PendingInspectionRow(inspection: inspection)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                offlineManager.deletePendingInspection(offlineManager.pendingInspections[index])
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

struct PendingInspectionRow: View {
    let inspection: OfflineInspection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inspection #\(inspection.inspectionNumber)")
                .font(.headline)
            
            if let locationName = inspection.locationName {
                Text(locationName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Created \(inspection.createdAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InspectionRowView: View {
    let inspection: Inspection
    
    private var statusColor: Color {
        switch inspection.status {
        case "NOT_STARTED":
            return .gray
        case "IN_PROGRESS":
            return .blue
        case "COMPLETED":
            return .green
        case "FAILED":
            return .red
        default:
            return .gray
        }
    }
    
    private var statusIcon: String {
        switch inspection.status {
        case "NOT_STARTED":
            return "circle"
        case "IN_PROGRESS":
            return "clock.fill"
        case "COMPLETED":
            return "checkmark.circle.fill"
        case "FAILED":
            return "xmark.circle.fill"
        default:
            return "circle"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with number and status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Inspection #\(inspection.inspectionNumber)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Text(inspection.projectInspectionTemplate.template.name)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.caption)
                        Text(inspection.status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(6)
                }
            }
            
            // Meta info row
            HStack(spacing: 12) {
                if let location = inspection.location {
                    DetailItem(icon: "mappin.circle.fill", text: location.name, color: .blue)
                }
                
                if let assignee = inspection.assignedTo {
                    DetailItem(icon: "person.fill", text: assignee.displayName, color: .orange)
                }
            }
            
            // Progress info
            if let stageResults = inspection.stageResults, !stageResults.isEmpty {
                let completedCount = stageResults.filter { $0.status != "PENDING" }.count
                let totalCount = stageResults.count
                
                HStack {
                    ProgressView(value: Double(completedCount), total: Double(totalCount))
                        .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                    
                    Text("\(completedCount)/\(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Created date
            HStack {
                Spacer()
                Text(formatDate(inspection.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .brandCard()
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

// Reuse DetailItem from LogsListView
// struct DetailItem: View { ... } - already defined in LogsListView.swift

