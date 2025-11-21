import SwiftUI

struct MaterialRequisitionsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var requisitions: [MaterialRequisition] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .number
    @State private var filterOption: FilterOption = .all
    @State private var showCreateRequisition = false
    @State private var isRefreshing = false
    @State private var selectedRequisition: MaterialRequisition?
    
    enum SortOption: String, CaseIterable, Identifiable {
        case number = "Number"
        case date = "Date"
        case title = "Title"
        case status = "Status"
        var id: String { rawValue }
    }
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case draft = "Draft"
        case submitted = "Submitted"
        case accepted = "Accepted"
        case processing = "Processing"
        case ordered = "Ordered"
        case delivered = "Delivered"
        case completed = "Completed"
        case cancelled = "Cancelled"
        case rejected = "Rejected"
        var id: String { rawValue }
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading requisitions...")
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
                        fetchRequisitions()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requisitions.isEmpty {
                emptyStateView
            } else {
                requisitionsList
            }
        }
        .navigationTitle("Material Requisitions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search requisitions...")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    sortMenu
                    Divider()
                    filterMenu
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                
                if sessionManager.hasPermission("raise_requisitions") {
                    Button(action: {
                        showCreateRequisition = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            if requisitions.isEmpty {
                fetchRequisitions()
            }
        }
        .refreshable {
            await refreshRequisitions()
        }
        .sheet(isPresented: $showCreateRequisition) {
            CreateMaterialRequisitionView(
                projectId: projectId,
                token: token,
                projectName: projectName,
                onSuccess: {
                    showCreateRequisition = false
                    fetchRequisitions()
                }
            )
        }
        .sheet(item: $selectedRequisition) { requisition in
            NavigationView {
                MaterialRequisitionDetailView(
                    requisition: requisition,
                    projectId: projectId,
                    token: token,
                    projectName: projectName,
                    onRefresh: {
                        fetchRequisitions()
                    }
                )
                .environmentObject(sessionManager)
            }
        }
    }
    
    private var sortMenu: some View {
        Section("Sort By") {
            ForEach(SortOption.allCases) { option in
                Button(action: {
                    sortOption = option
                }) {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var filterMenu: some View {
        Section("Filter By Status") {
            ForEach(FilterOption.allCases) { option in
                Button(action: {
                    filterOption = option
                }) {
                    HStack {
                        Text(option.rawValue)
                        if filterOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Requisitions")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Create your first material requisition to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if sessionManager.hasPermission("raise_requisitions") {
                Button {
                    showCreateRequisition = true
                } label: {
                    Label("Create Requisition", systemImage: "plus")
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
    
    private var requisitionsList: some View {
        List {
            ForEach(filteredAndSortedRequisitions) { requisition in
                Button(action: {
                    selectedRequisition = requisition
                }) {
                    MaterialRequisitionRow(requisition: requisition)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
    }
    
    private var filteredAndSortedRequisitions: [MaterialRequisition] {
        var filtered = requisitions
        
        // Filter by status
        if filterOption != .all {
            filtered = filtered.filter { requisition in
                switch filterOption {
                case .all: return true
                case .draft: return requisition.status == .draft
                case .submitted: return requisition.status == .submitted
                case .accepted: return requisition.status == .accepted
                case .processing: return requisition.status == .processing
                case .ordered: return requisition.status == .ordered
                case .delivered: return requisition.status == .delivered
                case .completed: return requisition.status == .completed
                case .cancelled: return requisition.status == .cancelled
                case .rejected: return requisition.status == .rejected
                }
            }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            filtered = filtered.filter { requisition in
                requisition.title.lowercased().contains(lowercasedSearch) ||
                (requisition.formattedNumber ?? "MR-\(String(format: "%04d", requisition.number))").lowercased().contains(lowercasedSearch) ||
                (requisition.notes?.lowercased().contains(lowercasedSearch) ?? false) ||
                (requisition.requestedBy?.displayName.lowercased().contains(lowercasedSearch) ?? false) ||
                (requisition.buyer?.displayName.lowercased().contains(lowercasedSearch) ?? false)
            }
        }
        
        // Sort
        switch sortOption {
        case .number:
            filtered.sort { $0.number > $1.number }
        case .date:
            filtered.sort { (req1, req2) in
                let date1 = req1.createdAt ?? ""
                let date2 = req2.createdAt ?? ""
                return date1 > date2
            }
        case .title:
            filtered.sort { $0.title < $1.title }
        case .status:
            filtered.sort { $0.status.rawValue < $1.status.rawValue }
        }
        
        return filtered
    }
    
    private func fetchRequisitions() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetched = try await APIClient.fetchMaterialRequisitions(projectId: projectId, token: token)
                await MainActor.run {
                    requisitions = fetched
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
                await MainActor.run {
                    errorMessage = "Failed to load requisitions: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func refreshRequisitions() async {
        isRefreshing = true
        do {
            let fetched = try await APIClient.fetchMaterialRequisitions(projectId: projectId, token: token)
            await MainActor.run {
                requisitions = fetched
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to refresh requisitions: \(error.localizedDescription)"
                isRefreshing = false
            }
        }
    }
}

struct MaterialRequisitionRow: View {
    let requisition: MaterialRequisition
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(requisition.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        Text(requisition.formattedNumber ?? "MR-\(String(format: "%04d", requisition.number))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let buyer = requisition.buyer {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Buyer: \(buyer.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                MaterialRequisitionStatusBadge(status: requisition.status)
            }
            
            HStack(spacing: 12) {
                if let createdAt = requisition.createdAt {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatDate(createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let requestedBy = requisition.requestedBy {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(requestedBy.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let totalValue = requisition.totalValue, let total = Double(totalValue) {
                    Text(String(format: "£%.2f", total))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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

struct MaterialRequisitionStatusBadge: View {
    let status: MaterialRequisitionStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .draft: return .gray
        case .submitted: return .blue
        case .accepted: return .green
        case .processing: return .orange
        case .ordered: return .purple
        case .delivered: return .teal
        case .completed: return .green
        case .archived: return .gray
        case .cancelled: return .red
        case .rejected: return .red
        }
    }
}

