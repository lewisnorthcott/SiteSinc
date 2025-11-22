import SwiftUI
import PhotosUI
import AVFoundation
import WebKit

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
    @State private var showFileUploader = false
    @State private var showBuyerAssignment = false
    @State private var availableBuyers: [MaterialRequisitionBuyer] = []
    @State private var isLoadingBuyers = false
    @State private var editingItems: [MaterialRequisitionItem] = []
    @State private var showDeliveryConfirmation = false
    @State private var deliveryItems: [MaterialRequisitionItem] = []
    @State private var deliveryTicketImage: UIImage?
    @State private var deliveryNotes = ""
    @State private var isSavingDelivery = false
    @State private var showCameraPicker = false
    @State private var showPhotoActionSheet = false
    @State private var showPhotosPicker = false
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showCameraFromSheet = false
    @State private var selectedAttachment: MaterialRequisitionAttachment? = nil
    @State private var showAttachmentViewer = false
    
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
                if !editingItems.isEmpty {
                    itemsSection(items: editingItems)
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
            if let items = currentRequisition.items {
                editingItems = items
            }
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
        .sheet(isPresented: $showDeliveryConfirmation) {
            DeliveryConfirmationSheet(
                items: $deliveryItems,
                deliveryTicketImage: $deliveryTicketImage,
                deliveryNotes: $deliveryNotes,
                isSaving: $isSavingDelivery,
                showPhotoActionSheet: $showPhotoActionSheet,
                showPhotosPicker: $showPhotosPicker,
                photosPickerItems: $photosPickerItems,
                onCancel: {
                    showDeliveryConfirmation = false
                    deliveryTicketImage = nil
                    deliveryNotes = ""
                },
                onConfirm: {
                    saveDeliveryConfirmation()
                },
                onShowCamera: {
                    showCameraFromSheet = true
                }
            )
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerWithLocation(
                onImageCaptured: { photoWithLocation in
                    if let image = UIImage(data: photoWithLocation.image) {
                        deliveryTicketImage = image
                    }
                    showCameraPicker = false
                },
                onDismiss: {
                    showCameraPicker = false
                }
            )
        }
        .sheet(isPresented: $showCameraFromSheet) {
            CameraPickerWithLocation(
                onImageCaptured: { photoWithLocation in
                    if let image = UIImage(data: photoWithLocation.image) {
                        deliveryTicketImage = image
                    }
                    showCameraFromSheet = false
                },
                onDismiss: {
                    showCameraFromSheet = false
                }
            )
        }
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentViewer(attachment: attachment)
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
            
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
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
                    
                    VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let quantity = item.quantity {
                                Text("Qty Requested: \(quantity)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let orderedQuantity = item.orderedQuantity {
                                Text("Qty Ordered: \(orderedQuantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let unit = item.unit {
                            Text("Unit: \(unit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                            Spacer()
                        }
                        
                        if let deliveredQuantity = item.deliveredQuantity {
                            Text("Qty Delivered: \(deliveredQuantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
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
                let hasFileKey = attachment.fileKey != nil
                let hasUrl = attachment.url != nil
                
                Button(action: {
                    selectedAttachment = attachment
                }) {
                    HStack {
                        Image(systemName: hasFileKey || hasUrl ? "doc.fill" : "doc")
                            .foregroundColor(hasFileKey || hasUrl ? .blue : .gray)
                        Text(attachment.name ?? "File \(index + 1)")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                        if hasFileKey || hasUrl {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                .disabled(!hasFileKey && !hasUrl)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if currentRequisition.status == .ordered && canEditDeliveredQuantities {
                Button(action: {
                    // Initialize delivery items with current items
                    deliveryItems = editingItems.map { item in
                        // Create a copy with delivered quantity set to ordered quantity by default
                        do {
                            let encoder = JSONEncoder()
                            let itemData = try encoder.encode(item)
                            var itemDict = try JSONSerialization.jsonObject(with: itemData) as? [String: Any] ?? [:]
                            // Set delivered quantity to ordered quantity if not already set
                            if itemDict["deliveredQuantity"] == nil, let orderedQty = itemDict["orderedQuantity"] as? String {
                                itemDict["deliveredQuantity"] = orderedQty
                            }
                            let decoder = JSONDecoder()
                            let updatedItemData = try JSONSerialization.data(withJSONObject: itemDict)
                            return try decoder.decode(MaterialRequisitionItem.self, from: updatedItemData)
                        } catch {
                            return item
                        }
                    }
                    deliveryNotes = currentRequisition.deliveryNotes ?? ""
                    showDeliveryConfirmation = true
                }) {
                    Label("Mark as Delivered", systemImage: "checkmark.circle.fill")
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
    
    private var canEditDeliveredQuantities: Bool {
        guard let userId = sessionManager.user?.id else { return false }
        let isRequester = currentRequisition.requestedById == userId
        return sessionManager.hasPermission("manage_any_requisitions") || isRequester
    }
    
    // MARK: - Actions
    
    private func fetchUpdatedRequisition() {
        Task {
            do {
                let updated = try await APIClient.fetchMaterialRequisition(id: currentRequisition.id, token: currentToken)
                await MainActor.run {
                    currentRequisition = updated
                    if let items = updated.items {
                        editingItems = items
                    }
                }
            } catch {
                print("Error fetching updated requisition: \(error)")
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
    
    private func saveDeliveryConfirmation() {
        guard currentRequisition.status == .ordered else { return }
        
        isSavingDelivery = true
        
        Task {
            do {
                // Convert delivery items to the format expected by the API
                let itemsToUpdate = deliveryItems.map { item in
                    MaterialRequisitionItemInput(
                        lineItem: item.lineItem,
                        description: item.description,
                        quantity: item.quantity,
                        unit: item.unit,
                        rate: item.rate,
                        total: item.total,
                        orderedQuantity: item.orderedQuantity,
                        orderedRate: item.orderedRate,
                        orderedTotal: item.orderedTotal,
                        deliveredQuantity: item.deliveredQuantity,
                        position: item.position
                    )
                }
                
                // Upload delivery ticket photo if present
                var deliveryTicketPhoto: DeliveryTicketPhoto? = nil
                if let image = deliveryTicketImage,
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    
                    let fileName = "delivery_ticket_\(UUID().uuidString).jpg"
                    print("📤 [DeliveryConfirmation] Uploading delivery ticket photo: \(fileName) (\(imageData.count) bytes)")
                    
                    // Upload the file first
                    let uploadedAttachments = try await APIClient.uploadMaterialRequisitionFiles(
                        id: currentRequisition.id,
                        files: [imageData],
                        fileNames: [fileName],
                        token: currentToken
                    )
                    
                    if let attachment = uploadedAttachments.first {
                        print("✅ [DeliveryConfirmation] Photo uploaded successfully. FileKey: \(attachment.fileKey ?? "nil")")
                        
                        deliveryTicketPhoto = DeliveryTicketPhoto(
                            name: attachment.name,
                            type: attachment.type,
                            size: attachment.size,
                            fileKey: attachment.fileKey,
                            url: attachment.url
                        )
                    }
                }
                
                // Update requisition with delivered quantities, delivery ticket, and notes
                _ = try await APIClient.updateMaterialRequisition(
                    id: currentRequisition.id,
                    request: UpdateMaterialRequisitionRequest(
                        title: nil,
                        buyerId: nil,
                        notes: nil,
                        requiredByDate: nil,
                        quoteAttachments: nil,
                        orderAttachments: nil,
                        orderReference: nil,
                        metadata: nil,
                        items: itemsToUpdate,
                        deliveryTicketPhoto: deliveryTicketPhoto,
                        deliveryNotes: deliveryNotes.isEmpty ? nil : deliveryNotes
                    ),
                    token: currentToken
                )
                
                // Update status to DELIVERED
                _ = try await APIClient.updateMaterialRequisitionStatus(
                    id: currentRequisition.id,
                    status: MaterialRequisitionStatus.delivered.rawValue,
                    orderReference: nil,
                    token: currentToken
                )
                
                // Fetch the fully updated requisition to ensure we have all attachment details
                let finalUpdated = try await APIClient.fetchMaterialRequisition(
                    id: currentRequisition.id,
                    token: currentToken
                )
                
                await MainActor.run {
                    currentRequisition = finalUpdated
                    if let finalItems = finalUpdated.items {
                        editingItems = finalItems
                    }
                    showDeliveryConfirmation = false
                    deliveryTicketImage = nil
                    deliveryNotes = ""
                    isSavingDelivery = false
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save delivery confirmation: \(error.localizedDescription)"
                    isSavingDelivery = false
                    print("❌ Error saving delivery confirmation: \(error)")
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

struct AttachmentViewer: View {
    let attachment: MaterialRequisitionAttachment
    @Environment(\.dismiss) private var dismiss
    
    private var isImage: Bool {
        guard let type = attachment.type else {
            // Check filename extension if type is not available
            if let name = attachment.name {
                let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
                return imageExtensions.contains { name.lowercased().hasSuffix(".\($0)") }
            }
            return false
        }
        return type.hasPrefix("image/")
    }
    
    private var attachmentURL: URL? {
        if let urlString = attachment.url {
            return URL(string: urlString)
        }
        return nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let url = attachmentURL {
                    if isImage {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .failure(let error):
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.white)
                                    Text("Failed to load image")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                    Text(error.localizedDescription)
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        // For PDFs and other documents, use AttachmentWebView
                        AttachmentWebView(url: url)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                        Text("No URL available")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle(attachment.name ?? "Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct AttachmentWebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Optional: Handle navigation completion
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

struct DeliveryConfirmationSheet: View {
    @Binding var items: [MaterialRequisitionItem]
    @Binding var deliveryTicketImage: UIImage?
    @Binding var deliveryNotes: String
    @Binding var isSaving: Bool
    @Binding var showPhotoActionSheet: Bool
    @Binding var showPhotosPicker: Bool
    @Binding var photosPickerItems: [PhotosPickerItem]
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onShowCamera: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Items Table
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Delivered Quantities")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                setAllDeliveredQuantitiesToOrdered()
                            }) {
                                Label("Copy Qty to Delivered", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }
                        
                        ForEach(items.indices, id: \.self) { index in
                            let item = items[index]
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.lineItem ?? "\(index + 1)")
                                        .font(.headline)
                                    
                                    Spacer()
                                }
                                
                                if let description = item.description {
                                    Text(description)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    if let orderedQuantity = item.orderedQuantity {
                                        Text("Qty Ordered: \(orderedQuantity)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let unit = item.unit {
                                        Text("Unit: \(unit)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                
                                HStack {
                                    Text("Qty Delivered:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Enter quantity", text: Binding(
                                        get: { item.deliveredQuantity ?? "" },
                                        set: { newValue in
                                            updateDeliveredQuantity(at: index, value: newValue)
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Delivery Ticket Photo
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Delivery Ticket Photo")
                            .font(.headline)
                        
                        if let image = deliveryTicketImage {
                            HStack {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 100)
                                    .cornerRadius(8)
                                
                                Spacer()
                                
                                Button(action: {
                                    deliveryTicketImage = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            Button(action: {
                                showPhotoActionSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "camera.fill")
                                    Text("Add Photo")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Delivery Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Delivery Notes")
                            .font(.headline)
                        
                        TextEditor(text: $deliveryNotes)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }
                }
                .padding()
            }
            .navigationTitle("Confirm Delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm()
                    }
                    .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showPhotoActionSheet, titleVisibility: .visible) {
                Button("Take Photo") {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .authorized {
                        onShowCamera()
                    } else if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    onShowCamera()
                                }
                            }
                        }
                    }
                }
                Button("Choose From Library") {
                    showPhotosPicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItems, maxSelectionCount: 1, matching: .images)
            .onChange(of: photosPickerItems) { oldItems, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                deliveryTicketImage = image
                                photosPickerItems = []
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateDeliveredQuantity(at index: Int, value: String) {
        guard index < items.count else { return }
        
        let currentItem = items[index]
        
        // Create updated item using JSON encoding/decoding since MaterialRequisitionItem has immutable properties
        do {
            let encoder = JSONEncoder()
            let itemData = try encoder.encode(currentItem)
            var itemDict = try JSONSerialization.jsonObject(with: itemData) as? [String: Any] ?? [:]
            itemDict["deliveredQuantity"] = value.isEmpty ? nil : value
            
            let decoder = JSONDecoder()
            let updatedItemData = try JSONSerialization.data(withJSONObject: itemDict)
            let updatedItem = try decoder.decode(MaterialRequisitionItem.self, from: updatedItemData)
            
            var updatedItems = items
            updatedItems[index] = updatedItem
            items = updatedItems
        } catch {
            print("Error updating delivered quantity: \(error)")
        }
    }
    
    private func setAllDeliveredQuantitiesToOrdered() {
        var updatedItems = items
        for index in updatedItems.indices {
            let item = updatedItems[index]
            if let orderedQuantity = item.orderedQuantity {
                do {
                    let encoder = JSONEncoder()
                    let itemData = try encoder.encode(item)
                    var itemDict = try JSONSerialization.jsonObject(with: itemData) as? [String: Any] ?? [:]
                    itemDict["deliveredQuantity"] = orderedQuantity
                    
                    let decoder = JSONDecoder()
                    let updatedItemData = try JSONSerialization.data(withJSONObject: itemDict)
                    let updatedItem = try decoder.decode(MaterialRequisitionItem.self, from: updatedItemData)
                    updatedItems[index] = updatedItem
                } catch {
                    print("Error setting delivered quantity: \(error)")
                }
            }
        }
        items = updatedItems
    }
}

