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
    @State private var showCloseRFIDialog = false
    @State private var closingRFI = false
    @State private var showAcceptRequiredAlert = false
    @State private var previewURL: URL? = nil
    
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
            } catch APIError.forbidden {
                await MainActor.run { sessionManager.handleTokenExpiration() }
            } catch {
                print("Error fetching updated RFI: \(error)")
            }
        }
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
    
    private var hasAcceptedResponse: Bool { RFIPermissions.hasAcceptedResponse(currentRFI) }

    // Disable review actions while submitting/approving/closing or when a local
    // optimistic response is still present (uses a temporary high id).
    private var shouldDisableReviewActions: Bool {
        return isSubmittingResponse || isUpdatingStatus || closingRFI || hasOptimisticPendingResponse
    }

    private var hasOptimisticPendingResponse: Bool {
        guard let responses = currentRFI.responses else { return false }
        return responses.contains { $0.status.lowercased() == "pending" && $0.id >= 1_000_000 }
    }

    private var canClose: Bool { RFIPermissions.canClose(user: sessionManager.user, rfi: currentRFI) }
    
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
                .accessibilityIdentifier("rfi_close_button")
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
                if let manager = currentRFI.manager ?? (currentRFI.submittedBy?.id == currentRFI.managerId ? currentRFI.submittedBy : nil) {
                    HStack {
                        Text("Manager:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(manager.firstName) \(manager.lastName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let managerId = currentRFI.managerId {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assigned Users:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(assignedUsers, id: \.user.id) { au in
                            HStack {
                                Circle().fill(Color.blue.opacity(0.15)).frame(width: 18, height: 18)
                                    .overlay(Text(String(au.user.firstName.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundColor(.blue))
                                Text("\(au.user.firstName) \(au.user.lastName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
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
                
                descriptionSectionView()
                
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

                // Optimistic UI: accept the selected response
                await MainActor.run { optimisticallySetResponseStatus(responseId: responseId, status: "approved") }

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
                        manager: currentRFI.manager,
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
                        manager: currentRFI.manager,
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
            } catch APIError.forbidden {
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

    // no-op helpers removed
}

enum ResponseAction {
    case approve
    case reject
}

struct ResponseCard: View {
    let response: RFI.RFIResponseItem
    let canReview: Bool
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
            
            if response.status.lowercased() == "pending" && canReview {
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
