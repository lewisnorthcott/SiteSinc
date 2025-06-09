import SwiftUI

// MARK: - RepeaterFieldView
struct RepeaterFieldView: View {
    let field: FormField
    @Binding var responses: [String: String]
    
    @State private var repeaterData: [[String: String]] = []
    @State private var showingSignaturePad: String? // fieldId_rowIndex format
    @State private var signatureImages: [String: UIImage] = [:] // fieldId_rowIndex -> UIImage
    
    private var minItems: Int { field.minItems ?? 0 }
    private var maxItems: Int { field.maxItems ?? 10 }
    private var addButtonText: String { field.addButtonText ?? "Add \(field.label)" }
    private var removeButtonText: String { field.removeButtonText ?? "Remove" }
    
    // Computed properties to break down complex expressions
    private var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { showingSignaturePad != nil },
            set: { if !$0 { showingSignaturePad = nil } }
        )
    }
    
    private func signatureImageBinding(for key: String) -> Binding<UIImage?> {
        Binding<UIImage?>(
            get: { signatureImages[key] },
            set: { newImage in
                handleSignatureImageChange(key: key, image: newImage)
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            itemsCountHeader
            itemsList
            addButton
            maxItemsReachedText
        }
        .onAppear {
            loadExistingData()
        }
        .onChange(of: repeaterData) { _, _ in
            saveRepeaterData()
        }
        .sheet(isPresented: isSheetPresented) {
            signaturePadSheet
        }
    }
    
    @ViewBuilder
    private var itemsCountHeader: some View {
        HStack {
            Text("Items: \(repeaterData.count)/\(maxItems)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private var itemsList: some View {
        ForEach(Array(repeaterData.enumerated()), id: \.offset) { index, item in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(field.label) #\(index + 1)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    if repeaterData.count > minItems {
                        Button(action: {
                            removeItem(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Render sub-fields
                if let subFields = field.subFields {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(subFields, id: \.id) { subField in
                            renderSubField(subField: subField, rowIndex: index)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var addButton: some View {
        if repeaterData.count < maxItems {
            Button(action: addItem) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(addButtonText)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }
    
    @ViewBuilder
    private var maxItemsReachedText: some View {
        if repeaterData.count >= maxItems {
            Text("Maximum of \(maxItems) items reached")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var signaturePadSheet: some View {
        if let currentSignatureKey = showingSignaturePad {
            SignaturePadView(
                signatureImage: signatureImageBinding(for: currentSignatureKey),
                onDismiss: {
                    showingSignaturePad = nil
                }
            )
        }
    }
    
    private func handleSignatureImageChange(key: String, image: UIImage?) {
        if let image = image {
            signatureImages[key] = image
            // Convert image to base64 and save to repeater data
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let base64String = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                updateSignatureInRepeaterData(fieldKey: key, signature: base64String)
            }
        } else {
            signatureImages.removeValue(forKey: key)
            updateSignatureInRepeaterData(fieldKey: key, signature: "")
        }
    }
    
    private func loadExistingData() {
        if let existingJson = responses[field.id], !existingJson.isEmpty {
            if let data = existingJson.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) {
                repeaterData = decoded
                
                // Load existing signatures into signatureImages
                for (rowIndex, rowData) in decoded.enumerated() {
                    if let subFields = field.subFields {
                        for subField in subFields where subField.type == "signature" {
                            if let base64String = rowData[subField.id], !base64String.isEmpty {
                                // Convert base64 back to UIImage
                                if let image = base64ToUIImage(base64String) {
                                    let signatureKey = "\(subField.id)_\(rowIndex)"
                                    signatureImages[signatureKey] = image
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Ensure minimum items
        while repeaterData.count < minItems {
            addItem()
        }
    }
    
    private func base64ToUIImage(_ base64String: String) -> UIImage? {
        // Handle both "data:image/jpeg;base64,..." and plain base64 formats
        let base64Data: String
        if base64String.hasPrefix("data:image/") {
            guard let range = base64String.range(of: ";base64,") else { return nil }
            base64Data = String(base64String[range.upperBound...])
        } else {
            base64Data = base64String
        }
        
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return UIImage(data: data)
    }
    
    private func saveRepeaterData() {
        // Store as JSON array structure that matches frontend format
        // Convert [[String: String]] to JSON array string that can be parsed by frontend
        do {
            let jsonData = try JSONEncoder().encode(repeaterData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                responses[field.id] = jsonString
            }
        } catch {
            print("Failed to encode repeater data: \(error)")
        }
    }
    
    private func addItem() {
        guard repeaterData.count < maxItems else { return }
        
        var newItem: [String: String] = [:]
        // Initialize with empty values for all sub-fields
        field.subFields?.forEach { subField in
            newItem[subField.id] = ""
        }
        repeaterData.append(newItem)
    }
    
    private func removeItem(at index: Int) {
        guard index < repeaterData.count, repeaterData.count > minItems else { return }
        repeaterData.remove(at: index)
    }
    
    private func updateSignatureInRepeaterData(fieldKey: String, signature: String) {
        let components = fieldKey.split(separator: "_")
        
        guard components.count >= 2,
              let rowIndex = Int(components.last!) else { 
            return 
        }
        
        // Field ID is everything except the last component (row index)
        let fieldIdComponents = components.dropLast()
        let fieldId = fieldIdComponents.joined(separator: "_")
        
        if rowIndex < repeaterData.count {
            repeaterData[rowIndex][fieldId] = signature
        }
    }
    
    @ViewBuilder
    private func renderSubField(subField: FormField, rowIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(subField.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if subField.required {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()
                
                // Show validation status for required fields
                if subField.required {
                    let currentValue = repeaterData[safe: rowIndex]?[subField.id] ?? ""
                    let isEmpty = currentValue.isEmpty || currentValue == ""
                    
                    if isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            
            switch subField.type {
            case "text", "input":
                TextField("Enter \(subField.label.lowercased())", text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case "textarea":
                TextEditor(text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
                
            case "yesNoNA":
                Picker("", selection: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                )) {
                    Text("Select").tag("")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                    Text("N/A").tag("na")
                }
                .pickerStyle(SegmentedPickerStyle())
                
            case "dropdown":
                Picker(subField.label, selection: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                )) {
                    Text("Select").tag("")
                    ForEach(subField.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
            case "radio":
                if let options = subField.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                if rowIndex < repeaterData.count {
                                    repeaterData[rowIndex][subField.id] = option
                                }
                            }) {
                                HStack {
                                    Image(systemName: (repeaterData[safe: rowIndex]?[subField.id] == option) ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(.blue)
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                
            case "checkbox":
                if let options = subField.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options, id: \.self) { option in
                            let isSelected = (repeaterData[safe: rowIndex]?[subField.id + "_" + option] == "true")
                            Toggle(isOn: Binding(
                                get: { isSelected },
                                set: { newValue in
                                    if rowIndex < repeaterData.count {
                                        repeaterData[rowIndex][subField.id + "_" + option] = newValue ? "true" : "false"
                                    }
                                }
                            )) {
                                Text(option)
                            }
                        }
                    }
                }
                
            case "signature":
                let signatureKey = "\(subField.id)_\(rowIndex)"
                VStack(alignment: .leading, spacing: 8) {
                    // Show existing signature if available
                    if let signatureImage = signatureImages[signatureKey] {
                        VStack(spacing: 8) {
                            Image(uiImage: signatureImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 80)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3))
                                )
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    showingSignaturePad = signatureKey
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }
                                
                                Button(action: {
                                    signatureImages.removeValue(forKey: signatureKey)
                                    updateSignatureInRepeaterData(fieldKey: signatureKey, signature: "")
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(6)
                                }
                                
                                Spacer()
                            }
                        }
                    } else {
                        // Show add signature button
                        Button(action: {
                            showingSignaturePad = signatureKey
                        }) {
                            HStack {
                                Image(systemName: "signature")
                                Text("Add Signature")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                    }
                }
                
            case "image", "camera":
                VStack(alignment: .leading, spacing: 8) {
                    // Note: Image/Camera functionality for repeater fields is not yet implemented
                    // This would require complex state management similar to signature fields
                    Button(action: {
                        // TODO: Implement image selection/camera capture for repeater fields
                    }) {
                        HStack {
                            Image(systemName: subField.type == "camera" ? "camera" : "photo")
                            Text(subField.type == "camera" ? "Take Photo" : "Select Image")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                    }
                    .disabled(true)
                    
                    Text("Image/Camera fields in repeaters coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case "attachment":
                VStack(alignment: .leading, spacing: 8) {
                    // Note: Attachment functionality for repeater fields is not yet implemented
                    Button(action: {
                        // TODO: Implement file attachment for repeater fields
                    }) {
                        HStack {
                            Image(systemName: "paperclip")
                            Text("Select File")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                    }
                    .disabled(true)
                    
                    Text("File attachments in repeaters coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            default:
                TextField("Enter \(subField.label.lowercased())", text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
}

// Safe array access extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

// Helper struct for identifiable string (needed for sheet presentation)
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    
    init(_ value: String) {
        self.value = value
    }
}

// Note: SignaturePadView and IdentifiablePath are defined in FormSubmissionCreateView.swift 