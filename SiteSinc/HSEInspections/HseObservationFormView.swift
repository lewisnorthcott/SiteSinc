import SwiftUI

// MARK: - Raise / edit an HSE observation
// Mirrors the web ObservationFormDialog. The parent decides where the data
// goes (server API or offline local draft) via the async onSave closure.

struct HseObservationFormView: View {
    let sectionTitle: String
    let sectionId: String
    let observationFields: [HseObservationFieldDef]
    let locationsEnabled: Bool
    let categories: [HseObservationCategory]
    let users: [HseUser]
    let locations: [ProjectLocation]
    let existingInput: HseObservationInput?
    /// Present when editing a server observation (enables photo management).
    let existingServerObservation: HseObservation?
    let projectId: Int
    let token: String
    let onSave: (HseObservationInput, [HsePendingPhoto]) async throws -> Void
    let onDelete: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var descriptionText = ""
    @State private var categoryId: Int?
    @State private var fieldAnswers: [String: String] = [:]
    @State private var assignedToId: Int?
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var locationId: Int?
    @State private var pendingPhotos: [HsePendingPhoto] = []
    @State private var existingPhotos: [HseObservationPhoto] = []

    @State private var showAssigneePicker = false
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var isEditing: Bool { existingInput != nil }

    private var flatLocations: [(id: Int, name: String)] {
        func flatten(_ nodes: [ProjectLocation], prefix: String) -> [(Int, String)] {
            nodes.flatMap { node -> [(Int, String)] in
                let name = prefix.isEmpty ? node.name : "\(prefix) › \(node.name)"
                return [(node.id, name)] + flatten(node.children ?? [], prefix: name)
            }
        }
        return flatten(locations, prefix: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe the observation...", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Observation — \(sectionTitle)")
                }

                Section("Classification") {
                    if !categories.isEmpty {
                        Picker("Category", selection: $categoryId) {
                            Text("None").tag(Int?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(Int?.some(category.id))
                            }
                        }
                    }
                    ForEach(observationFields) { field in
                        observationFieldRow(field)
                    }
                }

                Section("Close-out") {
                    HStack {
                        Text("Assign to")
                        Spacer()
                        Button {
                            showAssigneePicker = true
                        } label: {
                            Text(assigneeName ?? "Unassigned")
                                .foregroundColor(assignedToId == nil ? .secondary : .primary)
                        }
                    }
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                    if locationsEnabled && !flatLocations.isEmpty {
                        Picker("Location", selection: $locationId) {
                            Text("None").tag(Int?.none)
                            ForEach(flatLocations, id: \.id) { location in
                                Text(location.name).tag(Int?.some(location.id))
                            }
                        }
                    }
                }

                Section {
                    if !existingPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(existingPhotos) { photo in
                                    HseRemotePhotoThumb(photo: photo, projectId: projectId, token: token)
                                }
                            }
                        }
                    }
                    HsePhotoPickerSection(photos: $pendingPhotos, title: existingPhotos.isEmpty ? "Photos" : "Add More Photos")
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Photos are stamped with date, time and GPS position.")
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Observation", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Observation" : "New Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showAssigneePicker) {
                HseUserSelectSheet(users: users, allowClear: true) { user in
                    assignedToId = user?.id
                }
            }
            .confirmationDialog("Delete this observation?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .onAppear { loadExisting() }
        }
    }

    private var assigneeName: String? {
        guard let assignedToId else { return nil }
        return users.first { $0.id == assignedToId }?.displayName
    }

    @ViewBuilder
    private func observationFieldRow(_ field: HseObservationFieldDef) -> some View {
        let label = field.isRequired ? "\(field.label) *" : field.label
        if field.type == "dropdown", let options = field.options, !options.isEmpty {
            Picker(label, selection: Binding(
                get: { fieldAnswers[field.id] ?? "" },
                set: { fieldAnswers[field.id] = $0 }
            )) {
                Text("Select...").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundColor(.secondary)
                TextField(field.label, text: Binding(
                    get: { fieldAnswers[field.id] ?? "" },
                    set: { fieldAnswers[field.id] = $0 }
                ))
            }
        }
    }

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        if let input = existingInput {
            descriptionText = input.description
            categoryId = input.categoryId
            fieldAnswers = input.categoryData
            assignedToId = input.assignedToId
            if let due = input.dueDate {
                hasDueDate = true
                dueDate = due
            }
            locationId = input.locationId
        }
        existingPhotos = existingServerObservation?.photos?.filter { $0.isImage } ?? []
    }

    private func save() async {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let missingRequired = observationFields.filter {
            $0.isRequired && (fieldAnswers[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard missingRequired.isEmpty else {
            errorMessage = "Please complete: \(missingRequired.map { $0.label }.joined(separator: ", "))"
            return
        }

        isSaving = true
        defer { isSaving = false }

        var input = HseObservationInput(sectionId: sectionId)
        input.description = trimmed
        input.categoryId = categoryId
        input.categoryData = fieldAnswers.filter { !$0.value.isEmpty }
        input.assignedToId = assignedToId
        input.dueDate = hasDueDate ? dueDate : nil
        input.locationId = locationId

        do {
            try await onSave(input, pendingPhotos)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func performDelete() async {
        guard let onDelete else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onDelete()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
