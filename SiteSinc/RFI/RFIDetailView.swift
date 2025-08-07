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
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(currentRFI.id)")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let updatedRFI = try JSONDecoder().decode(RFI.self, from: data)
                    await MainActor.run {
                        self.currentRFI = updatedRFI
                    }
                }
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
    
    private var canClose: Bool {
        guard let currentUser = sessionManager.user else { return false }
        
        // Check if user is the RFI manager
        let isRFIManager = currentRFI.managerId == currentUser.id
        
        // Check if user has manager permissions
        let permissions = currentUser.permissions ?? []
        let isManager = permissions.contains(where: { $0.name == "manage_rfis" }) || 
                       permissions.contains(where: { $0.name == "manage_any_rfis" })
        
        // User can close if they are the RFI manager OR if they have manager permissions
        return isRFIManager || isManager
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
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
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    
                    Text(currentRFI.description ?? "No description provided")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
                
                // RFI Information
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
                
                // Query
                VStack(alignment: .leading, spacing: 8) {
                    Text("Query")
                        .font(.headline)
                    
                    Text(currentRFI.query ?? "No query provided")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
                
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
                
                // Close RFI (if user can close and RFI has responses)
                if canClose && currentRFI.status?.lowercased() != "closed" && (currentRFI.responses?.count ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Close RFI")
                            .font(.headline)
                        
                        Button("Close RFI") {
                            showCloseRFIDialog = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(closingRFI)
                        
                        if closingRFI {
                            ProgressView("Closing RFI...")
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                
                // Attachments
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Attachments")
                            .font(.headline)
                        
                        Spacer()
                        
                        if canEdit {
                            Button("Add") {
                                showAttachmentUploader = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    
                    if let attachments = rfi.attachments, !attachments.isEmpty {
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
                
                // Drawings
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Linked Drawings")
                            .font(.headline)
                        
                        Spacer()
                        
                        if canEdit {
                            Button("Add") {
                                showDrawingSelector = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    
                    if let drawings = rfi.drawings, !drawings.isEmpty {
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
        guard !responseText.isEmpty else { 
            print("Response text is empty")
            return 
        }
        
        print("Submitting response: \(responseText)")
        isSubmittingResponse = true
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(currentRFI.id)/responses")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["content": responseText]
                request.httpBody = try JSONEncoder().encode(body)
                
                print("Making request to: \(url)")
                let (_, response) = try await URLSession.shared.data(for: request)
                
                                 await MainActor.run {
                     isSubmittingResponse = false
                     if let httpResponse = response as? HTTPURLResponse {
                         print("Response status: \(httpResponse.statusCode)")
                         if httpResponse.statusCode == 201 {
                             responseText = ""
                             print("Response submitted successfully")
                             // Fetch updated RFI data to refresh the view
                             fetchUpdatedRFI()
                         } else {
                             print("Failed to submit response: \(httpResponse.statusCode)")
                         }
                     }
                 }
            } catch {
                await MainActor.run {
                    isSubmittingResponse = false
                    print("Error submitting response: \(error)")
                }
            }
        }
    }
    
    private func handleResponseAction(_ response: RFI.RFIResponseItem, action: ResponseAction) {
        switch action {
        case .approve:
            acceptResponse(response.id)
        case .reject:
            showResponseReview = true
            selectedResponseForReview = response
        }
    }
    
    private func acceptResponse(_ responseId: Int) {
        isUpdatingStatus = true
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(currentRFI.id)/responses/\(responseId)/accept")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    isUpdatingStatus = false
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            print("Response accepted successfully")
                            fetchUpdatedRFI()
                        } else {
                            print("Failed to accept response: \(httpResponse.statusCode)")
                        }
                    } else {
                        print("Failed to accept response: Invalid response type")
                    }
                }
            } catch {
                await MainActor.run {
                    isUpdatingStatus = false
                    print("Error accepting response: \(error)")
                }
            }
        }
    }
    
    private func rejectResponse(_ responseId: Int, reason: String) {
        isUpdatingStatus = true
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(currentRFI.id)/responses/reject")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["reason": reason]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    isUpdatingStatus = false
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            print("Response rejected successfully")
                            fetchUpdatedRFI()
                        } else {
                            print("Failed to reject response: \(httpResponse.statusCode)")
                        }
                    } else {
                        print("Failed to reject response: Invalid response type")
                    }
                }
            } catch {
                await MainActor.run {
                    isUpdatingStatus = false
                    print("Error rejecting response: \(error)")
                }
            }
        }
    }
    
    private func closeRFI() {
        print("Close RFI button clicked")
        closingRFI = true
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(currentRFI.id)")!
                print("Making request to close RFI: \(url)")
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["status": "CLOSED"]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                print("Request body: \(body)")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    closingRFI = false
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            print("RFI closed successfully")
                            fetchUpdatedRFI()
                        } else {
                            print("Failed to close RFI: \(httpResponse.statusCode)")
                        }
                    } else {
                        print("Failed to close RFI: Invalid response type")
                    }
                }
            } catch {
                await MainActor.run {
                    closingRFI = false
                    print("Error closing RFI: \(error)")
                }
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
            
            if response.status == "pending" && canReview {
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
