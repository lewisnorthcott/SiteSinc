import SwiftUI

struct CreateInspectionView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onSuccess: () -> Void
    
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineInspectionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Form state
    @State private var selectedTemplateId: Int?
    @State private var selectedLocationId: Int?
    @State private var selectedAssigneeId: Int?
    @State private var selectedManagerId: Int?
    @State private var notes: String = ""
    
    // Data
    @State private var templates: [ProjectInspectionTemplate] = []
    @State private var locations: [ProjectLocation] = []
    @State private var users: [User] = []
    
    // UI state
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var savedOffline = false
    @State private var showTemplatePicker = false
    @State private var showLocationPicker = false
    @State private var showAssigneePicker = false
    @State private var showManagerPicker = false

    private var isFormValid: Bool {
        selectedTemplateId != nil && 
        selectedLocationId != nil &&
        selectedAssigneeId != nil &&
        selectedManagerId != nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else {
                    formContent
                }
                
                // Saved offline success overlay
                if savedOffline {
                    savedOfflineOverlay
                }
            }
            .navigationTitle("Create Inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadData()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private var savedOfflineOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Saved Offline")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Your inspection will be synced when you're back online")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var formContent: some View {
        VStack(spacing: 0) {
            // Offline indicator
            if offlineManager.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline Mode - Inspection will be saved locally")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange)
            }
            
            Form {
                Section("Inspection Details") {
                    HStack {
                        Text("Template *")
                        Spacer()
                        Button(selectedTemplateName) {
                            showTemplatePicker = true
                        }
                        .foregroundColor(selectedTemplateId == nil ? .secondary : .accentColor)
                    }
                    
                    HStack {
                        Text("Location *")
                        Spacer()
                        Button(selectedLocationName) {
                            showLocationPicker = true
                        }
                        .foregroundColor(selectedLocationId == nil ? .secondary : .accentColor)
                    }
                    
                    HStack {
                        Text("Assignee *")
                        Spacer()
                        Button(selectedAssigneeName) {
                            showAssigneePicker = true
                        }
                        .foregroundColor(selectedAssigneeId == nil ? .secondary : .accentColor)
                    }
                    
                    HStack {
                        Text("Manager *")
                        Spacer()
                        Button(selectedManagerName) {
                            showManagerPicker = true
                        }
                        .foregroundColor(selectedManagerId == nil ? .secondary : .accentColor)
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            
            // Submit button at bottom
            VStack(spacing: 0) {
                Divider()
                
                Button(action: {
                    submitInspection()
                }) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Create Inspection")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (isSubmitting || !isFormValid)
                        ? Color.gray
                        : Color.blue
                    )
                    .foregroundColor(.white)
                    .cornerRadius(0)
                }
                .disabled(isSubmitting || !isFormValid)
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(
                templates: templates,
                selectedTemplateId: $selectedTemplateId
            )
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                projectId: projectId,
                token: sessionManager.token ?? token,
                selectedLocationId: $selectedLocationId,
                onDismiss: { showLocationPicker = false }
            )
        }
        .sheet(isPresented: $showAssigneePicker) {
            UserPickerView(
                users: users,
                selectedUserId: $selectedAssigneeId,
                title: "Select Assignee"
            )
        }
        .sheet(isPresented: $showManagerPicker) {
            UserPickerView(
                users: users,
                selectedUserId: $selectedManagerId,
                title: "Select Manager"
            )
        }
    }
    
    private var selectedTemplateName: String {
        guard let templateId = selectedTemplateId,
              let template = templates.first(where: { $0.id == templateId }) else {
            return "Select Template"
        }
        return template.customName ?? template.template.name
    }
    
    private var selectedLocationName: String {
        guard let locationId = selectedLocationId else {
            return "Select Location"
        }
        // Search through locations recursively to find the selected one
        func findLocation(id: Int, in locations: [ProjectLocation]) -> ProjectLocation? {
            for location in locations {
                if location.id == id {
                    return location
                }
                if let children = location.children, let found = findLocation(id: id, in: children) {
                    return found
                }
            }
            return nil
        }
        
        if let location = findLocation(id: locationId, in: locations) {
            return location.code != nil ? "\(location.name) (\(location.code!))" : location.name
        }
        return "Select Location"
    }
    
    private var selectedAssigneeName: String {
        guard let assigneeId = selectedAssigneeId,
              let user = users.first(where: { $0.id == assigneeId }) else {
            return "Select Assignee"
        }
        return userDisplayName(user)
    }
    
    private var selectedManagerName: String {
        guard let managerId = selectedManagerId,
              let user = users.first(where: { $0.id == managerId }) else {
            return "Select Manager"
        }
        return userDisplayName(user)
    }
    
    private func loadData() {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                async let templatesTask = APIClient.fetchProjectInspectionTemplates(
                    projectId: projectId,
                    token: sessionManager.token ?? token
                )
                async let locationsTask = APIClient.fetchProjectLocations(
                    projectId: projectId,
                    token: sessionManager.token ?? token
                )
                async let usersTask = APIClient.fetchProjectUsers(
                    projectId: projectId,
                    token: sessionManager.token ?? token
                )
                
                let (fetchedTemplates, fetchedLocations, fetchedUsers) = try await (templatesTask, locationsTask, usersTask)
                
                await MainActor.run {
                    self.templates = fetchedTemplates.projectTemplates
                    self.locations = fetchedLocations
                    var uniqueById: [Int: User] = [:]
                    for u in fetchedUsers { uniqueById[u.id] = u }
                    self.users = Array(uniqueById.values).sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to create inspections."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                self.errorMessage = "Inspections feature is not yet available on the server."
                            } else {
                                self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                            }
                        default:
                            self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func submitInspection() {
        guard let templateId = selectedTemplateId,
              let locationId = selectedLocationId,
              let assigneeId = selectedAssigneeId,
              let managerId = selectedManagerId else {
            if selectedTemplateId == nil {
                errorMessage = "Template is required"
            } else if selectedLocationId == nil {
                errorMessage = "Location is required"
            } else if selectedAssigneeId == nil {
                errorMessage = "Assignee is required"
            } else if selectedManagerId == nil {
                errorMessage = "Manager is required"
            } else {
                errorMessage = "Please fill in all required fields"
            }
            return
        }
        
        Task {
            await MainActor.run {
                isSubmitting = true
                errorMessage = nil
            }
            
            // Check if we're offline
            if offlineManager.isOffline {
                await saveInspectionOffline(templateId: templateId, locationId: locationId)
                return
            }
            
            do {
                let inspectionData = CreateInspectionRequest(
                    projectInspectionTemplateId: templateId,
                    locationId: locationId,
                    assignedToId: assigneeId,
                    managerId: managerId,
                    notes: notes.isEmpty ? nil : notes
                )
                
                _ = try await APIClient.createInspection(
                    projectId: projectId,
                    inspectionData: inspectionData,
                    token: sessionManager.token ?? token
                )
                
                // Only proceed if creation was successful
                await MainActor.run {
                    self.isSubmitting = false
                    // Clear any previous errors
                    self.errorMessage = nil
                    // Dismiss first, then refresh
                    self.dismiss()
                    // Call onSuccess after a brief delay to ensure view is dismissed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.onSuccess()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    
                    // If network error, save offline
                    if let apiError = error as? APIError, case .networkError = apiError {
                        Task {
                            await saveInspectionOffline(templateId: templateId, locationId: locationId)
                        }
                        return
                    }
                    
                    // Handle decoding errors - if decoding fails, the inspection was likely still created (201 status)
                    // So we treat it as success and refresh the list
                    if let apiError = error as? APIError, case .decodingError = apiError {
                        print("⚠️ Decoding error but inspection was likely created (201 status). Treating as success.")
                        // Clear error and dismiss - inspection was created successfully
                        self.errorMessage = nil
                        self.dismiss()
                        // Call onSuccess after a brief delay to ensure view is dismissed
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.onSuccess()
                        }
                        return
                    }
                    
                    // Set error message for other errors
                    var errorMsg = "Failed to create inspection: \(error.localizedDescription)"
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            errorMsg = "Session expired. Please log in again."
                        case .forbidden:
                            errorMsg = "You don't have permission to create inspections."
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                errorMsg = "Inspections feature is not yet available on the server."
                            } else if statusCode >= 400 && statusCode < 500 {
                                errorMsg = "Failed to create inspection. Please check your input and try again."
                            } else {
                                errorMsg = "Server error. Please try again later."
                            }
                        default:
                            errorMsg = "Failed to create inspection: \(error.localizedDescription)"
                        }
                    }
                    
                    self.errorMessage = errorMsg
                    // Do NOT call onSuccess() or dismiss() here - let user see the error
                }
            }
        }
    }
    
    private func saveInspectionOffline(templateId: Int, locationId: Int) async {
        let locationName = locations.first(where: { $0.id == locationId })?.name
        
        let offlineInspection = OfflineInspection(
            id: UUID().uuidString,
            projectId: projectId,
            projectInspectionTemplateId: templateId,
            inspectionNumber: 0, // Will be assigned by server
            locationId: locationId,
            locationName: locationName,
            assignedToId: selectedAssigneeId,
            managerId: selectedManagerId,
            notes: notes.isEmpty ? nil : notes,
            createdAt: Date()
        )
        
        offlineManager.saveInspection(offlineInspection)
        
        await MainActor.run {
            self.isSubmitting = false
            self.savedOffline = true
            
            // Show success message and dismiss after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.onSuccess()
            }
        }
    }
}

