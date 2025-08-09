import SwiftUI

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
    @State private var showCloseRFIDialog = false
    @State private var closingRFI = false
    @State private var showAcceptRequiredAlert = false
    
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
    
    // Function to fetch updated RFI data
    private func fetchUpdatedRFI() {
        Task {
            do {
                // Try online first
                let updated = try await APIClient.fetchRFI(projectId: currentRFI.projectId, rfiId: currentRFI.id, token: token)
                await MainActor.run { self.currentRFI = updated }
            } catch APIError.networkError, APIError.invalidResponse {
                // Offline or server unavailable: optimistically update local state for UI responsiveness
                await MainActor.run {
                    // Best-effort: toggle status if we know the action implies it
                    // Call sites should set desired optimistic status via closures if needed
                }
            } catch APIError.tokenExpired {
                await MainActor.run { sessionManager.handleTokenExpiration() }
            } catch {
                print("Error fetching updated RFI: \(error)")
            }
        }
    }

    private var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let createdAtDateStr = rfi.createdAt, let date = ISO8601DateFormatter().date(from: createdAtDateStr) {
            return formatter.string(from: date)
        }
        return "Unknown"
    }
    
    private var canRespond: Bool {
        guard let currentUser = sessionManager.user else { return false }
        
        // Check if user is assigned to this RFI
        let isAssigned = currentRFI.assignedUsers?.contains { $0.user.id == currentUser.id } == true
        
        // Check if user has manager permissions
        let permissions = currentUser.permissions ?? []
        let isManager = permissions.contains(where: { $0.name == "manage_rfis" }) || 
                       permissions.contains(where: { $0.name == "manage_any_rfis" })
        
        // User can respond if they are assigned OR if they are a manager
        return isAssigned || isManager
    }
    
    private var canReview: Bool {
        guard let currentUser = sessionManager.user else { return false }
        
        // Check if user is the RFI manager
        let isRFIManager = currentRFI.managerId == currentUser.id
        
        // Check if user has manager permissions
        let permissions = currentUser.permissions ?? []
        let isManager = permissions.contains(where: { $0.name == "manage_rfis" }) || 
                       permissions.contains(where: { $0.name == "manage_any_rfis" })
        
        // User can review if they are the RFI manager OR if they have manager permissions
        return isRFIManager || isManager
    }
    
    private var canEdit: Bool {
        guard let currentUser = sessionManager.user else { return false }
        
        // Check if user is assigned to this RFI
        let isAssigned = currentRFI.assignedUsers?.contains { $0.user.id == currentUser.id } == true
        
        // Check if user is the RFI manager
        let isRFIManager = currentRFI.managerId == currentUser.id
        
        // Check if user has manager permissions
        let permissions = currentUser.permissions ?? []
        let isManager = permissions.contains(where: { $0.name == "manage_rfis" }) || 
                       permissions.contains(where: { $0.name == "manage_any_rfis" })
        
        // User can edit if they are assigned OR if they are the RFI manager OR if they have manager permissions
        return isAssigned || isRFIManager || isManager
    }
    
    private var hasAcceptedResponse: Bool {
        // acceptedResponse provided by API OR any response with status approved
        if currentRFI.acceptedResponse != nil { return true }
        if let responses = currentRFI.responses {
            return responses.contains { $0.status.lowercased() == "approved" }
        }
        return false
    }

    private var canClose: Bool {
        guard let currentUser = sessionManager.user else { return false }
        
        // Check if user is the RFI manager
        let isRFIManager = currentRFI.managerId == currentUser.id
        
        // Check if user has manager permissions
        let permissions = currentUser.permissions ?? []
        let isManager = permissions.contains(where: { $0.name == "manage_rfis" }) || 
                       permissions.contains(where: { $0.name == "manage_any_rfis" })
        
        // User can close only if they are manager (or have permission) AND an accepted response exists
        return (isRFIManager || isManager) && hasAcceptedResponse
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
                Text("Can Review: " + (canReview ? "Yes" : "No"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(responses, id: \.id) { response in
                    ResponseCard(response: response, canReview: canReview) { action in
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
                Text("Can Respond: " + (canRespond ? "Yes" : "No"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $responseText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                HStack {
                    Button("Submit Response") { submitResponse() }
                        .disabled(responseText.isEmpty || isSubmittingResponse)
                        .buttonStyle(.borderedProminent)
                    if isSubmittingResponse { ProgressView().scaleEffect(0.8) }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        } else {
            // Debug info for why response section is not showing
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug Info")
                    .font(.headline)
                Text("Can Respond: " + (canRespond ? "Yes" : "No"))
                    .font(.caption)
                Text("RFI Status: " + (currentRFI.status ?? "Unknown"))
                    .font(.caption)
                Text("Is Closed: " + ((currentRFI.status?.lowercased() == "closed") ? "Yes" : "No"))
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func closeSectionView() -> some View {
        if currentRFI.status?.lowercased() != "closed" && (currentRFI.responses?.count ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Close RFI")
                    .font(.headline)
                Button("Close RFI") {
                    if hasAcceptedResponse && canClose {
                        showCloseRFIDialog = true
                    } else {
                        showAcceptRequiredAlert = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(closingRFI)
                if closingRFI {
                    ProgressView("Closing RFI...")
                        .scaleEffect(0.8)
                }
                if !hasAcceptedResponse {
                    Text("You must accept a response before closing the RFI.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
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
    private func descriptionSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(currentRFI.description ?? "No description provided")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func infoSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RFI Information")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                if let managerId = currentRFI.managerId {
                    HStack {
                        Text("Manager:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("User ID: \(managerId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let assignedUsers = currentRFI.assignedUsers, !assignedUsers.isEmpty {
                    HStack {
                        Text("Assigned Users:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(assignedUsers.count) user(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let submittedBy = currentRFI.submittedBy {
                    HStack {
                        Text("Submitted By:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(submittedBy.firstName) \(submittedBy.lastName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
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
                    AttachmentRow(fileUrl: attachment.fileUrl)
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
                if canEdit {
                    Button("Add") { showDrawingSelector = true }
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            if let drawings = currentRFI.drawings, !drawings.isEmpty {
                ForEach(drawings, id: \.id) { drawing in
                    RFIDrawingRow(drawing: drawing)
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
                
                descriptionSectionView()
                
                infoSectionView()
                
                querySectionView()
                
                // Response Section
                if let responses = currentRFI.responses, !responses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Responses")
                            .font(.headline)
                        
                        // Debug info for response review permissions
                        Text("Can Review: \(canReview ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(responses, id: \.id) { response in
                            ResponseCard(response: response, canReview: canReview) { action in
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
                        
                        // Debug info
                        Text("Can Respond: \(canRespond ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
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
                    // Debug info for why response section is not showing
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug Info")
                            .font(.headline)
                        
                        Text("Can Respond: \(canRespond ? "Yes" : "No")")
                            .font(.caption)
                        Text("RFI Status: \(currentRFI.status ?? "Unknown")")
                            .font(.caption)
                        Text("Is Closed: \(currentRFI.status?.lowercased() == "closed" ? "Yes" : "No")")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                
                // Close RFI (enabled only if an accepted response exists)
                if currentRFI.status?.lowercased() != "closed" && (currentRFI.responses?.count ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Close RFI")
                            .font(.headline)
                        
                        Button("Close RFI") {
                            if hasAcceptedResponse && canClose {
                                showCloseRFIDialog = true
                            } else {
                                showAcceptRequiredAlert = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(closingRFI)
                        
                        if closingRFI {
                            ProgressView("Closing RFI...")
                                .scaleEffect(0.8)
                        }
                        if !hasAcceptedResponse {
                            Text("You must accept a response before closing the RFI.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                
                attachmentsSectionView()
                
                drawingsSectionView()
            }
            .padding()
        }
        .navigationTitle("RFI Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAttachmentUploader) {
            RFIAttachmentUploader(projectId: rfi.projectId, rfiId: rfi.id) {
                // Refresh RFI data
            }
        }
        .sheet(isPresented: $showDrawingSelector) {
            RFIDrawingSelector(projectId: rfi.projectId, rfiId: rfi.id) {
                // Refresh RFI data
            }
        }
        .alert("Close RFI", isPresented: $showCloseRFIDialog) {
            Button("Cancel", role: .cancel) { 
                print("Close RFI dialog cancelled")
            }
            Button("Close RFI", role: .destructive) {
                print("Close RFI confirmed in dialog")
                closeRFI()
            }
        } message: {
            Text("Are you sure you want to close this RFI? This action cannot be undone.")
        }
        .alert("Accept a Response First", isPresented: $showAcceptRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To close an RFI, you must first accept one of the responses (mark it as the answer).")
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
    }
    
    private func submitResponse() {
        guard !responseText.isEmpty else { return }
        isSubmittingResponse = true
        Task {
            do {
                try await APIClient.submitRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, content: responseText, token: token)
                await MainActor.run {
                    isSubmittingResponse = false
                    responseText = ""
                }
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
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
                try await APIClient.reviewRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, responseId: responseId, status: "approved", token: token)
                // Optimistically mark accepted
                await MainActor.run { isUpdatingStatus = false }
                fetchUpdatedRFI()
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
                        assignedUsers: currentRFI.assignedUsers,
                        attachments: currentRFI.attachments,
                        drawings: currentRFI.drawings,
                        responses: currentRFI.responses,
                        acceptedResponse: currentRFI.acceptedResponse
                    )
                    onRefresh?()
                }
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
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
                try await APIClient.reviewRFIResponse(projectId: currentRFI.projectId, rfiId: currentRFI.id, responseId: responseId, status: "rejected", rejectionReason: reason, token: token)
                await MainActor.run { isUpdatingStatus = false }
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
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
    
    private func closeRFI() {
        closingRFI = true
        Task {
            do {
                try await APIClient.closeRFI(projectId: currentRFI.projectId, rfiId: currentRFI.id, token: token)
                await MainActor.run {
                    closingRFI = false
                    // Optimistically flip status for instant UI feedback
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
                        assignedUsers: currentRFI.assignedUsers,
                        attachments: currentRFI.attachments,
                        drawings: currentRFI.drawings,
                        responses: currentRFI.responses,
                        acceptedResponse: currentRFI.acceptedResponse
                    )
                    onRefresh?()
                }
                // Then fetch authoritative state when online (fallback to optimistic if offline)
                fetchUpdatedRFI()
            } catch APIError.tokenExpired {
                await MainActor.run {
                    closingRFI = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run { closingRFI = false }
                print("Error closing RFI: \(error)")
            }
        }
    }
}

enum ResponseAction {
    case approve
    case reject
}

struct ResponseCard: View {
    let response: RFI.RFIResponseItem
    let canReview: Bool
    let onAction: (ResponseAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(response.content)
                .font(.body)
            
            HStack {
                Text("By: \(response.user.firstName) \(response.user.lastName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(response.createdAt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if response.status.lowercased() == "pending" && canReview {
                HStack {
                    Button("Approve") {
                        onAction(.approve)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button("Reject") {
                        onAction(.reject)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                // Debug info for response status
                Text("Response Status: \(response.status)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Status: \(response.status.capitalized)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(response.status).opacity(0.2))
                        .foregroundColor(statusColor(response.status))
                        .cornerRadius(4)
                    
                    if let rejectionReason = response.rejectionReason {
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
        case "approved": return .green
        case "rejected": return .red
        case "pending": return .orange
        default: return .gray
        }
    }
}

struct RFIDrawingRow: View {
    let drawing: RFI.RFIDrawing
    
    var body: some View {
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
            
            if drawing.downloadUrl != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
    }
}
