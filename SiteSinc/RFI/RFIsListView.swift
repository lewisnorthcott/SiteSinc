import Foundation
import SwiftUI
import SwiftData

struct RFIsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var unifiedRFIs: [UnifiedRFI] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .number
    @State private var filterOption: FilterOption = .all
    @State private var showCreateRFI = false
    @State private var isRefreshing = false
    @Environment(\.modelContext) private var modelContext

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
        case responded = "Responded"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with search and filters
                    VStack(spacing: 16) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Search RFIs...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        // Filter and sort controls
                        HStack(spacing: 12) {
                            // Filter picker
                            Menu {
                                ForEach(FilterOption.allCases) { option in
                                    Button(action: { filterOption = option }) {
                                        HStack {
                                            Text(option.rawValue)
                                            if filterOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text(filterOption.rawValue)
                                    Image(systemName: "chevron.down")
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                            }
                            
                            // Sort picker
                            Menu {
                                ForEach(SortOption.allCases) { option in
                                    Button(action: { sortOption = option }) {
                                        HStack {
                                            Text(option.rawValue)
                                            if sortOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(sortOption.rawValue)
                                    Image(systemName: "chevron.down")
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // RFI count
                            Text("\(filteredUnifiedRFIs.count) RFIs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Content
                    if isLoading {
                        LoadingView()
                    } else if let errorMessage = errorMessage {
                        ErrorView(message: errorMessage, retryAction: fetchRFIs)
                    } else if filteredUnifiedRFIs.isEmpty {
                        RFIEmptyStateView(searchText: searchText, filterOption: filterOption)
                    } else {
                        RFIListView(
                            rfis: filteredUnifiedRFIs,
                            onRefresh: {
                                isRefreshing = true
                                fetchRFIs()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    isRefreshing = false
                                }
                            },
                            token: token
                        )
                    }
                }
            }
            .navigationTitle("RFIs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Group {
                        if sessionManager.hasPermission("create_rfis") {
                            Button(action: { showCreateRFI = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            .accessibilityIdentifier("rfi_create_button")
                        }
                    }
                }
            }
        .onAppear {
            fetchRFIs()
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(
                projectId: projectId,
                token: token,
                projectName: projectName,
                onSuccess: {
                    showCreateRFI = false
                    fetchRFIs()
                },
                prefilledTitle: nil,
                prefilledAttachmentData: nil,
                prefilledDrawing: nil,
                sourceMarkup: nil
            )
        }
    }

    private func destinationView(for unifiedRFI: UnifiedRFI) -> some View {
        if unifiedRFI.draftObject != nil {
            return AnyView(RFIDraftDetailView(draft: unifiedRFI.draftObject!, token: token, onSubmit: { draft in
                submitDraft(draft)
            }))
        } else {
            return AnyView(RFIDetailView(rfi: unifiedRFI.serverRFI!, token: token, onRefresh: {
                fetchRFIs()
            }))
        }
    }

    private var filteredUnifiedRFIs: [UnifiedRFI] {
        var filtered = unifiedRFIs
        
        // Apply filter
        switch filterOption {
        case .all:
            break
        case .open:
            filtered = filtered.filter { $0.status?.lowercased() != "closed" }
        case .closed:
            filtered = filtered.filter { $0.status?.lowercased() == "closed" }
        case .pending:
            filtered = filtered.filter { $0.status?.lowercased() == "pending" }
        case .responded:
            filtered = filtered.filter { $0.status?.lowercased() == "responded" }
        }
        
        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter {
                ($0.title ?? "").lowercased().contains(searchText.lowercased()) ||
                String($0.number).lowercased().contains(searchText.lowercased()) ||
                ($0.query ?? "").lowercased().contains(searchText.lowercased())
            }
        }
        
        // Apply sort
        switch sortOption {
        case .number:
            filtered.sort { rfi1, rfi2 in
                return rfi1.number > rfi2.number
            }
        case .date:
            filtered.sort { rfi1, rfi2 in
                let date1 = ISO8601DateFormatter().date(from: rfi1.createdAt ?? "") ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: rfi2.createdAt ?? "") ?? Date.distantPast
                return date1 > date2
            }
        case .title:
            filtered.sort(by: { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() })
        case .status:
            filtered.sort(by: { ($0.status ?? "").lowercased() < ($1.status ?? "").lowercased() })
        case .priority:
            // Sort by priority: pending > responded > open > closed
            let priorityOrder = ["pending", "responded", "open", "submitted", "closed"]
            filtered.sort { rfi1, rfi2 in
                let status1 = rfi1.status?.lowercased() ?? ""
                let status2 = rfi2.status?.lowercased() ?? ""
                let index1 = priorityOrder.firstIndex(of: status1) ?? 999
                let index2 = priorityOrder.firstIndex(of: status2) ?? 999
                return index1 < index2
            }
        }
        
        return filtered
    }

    private func fetchRFIs() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        let drafts = (try? modelContext.fetch(fetchDescriptor)) ?? []
        let draftRFIs = drafts.map { UnifiedRFI.draft($0) }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let r = try await APIClient.fetchRFIs(projectId: projectId, token: token)
                await MainActor.run {
                    let serverRFIs = r.map { UnifiedRFI.server($0) }
                    unifiedRFIs = draftRFIs + serverRFIs
                    saveRFIsToCache(r)
                    if r.isEmpty {
                        print("No RFIs returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(r.count) RFIs for projectId: \(projectId)")
                    }
                    syncDrafts()
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        if let cachedRFIs = loadRFIsFromCache() {
                            unifiedRFIs = draftRFIs + cachedRFIs.map { UnifiedRFI.server($0) }
                            errorMessage = "Loaded cached RFIs (offline mode)"
                        } else {
                            unifiedRFIs = draftRFIs
                            errorMessage = "No internet connection and no cached data available"
                        }
                    } else {
                        unifiedRFIs = draftRFIs
                        errorMessage = "Failed to load RFIs: \(error.localizedDescription)"
                        print("Error fetching RFIs: \(error)")
                    }
                }
            }
        }
    }

    private func saveRFIsToCache(_ rfis: [RFI]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rfis) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }

    private func loadRFIsFromCache() -> [RFI]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedRFIs = try? decoder.decode([RFI].self, from: data) {
                print("Loaded \(cachedRFIs.count) RFIs from cache for project \(projectId)")
                return cachedRFIs
            }
        }
        return nil
    }



    private func syncDrafts() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        guard let drafts = try? modelContext.fetch(fetchDescriptor), !drafts.isEmpty else { return }
        
        for draft in drafts {
            submitDraft(draft)
        }
    }

    private func submitDraft(_ draft: RFIDraft) {
        Task {
            do {
                // Step 1: Upload files
                var uploadedFiles: [[String: Any]] = []
                let fileURLs = draft.selectedFiles.compactMap { URL(fileURLWithPath: $0) }
                
                for fileURL in fileURLs {
                    guard let uploadData = try? Data(contentsOf: fileURL) else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read file data"])
                    }
                    let fileName = fileURL.lastPathComponent
                    let url = URL(string: "\(APIClient.baseURL)/rfis/upload-file")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    let boundary = "Boundary-\(UUID().uuidString)"
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    
                    var body = Data()
                    let boundaryPrefix = "--\(boundary)\r\n"
                    body.append(boundaryPrefix.data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                    body.append(uploadData)
                    body.append("\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    request.httpBody = body
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        if statusCode == 401 { throw APIError.tokenExpired }
                        if statusCode == 403 { throw APIError.forbidden }
                        throw NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
                    }
                    guard let fileData = try? JSONDecoder().decode(UploadedFileResponse.self, from: data) else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode upload response"])
                    }
                    uploadedFiles.append([
                        "fileUrl": fileData.fileUrl,
                        "fileName": fileData.fileName,
                        "fileType": fileData.fileType
                    ])
                }

                // Step 2: Submit RFI
                let body: [String: Any] = [
                    "title": draft.title,
                    "query": draft.query,
                    "description": draft.query,
                    "projectId": draft.projectId,
                    "managerId": draft.managerId!,
                    "assignedUserIds": draft.assignedUserIds,
                    "returnDate": draft.returnDate?.ISO8601Format() ?? "",
                    "attachments": uploadedFiles,
                    "drawings": draft.selectedDrawings.map { ["drawingId": $0.drawingId, "revisionId": $0.revisionId] }
                ]

                guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request"])
                }

                let url = URL(string: "\(APIClient.baseURL)/rfis")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if statusCode == 401 { throw APIError.tokenExpired }
                    if statusCode == 403 { throw APIError.forbidden }
                    throw NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to sync draft RFI"])
                }

                await MainActor.run {
                    self.modelContext.delete(draft)
                    try? self.modelContext.save()
                    fetchRFIs()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to sync draft RFI: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Loading RFIs...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Something went wrong")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct RFIEmptyStateView: View {
    let searchText: String
    let filterOption: RFIsListView.FilterOption
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No RFIs found"
        }
        
        switch filterOption {
        case .all:
            return "No RFIs yet"
        case .open:
            return "No open RFIs"
        case .closed:
            return "No closed RFIs"
        case .pending:
            return "No pending RFIs"
        case .responded:
            return "No responded RFIs"
        }
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try adjusting your search terms or filters"
        }
        
        switch filterOption {
        case .all:
            return "Create your first RFI to get started"
        case .open:
            return "All RFIs are currently closed"
        case .closed:
            return "No RFIs have been closed yet"
        case .pending:
            return "No RFIs are currently pending"
        case .responded:
            return "No RFIs have responses yet"
        }
    }
}

