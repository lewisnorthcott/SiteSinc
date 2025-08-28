import SwiftUI

// Temporary FieldType for UI, you might want to make this more robust
// or align it with backend defined types directly.
enum FormFieldUIType: String, CaseIterable, Identifiable {
    case text = "Text"
    case yesNoNA = "Yes/No/NA"
    case image = "Image"
    case attachment = "Attachment"
    case dropdown = "Dropdown"
    case checkbox = "Checkbox"
    case radio = "Radio"
    case subheading = "Subheading"

    var id: String { self.rawValue }

    // Maps to backend string values
    var apiType: String {
        switch self {
        case .text: return "text"
        case .yesNoNA: return "yesNoNA"
        case .image: return "image"
        case .attachment: return "attachment"
        case .dropdown: return "dropdown"
        case .checkbox: return "checkbox"
        case .radio: return "radio"
        case .subheading: return "subheading"
        }
    }
}

struct CreateFormTemplateView: View {
    let projectId: Int // Passed in, though not directly used by /forms endpoint, good for context
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var reference: String = ""
    @State private var description: String = ""
    @State private var fields: [APIClient.FormFieldData] = []

    @State private var showingAddFieldSheet = false
    @State private var fieldToEdit: APIClient.FormFieldData?
    @State private var editingFieldIndex: Int?

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Template Details")) {
                    TextField("Title*", text: $title)
                    TextField("Reference (Optional)", text: $reference)
                    TextField("Description (Optional)", text: $description)
                }

                Section(header: Text("Fields")) {
                    if fields.isEmpty {
                        Text("No fields added yet. Tap '+' to add a field.")
                            .foregroundColor(.gray)
                            .padding(.vertical)
                    }
                    ForEach(fields.indices, id: \.self) { index in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(fields[index].label)
                                    .font(.headline)
                                Text("Type: \(fields[index].type) - Required: \(fields[index].required ? "Yes" : "No")")
                                    .font(.caption)
                                if let options = fields[index].options, !options.isEmpty {
                                    Text("Options: \(options.joined(separator: ", "))")
                                        .font(.caption)
                                }
                            }
                            Spacer()
                            Button {
                                fieldToEdit = fields[index]
                                editingFieldIndex = index
                                showingAddFieldSheet = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            Button {
                                fields.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .onDelete(perform: removeFields)
                }

                if isLoading {
                    ProgressView()
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                if let successMessage = successMessage {
                    Text(successMessage)
                        .foregroundColor(.green)
                }
            }
            .navigationTitle("Create New Template")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        fieldToEdit = nil // Ensure we are adding a new field
                        editingFieldIndex = nil
                        showingAddFieldSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isLoading)
                    
                    Button("Create") {
                        createTemplate()
                    }
                    .disabled(isLoading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddFieldSheet) {
                AddFieldView(
                    existingFieldData: $fieldToEdit,
                    onSave: { newFieldData in
                        if let index = editingFieldIndex { // Editing existing field
                            fields[index] = newFieldData
                        } else { // Adding new field
                             // Ensure unique ID for the new field if not editing
                            let uniqueId = "field-\(fields.count)-\(Int(Date().timeIntervalSince1970))"
                            let fieldWithId = APIClient.FormFieldData(
                                id: newFieldData.id.isEmpty ? uniqueId : newFieldData.id,
                                label: newFieldData.label,
                                type: newFieldData.type,
                                required: newFieldData.required,
                                options: newFieldData.options
                            )
                            fields.append(fieldWithId)
                        }
                        fieldToEdit = nil
                        editingFieldIndex = nil
                    }
                )
            }
        }
    }

    private func removeFields(at offsets: IndexSet) {
        fields.remove(atOffsets: offsets)
    }

    private func createTemplate() {
        guard let token = sessionManager.token else {
            errorMessage = "Authentication token not found."
            return
        }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Title is required."
            return
        }
        
        guard !fields.isEmpty else {
            errorMessage = "At least one field is required for the template."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        let templateData = APIClient.CreateFormTemplateRequest(
            title: title,
            reference: reference.isEmpty ? nil : reference,
            description: description.isEmpty ? nil : description,
            fields: fields
        )

        Task {
            do {
                _ = try await APIClient.createFormTemplate(token: token, templateData: templateData)
                await MainActor.run {
                    isLoading = false
                    successMessage = "Template created successfully!"
                    // Optionally dismiss or reset form after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    isLoading = false
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    isLoading = false
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to create template: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AddFieldView: View {
    @Binding var existingFieldData: APIClient.FormFieldData? // Used for editing
    var onSave: (APIClient.FormFieldData) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var label: String = ""
    @State private var type: FormFieldUIType = .text
    @State private var required: Bool = false
    @State private var optionsString: String = "" // Comma-separated for text field
    
    // For options that need individual text fields, e.g., for dropdown, radio, checkbox
    @State private var currentOption: String = ""
    @State private var fieldOptions: [String] = []


    private var showsOptionsInput: Bool {
        switch type {
        case .dropdown, .checkbox, .radio:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(existingFieldData == nil ? "Add New Field" : "Edit Field")) {
                    TextField("Label*", text: $label)
                    Picker("Type*", selection: $type) {
                        ForEach(FormFieldUIType.allCases) { fieldType in
                            Text(fieldType.rawValue).tag(fieldType)
                        }
                    }
                    Toggle("Required", isOn: $required)

                    if showsOptionsInput {
                        Section(header: Text("Options (for \(type.rawValue))")) {
                            ForEach(fieldOptions.indices, id: \.self) { index in
                                HStack {
                                    Text(fieldOptions[index])
                                    Spacer()
                                    Button {
                                        fieldOptions.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .onDelete(perform: removeOption)
                            
                            HStack {
                                TextField("Add an option", text: $currentOption)
                                Button("Add") {
                                    if !currentOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        fieldOptions.append(currentOption.trimmingCharacters(in: .whitespacesAndNewlines))
                                        currentOption = ""
                                    }
                                }
                                .disabled(currentOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if fieldOptions.isEmpty {
                                Text("Add at least one option for \(type.rawValue) fields.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingFieldData == nil ? "Add Field" : "Edit Field")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveField()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (showsOptionsInput && fieldOptions.isEmpty))
                }
            }
            .onAppear {
                if let fieldData = existingFieldData {
                    label = fieldData.label
                    type = FormFieldUIType(rawValue: fieldData.type.capitalizedFirst()) ?? .text // Attempt to map back
                    if !FormFieldUIType.allCases.contains(where: { $0.apiType == fieldData.type }) { // Fallback or log warning
                        print("Warning: Unknown field type '\(fieldData.type)' encountered during edit. Defaulting to Text.")
                        type = .text
                    } else {
                         type = FormFieldUIType.allCases.first(where: { $0.apiType == fieldData.type }) ?? .text
                    }
                    required = fieldData.required
                    fieldOptions = fieldData.options ?? []
                }
            }
        }
    }
    
    private func removeOption(at offsets: IndexSet) {
        fieldOptions.remove(atOffsets: offsets)
    }

    private func saveField() {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if showsOptionsInput && fieldOptions.isEmpty { return }

        let newField = APIClient.FormFieldData(
            id: existingFieldData?.id ?? "", // ID is preserved if editing, or will be generated by parent if new
            label: label,
            type: type.apiType, // Use the API type string
            required: required,
            options: showsOptionsInput ? fieldOptions : nil
        )
        onSave(newField)
        dismiss()
    }
}

extension String {
    func capitalizedFirst() -> String {
        return prefix(1).capitalized + dropFirst()
    }
}

// Preview
struct CreateFormTemplateView_Previews: PreviewProvider {
    static var previews: some View {
        // Mock SessionManager for preview
        let mockSessionManager = SessionManager()
        // Populate with some dummy user data if needed for hasPermissionToManageForms check
        // mockSessionManager.currentUser = User(id: 1, tenantId: 1, /* other necessary fields */)
        // mockSessionManager.token = "dummy_token"

        return CreateFormTemplateView(projectId: 1)
            .environmentObject(mockSessionManager)
    }
}

// You would also need a preview for AddFieldView if desired
struct AddFieldView_Previews: PreviewProvider {
    // A dummy binding for previewing AddFieldView for adding a new field
    @State static var dummyExistingFieldData: APIClient.FormFieldData? = nil
    // A dummy binding for previewing AddFieldView for editing an existing field
    @State static var dummyFieldToEdit: APIClient.FormFieldData? = APIClient.FormFieldData(id: "field-0", label: "Sample Question", type: "text", required: true, options: nil)


    static var previews: some View {
        // Preview for adding a new field
        AddFieldView(existingFieldData: $dummyExistingFieldData, onSave: { _ in print("Field saved (preview)") })
        
        // Preview for editing an existing field
        // AddFieldView(existingFieldData: $dummyFieldToEdit, onSave: { _ in print("Field updated (preview)") })
    }
} 