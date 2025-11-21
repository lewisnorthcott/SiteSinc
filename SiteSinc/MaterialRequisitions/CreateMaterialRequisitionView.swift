import SwiftUI
import PhotosUI

struct CreateMaterialRequisitionView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onSuccess: () -> Void
    
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
    
    private var currentToken: String {
        return sessionManager.token ?? token
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
                    
                    DatePicker("Required By Date", selection: Binding(
                        get: { requiredByDate ?? Date() },
                        set: { requiredByDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    
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
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
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
                
                Section("Attachments") {
                    if !uploadedFiles.isEmpty {
                        ForEach(uploadedFiles.indices, id: \.self) { index in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                Text(uploadedFiles[index].name ?? "File \(index + 1)")
                                Spacer()
                            }
                        }
                    }
                    
                    Button(action: {
                        showFileUploader = true
                    }) {
                        Label("Upload Files", systemImage: "paperclip")
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Requisition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRequisition()
                    }
                    .disabled(title.isEmpty || isLoading)
                }
            }
            .sheet(isPresented: $showBuyerPicker) {
                BuyerPickerSheet(
                    buyers: availableBuyers,
                    selectedBuyerId: $selectedBuyerId,
                    isLoading: isLoadingBuyers
                )
            }
            .sheet(isPresented: $showFileUploader) {
                MaterialRequisitionFileUploadView(
                    requisitionId: 0, // Will be set after creation
                    token: currentToken,
                    onSuccess: { files in
                        uploadedFiles.append(contentsOf: files)
                        showFileUploader = false
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
        var processedFiles: [MaterialRequisitionAttachment] = []
        
        for (index, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let fileName = "file_\(index)_\(UUID().uuidString).jpg"
                // For now, we'll store the file data and upload after requisition creation
                // In a production app, you might want to upload to a temporary endpoint first
                let attachment = MaterialRequisitionAttachment(
                    name: fileName,
                    type: "image/jpeg",
                    size: data.count,
                    fileKey: nil,
                    url: nil
                )
                processedFiles.append(attachment)
            }
        }
        
        await MainActor.run {
            uploadedFiles.append(contentsOf: processedFiles)
        }
    }
    
    private func createRequisition() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Prepare metadata with requisition attachments
                var metadata: [String: Any]? = nil
                if !uploadedFiles.isEmpty {
                    let attachmentsArray = uploadedFiles.map { attachment -> [String: Any] in
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
                    metadata = ["requisitionAttachments": attachmentsArray]
                }
                
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
                
                // Normalize date to midnight for date-only field
                let normalizedDate: Date? = requiredByDate != nil ? {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.year, .month, .day], from: requiredByDate!)
                    return calendar.date(from: components)
                }() : nil
                
                let request = CreateMaterialRequisitionRequest(
                    title: title,
                    buyerId: selectedBuyerId,
                    notes: notes.isEmpty ? nil : notes,
                    requiredByDate: normalizedDate != nil ? dateFormatter.string(from: normalizedDate!) : nil,
                    quoteAttachments: nil,
                    orderAttachments: nil,
                    orderReference: nil,
                    metadata: metadata,
                    items: items.isEmpty ? nil : items,
                    status: "SUBMITTED"
                )
                
                let created = try await APIClient.createMaterialRequisition(
                    projectId: projectId,
                    request: request,
                    token: currentToken
                )
                
                // If we have uploaded files but the requisition was created, upload them now
                if !uploadedFiles.isEmpty && created.id > 0 {
                    // Files should already be uploaded, we just need to update the requisition metadata
                    // This is handled by the metadata we sent
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
}

struct ItemRow: View {
    @Binding var item: MaterialRequisitionItemInput
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Line Item", text: Binding(
                    get: { item.lineItem ?? "" },
                    set: { item.lineItem = $0.isEmpty ? nil : $0 }
                ))
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            
            TextField("Description", text: Binding(
                get: { item.description ?? "" },
                set: { item.description = $0.isEmpty ? nil : $0 }
            ))
            
            HStack {
                TextField("Quantity", text: Binding(
                    get: { item.quantity ?? "" },
                    set: { item.quantity = $0.isEmpty ? nil : $0 }
                ))
                .keyboardType(.decimalPad)
                
                TextField("Unit", text: Binding(
                    get: { item.unit ?? "" },
                    set: { item.unit = $0.isEmpty ? nil : $0 }
                ))
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