struct RFIListView: View {
    let rfis: [UnifiedRFI]
    let onRefresh: () -> Void
    let token: String
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(rfis) { unifiedRFI in
                    NavigationLink(destination: destinationView(for: unifiedRFI)) {
                        EnhancedRFIRow(unifiedRFI: unifiedRFI)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable {
            onRefresh()
        }
    }
    
    private func destinationView(for unifiedRFI: UnifiedRFI) -> some View {
        if unifiedRFI.draftObject != nil {
            return AnyView(RFIDraftDetailView(draft: unifiedRFI.draftObject!, token: token, onSubmit: { draft in
                // Handle draft submission
            }))
        } else {
            return AnyView(RFIDetailView(rfi: unifiedRFI.serverRFI!, token: token, onRefresh: {
                // Handle refresh
            }))
        }
    }
}

struct EnhancedRFIRow: View {
    let unifiedRFI: UnifiedRFI
    
    private var title: String {
        return unifiedRFI.title ?? "Untitled"
    }
    
    private var number: Int {
        return unifiedRFI.number
    }
    
    private var status: String {
        return unifiedRFI.status?.capitalized ?? "Unknown"
    }
    
    private var createdAt: String {
        if let createdAtStr = unifiedRFI.createdAt, let date = ISO8601DateFormatter().date(from: createdAtStr) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Unknown"
    }
    