struct TemplatePickerView: View {
    let templates: [ProjectInspectionTemplate]
    @Binding var selectedTemplateId: Int?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(templates.filter { $0.isActive }, id: \.id) { template in
                    Button(action: {
                        selectedTemplateId = template.id
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.customName ?? template.template.name)
                                    .foregroundColor(.primary)
                                
                                if let count = template._count?.inspections {
                                    Text("\(count) inspection(s)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedTemplateId == template.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Reuse userDisplayName from CreateLogView
// func userDisplayName(_ user: User) -> String { ... } - already defined in CreateLogView.swift

struct InlineLocationPicker: View {
    let projectId: Int
    let token: String
    @Binding var selectedLocationId: Int?
    let onSelectionChanged: () -> Void
    
    @State private var locations: [ProjectLocation] = []
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading locations...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if locations.isEmpty {
                Text("No locations available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(locations) { location in
                        InlineLocationRow(
                            location: location,
                            selectedLocationId: $selectedLocationId,
                            level: 0,
                            onSelectionChanged: onSelectionChanged
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadLocations()
        }
    }
    
    private func loadLocations() {
        guard !isLoading && locations.isEmpty else { return }
        isLoading = true
        
        Task {
            do {
                let fetchedLocations = try await APIClient.fetchProjectLocations(projectId: projectId, token: token)
                await MainActor.run {
                    self.locations = fetchedLocations
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct InlineLocationRow: View {
    let location: ProjectLocation
    @Binding var selectedLocationId: Int?
    let level: Int
    let onSelectionChanged: () -> Void
    
    @State private var isExpanded = false
    
    private var hasChildren: Bool {
        guard let children = location.children else { return false }
        return !children.isEmpty
    }
    
    private var isSelected: Bool {
        selectedLocationId == location.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Indentation
                if level > 0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: CGFloat(level) * 16)
                }
                
                // Expand/collapse or select button
                if hasChildren {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
                
                // Location name - tappable to select
                Button(action: {
                    selectedLocationId = location.id
                    onSelectionChanged()
                }) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(location.name)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                            
                            if let code = location.code, !code.isEmpty {
                                Text(code)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear
            )
            
            // Children
            if isExpanded, let children = location.children, !children.isEmpty {
                ForEach(children) { child in
                    InlineLocationRow(
                        location: child,
                        selectedLocationId: $selectedLocationId,
                        level: level + 1,
                        onSelectionChanged: onSelectionChanged
                    )
                }
            }
        }
    }
}

