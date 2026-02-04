import SwiftUI
import PhotosUI

struct CreateMaterialRequisitionView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onSuccess: () -> Void
    let editingRequisitionId: Int? // If provided, we're editing a draft
    
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var selectedBuyerId: Int?
    @State private var notes = ""
    @State private var requiredByDate: Date?
    @State private var showDatePicker = false
    @State private var items: [MaterialRequisitionItemInput] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var availableBuyers: [MaterialRequisitionBuyer] = []
    @State private var isLoadingBuyers = false
    @State private var showBuyerPicker = false
    @State private var uploadedFiles: [MaterialRequisitionAttachment] = []
    @State private var showFileUploader = false
    @State private var selectedFiles: [PhotosPickerItem] = []
    @State private var pendingFileData: [(data: Data, fileName: String, mimeType: String)] = []
    @State private var showCloseConfirmation = false
    @State private var showCameraPicker = false
    @State private var showAttachmentActionSheet = false
    @State private var isLoadingDraft = false
    @State private var existingAttachments: [MaterialRequisitionAttachment] = []
    @State private var selectedAttachment: MaterialRequisitionAttachment? = nil
    @State private var selectedPendingImageIndex: Int? = nil
    @State private var showPendingImagePreview = false
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    private var isFormValid: Bool {
        let isBuyerSelected = selectedBuyerId != nil
        let isDateValid = requiredByDate != nil && requiredByDate! >= Calendar.current.startOfDay(for: Date())
        let hasItems = !items.isEmpty
        let hasTitle = !title.isEmpty
        return isBuyerSelected && isDateValid && hasItems && hasTitle
    }
    
    private var isDraftValid: Bool {
        // For drafts, only title is required
        return !title.isEmpty
    }
    
    private var isEditing: Bool {
        return editingRequisitionId != nil
    }
    
    private var hasUnsavedChanges: Bool {
        return !title.isEmpty || selectedBuyerId != nil || !notes.isEmpty || requiredByDate != nil || !items.isEmpty || !pendingFileData.isEmpty
    }
    
    private var buyerDisplayName: String {
        guard let selectedBuyerId = selectedBuyerId else {
            return "Not selected"
        }
        return availableBuyers.first(where: { $0.id == selectedBuyerId })?.displayName ?? "Selected"
    }
    
    var body: some View {
        NavigationView {
            Form {
                basicInfoSection
                
                notesSection
                
                itemsSection
                
                attachmentsSection
                
                errorSection
            }
            .navigationTitle(isEditing ? "Edit Draft" : "New Requisition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showCloseConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isEditing {
                        // When editing, show "Save as Draft" and "Submit" buttons
                        Button("Save Draft") {
                            saveAsDraft()
                        }
                        .disabled(!isDraftValid || isLoading)
                        
                        Button("Submit") {
                            submitRequisition()
                        }
                        .disabled(!isFormValid || isLoading)
                    } else {
                        // When creating new, show "Save Draft" and "Create" buttons
                        Button("Save Draft") {
                            saveAsDraft()
                        }
                        .disabled(!isDraftValid || isLoading)
                        
                        Button("Create") {
                            createRequisition()
                        }
                        .disabled(!isFormValid || isLoading)
                    }
                }
            }
            .alert("Unsaved Changes", isPresented: $showCloseConfirmation) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .sheet(isPresented: $showBuyerPicker) {
                BuyerPickerSheet(
                    buyers: availableBuyers,
                    selectedBuyerId: $selectedBuyerId,
                    isLoading: isLoadingBuyers
                )
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationView {
                    DatePicker("Required By Date", selection: Binding(
                        get: { 
                            requiredByDate ?? Calendar.current.startOfDay(for: Date())
                        },
                        set: { newDate in
                            let today = Calendar.current.startOfDay(for: Date())
                            let selectedDate = Calendar.current.startOfDay(for: newDate)
                            if selectedDate >= today {
                                requiredByDate = selectedDate
                            }
                        }
                    ), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showDatePicker = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFileUploader) {
                MaterialRequisitionFileUploadView(
                    requisitionId: 0, // Will be set after creation
                    token: currentToken,
                    onSuccess: { files in
                        uploadedFiles.append(contentsOf: files)
                        showFileUploader = false
                    },
                    onFileDataSelected: handleFileDataSelected
                )
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraPickerWithLocation(
                    onImageCaptured: { photoWithLocation in
                        let fileName = "photo_\(UUID().uuidString).jpg"
                        let mimeType = "image/jpeg"
                        let data = photoWithLocation.image
                        
                        // Create a placeholder attachment for display
                        let attachment = MaterialRequisitionAttachment(
                            name: fileName,
                            type: mimeType,
                            size: data.count,
                            fileKey: nil,
                            url: nil
                        )
                        
                        uploadedFiles.append(attachment)
                        pendingFileData.append((data: data, fileName: fileName, mimeType: mimeType))
                        
                        showCameraPicker = false
                    },
                    onDismiss: {
                        showCameraPicker = false
                    }
                )
            }
            .photosPicker(isPresented: $showFileUploader, selection: $selectedFiles, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
            .onChange(of: selectedFiles) { oldItems, newItems in
                if !newItems.isEmpty {
                    Task {
                        await processSelectedFiles(newItems)
                    }
                }
            }
            .onAppear {
                loadBuyers()
                if let requisitionId = editingRequisitionId {
                    loadDraftRequisition(id: requisitionId)
                }
            }
            .sheet(item: $selectedAttachment) { attachment in
                AttachmentViewer(attachment: attachment)
            }
            .sheet(isPresented: $showPendingImagePreview) {
                if let index = selectedPendingImageIndex,
                   index < pendingFileData.count,
                   let uiImage = UIImage(data: pendingFileData[index].data) {
                    NavigationView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .navigationTitle(uploadedFiles.indices.contains(index) ? (uploadedFiles[index].name ?? "Image") : "Preview")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        showPendingImagePreview = false
                                        selectedPendingImageIndex = nil
                                    }
                                }
                            }
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }
    
    private var basicInfoSection: some View {
        Section("Basic Information") {
            TextField("Title", text: $title)
            
            Button(action: {
                loadBuyers()
                showBuyerPicker = true
            }) {
                HStack {
                    Text("Buyer")
                    Spacer()
                    Text(buyerDisplayName)
                    .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                showDatePicker = true
            }) {
                HStack {
                    Text("Required By Date")
                    Spacer()
                    if let date = requiredByDate {
                        Text(formatDate(date))
                            .foregroundColor(.primary)
                    } else {
                        Text("Not selected")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if requiredByDate != nil {
                Button(action: {
                    requiredByDate = nil
                }) {
                    HStack {
                        Spacer()
                        Text("Clear Date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
            .frame(minHeight: 100)
        }
    }
    
    private var itemsSection: some View {
        Section("Items") {
            ForEach(items.indices, id: \.self) { index in
                ItemRow(item: $items[index], onDelete: {
                    items.remove(at: index)
                })
            }
            
            Button(action: {
                items.append(MaterialRequisitionItemInput(
                    lineItem: "\(items.count + 1)",
                    description: nil,
                    quantity: nil,
                    unit: nil,
                    rate: nil,
                    total: nil,
                    orderedQuantity: nil,
                    orderedRate: nil,
                    orderedTotal: nil,
                    deliveredQuantity: nil,
                    position: items.count
                ))
            }) {
                Label("Add Item", systemImage: "plus")
            }
        }
    }
    
    private var attachmentsSection: some View {
        Section("Attachments") {
            // Show existing attachments (from draft)
            if !existingAttachments.isEmpty {
                ForEach(existingAttachments.indices, id: \.self) { index in
                    let attachment = existingAttachments[index]
                    let hasFileKey = attachment.fileKey != nil
                    let hasUrl = attachment.url != nil
                    let canPreview = hasFileKey || hasUrl
                    
                    HStack {
                        Button(action: {
                            if canPreview {
                                // If we have a URL, use it directly
                                if hasUrl {
                                    selectedAttachment = attachment
                                } else if hasFileKey, let requisitionId = editingRequisitionId {
                                    // If we only have fileKey, fetch the download URL first
                                    Task {
                                        do {
                                            let downloadUrl = try await APIClient.getMaterialRequisitionFileDownloadUrl(
                                                id: requisitionId,
                                                fileKey: attachment.fileKey!,
                                                token: currentToken
                                            )
                                            // Create attachment with URL for preview
                                            let attachmentWithUrl = MaterialRequisitionAttachment(
                                                name: attachment.name,
                                                type: attachment.type,
                                                size: attachment.size,
                                                fileKey: attachment.fileKey,
                                                url: downloadUrl
                                            )
                                            await MainActor.run {
                                                selectedAttachment = attachmentWithUrl
                                            }
                                        } catch {
                                            await MainActor.run {
                                                errorMessage = "Failed to load attachment: \(error.localizedDescription)"
                                            }
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: canPreview ? "doc.fill" : "doc")
                                    .foregroundColor(canPreview ? .blue : .gray)
                                    .frame(width: 40, height: 40)
                                
                                Text(attachment.name ?? "File \(index + 1)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if canPreview {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(!canPreview)
                        .buttonStyle(.plain)
                        
                        // Delete button - separate to prevent triggering preview
                        Button(action: {
                            existingAttachments.remove(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Show newly uploaded files
            if !uploadedFiles.isEmpty {
                ForEach(uploadedFiles.indices, id: \.self) { index in
                    let attachment = uploadedFiles[index]
                    let isImage = index < pendingFileData.count && pendingFileData[index].mimeType.hasPrefix("image/")
                    let hasData = index < pendingFileData.count
                    
                    HStack {
                        Button(action: {
                            if hasData && isImage {
                                selectedPendingImageIndex = index
                                showPendingImagePreview = true
                            }
                        }) {
                            HStack {
                                // Thumbnail preview
                                if hasData && isImage,
                                   let uiImage = UIImage(data: pendingFileData[index].data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(4)
                                        .clipped()
                                } else {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 40, height: 40)
                                }
                                
                                Text(attachment.name ?? "File \(index + 1)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if hasData && isImage {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(!hasData || !isImage)
                        .buttonStyle(.plain)
                        
                        // Delete button - separate to prevent triggering preview
                        Button(action: {
                            if index < uploadedFiles.count {
                                uploadedFiles.remove(at: index)
                            }
                            if index < pendingFileData.count {
                                pendingFileData.remove(at: index)
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button(action: {
                showAttachmentActionSheet = true
            }) {
                Label("Upload Files", systemImage: "paperclip")
            }
            .confirmationDialog("Add Attachment", isPresented: $showAttachmentActionSheet) {
                Button("Take Photo") {
                    showCameraPicker = true
                }
                Button("Choose from Library") {
                    showFileUploader = true
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    private var errorSection: some View {
        Group {
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private func loadBuyers() {
        guard !isLoadingBuyers else { return }
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
    
    private func processSelectedFiles(_ items: [PhotosPickerItem]) async {
        print("📸 [CreateRequisition] Processing \(items.count) selected files")
        for (index, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                var fileName = "file_\(index)_\(UUID().uuidString)"
                var mimeType = "image/jpeg"
                
                // Determine file type from supported content types
                if let typeIdentifier = item.supportedContentTypes.first {
                    if typeIdentifier.conforms(to: .image) {
                        if typeIdentifier.conforms(to: .png) {
                            fileName += ".png"
                            mimeType = "image/png"
                        } else {
                            fileName += ".jpg"
                            mimeType = "image/jpeg"
                        }
                    } else if typeIdentifier.conforms(to: .movie) {
                        fileName += ".mov"
                        mimeType = "video/quicktime"
                    }
                }
                
                print("📸 [CreateRequisition] File \(index + 1): \(fileName), size: \(data.count) bytes, type: \(mimeType)")
                
                // Create a placeholder attachment for display
                let attachment = MaterialRequisitionAttachment(
                    name: fileName,
                    type: mimeType,
                    size: data.count,
                    fileKey: nil,
                    url: nil
                )
                
                await MainActor.run {
                    uploadedFiles.append(attachment)
                    pendingFileData.append((data: data, fileName: fileName, mimeType: mimeType))
                }
            } else {
                print("❌ [CreateRequisition] Failed to load data for file \(index + 1)")
            }
        }
        print("📸 [CreateRequisition] Total pending files: \(pendingFileData.count)")
    }
    
    private func handleFileDataSelected(fileDataArray: [Data], fileNamesArray: [String], mimeTypesArray: [String]) {
        // Store the file data for later upload after requisition creation
        print("📦 [CreateRequisition] Received \(fileDataArray.count) files from upload view")
        for (index, fileName) in fileNamesArray.enumerated() {
            pendingFileData.append((
                data: fileDataArray[index],
                fileName: fileName,
                mimeType: mimeTypesArray[index]
            ))
            print("📦 [CreateRequisition] Added to pending: \(fileName) (\(fileDataArray[index].count) bytes)")
        }
    }
    
    private func createRequisition() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Don't include metadata in initial creation - we'll add it after files are uploaded
                // This ensures files are uploaded first, then metadata is updated with fileKeys and URLs
                
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                
                // Normalize date to midnight for date-only field
                let normalizedDate: Date? = requiredByDate != nil ? {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.year, .month, .day], from: requiredByDate!)
                    return calendar.date(from: components)
                }() : nil
                
                // Validate and clean items - ensure numeric fields are valid decimals or nil
                let validatedItems = items.map { item -> MaterialRequisitionItemInput in
                    var validated = item
                    
                    // Validate quantity - must be a valid decimal or nil
                    if let qty = item.quantity, !qty.isEmpty {
                        if Double(qty) == nil {
                            print("⚠️ [CreateRequisition] Invalid quantity '\(qty)', setting to nil")
                            validated.quantity = nil
                        }
                    }
                    
                    // Validate rate - must be a valid decimal or nil
                    if let rate = item.rate, !rate.isEmpty {
                        if Double(rate) == nil {
                            print("⚠️ [CreateRequisition] Invalid rate '\(rate)', setting to nil")
                            validated.rate = nil
                        }
                    }
                    
                    // Validate total - must be a valid decimal or nil
                    if let total = item.total, !total.isEmpty {
                        if Double(total) == nil {
                            print("⚠️ [CreateRequisition] Invalid total '\(total)', setting to nil")
                            validated.total = nil
                        }
                    }
                    
                    return validated
                }
                
                print("📋 [CreateRequisition] Sending \(validatedItems.count) items to backend")
                for (index, item) in validatedItems.enumerated() {
                    print("   Item \(index + 1): lineItem=\(item.lineItem ?? "nil"), quantity=\(item.quantity ?? "nil"), rate=\(item.rate ?? "nil"), total=\(item.total ?? "nil")")
                }
                
                let request = CreateMaterialRequisitionRequest(
                    title: title,
                    buyerId: selectedBuyerId,
                    notes: notes.isEmpty ? nil : notes,
                    requiredByDate: normalizedDate != nil ? dateFormatter.string(from: normalizedDate!) : nil,
                    quoteAttachments: nil,
                    orderAttachments: nil,
                    orderReference: nil,
                    metadata: nil, // Will be set after files are uploaded
                    items: validatedItems.isEmpty ? nil : validatedItems,
                    status: "SUBMITTED"
                )
                
                print("📝 [CreateRequisition] Creating requisition with title: '\(title)'")
                let created = try await APIClient.createMaterialRequisition(
                    projectId: projectId,
                    request: request,
                    token: currentToken
                )
                print("✅ [CreateRequisition] Requisition created with ID: \(created.id)")
                print("📦 [CreateRequisition] Pending files count: \(pendingFileData.count)")
                
                // Upload files after requisition creation
                if !pendingFileData.isEmpty && created.id > 0 {
                    print("📤 [CreateRequisition] Starting file upload for requisition \(created.id)")
                    do {
                        let fileDataArray = pendingFileData.map { $0.data }
                        let fileNamesArray = pendingFileData.map { $0.fileName }
                        
                        print("📤 [CreateRequisition] Uploading \(fileDataArray.count) files:")
                        for (index, fileName) in fileNamesArray.enumerated() {
                            print("   - File \(index + 1): \(fileName) (\(fileDataArray[index].count) bytes)")
                        }
                        
                        let uploadedAttachments = try await APIClient.uploadMaterialRequisitionFiles(
                            id: created.id,
                            files: fileDataArray,
                            fileNames: fileNamesArray,
                            token: currentToken
                        )
                        
                        print("✅ [CreateRequisition] Files uploaded successfully. Received \(uploadedAttachments.count) attachments:")
                        for (index, attachment) in uploadedAttachments.enumerated() {
                            print("   - Attachment \(index + 1):")
                            print("     name: \(attachment.name ?? "nil")")
                            print("     type: \(attachment.type ?? "nil")")
                            print("     size: \(attachment.size?.description ?? "nil")")
                            print("     fileKey: \(attachment.fileKey ?? "nil")")
                            print("     url: \(attachment.url ?? "nil")")
                        }
                        
                        // Update the requisition metadata with the uploaded file information
                        let attachmentsArray = uploadedAttachments.map { attachment -> [String: Any] in
                            var dict: [String: Any] = [:]
                            if let name = attachment.name {
                                dict["name"] = name
                            }
                            if let type = attachment.type {
                                dict["type"] = type
                            }
                            if let size = attachment.size {
                                dict["size"] = size
                            }
                            if let fileKey = attachment.fileKey {
                                dict["fileKey"] = fileKey
                            }
                            if let url = attachment.url {
                                dict["url"] = url
                            }
                            return dict
                        }
                        
                        let updatedMetadata = ["requisitionAttachments": attachmentsArray]
                        
                        // Log the metadata that will be sent
                        if let jsonData = try? JSONSerialization.data(withJSONObject: updatedMetadata, options: .prettyPrinted),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            print("📋 [CreateRequisition] Metadata to be sent:")
                            print(jsonString)
                        }
                        
                        print("🔄 [CreateRequisition] Updating requisition \(created.id) with metadata...")
                        // Update the requisition with the correct metadata containing fileKeys and URLs
                        let updated = try await APIClient.updateMaterialRequisition(
                            id: created.id,
                            request: UpdateMaterialRequisitionRequest(
                                title: nil,
                                buyerId: nil,
                                notes: nil,
                                requiredByDate: nil,
                                quoteAttachments: nil,
                                orderAttachments: nil,
                                orderReference: nil,
                                metadata: updatedMetadata,
                                items: nil,
                                deliveryTicketPhoto: nil,
                                deliveryNotes: nil
                            ),
                            token: currentToken
                        )
                        
                        print("✅ [CreateRequisition] Requisition updated successfully")
                        print("📋 [CreateRequisition] Updated requisition has \(updated.requisitionAttachments?.count ?? 0) requisition attachments")
                        if let attachments = updated.requisitionAttachments {
                            for (index, attachment) in attachments.enumerated() {
                                print("   - Attachment \(index + 1): \(attachment.name ?? "unnamed"), fileKey: \(attachment.fileKey ?? "nil"), url: \(attachment.url ?? "nil")")
                            }
                        } else {
                            print("⚠️ [CreateRequisition] Updated requisition has NO requisition attachments!")
                        }
                        
                        // Fetch the requisition again to verify what was actually saved
                        print("🔍 [CreateRequisition] Fetching requisition \(created.id) to verify saved state...")
                        let verified = try await APIClient.fetchMaterialRequisition(id: created.id, token: currentToken)
                        print("📋 [CreateRequisition] Verified requisition has \(verified.requisitionAttachments?.count ?? 0) requisition attachments")
                        if let attachments = verified.requisitionAttachments {
                            for (index, attachment) in attachments.enumerated() {
                                print("   - Verified Attachment \(index + 1): \(attachment.name ?? "unnamed"), fileKey: \(attachment.fileKey ?? "nil"), url: \(attachment.url ?? "nil")")
                            }
                        } else {
                            print("❌ [CreateRequisition] VERIFICATION FAILED: Requisition has NO attachments after fetch!")
                        }
                    } catch {
                        // Log error but don't fail the creation
                        print("❌ [CreateRequisition] Failed to upload files after requisition creation: \(error)")
                        print("❌ [CreateRequisition] Error details: \(error.localizedDescription)")
                        if let apiError = error as? APIError {
                            print("❌ [CreateRequisition] API Error: \(apiError)")
                        }
                    }
                } else {
                    if pendingFileData.isEmpty {
                        print("⚠️ [CreateRequisition] No pending files to upload")
                    }
                    if created.id <= 0 {
                        print("⚠️ [CreateRequisition] Invalid requisition ID: \(created.id)")
                    }
                }
                
                await MainActor.run {
                    isLoading = false
                    onSuccess()
                    dismiss()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create requisition: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return formatDate(date)
    }
    
    private func loadDraftRequisition(id: Int) {
        isLoadingDraft = true
        
        Task {
            do {
                let requisition = try await APIClient.fetchMaterialRequisition(id: id, token: currentToken)
                
                await MainActor.run {
                    title = requisition.title
                    selectedBuyerId = requisition.buyerId
                    notes = requisition.notes ?? ""
                    
                    // Parse requiredByDate
                    if let dateString = requisition.requiredByDate {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        requiredByDate = formatter.date(from: dateString)
                    }
                    
                    // Load items
                    if let requisitionItems = requisition.items {
                        items = requisitionItems.map { item in
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
                    } else {
                        items = []
                    }
                    
                    // Load existing attachments
                    if let attachments = requisition.requisitionAttachments {
                        existingAttachments = attachments
                    }
                    
                    isLoadingDraft = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load draft: \(error.localizedDescription)"
                    isLoadingDraft = false
                }
            }
        }
    }
    
    private func saveAsDraft() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                
                // Normalize date to midnight for date-only field
                let normalizedDate: Date? = requiredByDate != nil ? {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.year, .month, .day], from: requiredByDate!)
                    return calendar.date(from: components)
                }() : nil
                
                // Validate and clean items
                let validatedItems = items.map { item -> MaterialRequisitionItemInput in
                    var validated = item
                    
                    if let qty = item.quantity, !qty.isEmpty {
                        if Double(qty) == nil {
                            validated.quantity = nil
                        }
                    }
                    
                    if let rate = item.rate, !rate.isEmpty {
                        if Double(rate) == nil {
                            validated.rate = nil
                        }
                    }
                    
                    if let total = item.total, !total.isEmpty {
                        if Double(total) == nil {
                            validated.total = nil
                        }
                    }
                    
                    return validated
                }
                
                if let requisitionId = editingRequisitionId {
                    // Update existing draft
                    let request = UpdateMaterialRequisitionRequest(
                        title: title,
                        buyerId: selectedBuyerId,
                        notes: notes.isEmpty ? nil : notes,
                        requiredByDate: normalizedDate != nil ? dateFormatter.string(from: normalizedDate!) : nil,
                        quoteAttachments: nil,
                        orderAttachments: nil,
                        orderReference: nil,
                        metadata: nil,
                        items: validatedItems.isEmpty ? nil : validatedItems,
                        deliveryTicketPhoto: nil,
                        deliveryNotes: nil
                    )
                    
                    _ = try await APIClient.updateMaterialRequisition(
                        id: requisitionId,
                        request: request,
                        token: currentToken
                    )
                    
                    // Upload any new files
                    if !pendingFileData.isEmpty {
                        let fileDataArray = pendingFileData.map { $0.data }
                        let fileNamesArray = pendingFileData.map { $0.fileName }
                        
                        let uploadedAttachments = try await APIClient.uploadMaterialRequisitionFiles(
                            id: requisitionId,
                            files: fileDataArray,
                            fileNames: fileNamesArray,
                            token: currentToken
                        )
                        
                        // Update metadata with all attachments (existing + new)
                        var allAttachments = existingAttachments.map { attachment -> [String: Any] in
                            var dict: [String: Any] = [:]
                            if let name = attachment.name { dict["name"] = name }
                            if let type = attachment.type { dict["type"] = type }
                            if let size = attachment.size { dict["size"] = size }
                            if let fileKey = attachment.fileKey { dict["fileKey"] = fileKey }
                            if let url = attachment.url { dict["url"] = url }
                            return dict
                        }
                        
                        allAttachments.append(contentsOf: uploadedAttachments.map { attachment -> [String: Any] in
                            var dict: [String: Any] = [:]
                            if let name = attachment.name { dict["name"] = name }
                            if let type = attachment.type { dict["type"] = type }
                            if let size = attachment.size { dict["size"] = size }
                            if let fileKey = attachment.fileKey { dict["fileKey"] = fileKey }
                            if let url = attachment.url { dict["url"] = url }
                            return dict
                        })
                        
                        let updatedMetadata = ["requisitionAttachments": allAttachments]
                        
                        _ = try await APIClient.updateMaterialRequisition(
                            id: requisitionId,
                            request: UpdateMaterialRequisitionRequest(
                                title: nil,
                                buyerId: nil,
                                notes: nil,
                                requiredByDate: nil,
                                quoteAttachments: nil,
                                orderAttachments: nil,
                                orderReference: nil,
                                metadata: updatedMetadata,
                                items: nil,
                                deliveryTicketPhoto: nil,
                                deliveryNotes: nil
                            ),
                            token: currentToken
                        )
                        
                        // Clear pending files after successful upload
                        pendingFileData.removeAll()
                    }
                } else {
                    // Create new draft
                    let request = CreateMaterialRequisitionRequest(
                        title: title,
                        buyerId: selectedBuyerId,
                        notes: notes.isEmpty ? nil : notes,
                        requiredByDate: normalizedDate != nil ? dateFormatter.string(from: normalizedDate!) : nil,
                        quoteAttachments: nil,
                        orderAttachments: nil,
                        orderReference: nil,
                        metadata: nil,
                        items: validatedItems.isEmpty ? nil : validatedItems,
                        status: "DRAFT"
                    )
                    
                    let created = try await APIClient.createMaterialRequisition(
                        projectId: projectId,
                        request: request,
                        token: currentToken
                    )
                    
                    // Upload files after creation
                    if !pendingFileData.isEmpty && created.id > 0 {
                        let fileDataArray = pendingFileData.map { $0.data }
                        let fileNamesArray = pendingFileData.map { $0.fileName }
                        
                        let uploadedAttachments = try await APIClient.uploadMaterialRequisitionFiles(
                            id: created.id,
                            files: fileDataArray,
                            fileNames: fileNamesArray,
                            token: currentToken
                        )
                        
                        let attachmentsArray = uploadedAttachments.map { attachment -> [String: Any] in
                            var dict: [String: Any] = [:]
                            if let name = attachment.name { dict["name"] = name }
                            if let type = attachment.type { dict["type"] = type }
                            if let size = attachment.size { dict["size"] = size }
                            if let fileKey = attachment.fileKey { dict["fileKey"] = fileKey }
                            if let url = attachment.url { dict["url"] = url }
                            return dict
                        }
                        
                        let updatedMetadata = ["requisitionAttachments": attachmentsArray]
                        
                        _ = try await APIClient.updateMaterialRequisition(
                            id: created.id,
                            request: UpdateMaterialRequisitionRequest(
                                title: nil,
                                buyerId: nil,
                                notes: nil,
                                requiredByDate: nil,
                                quoteAttachments: nil,
                                orderAttachments: nil,
                                orderReference: nil,
                                metadata: updatedMetadata,
                                items: nil,
                                deliveryTicketPhoto: nil,
                                deliveryNotes: nil
                            ),
                            token: currentToken
                        )
                        
                        pendingFileData.removeAll()
                    }
                }
                
                await MainActor.run {
                    isLoading = false
                    onSuccess()
                    dismiss()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save draft: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func submitRequisition() {
        // For drafts, submit means updating status to SUBMITTED
        guard let requisitionId = editingRequisitionId else {
            // If not editing, just create as submitted
            createRequisition()
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // First update the requisition with current data
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                
                let normalizedDate: Date? = requiredByDate != nil ? {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.year, .month, .day], from: requiredByDate!)
                    return calendar.date(from: components)
                }() : nil
                
                let validatedItems = items.map { item -> MaterialRequisitionItemInput in
                    var validated = item
                    if let qty = item.quantity, !qty.isEmpty {
                        if Double(qty) == nil { validated.quantity = nil }
                    }
                    if let rate = item.rate, !rate.isEmpty {
                        if Double(rate) == nil { validated.rate = nil }
                    }
                    if let total = item.total, !total.isEmpty {
                        if Double(total) == nil { validated.total = nil }
                    }
                    return validated
                }
                
                let request = UpdateMaterialRequisitionRequest(
                    title: title,
                    buyerId: selectedBuyerId,
                    notes: notes.isEmpty ? nil : notes,
                    requiredByDate: normalizedDate != nil ? dateFormatter.string(from: normalizedDate!) : nil,
                    quoteAttachments: nil,
                    orderAttachments: nil,
                    orderReference: nil,
                    metadata: nil,
                    items: validatedItems.isEmpty ? nil : validatedItems,
                    deliveryTicketPhoto: nil,
                    deliveryNotes: nil
                )
                
                _ = try await APIClient.updateMaterialRequisition(
                    id: requisitionId,
                    request: request,
                    token: currentToken
                )
                
                // Upload any new files
                if !pendingFileData.isEmpty {
                    let fileDataArray = pendingFileData.map { $0.data }
                    let fileNamesArray = pendingFileData.map { $0.fileName }
                    
                    let uploadedAttachments = try await APIClient.uploadMaterialRequisitionFiles(
                        id: requisitionId,
                        files: fileDataArray,
                        fileNames: fileNamesArray,
                        token: currentToken
                    )
                    
                    var allAttachments = existingAttachments.map { attachment -> [String: Any] in
                        var dict: [String: Any] = [:]
                        if let name = attachment.name { dict["name"] = name }
                        if let type = attachment.type { dict["type"] = type }
                        if let size = attachment.size { dict["size"] = size }
                        if let fileKey = attachment.fileKey { dict["fileKey"] = fileKey }
                        if let url = attachment.url { dict["url"] = url }
                        return dict
                    }
                    
                    allAttachments.append(contentsOf: uploadedAttachments.map { attachment -> [String: Any] in
                        var dict: [String: Any] = [:]
                        if let name = attachment.name { dict["name"] = name }
                        if let type = attachment.type { dict["type"] = type }
                        if let size = attachment.size { dict["size"] = size }
                        if let fileKey = attachment.fileKey { dict["fileKey"] = fileKey }
                        if let url = attachment.url { dict["url"] = url }
                        return dict
                    })
                    
                    let updatedMetadata = ["requisitionAttachments": allAttachments]
                    
                    _ = try await APIClient.updateMaterialRequisition(
                        id: requisitionId,
                        request: UpdateMaterialRequisitionRequest(
                            title: nil,
                            buyerId: nil,
                            notes: nil,
                            requiredByDate: nil,
                            quoteAttachments: nil,
                            orderAttachments: nil,
                            orderReference: nil,
                            metadata: updatedMetadata,
                            items: nil,
                            deliveryTicketPhoto: nil,
                            deliveryNotes: nil
                        ),
                        token: currentToken
                    )
                    
                    pendingFileData.removeAll()
                }
                
                // Then update status to SUBMITTED
                _ = try await APIClient.updateMaterialRequisitionStatus(
                    id: requisitionId,
                    status: "SUBMITTED",
                    orderReference: nil,
                    token: currentToken
                )
                
                await MainActor.run {
                    isLoading = false
                    onSuccess()
                    dismiss()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to submit requisition: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct ItemRow: View {
    @Binding var item: MaterialRequisitionItemInput
    let onDelete: () -> Void
    var showDeliveredQuantity: Bool = false
    var disableQuantityEdit: Bool = false
    var showDeleteButton: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.lineItem ?? "")
                    .font(.headline)
                    .frame(width: 50, alignment: .leading)
                
                Spacer()
                
                if showDeleteButton {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Item", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            
            TextField("Description", text: Binding(
                get: { item.description ?? "" },
                set: { item.description = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                TextField("Quantity", text: Binding(
                    get: { item.quantity ?? "" },
                    set: { item.quantity = $0.isEmpty ? nil : $0 }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(disableQuantityEdit)
                
                TextField("Unit", text: Binding(
                    get: { item.unit ?? "" },
                    set: { item.unit = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            if showDeliveredQuantity {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivered Quantity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter delivered quantity", text: Binding(
                        get: { item.deliveredQuantity ?? "" },
                        set: { item.deliveredQuantity = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
        }
        .padding(.vertical, 4)
    }
}

struct BuyerPickerSheet: View {
    let buyers: [MaterialRequisitionBuyer]
    @Binding var selectedBuyerId: Int?
    let isLoading: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    selectedBuyerId = nil
                    dismiss()
                }) {
                    HStack {
                        Text("No Buyer")
                        Spacer()
                        if selectedBuyerId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(buyers) { buyer in
                    Button(action: {
                        selectedBuyerId = buyer.id
                        dismiss()
                    }) {
                        HStack {
                            Text(buyer.displayName)
                            Spacer()
                            if selectedBuyerId == buyer.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Buyer")
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

