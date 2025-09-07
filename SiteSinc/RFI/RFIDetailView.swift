import SwiftUI
import WebKit

struct RFIDetailView: View {
    let rfi: RFI
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentRFI: RFI
    @State private var responseText = ""
    @State private var isSubmittingResponse = false
    @State private var showAttachmentUploader = false
    @State private var showDrawingSelector = false
    @State private var showResponseReview = false
    @State private var selectedResponseForReview: RFI.RFIResponseItem?
    @State private var rejectionReason = ""
    @State private var isUpdatingStatus = false
    @State private var previewURL: URL? = nil
    @State private var managerUser: User? = nil
    @State private var isLoadingManager = false
    
    init(rfi: RFI, token: String, onRefresh: (() -> Void)?) {
        self.rfi = rfi
        self.token = token
        self.onRefresh = onRefresh
        self._currentRFI = State(initialValue: rfi)
    }
    
    // Function to refresh RFI data
    private func refreshRFIData() {
        // Call the refresh callback to update the parent view
        onRefresh?()
    }
    
    // Function to fetch manager details when only ID is available
    private func fetchManagerDetails() {
        guard let managerId = currentRFI.managerId, currentRFI.manager == nil, !isLoadingManager else { return }
        
        isLoadingManager = true
        Task {
            do {
                let users = try await APIClient.fetchUsers(projectId: currentRFI.projectId, token: token)
                await MainActor.run {
                    self.managerUser = users.first { $0.id == managerId }
                    self.isLoadingManager = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    self.isLoadingManager = false
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    self.isLoadingManager = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingManager = false
                    print("Failed to fetch manager details: \(error)")
                }
            }
        }
    }

    // Function to fetch updated RFI data
    private func fetchUpdatedRFI() {
        Task {
            do {
                // Try online first
                let updated = try await APIClient.fetchRFI(projectId: currentRFI.projectId, rfiId: currentRFI.id, token: token)
                await MainActor.run {
                    // Only update if the server data is actually more recent or different
                    // This prevents overwriting optimistic updates with stale server data
                    if self.shouldUpdateFromServer(updated) {
                        self.currentRFI = updated
                    }
                }
            } catch APIError.networkError, APIError.invalidResponse {
                // Offline or server unavailable: keep optimistic state
                print("Network error fetching RFI, keeping optimistic state")
            } catch APIError.tokenExpired {
                await MainActor.run { sessionManager.handleTokenExpiration() }
            } catch APIError.forbidden {
                await MainActor.run { sessionManager.handleTokenExpiration() }
            } catch {
                print("Error fetching updated RFI: \(error)")
            }
        }
    }

    private func shouldUpdateFromServer(_ serverRFI: RFI) -> Bool {
        // Don't update if we have optimistic changes that the server hasn't reflected yet
        // Check if response statuses differ significantly
        guard let localResponses = currentRFI.responses,
              let serverResponses = serverRFI.responses else {
            return true // Update if we don't have response data to compare
        }

        // If we have approved responses locally but server shows them as pending,
        // don't overwrite our optimistic state
        for localResponse in localResponses {
            if localResponse.status.lowercased() == "approved" {
                if let serverResponse = serverResponses.first(where: { $0.id == localResponse.id }) {
                    if serverResponse.status.lowercased() == "pending" {
                        print("Server shows approved response as pending, keeping optimistic state")
                        return false
                    }
                }
            }
        }

        return true // Update if no conflicts detected
    }

    // MARK: - Openers
    private func openAttachment(_ attachment: RFI.RFIAttachment) {
        let urlString = attachment.downloadUrl ?? attachment.fileUrl
        // Prefer in-app preview via WebView
        if let url = URL(string: urlString) {
            previewURL = url
            return
        }
        if urlString.hasPrefix("tenants/") || urlString.hasPrefix("projects/") {
            if let url = URL(string: "\(APIClient.baseURL)/\(urlString)") {
                previewURL = url
                return
            }
        }
        print("Unable to preview attachment URL: \(urlString)")
    }

    // Removed external opener for drawings; drawings now use in-app preview via sheet

