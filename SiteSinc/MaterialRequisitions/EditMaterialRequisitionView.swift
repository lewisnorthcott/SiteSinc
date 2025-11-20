import SwiftUI

struct EditMaterialRequisitionView: View {
    let requisition: MaterialRequisition
    let projectId: Int
    let token: String
    let projectName: String
    let onSuccess: () -> Void
    
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var selectedBuyerId: Int?
    @State private var notes: String
    @State private var requiredByDate: Date?
    @State private var showDatePicker = false
    @State private var items: [MaterialRequisitionItemInput] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var availableBuyers: [MaterialRequisitionBuyer] = []
    @State private var isLoadingBuyers = false
    @State private var showBuyerPicker = false
    @State private var deliveryNotes: String = ""
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    init(requisition: MaterialRequisition, projectId: Int, token: String, projectName: String, onSuccess: @escaping () -> Void) {
        self.requisition = requisition
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.onSuccess = onSuccess
        
        _title = State(initialValue: requisition.title)
        _selectedBuyerId = State(initialValue: requisition.buyerId)
        _notes = State(initialValue: requisition.notes ?? "")
        _deliveryNotes = State(initialValue: requisition.deliveryNotes ?? "")
        
        if let requiredByDateString = requisition.requiredByDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _requiredByDate = State(initialValue: formatter.date(from: requiredByDateString))
        }
        
        if let requisitionItems = requisition.items {
            _items = State(initialValue: requisitionItems.map { item in
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
            })
        }
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
                            Text(selectedBuyerId != nil ? 
                                 (availableBuyers.first(where: { $0.id == selectedBuyerId })?.displayName ?? "Selected") : 
                                 "Not selected")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DatePicker("Required By Date", selection: Binding(
                        get: { requiredByDate ?? Date() },
                        set: { requiredByDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                if requisition.status == .delivered || requisition.status == .completed {
                    Section("Delivery Notes") {
                        TextEditor(text: $deliveryNotes)
                            .frame(minHeight: 100)
                    }
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
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Requisition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        updateRequisition()
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
    
    private func updateRequisition() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime]
                
                let request = UpdateMaterialRequisitionRequest(
                    title: title,
                    buyerId: selectedBuyerId,
                    notes: notes.isEmpty ? nil : notes,
                    requiredByDate: requiredByDate != nil ? dateFormatter.string(from: requiredByDate!) : nil,
                    quoteAttachments: nil,
                    orderAttachments: nil,
                    orderReference: nil,
                    metadata: nil,
                    items: items.isEmpty ? nil : items,
                    deliveryTicketPhoto: nil,
                    deliveryNotes: deliveryNotes.isEmpty ? nil : deliveryNotes
                )
                
                _ = try await APIClient.updateMaterialRequisition(
                    id: requisition.id,
                    request: request,
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
                    errorMessage = "Failed to update requisition: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

