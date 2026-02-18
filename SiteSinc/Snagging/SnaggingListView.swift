import SwiftUI

enum SnaggingViewMode: String, CaseIterable {
    case drawings = "Drawings"
    case table = "All Snags"
}

struct SnaggingListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selections: [APIClient.SnagSelectedDrawing] = []
    @State private var allSnags: [APIClient.SnagWithDrawing] = []
    @State private var viewMode: SnaggingViewMode = .drawings
    @State private var selectedSnag: APIClient.SnagWithDrawing? = nil
    @State private var statusFilter: String = "all"
    @State private var assignedToMeOnly: Bool = false
    @State private var navigateToDrawing: APIClient.SnagSelectedDrawing? = nil

    var canViewSnags: Bool {
        sessionManager.hasPermission("snag_manager") ||
        sessionManager.hasPermission("view_all_snags") ||
        sessionManager.hasPermission("view_snags")
    }
    
    var filteredSnags: [APIClient.SnagWithDrawing] {
        var list = allSnags
        if assignedToMeOnly, let currentUserId = sessionManager.user?.id {
            list = list.filter { $0.userId == currentUserId }
        }
        if statusFilter == "all" {
            return list
        }
        return list.filter { $0.status.uppercased() == statusFilter.uppercased() }
    }

    /// Count of snags assigned to the current user (for "Assigned to me" filter)
    private var assignedToMeCount: Int {
        guard let currentUserId = sessionManager.user?.id else { return 0 }
        return allSnags.filter { $0.userId == currentUserId }.count
    }
    
    var snagCounts: [String: Int] {
        var counts: [String: Int] = ["all": allSnags.count]
        for snag in allSnags {
            let status = snag.status.uppercased()
            counts[status, default: 0] += 1
        }
        return counts
    }
    
    /// Get snag counts for a specific drawing selection
    func snagCountsForDrawing(_ selection: APIClient.SnagSelectedDrawing) -> (total: Int, byStatus: [String: Int]) {
        let drawingSnags = allSnags.filter { snag in
            snag.drawingId == selection.drawingId && snag.drawingFileId == selection.drawingFileId
        }
        
        var statusCounts: [String: Int] = [:]
        for snag in drawingSnags {
            let status = snag.status.uppercased()
            statusCounts[status, default: 0] += 1
        }
        
        return (total: drawingSnags.count, byStatus: statusCounts)
    }

    var body: some View {
        VStack(spacing: 0) {
            // View Mode Picker
            Picker("View Mode", selection: $viewMode) {
                ForEach(SnaggingViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            if viewMode == .table {
                // Assigned to me filter
                Toggle(isOn: $assignedToMeOnly) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .foregroundColor(assignedToMeOnly ? .accentColor : .secondary)
                        Text("Assigned to me")
                        if assignedToMeOnly && assignedToMeCount > 0 {
                            Text("(\(assignedToMeCount))")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Status Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        StatusFilterPill(label: "All", count: snagCounts["all"] ?? 0, isSelected: statusFilter == "all") {
                            statusFilter = "all"
                        }
                        StatusFilterPill(label: "Open", count: snagCounts["OPEN"] ?? 0, color: .red, isSelected: statusFilter == "OPEN") {
                            statusFilter = "OPEN"
                        }
                        StatusFilterPill(label: "In Progress", count: snagCounts["IN_PROGRESS"] ?? 0, color: .orange, isSelected: statusFilter == "IN_PROGRESS") {
                            statusFilter = "IN_PROGRESS"
                        }
                        StatusFilterPill(label: "Resolved", count: snagCounts["RESOLVED"] ?? 0, color: .blue, isSelected: statusFilter == "RESOLVED") {
                            statusFilter = "RESOLVED"
                        }
                        StatusFilterPill(label: "Closed", count: snagCounts["CLOSED"] ?? 0, color: .green, isSelected: statusFilter == "CLOSED") {
                            statusFilter = "CLOSED"
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading {
                        ProgressView(viewMode == .drawings ? "Loading drawings…" : "Loading snags…")
                            .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    } else if let error = errorMessage {
                        errorBanner(error)
                    } else {
                        switch viewMode {
                        case .drawings:
                            drawingsGridView
                        case .table:
                            snagsTableView
                        }
                    }
                }
            }
        }
        .navigationTitle("Snagging")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoading {
                    ProgressView()
                } else {
                    Button(action: { Task { await refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .onChange(of: viewMode) {
            Task { await refresh() }
        }
        .onAppear {
            Task { await refresh() }
            // Track screen view (GA4)
            AnalyticsManager.shared.trackScreenView("Snagging", projectId: projectId)
        }
        .trackPageView("/projects/\(projectId)/snagging", projectId: projectId)
        .sheet(item: $selectedSnag) { snag in
            SnagQuickDetailSheet(
                snag: snag,
                projectId: projectId,
                token: token,
                selections: selections,
                onViewOnDrawing: { selection in
                    selectedSnag = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToDrawing = selection
                    }
                }
            )
            .environmentObject(sessionManager)
        }
        .navigationDestination(isPresented: Binding(
            get: { navigateToDrawing != nil },
            set: { if !$0 { navigateToDrawing = nil } }
        )) {
            if let selection = navigateToDrawing {
                SnaggingViewer(
                    projectId: projectId,
                    token: token,
                    drawing: selection.drawing,
                    drawingFileId: selection.drawingFileId
                )
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
            }
        }
    }
    
    // MARK: - Drawings Grid View
    @ViewBuilder
    private var drawingsGridView: some View {
        if selections.isEmpty {
            emptyStateDrawings
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(selections, id: \.id) { selection in
                    NavigationLink(
                        destination: SnaggingViewer(
                            projectId: projectId,
                            token: token,
                            drawing: selection.drawing,
                            drawingFileId: selection.drawingFileId
                        )
                        .environmentObject(sessionManager)
                        .environmentObject(networkStatusManager)
                    ) {
                        SnaggingDrawingCard(
                            selection: selection,
                            token: token,
                            snagCounts: snagCountsForDrawing(selection)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Snags Table View
    @ViewBuilder
    private var snagsTableView: some View {
        if filteredSnags.isEmpty {
            emptyStateSnags
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredSnags) { snag in
                    SnagTableRow(snag: snag)
                        .onTapGesture {
                            selectedSnag = snag
                        }
                    
                    if snag.id != filteredSnags.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .padding(.horizontal)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(projectName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(viewMode == .drawings ? "Selected drawings available for snagging" : "All snags in this project")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var emptyStateDrawings: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44)).foregroundColor(.gray.opacity(0.5))
            Text("No drawings selected for snagging")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Use the web app to select drawings (PDF files) for snagging, then pull to refresh here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
    
    private var emptyStateSnags: some View {
        let headline: String = {
            if assignedToMeOnly {
                return "No snags assigned to you"
            }
            if statusFilter == "all" {
                return "No snags found"
            }
            return "No \(statusFilter.lowercased().replacingOccurrences(of: "_", with: " ")) snags"
        }()
        let subtitle: String = assignedToMeOnly
            ? "Turn off \"Assigned to me\" to see all snags."
            : "Snags created on drawings will appear here."
        return VStack(spacing: 12) {
            Image(systemName: assignedToMeOnly ? "person.crop.circle.badge.questionmark" : "checkmark.circle")
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.5))
            Text(headline)
                .font(.headline)
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Failed to load").font(.headline)
                Text(message).font(.subheadline)
                Button("Retry") { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func refresh() async {
        guard canViewSnags else {
            await MainActor.run { self.errorMessage = "You don't have permission to view snags." }
            return
        }
        await MainActor.run { isLoading = true; errorMessage = nil }
        
        do {
            switch viewMode {
            case .drawings:
                // Load both selections and snags (for indicators on drawing cards)
                async let selectionsTask = APIClient.fetchSelectedSnagDrawings(projectId: projectId, token: token)
                async let snagsTask = APIClient.fetchAllSnagsForProject(projectId: projectId, token: token)
                
                let (loadedSelections, loadedSnags) = try await (selectionsTask, snagsTask)
                await MainActor.run {
                    self.selections = loadedSelections
                    self.allSnags = loadedSnags
                    self.isLoading = false
                }
            case .table:
                // Load both snags and selections (for "View on Drawing" button)
                async let snagsTask = APIClient.fetchAllSnagsForProject(projectId: projectId, token: token)
                async let selectionsTask = APIClient.fetchSelectedSnagDrawings(projectId: projectId, token: token)
                
                let (loadedSnags, loadedSelections) = try await (snagsTask, selectionsTask)
                await MainActor.run {
                    self.allSnags = loadedSnags
                    self.selections = loadedSelections
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Status Filter Pill
private struct StatusFilterPill: View {
    let label: String
    let count: Int
    var color: Color = .gray
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color(.systemGray5))
                    .cornerRadius(8)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.systemGray6))
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Snag Table Row
private struct SnagTableRow: View {
    let snag: APIClient.SnagWithDrawing

    private func snagAssignedUserDisplayName(_ snag: APIClient.SnagWithDrawing) -> String? {
        guard let u = snag.User else { return nil }
        if let t = u.tenants?.first, let first = t.firstName, let last = t.lastName, !first.isEmpty || !last.isEmpty {
            return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        }
        if let email = u.email, !email.isEmpty { return email }
        return "User #\(u.id)"
    }
    
    var statusColor: Color {
        switch snag.status.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .blue
        case "CLOSED": return .green
        default: return .gray
        }
    }
    
    var priorityColor: Color {
        switch snag.priority?.lowercased() {
        case "high", "critical": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            // Main Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(snag.id)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text(snag.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    // Drawing
                    if let drawingTitle = snag.drawing?.title {
                        Label(drawingTitle, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Assigned company
                    if let company = snag.assignments?.first?.company?.name {
                        Label(company, systemImage: "building.2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Assigned user
                    if let assignedName = snagAssignedUserDisplayName(snag) {
                        Label(assignedName, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Right side info
            VStack(alignment: .trailing, spacing: 4) {
                // Status badge
                Text(snag.status.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(6)
                
                // Date
                if let dateStr = snag.createdAt {
                    Text(formattedDate(dateStr))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func formattedDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        
        // Try without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        
        return dateString.prefix(10).description
    }
}

// MARK: - Snag Quick Detail Sheet
private struct SnagQuickDetailSheet: View {
    let snag: APIClient.SnagWithDrawing
    let projectId: Int
    let token: String
    let selections: [APIClient.SnagSelectedDrawing]
    let onViewOnDrawing: (APIClient.SnagSelectedDrawing) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    var statusColor: Color {
        switch snag.status.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .blue
        case "CLOSED": return .green
        default: return .gray
        }
    }
    
    var priorityLabel: String {
        snag.priority?.capitalized ?? "Medium"
    }
    
    var priorityColor: Color {
        switch snag.priority?.lowercased() {
        case "high", "critical": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .gray
        }
    }
    
    /// Find the matching drawing selection for this snag
    var matchingSelection: APIClient.SnagSelectedDrawing? {
        guard let drawingId = snag.drawingId,
              let drawingFileId = snag.drawingFileId else { return nil }
        return selections.first { $0.drawingId == drawingId && $0.drawingFileId == drawingFileId }
            ?? selections.first { $0.drawingId == drawingId }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with Status
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Snag #\(snag.id)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(snag.title)
                                .font(.system(size: 20, weight: .bold))
                        }
                        
                        Spacer()
                        
                        Text(snag.status.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusColor)
                            .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Details Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        DetailCell(label: "Priority", value: priorityLabel, color: priorityColor)
                        DetailCell(label: "Drawing", value: snag.drawing?.title ?? "Unknown")
                        if let page = snag.page {
                            DetailCell(label: "Page", value: "\(page)")
                        }
                        
                        if let company = snag.assignments?.first?.company?.name {
                            DetailCell(label: "Assigned To", value: company)
                        }
                        
                        if let dateStr = snag.createdAt {
                            DetailCell(label: "Created", value: formattedDate(dateStr))
                        }
                        
                        if let user = snag.User {
                            let name = (user.tenants?.first?.firstName ?? "") + " " + (user.tenants?.first?.lastName ?? "")
                            DetailCell(label: "Assigned User", value: name.trimmingCharacters(in: .whitespaces).isEmpty ? (user.email ?? "Unknown") : name)
                        }
                    }
                    
                    // Description
                    if let description = snag.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    
                    // View on Drawing Button
                    if let selection = matchingSelection {
                        Button(action: {
                            onViewOnDrawing(selection)
                        }) {
                            HStack {
                                Image(systemName: "doc.viewfinder")
                                Text("View on Drawing")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    } else {
                        // Drawing not in selected drawings
                        VStack(spacing: 8) {
                            Text("Drawing not available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("This drawing needs to be added to snagging selections first.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Snag Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func formattedDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Detail Cell
private struct DetailCell: View {
    let label: String
    let value: String
    var color: Color? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            if let color = color {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            } else {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SnaggingDrawingCard: View {
    let selection: APIClient.SnagSelectedDrawing
    let token: String
    let snagCounts: (total: Int, byStatus: [String: Int])

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail with overlay badge
            ZStack(alignment: .topTrailing) {
                GeometryReader { geometry in
                    DrawingThumbnailView(
                        fileId: selection.drawingFileId,
                        token: token,
                        width: geometry.size.width,
                        height: 140
                    )
                }
                .frame(height: 140)
                .clipped()
                .cornerRadius(10)
                
                // Snag count badge
                if snagCounts.total > 0 {
                    SnagCountBadge(count: snagCounts.total, statusCounts: snagCounts.byStatus)
                        .padding(8)
                }
            }
            
            Text("\(selection.drawing.number) – \(selection.drawing.title)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            HStack(spacing: 8) {
                Text("Selected \(formatted(dateString: selection.selectedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status indicators
                if snagCounts.total > 0 {
                    SnagStatusIndicators(statusCounts: snagCounts.byStatus)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1))
        .contentShape(Rectangle())
    }

    private func formatted(dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        
        // Use relative formatting for recent dates
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "yesterday at \(formatter.string(from: date))"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo <= 7 {
            return "\(daysAgo) days ago"
        } else {
            // For older dates, show date in user's locale format (e.g., "28 Nov 2025" or "Nov 28, 2025")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Snag Count Badge
private struct SnagCountBadge: View {
    let count: Int
    let statusCounts: [String: Int]
    
    var primaryStatus: String? {
        // Find the status with the most snags
        statusCounts.max(by: { $0.value < $1.value })?.key
    }
    
    var primaryColor: Color {
        switch primaryStatus?.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .blue
        case "CLOSED": return .green
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(primaryColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Snag Status Indicators
private struct SnagStatusIndicators: View {
    let statusCounts: [String: Int]
    
    var body: some View {
        HStack(spacing: 4) {
            if let openCount = statusCounts["OPEN"], openCount > 0 {
                StatusDot(color: .red, count: openCount)
            }
            if let inProgressCount = statusCounts["IN_PROGRESS"], inProgressCount > 0 {
                StatusDot(color: .orange, count: inProgressCount)
            }
            if let resolvedCount = statusCounts["RESOLVED"], resolvedCount > 0 {
                StatusDot(color: .blue, count: resolvedCount)
            }
            if let closedCount = statusCounts["CLOSED"], closedCount > 0 {
                StatusDot(color: .green, count: closedCount)
            }
        }
    }
}

// MARK: - Status Dot
private struct StatusDot: View {
    let color: Color
    let count: Int
    
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}