    private func optimisticallySetResponseStatus(responseId: Int, status: String, rejectionReason: String? = nil) {
        guard var responses = currentRFI.responses else { return }
        if let index = responses.firstIndex(where: { $0.id == responseId }) {
            let existing = responses[index]
            let updated = RFI.RFIResponseItem(
                id: existing.id,
                content: existing.content,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt,
                status: status,
                rejectionReason: rejectionReason,
                user: existing.user,
                attachments: existing.attachments
            )
            responses[index] = updated
            let newAccepted = status.lowercased() == "approved" ? updated : currentRFI.acceptedResponse
            currentRFI = currentRFI.replacing(responses: responses, acceptedResponse: newAccepted)
        }
    }

    private var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let simpleISO = ISO8601DateFormatter()
        let source = currentRFI.createdAt ?? currentRFI.submittedDate
        if let s = source {
            if let d = iso.date(from: s) ?? simpleISO.date(from: s) {
                return formatter.string(from: d)
            }
        }
        return "Unknown"
    }
    
    private var canRespond: Bool {
        RFIPermissions.canRespond(user: sessionManager.user, to: currentRFI)
    }
    
    private var canReview: Bool { RFIPermissions.canReview(user: sessionManager.user, for: currentRFI) }
    
    private var canEdit: Bool { RFIPermissions.canEdit(user: sessionManager.user, rfi: currentRFI) }
    
    private var hasManageAnyRFIs: Bool { (sessionManager.user?.permissions ?? []).contains { $0.name == "manage_any_rfis" } }
    
    private var shouldShowAddDrawingButton: Bool { RFIPermissions.shouldShowAddDrawingButton(user: sessionManager.user, rfi: currentRFI) }
    

    // Disable review actions while submitting/approving or when a local
    // optimistic response is still present (uses a temporary high id).
    private var shouldDisableReviewActions: Bool {
        return isSubmittingResponse || isUpdatingStatus || hasOptimisticPendingResponse
    }

    private var hasOptimisticPendingResponse: Bool {
        guard let responses = currentRFI.responses else { return false }
        return responses.contains { $0.status.lowercased() == "pending" && $0.id >= 1_000_000 }
    }

    
    private var statusColor: Color {
        switch currentRFI.status?.lowercased() {
        case "draft": return .gray
        case "submitted": return .blue
        case "in_review": return .orange
        case "responded": return .green
        case "closed": return .purple
        default: return .gray
        }
    }
    
    // MARK: - Section helpers to reduce body complexity
    @ViewBuilder
    private func responsesSectionView() -> some View {
        if let responses = currentRFI.responses, !responses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Responses")
                    .font(.headline)
                // Debug info for response review permissions
                // Removed debug: Can Review
                ForEach(responses, id: \.id) { response in
                    ResponseCard(
                        response: response,
                        canReview: canReview,
                        rfiStatus: currentRFI.status,
                        disabled: shouldDisableReviewActions
                    ) { action in
                        handleResponseAction(response, action: action)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func submitResponseSectionView() -> some View {
        if canRespond && currentRFI.status?.lowercased() != "closed" {
            VStack(alignment: .leading, spacing: 8) {
                Text("Submit Response")
                    .font(.headline)
                // Debug info
                    // Removed debug: Can Respond
                TextEditor(text: $responseText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                HStack {
                    Button("Submit Response") { submitResponse() }
                        .accessibilityIdentifier("rfi_submit_response_button")
                        .disabled(responseText.isEmpty || isSubmittingResponse)
                        .buttonStyle(.borderedProminent)
                    if isSubmittingResponse { ProgressView().scaleEffect(0.8) }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        } else {
            EmptyView()
        }
    }

    
    // MARK: - Additional section helpers
    @ViewBuilder
    private func headerSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RFI #\(currentRFI.number)")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text(currentRFI.status?.capitalized ?? "Unknown")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
            Text(currentRFI.title ?? "Untitled RFI")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Created: \(formattedCreatedAt)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func infoSectionView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            infoSectionHeader()
            infoSectionCards()
            assignedUsersSection()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Info Section Helper Functions
    @ViewBuilder
    private func infoSectionHeader() -> some View {
        HStack {
            Text("RFI Information")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func infoSectionCards() -> some View {
        VStack(spacing: 16) {
            managerCardView()
            submittedByCardView()
        }
    }
    
    @ViewBuilder
    private func managerCardView() -> some View {
        if let manager = currentRFI.manager {
            managerInfoCard(manager: manager)
        } else if let managerId = currentRFI.managerId {
            managerIdCard(managerId: managerId)
        }
    }
    
    @ViewBuilder
    private func managerInfoCard(manager: RFI.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            managerCardHeader()
            managerCardContent(manager: manager)
        }
    }
    
    @ViewBuilder
    private func managerCardHeader() -> some View {
        HStack {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#059669"))
            Text("Manager")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func managerCardContent(manager: RFI.UserInfo) -> some View {
        HStack(spacing: 12) {
            managerAvatar(manager: manager)
            managerInfo(manager: manager)
            Spacer()
            statusIndicator()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func managerAvatar(manager: RFI.UserInfo) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#059669").opacity(0.15))
                .frame(width: 36, height: 36)
            Text(String(manager.firstName.prefix(1) + manager.lastName.prefix(1)))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#059669"))
        }
    }
    
    @ViewBuilder
    private func managerInfo(manager: RFI.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(manager.firstName) \(manager.lastName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Text("Responsible for RFI management")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func statusIndicator() -> some View {
        Circle()
            .fill(Color(hex: "#10B981"))
            .frame(width: 8, height: 8)
    }
    
    @ViewBuilder
    private func managerIdCard(managerId: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            managerCardHeader()
            
            if let manager = managerUser {
                // Show full manager info once loaded
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#059669").opacity(0.15))
                            .frame(width: 36, height: 36)
                        Text(String((manager.firstName?.prefix(1) ?? "?") + (manager.lastName?.prefix(1) ?? "")))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#059669"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(manager.firstName ?? "Unknown") \(manager.lastName ?? "Manager")")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Responsible for RFI management")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    statusIndicator()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else if isLoadingManager {
                // Show loading state
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#059669").opacity(0.15))
                            .frame(width: 36, height: 36)
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loading manager...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Fetching details")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    statusIndicator()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else {
                // Fallback when manager couldn't be loaded
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#059669").opacity(0.15))
                            .frame(width: 36, height: 36)
                        Text("?")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#059669"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manager")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Assigned to this RFI")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    statusIndicator()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .onAppear {
            fetchManagerDetails()
        }
    }
    
    @ViewBuilder
    private func submittedByCardView() -> some View {
        if let submittedBy = currentRFI.submittedBy {
            VStack(alignment: .leading, spacing: 12) {
                submittedByCardHeader()
                submittedByCardContent(submittedBy: submittedBy)
            }
        }
    }
    
    @ViewBuilder
    private func submittedByCardHeader() -> some View {
        HStack {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#7C3AED"))
            Text("Submitted By")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func submittedByCardContent(submittedBy: RFI.UserInfo) -> some View {
        HStack(spacing: 12) {
            submittedByAvatar(submittedBy: submittedBy)
            submittedByInfo(submittedBy: submittedBy)
            Spacer()
            statusIndicator()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func submittedByAvatar(submittedBy: RFI.UserInfo) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#7C3AED").opacity(0.15))
                .frame(width: 36, height: 36)
            Text(String(submittedBy.firstName.prefix(1) + submittedBy.lastName.prefix(1)))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#7C3AED"))
        }
    }
    
    @ViewBuilder
    private func submittedByInfo(submittedBy: RFI.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(submittedBy.firstName) \(submittedBy.lastName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Text("RFI creator")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func assignedUsersSection() -> some View {
        if let assignedUsers = currentRFI.assignedUsers, !assignedUsers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                assignedUsersHeader(count: assignedUsers.count)
                assignedUsersList(users: assignedUsers)
            }
        }
    }
    
    @ViewBuilder
    private func assignedUsersHeader(count: Int) -> some View {
        HStack {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#F59E0B"))
            Text("Assigned Users")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func assignedUsersList(users: [RFI.AssignedUser]) -> some View {
        VStack(spacing: 8) {
            ForEach(users, id: \.user.id) { au in
                assignedUserRow(assignedUser: au)
            }
        }
    }
    
    @ViewBuilder
    private func assignedUserRow(assignedUser: RFI.AssignedUser) -> some View {
        HStack(spacing: 12) {
            assignedUserAvatar(user: assignedUser.user)
            assignedUserInfo(user: assignedUser.user)
            Spacer()
            statusIndicator()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func assignedUserAvatar(user: RFI.UserInfo) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#3B82F6").opacity(0.15))
                .frame(width: 36, height: 36)
            Text(String(user.firstName.prefix(1) + user.lastName.prefix(1)))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#3B82F6"))
        }
    }
    
    @ViewBuilder
    private func assignedUserInfo(user: RFI.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(user.firstName) \(user.lastName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Text("Assigned team member")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // Helper function for info cards
    @ViewBuilder
    private func infoCard(icon: String, iconColor: Color, title: String, value: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.gray.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func querySectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query")
                .font(.headline)
            Text(currentRFI.query ?? "No query provided")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func attachmentsSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attachments")
                    .font(.headline)
                Spacer()
                if canEdit {
                    Button("Add") { showAttachmentUploader = true }
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            if let attachments = currentRFI.attachments, !attachments.isEmpty {
                ForEach(attachments, id: \.id) { attachment in
                    let urlString = attachment.downloadUrl ?? attachment.fileUrl
                    Button {
                        openAttachment(attachment)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((URL(string: urlString)?.lastPathComponent ?? (urlString as NSString).lastPathComponent))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("Tap to preview")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            } else {
                Text("No attachments")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func drawingsSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Linked Drawings")
                    .font(.headline)
                Spacer()
                if shouldShowAddDrawingButton {
                    Button("Add") { showDrawingSelector = true }
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            if let drawings = currentRFI.drawings, !drawings.isEmpty {
                ForEach(drawings, id: \.id) { drawing in
                    RFIDrawingRow(drawing: drawing) { urlString in
                        let absolute: URL? = {
                            if let u = URL(string: urlString) { return u }
                            if urlString.hasPrefix("tenants/") || urlString.hasPrefix("projects/") {
                                return URL(string: "\(APIClient.baseURL)/\(urlString)")
                            }
                            return nil
                        }()
                        if let url = absolute { previewURL = url }
                    }
                }
            } else {
                Text("No drawings linked")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSectionView()

                infoSectionView()
                
                querySectionView()
                
                // Response Section
                if let responses = currentRFI.responses, !responses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Responses")
                            .font(.headline)
                        
                        // Removed debug: Can Review
                        
                        ForEach(responses, id: \.id) { response in
                            ResponseCard(
                                response: response,
                                canReview: canReview,
                                rfiStatus: currentRFI.status,
                                disabled: shouldDisableReviewActions
                            ) { action in
                                handleResponseAction(response, action: action)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                
                // Submit Response (if user can respond and RFI is not closed)
                if canRespond && currentRFI.status?.lowercased() != "closed" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Submit Response")
                            .font(.headline)
                        
                        // Removed debug: Can Respond
                        
                        TextEditor(text: $responseText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        HStack {
                            Button("Submit Response") {
                                submitResponse()
                            }
                            .disabled(responseText.isEmpty || isSubmittingResponse)
                            .buttonStyle(.borderedProminent)
                            
                            if isSubmittingResponse {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                } else {
                    EmptyView()
                }
                
                
                attachmentsSectionView()
                
                drawingsSectionView()
            }
            .padding()
        }
        .navigationTitle("RFI Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding<Bool>(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                AttachmentWebPreview(url: url)
            }
        }
        .sheet(isPresented: $showAttachmentUploader, onDismiss: { fetchUpdatedRFI() }) {
            RFIAttachmentUploader(projectId: rfi.projectId, rfiId: rfi.id) {
                // Refresh RFI data
            }
        }
        .sheet(isPresented: $showDrawingSelector, onDismiss: { fetchUpdatedRFI() }) {
            RFIDrawingSelector(projectId: rfi.projectId, rfiId: rfi.id) {
                // Refresh RFI data
            }
        }
        .alert("Reject Response", isPresented: $showResponseReview) {
            TextField("Rejection reason", text: $rejectionReason)
            Button("Cancel", role: .cancel) {
                rejectionReason = ""
                selectedResponseForReview = nil
            }
            Button("Reject", role: .destructive) {
                if let response = selectedResponseForReview {
                    rejectResponse(response.id, reason: rejectionReason)
                }
                rejectionReason = ""
                selectedResponseForReview = nil
            }
        } message: {
            Text("Please provide a reason for rejecting this response.")
        }
        .task { fetchUpdatedRFI() }
    }
    
    private func submitResponse() {
        guard !responseText.isEmpty else { return }
        isSubmittingResponse = true
        // Optimistically append a local response for immediate UI feedback
        // Build a lightweight placeholder user label
        let meFirst = (sessionManager.user?.firstName ?? "You")
        let meLast = (sessionManager.user?.lastName ?? "")
        // Use the public encoder-friendly initializer by decoding from inline JSON
        let optimisticUser: RFI.UserInfo = {
            let temp = [
                "id": sessionManager.user?.id ?? -1,
                "tenants": [["firstName": meFirst, "lastName": meLast]]
            ] as [String : Any]
            let data = try! JSONSerialization.data(withJSONObject: temp)
            return try! JSONDecoder().decode(RFI.UserInfo.self, from: data)
        }()
        let optimistic = RFI.RFIResponseItem(
            id: Int.random(in: 1_000_000...9_999_999),
            content: responseText,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: nil,
            status: "pending",
            rejectionReason: nil,
            user: optimisticUser,
            attachments: nil
        )
        if var existing = currentRFI.responses { existing.append(optimistic); currentRFI = currentRFI.replacing(responses: existing) }
        Task {
            do {
                try await APIClient.submitRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, content: responseText, token: token)
                await MainActor.run {
                    isSubmittingResponse = false
                    responseText = ""
                }
                // Immediately refresh to replace optimistic item with real one
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
                await MainActor.run {
                    isSubmittingResponse = false
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    isSubmittingResponse = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run { isSubmittingResponse = false }
                print("Error submitting response: \(error)")
            }
        }
    }
    
    private func handleResponseAction(_ response: RFI.RFIResponseItem, action: ResponseAction) {
        // Avoid acting on placeholder ids or while an in-flight operation is running
        if shouldDisableReviewActions || response.id >= 1_000_000 { return }
        switch action {
        case .approve:
            acceptResponseAndClose(response.id)
        case .reject:
            showResponseReview = true
            selectedResponseForReview = response
        }
    }
    
    private func acceptResponseAndClose(_ responseId: Int) {
        isUpdatingStatus = true
        Task {
            do {
                // Find all pending responses except the one being accepted
                let pendingResponsesToReject = currentRFI.responses?.filter {
                    $0.id != responseId && $0.status.lowercased() == "pending"
                } ?? []

                // Optimistic UI: reject all other pending responses
                for response in pendingResponsesToReject {
                    await MainActor.run {
                        optimisticallySetResponseStatus(
                            responseId: response.id,
                            status: "rejected",
                            rejectionReason: "Another response was accepted as the answer"
                        )
                    }
                }

                // Optimistic UI: accept the selected response (clear any rejection reason)
                await MainActor.run { optimisticallySetResponseStatus(responseId: responseId, status: "approved", rejectionReason: nil) }

                // Reject all other pending responses
                for response in pendingResponsesToReject {
                    try await APIClient.reviewRFIResponse(
                        projectId: currentRFI.projectId,
                        rfiId: currentRFI.id,
                        responseId: response.id,
                        status: "rejected",
                        rejectionReason: "Another response was accepted as the answer",
                        token: token
                    )
                }

                // Accept the selected response
                try await APIClient.reviewRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, responseId: responseId, status: "approved", token: token)

                // Optimistically mark as completed
                await MainActor.run { isUpdatingStatus = false }

                // Close immediately after accept
                try await APIClient.closeRFI(projectId: currentRFI.projectId, rfiId: currentRFI.id, token: token)
                await MainActor.run {
                    self.currentRFI = RFI(
                        id: currentRFI.id,
                        number: currentRFI.number,
                        title: currentRFI.title,
                        description: currentRFI.description,
                        query: currentRFI.query,
                        status: "closed",
                        createdAt: currentRFI.createdAt,
                        submittedDate: currentRFI.submittedDate,
                        returnDate: currentRFI.returnDate,
                        closedDate: ISO8601DateFormatter().string(from: Date()),
                        projectId: currentRFI.projectId,
                        submittedBy: currentRFI.submittedBy,
                        managerId: currentRFI.managerId,
                        manager: currentRFI.manager,
                        assignedUsers: currentRFI.assignedUsers,
                        attachments: currentRFI.attachments,
                        drawings: currentRFI.drawings,
                        responses: currentRFI.responses,
                        acceptedResponse: currentRFI.acceptedResponse
                    )
                    onRefresh?()
                }

                // Fetch updated data once at the end to ensure we have the latest state
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
                await MainActor.run {
                    isUpdatingStatus = false
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    isUpdatingStatus = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run { isUpdatingStatus = false }
                print("Error accepting response: \(error)")
            }
        }
    }
    
    private func rejectResponse(_ responseId: Int, reason: String) {
        isUpdatingStatus = true
        Task {
            do {
                // Optimistic UI: mark as rejected to hide buttons immediately
                await MainActor.run { optimisticallySetResponseStatus(responseId: responseId, status: "rejected", rejectionReason: reason) }
                try await APIClient.reviewRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, responseId: responseId, status: "rejected", rejectionReason: reason, token: token)
                await MainActor.run { isUpdatingStatus = false }
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
                await MainActor.run {
                    isUpdatingStatus = false
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    isUpdatingStatus = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run { isUpdatingStatus = false }
                print("Error rejecting response: \(error)")
            }
        }
    }
    

    // no-op helpers removed
}

enum ResponseAction {
    case approve
    case reject
}

struct ResponseCard: View {
    let response: RFI.RFIResponseItem
    let canReview: Bool
    let rfiStatus: String?
    var disabled: Bool = false
    let onAction: (ResponseAction) -> Void
    
    private var formattedCreatedAt: String {
        let iso = ISO8601DateFormatter()
        // Support fractional seconds
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISO = ISO8601DateFormatter()
        if let date = iso.date(from: response.createdAt) ?? fallbackISO.date(from: response.createdAt) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return response.createdAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(response.content)
                .font(.body)
            
            HStack {
                Text("By: \(response.user.firstName) \(response.user.lastName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formattedCreatedAt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if response.status.lowercased() == "pending" && canReview && rfiStatus?.lowercased() != "closed" {
                HStack {
                    Button("Approve") {
                        onAction(.approve)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(disabled)
                    .accessibilityIdentifier("rfi_response_approve_button")
                    
                    Button("Reject") {
                        onAction(.reject)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(disabled)
                    .accessibilityIdentifier("rfi_response_reject_button")
                }
            } else {
                // Removed debug: Response Status text
                HStack {
                    Text("Status: \(response.status.capitalized)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(response.status).opacity(0.2))
                        .foregroundColor(statusColor(response.status))
                        .cornerRadius(4)
                    
                    // Show appropriate message based on status
                    if response.status.lowercased() == "approved" || response.status.lowercased() == "accepted" {
                        Text("Accepted as the answer")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if let rejectionReason = response.rejectionReason, response.status.lowercased() == "rejected" {
                        Text("Reason: \(rejectionReason)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved", "accepted": return .green
        case "rejected": return .red
        case "pending": return .orange
        default: return .gray
        }
    }
}

struct RFIDrawingRow: View {
    let drawing: RFI.RFIDrawing
    let onOpen: (String) -> Void
    
    var body: some View {
        Button(action: {
            if let urlString = drawing.downloadUrl { onOpen(urlString) }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "#3B82F6"))
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(drawing.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text("Drawing #\(drawing.number)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Rev \(drawing.revisionNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(drawing.downloadUrl == nil)
    }
}

struct AttachmentWebPreview: View {
    let url: URL
    @State private var isLoading = true
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            WebView(url: url, isLoading: $isLoading, loadError: $loadError)
            if isLoading {
                ProgressView()
            }
            if let err = loadError {
                Text(err).foregroundColor(.red).padding()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.secondary)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(12)
            .accessibilityLabel("Close preview")
        }
    }
}