    private var createdDate: String {
        if let createdAtStr = unifiedRFI.createdAt, let date = ISO8601DateFormatter().date(from: createdAtStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return "Unknown"
    }
    
    private var dueDate: String? {
        if let dueDateStr = unifiedRFI.returnDate, let date = ISO8601DateFormatter().date(from: dueDateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return nil
    }
    
    private var assignedUsers: String {
        if let users = unifiedRFI.assignedUsers, !users.isEmpty {
            return users.map { "\($0.user.firstName) \($0.user.lastName)" }.joined(separator: ", ")
        }
        return "Unassigned"
    }
    
    private var statusColor: Color {
        switch unifiedRFI.status?.lowercased() {
        case "draft": return .gray
        case "submitted": return .blue
        case "in_review": return .orange
        case "responded": return .green
        case "closed": return .purple
        case "pending": return .orange
        default: return .gray
        }
    }
    
    private var isUrgent: Bool {
        guard let dueDateStr = unifiedRFI.returnDate,
              let dueDate = ISO8601DateFormatter().date(from: dueDateStr) else {
            return false
        }
        
        let calendar = Calendar.current
        let daysUntilDue = calendar.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        return daysUntilDue <= 3 && daysUntilDue >= 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with number, status, and priority
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("RFI #\(number)")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if isUrgent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        Text(status)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.2))
                            .foregroundColor(statusColor)
                            .cornerRadius(6)
                    }
                    
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }
            
            // Metadata row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(createdAt)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(createdDate)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let dueDate = dueDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Due")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dueDate)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isUrgent ? .red : .primary)
                    }
                }
            }
            
            // Bottom row with assigned users and indicators
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assigned To")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(assignedUsers)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Quick indicators
                HStack(spacing: 8) {
                    // Manager indicator
                    if unifiedRFI.managerId != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.caption2)
                            Text("Mgr")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                    
                    // Attachment count
                    if let attachments = unifiedRFI.attachments, !attachments.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(attachments.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                    
                    // Drawing count
                    if let drawings = unifiedRFI.drawings, !drawings.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                            Text("\(drawings.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.green)
                    }
                    
                    // Response count
                    if let responses = unifiedRFI.responses, !responses.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "message")
                                .font(.caption2)
                            Text("\(responses.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isUrgent ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        RFIsListView(projectId: 1, token: "sample_token", projectName: "Sample Project")
            .environmentObject(SessionManager())
    }
}
