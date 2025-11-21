import SwiftUI

struct MaterialRequisitionDetailView: View {
    let requisition: MaterialRequisition
    let projectId: Int
    let token: String
    let projectName: String
    let onRefresh: () -> Void
    
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentRequisition: MaterialRequisition
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEditView = false
    @State private var showStatusChangeSheet = false
    @State private var selectedStatus: MaterialRequisitionStatus?
    @State private var orderReference = ""
    @State private var showFileUploader = false
    @State private var showBuyerAssignment = false
    @State private var availableBuyers: [MaterialRequisitionBuyer] = []
    @State private var isLoadingBuyers = false
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    init(requisition: MaterialRequisition, projectId: Int, token: String, projectName: String, onRefresh: @escaping () -> Void) {
        self.requisition = requisition
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.onRefresh = onRefresh
        self._currentRequisition = State(initialValue: requisition)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                headerSection
                
                // Status Section
                statusSection
                
                // Details Section
                detailsSection
                
                // Items Section
                if let items = currentRequisition.items, !items.isEmpty {
                    itemsSection(items: items)
                }
                
                // Attachments Section
                attachmentsSection
                
                // Actions Section
                actionsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Requisition Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if canEdit {
                        Button(action: {
                            showEditView = true
                        }) {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    
                    if canChangeStatus {
                        Button(action: {
                            showStatusChangeSheet = true
                        }) {
                            Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    
                    if canAssignBuyer {
                        Button(action: {
                            loadBuyers()
                            showBuyerAssignment = true
                        }) {
                            Label("Assign Buyer", systemImage: "person.badge.plus")
                        }
                    }
                    
                    if canUploadFiles {
                        Button(action: {
                            showFileUploader = true
                        }) {
                            Label("Upload Files", systemImage: "paperclip")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            fetchUpdatedRequisition()
        }
        .sheet(isPresented: $showEditView) {
            EditMaterialRequisitionView(
                requisition: currentRequisition,
                projectId: projectId,
                token: token,
                projectName: projectName,
                onSuccess: {
                    showEditView = false
                    fetchUpdatedRequisition()
                    onRefresh()
                }
            )
        }
        .sheet(isPresented: $showStatusChangeSheet) {
            StatusChangeSheet(
                currentStatus: currentRequisition.status,
                orderReference: $orderReference,
                onStatusChange: { newStatus in
                    updateStatus(newStatus)
                }
            )
        }
        .sheet(isPresented: $showBuyerAssignment) {
            BuyerAssignmentSheet(
                buyers: availableBuyers,
                currentBuyerId: currentRequisition.buyerId,
                isLoading: isLoadingBuyers,
                onAssign: { buyerId in
                    assignBuyer(buyerId)
                }
            )
        }
        .sheet(isPresented: $showFileUploader) {
            MaterialRequisitionFileUploadView(
                requisitionId: currentRequisition.id,
                token: currentToken,
                onSuccess: { _ in
                    showFileUploader = false
                    fetchUpdatedRequisition()
                }
            )
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentRequisition.title)
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Text(currentRequisition.formattedNumber ?? "MR-\(String(format: "%04d", currentRequisition.number))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                MaterialRequisitionStatusBadge(status: currentRequisition.status)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            
            HStack {
                MaterialRequisitionStatusBadge(status: currentRequisition.status)
                Spacer()
            }
            
            if let submittedAt = currentRequisition.submittedAt {
                InfoRow(label: "Submitted", value: formatDate(submittedAt))
            }
            if let acceptedAt = currentRequisition.acceptedAt {
                InfoRow(label: "Accepted", value: formatDate(acceptedAt))
            }
            if let orderedAt = currentRequisition.orderedAt {
                InfoRow(label: "Ordered", value: formatDate(orderedAt))
            }
            if let deliveredAt = currentRequisition.deliveredAt {
                InfoRow(label: "Delivered", value: formatDate(deliveredAt))
            }
            if let completedAt = currentRequisition.completedAt {
                InfoRow(label: "Completed", value: formatDate(completedAt))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            
            InfoRow(label: "Requested By", value: currentRequisition.requestedBy?.displayName ?? "Unknown")
            
            if let buyer = currentRequisition.buyer {
                InfoRow(label: "Buyer", value: buyer.displayName)
            } else {
                InfoRow(label: "Buyer", value: "Not assigned")
            }
            
            if let requiredByDate = currentRequisition.requiredByDate {
                InfoRow(label: "Required By", value: formatDate(requiredByDate))
            }
            
            if let orderReference = currentRequisition.orderReference {
                InfoRow(label: "Order Reference", value: orderReference)
            }
            
            if let totalValue = currentRequisition.totalValue, let total = Double(totalValue) {
                InfoRow(label: "Total Value", value: String(format: "£%.2f", total))
            }
            
            if let notes = currentRequisition.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func itemsSection(items: [MaterialRequisitionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(.headline)
            
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if let lineItem = item.lineItem {
                        Text(lineItem)
                            .font(.headline)
                    }
                    
                    if let description = item.description {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        if let quantity = item.quantity {
                            Text("Qty: \(quantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let unit = item.unit {
                            Text("Unit: \(unit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let total = item.total, let totalValue = Double(total) {
                            Text(String(format: "£%.2f", totalValue))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(.headline)
            
            if let requisitionAttachments = currentRequisition.requisitionAttachments, !requisitionAttachments.isEmpty {
                attachmentList(title: "Requisition", attachments: requisitionAttachments)
            }
            
            if let quoteAttachments = currentRequisition.quoteAttachments, !quoteAttachments.isEmpty {
                attachmentList(title: "Quotes", attachments: quoteAttachments)
            }
            
            if let orderAttachments = currentRequisition.orderAttachments, !orderAttachments.isEmpty {
                attachmentList(title: "Orders", attachments: orderAttachments)
            }
            
            if let deliveryTicketPhoto = currentRequisition.deliveryTicketPhoto {
                attachmentList(title: "Delivery Ticket", attachments: [deliveryTicketPhoto])
            }
            
            if (currentRequisition.requisitionAttachments?.isEmpty ?? true) &&
               (currentRequisition.quoteAttachments?.isEmpty ?? true) &&
               (currentRequisition.orderAttachments?.isEmpty ?? true) &&
               currentRequisition.deliveryTicketPhoto == nil {
                Text("No attachments")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func attachmentList(title: String, attachments: [MaterialRequisitionAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(attachments.indices, id: \.self) { index in
                let attachment = attachments[index]
                Button(action: {
                    if let fileKey = attachment.fileKey {
                        openFile(fileKey: fileKey)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text(attachment.name ?? "File \(index + 1)")
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if canChangeStatus {
                Button(action: {
                    showStatusChangeSheet = true
                }) {
                    Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Permission Checks
    
    private var canEdit: Bool {
        guard let userId = sessionManager.user?.id else { return false }
        let isRequester = currentRequisition.requestedById == userId
        let isDuringCreation = currentRequisition.status == .draft || currentRequisition.status == .submitted
        return sessionManager.hasPermission("edit_requisitions") ||
               sessionManager.hasPermission("manage_any_requisitions") ||
               (isRequester && isDuringCreation)
    }
    
    private var canChangeStatus: Bool {
        guard let userId = sessionManager.user?.id else { return false }
        let isRequester = currentRequisition.requestedById == userId
        let isBuyer = currentRequisition.buyerId == userId
        return sessionManager.hasPermission("process_requisitions") ||
               sessionManager.hasPermission("manage_any_requisitions") ||
               isRequester ||
               isBuyer
    }
    
    private var canAssignBuyer: Bool {
        return sessionManager.hasPermission("process_requisitions") ||
               sessionManager.hasPermission("manage_any_requisitions")
    }
    
    private var canUploadFiles: Bool {
        guard let userId = sessionManager.user?.id else { return false }
        let isRequester = currentRequisition.requestedById == userId
        let isDuringCreation = currentRequisition.status == .draft || currentRequisition.status == .submitted
        let isBuyer = currentRequisition.buyerId == userId
        return sessionManager.hasPermission("edit_requisitions") ||
               sessionManager.hasPermission("manage_any_requisitions") ||
               (isRequester && isDuringCreation) ||
               (isBuyer && sessionManager.hasPermission("process_requisitions"))
    }
    
    // MARK: - Actions
    
    private func fetchUpdatedRequisition() {
        Task {
            do {
                let updated = try await APIClient.fetchMaterialRequisition(id: currentRequisition.id, token: currentToken)
                await MainActor.run {
                    currentRequisition = updated
                }
            } catch {
                print("Error fetching updated requisition: \(error)")
            }
        }
    }
    
    private func updateStatus(_ newStatus: MaterialRequisitionStatus) {
        isLoading = true
        Task {
            do {
                let updated = try await APIClient.updateMaterialRequisitionStatus(
                    id: currentRequisition.id,
                    status: newStatus.rawValue,
                    orderReference: orderReference.isEmpty ? nil : orderReference,
                    token: currentToken
                )
                await MainActor.run {
                    currentRequisition = updated
                    isLoading = false
                    showStatusChangeSheet = false
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update status: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func assignBuyer(_ buyerId: Int?) {
        isLoading = true
        Task {
            do {
                let updated = try await APIClient.assignBuyerToMaterialRequisition(
                    id: currentRequisition.id,
                    buyerId: buyerId,
                    token: currentToken
                )
                await MainActor.run {
                    currentRequisition = updated
                    isLoading = false
                    showBuyerAssignment = false
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to assign buyer: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func loadBuyers() {
        isLoadingBuyers = true
        Task {
            do {
                let buyers = try await APIClient.fetchMaterialRequisitionBuyers(projectId: projectId, token: currentToken)
                await MainActor.run {
                    availableBuyers = buyers
                    isLoadingBuyers = false
                }
            } catch {
                await MainActor.run {
                    isLoadingBuyers = false
                }
            }
        }
    }
    
    private func openFile(fileKey: String) {
        Task {
            do {
                let downloadUrl = try await APIClient.getMaterialRequisitionFileDownloadUrl(
                    id: currentRequisition.id,
                    fileKey: fileKey,
                    token: currentToken
                )
                if let url = URL(string: downloadUrl) {
                    await MainActor.run {
                        UIApplication.shared.open(url)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd/MM/yyyy HH:mm"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Supporting Views

struct StatusChangeSheet: View {
    let currentStatus: MaterialRequisitionStatus
    @Binding var orderReference: String
    let onStatusChange: (MaterialRequisitionStatus) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("New Status") {
                    ForEach(MaterialRequisitionStatus.allCases, id: \.self) { status in
                        Button(action: {
                            onStatusChange(status)
                        }) {
                            HStack {
                                Text(status.displayName)
                                Spacer()
                                if status == currentStatus {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(status == currentStatus)
                    }
                }
                
                if currentStatus == .processing || currentStatus == .accepted {
                    Section("Order Reference") {
                        TextField("Order Reference", text: $orderReference)
                    }
                }
            }
            .navigationTitle("Change Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BuyerAssignmentSheet: View {
    let buyers: [MaterialRequisitionBuyer]
    let currentBuyerId: Int?
    let isLoading: Bool
    let onAssign: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    onAssign(nil)
                    dismiss()
                }) {
                    HStack {
                        Text("No Buyer")
                        Spacer()
                        if currentBuyerId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(buyers) { buyer in
                    Button(action: {
                        onAssign(buyer.id)
                        dismiss()
                    }) {
                        HStack {
                            Text(buyer.displayName)
                            Spacer()
                            if currentBuyerId == buyer.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assign Buyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }
}

