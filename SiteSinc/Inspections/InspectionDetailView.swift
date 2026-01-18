import SwiftUI
import PhotosUI
import AVFoundation

struct InspectionDetailView: View {
    let inspection: Inspection
    let projectId: Int
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineInspectionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentInspection: Inspection
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Use current token from session manager to avoid stale token issues
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    init(inspection: Inspection, projectId: Int, token: String, onRefresh: (() -> Void)?) {
        self.inspection = inspection
        self.projectId = projectId
        self.token = token
        self.onRefresh = onRefresh
        self._currentInspection = State(initialValue: inspection)
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Offline indicator
                    if offlineManager.isOffline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                            Text("Offline Mode - Changes will be saved locally")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    } else {
                        Spacer()
                            .frame(height: 16)
                    }
                    
                    headerSection
                        .padding(.bottom, 24)
                    
                    if let notes = currentInspection.notes, !notes.isEmpty {
                        notesSection(notes)
                            .padding(.bottom, 24)
                    }
                    
                    detailsSection
                        .padding(.bottom, 24)
                    
                    if let stageResults = currentInspection.stageResults, !stageResults.isEmpty {
                        stagesSection(stageResults)
                            .padding(.bottom, 24)
                    }
                }
            }
            .refreshable {
                await refreshInspection()
            }
        }
        .navigationTitle("Inspection #\(currentInspection.inspectionNumber)")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadInspectionDetails()
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
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentInspection.projectInspectionTemplate.template.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if let location = currentInspection.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.secondary)
                            Text(location.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Created: \(formatDate(currentInspection.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    InspectionStatusBadge(status: currentInspection.status)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(notes)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                if let assignedTo = currentInspection.assignedTo {
                    DetailRow(label: "Assigned To", value: assignedTo.displayName, icon: "person.fill")
                }
                
                if let manager = currentInspection.manager {
                    DetailRow(label: "Manager", value: manager.displayName, icon: "person.crop.circle.fill")
                }
                
                if let startedAt = currentInspection.startedAt {
                    DetailRow(label: "Started", value: formatDate(startedAt), icon: "play.fill")
                }
                
                if let completedAt = currentInspection.completedAt {
                    DetailRow(label: "Completed", value: formatDate(completedAt), icon: "checkmark.circle.fill")
                }
                
                if let signedOffAt = currentInspection.signedOffAt {
                    DetailRow(label: "Signed Off", value: formatDate(signedOffAt), icon: "signature")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func stagesSection(_ stageResults: [InspectionStageResult]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stages")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Group stages by section
            let groupedStages = groupStagesBySection(stageResults)
            
            VStack(spacing: 16) {
                // Display sections with their stages
                if let sections = currentInspection.projectInspectionTemplate.template.sections, !sections.isEmpty {
                    ForEach(sections.sorted(by: { $0.order < $1.order }), id: \.id) { section in
                        InspectionSectionView(
                            section: section,
                            stageResults: groupedStages[section.id] ?? [],
                            inspection: currentInspection,
                            projectId: projectId,
                            token: currentToken,
                            onRefresh: {
                                loadInspectionDetails()
                            }
                        )
                        .environmentObject(sessionManager)
                    }
                }
                
                // Display stages not in any section (sectionId is null)
                if let ungroupedStages = groupedStages[nil], !ungroupedStages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ungroupedStages.sorted(by: { $0.stage.order < $1.stage.order }), id: \.id) { stageResult in
                            NavigationLink(
                                destination: InspectionStageDetailView(
                                    inspection: currentInspection,
                                    projectId: projectId,
                                    stageResult: stageResult,
                                    token: currentToken,
                                    onRefresh: {
                                        loadInspectionDetails()
                                    }
                                )
                                .environmentObject(sessionManager)
                            ) {
                                InspectionStageRowView(stageResult: stageResult)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func groupStagesBySection(_ stageResults: [InspectionStageResult]) -> [Int?: [InspectionStageResult]] {
        var grouped: [Int?: [InspectionStageResult]] = [:]
        
        for stageResult in stageResults {
            let sectionId = stageResult.stage.sectionId
            if grouped[sectionId] == nil {
                grouped[sectionId] = []
            }
            grouped[sectionId]?.append(stageResult)
        }
        
        return grouped
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func loadInspectionDetails() {
        guard !isLoading else { return }
        
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let fetchedInspection = try await APIClient.fetchInspection(
                    projectId: projectId,
                    inspectionId: currentInspection.id,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.currentInspection = fetchedInspection
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
                            self.errorMessage = "You don't have permission to view this inspection."
                        default:
                            self.errorMessage = "Failed to load inspection: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func refreshInspection() async {
        // Reload inspection details
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await MainActor.run {
                    self.isLoading = true
                }
                
                do {
                    let fetchedInspection = try await APIClient.fetchInspection(
                        projectId: self.projectId,
                        inspectionId: self.currentInspection.id,
                        token: self.currentToken
                    )
                    
                    await MainActor.run {
                        self.currentInspection = fetchedInspection
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
                                self.errorMessage = "You don't have permission to view this inspection."
                            default:
                                self.errorMessage = "Failed to refresh inspection: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
        
        // Call onRefresh callback if provided
        await MainActor.run {
            onRefresh?()
        }
    }
}

struct InspectionStatusBadge: View {
    let status: String
    
    private var statusColor: Color {
        switch status {
        case "NOT_STARTED":
            return .gray
        case "IN_PROGRESS":
            return .blue
        case "COMPLETED":
            return .green
        case "FAILED":
            return .red
        default:
            return .gray
        }
    }
    
    private var statusIcon: String {
        switch status {
        case "NOT_STARTED":
            return "circle"
        case "IN_PROGRESS":
            return "clock.fill"
        case "COMPLETED":
            return "checkmark.circle.fill"
        case "FAILED":
            return "xmark.circle.fill"
        default:
            return "circle"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor)
        .cornerRadius(6)
    }
}

struct InspectionStageRowView: View {
    let stageResult: InspectionStageResult
    
    private var statusColor: Color {
        switch stageResult.status {
        case "PENDING":
            return .gray
        case "YES":
            return .green
        case "NO":
            return .red
        case "N_A":
            return .orange
        case "SKIPPED":
            return .blue
        default:
            return .gray
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stageResult.stage.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let completedAt = stageResult.completedAt {
                    Text("Completed: \(formatDate(completedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(stageResult.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor)
                .cornerRadius(6)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct InspectionStageDetailView: View {
    let inspection: Inspection
    let projectId: Int
    let stageResult: InspectionStageResult
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineInspectionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStageResult: InspectionStageResult
    @State private var selectedStatus: String
    @State private var notes: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    // Photo states
    @State private var photos: [InspectionStagePhoto] = []
    @State private var isLoadingPhotos = false
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showPhotoActionSheet = false
    @State private var isUploadingPhoto = false
    @State private var selectedPhoto: InspectionStagePhoto?
    @State private var showPhotoPreview = false
    @State private var showPhotosPicker = false
    @State private var stageDefects: [InspectionDefect] = []
    @State private var showSnagCreation = false
    @State private var pendingStageResultForSnag: InspectionStageResult?
    
    // Activity history state
    @State private var showActivityHistory = false
    @State private var activities: [StageActivity] = []
    @State private var isLoadingActivities = false
    
    // Use current token from session manager
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    // Status options
    private let statusOptions = ["YES", "NO", "N_A"]
    
    init(inspection: Inspection, projectId: Int, stageResult: InspectionStageResult, token: String, onRefresh: (() -> Void)?) {
        self.inspection = inspection
        self.projectId = projectId
        self.stageResult = stageResult
        self.token = token
        self.onRefresh = onRefresh
        self._currentStageResult = State(initialValue: stageResult)
        self._selectedStatus = State(initialValue: stageResult.status)
        self._notes = State(initialValue: stageResult.notes ?? "")
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Offline indicator
                    if offlineManager.isOffline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                            Text("Offline Mode - Changes will be saved locally")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    } else {
                        Spacer()
                            .frame(height: 16)
                    }
                    
                    // Stage information
                    stageInfoSection
                        .padding(.bottom, 24)
                    
                    // Status selection
                    statusSection
                        .padding(.bottom, 24)
                    
                    // Notes section
                    notesSection
                        .padding(.bottom, 24)
                    
                    // Completion info
                    if currentStageResult.status != "PENDING" {
                        completionInfoSection
                            .padding(.bottom, 24)
                    }
                    
                    // Linked Log section - show if status is NO or if there are defects with linked logs
                    if selectedStatus == "NO" || !stageDefects.isEmpty || (currentStageResult._count?.defects ?? 0) > 0 {
                        linkedLogSection
                            .padding(.bottom, 24)
                    }
                    
                    // Photos section
                    photosSection
                        .padding(.bottom, 24)
                    
                    // Submit button
                    submitButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            
            if isSubmitting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            }
        }
        .navigationTitle(stageResult.stage.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    loadActivityHistory()
                    showActivityHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .onAppear {
            loadPhotos()
            loadStageDefects()
        }
        .onChange(of: selectedStatus) { oldValue, newValue in
            // Reload defects when status changes
            if newValue == "NO" {
                loadStageDefects()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photosPickerItems) { oldItems, newItems in
            if !newItems.isEmpty {
                Task {
                    await processSelectedPhotos(newItems)
                }
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerWithLocation(
                onImageCaptured: { photoWithLocation in
                    Task {
                        await uploadPhotoFromCamera(photoWithLocation)
                    }
                },
                onDismiss: {
                    showCameraPicker = false
                }
            )
        }
        .confirmationDialog("Add Photo", isPresented: $showPhotoActionSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized {
                    showCameraPicker = true
                } else if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                showCameraPicker = true
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
        .sheet(item: $selectedPhoto) { photo in
            PhotoPreviewView(photo: photo)
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {
                onRefresh?()
                dismiss()
            }
        } message: {
            Text("Stage result updated successfully")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showSnagCreation) {
            if let pendingResult = pendingStageResultForSnag {
                CreateSnagFromInspectionView(
                    inspection: inspection,
                    stageResult: pendingResult,
                    projectId: projectId,
                    token: currentToken,
                    onSuccess: {
                        // Snag created successfully - refresh and dismiss
                        onRefresh?()
                        dismiss()
                    },
                    onSkip: {
                        // User skipped snag creation - just refresh and dismiss
                        onRefresh?()
                        dismiss()
                    }
                )
                .environmentObject(sessionManager)
            }
        }
        .sheet(isPresented: $showActivityHistory) {
            ActivityHistoryView(
                activities: activities,
                isLoading: isLoadingActivities,
                stageName: stageResult.stage.name,
                projectId: projectId
            )
            .environmentObject(sessionManager)
        }
    }
    
    private var stageInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stage Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                if let description = stageResult.stage.description, !description.isEmpty {
                    DetailRow(label: "Description", value: description, icon: "doc.text")
                }
                
                DetailRow(label: "Order", value: "\(stageResult.stage.order + 1)", icon: "number")
                
                DetailRow(
                    label: "Current Status",
                    value: currentStageResult.status.replacingOccurrences(of: "_", with: " ").capitalized,
                    icon: "checkmark.circle"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Status")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                ForEach(statusOptions, id: \.self) { status in
                    Button(action: {
                        selectedStatus = status
                    }) {
                        HStack {
                            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedStatus == status {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(12)
                        .background(selectedStatus == status ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notes")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var completionInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Completion Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                if let completedAt = currentStageResult.completedAt {
                    DetailRow(label: "Completed At", value: formatDate(completedAt), icon: "clock")
                }
                
                if let completedBy = currentStageResult.completedBy {
                    DetailRow(label: "Completed By", value: completedBy.displayName, icon: "person")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var linkedLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.orange)
                Text("Linked Snag")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if stageDefects.isEmpty {
                if (selectedStatus == "NO" || currentStageResult.status == "NO") && (currentStageResult._count?.defects ?? 0) > 0 {
                    // Status is NO and defect count > 0, but defects not loaded - show loading
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                    .task {
                        loadStageDefects()
                    }
                } else if currentStageResult.status == "NO" && selectedStatus == "NO" {
                    // Already saved with NO status but no snag created - allow creating one
                    VStack(spacing: 12) {
                        Text("No snag has been created for this failed inspection item.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            pendingStageResultForSnag = currentStageResult
                            showSnagCreation = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create Snag")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                } else if selectedStatus == "NO" && currentStageResult.status != "NO" {
                    // Selected NO but not saved yet
                    Text("You'll be prompted to create a snag log with a photo when you save")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("No linked snag")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(stageDefects) { defect in
                        LinkedSnagRowView(
                            defect: defect,
                            projectId: projectId,
                            inspectionId: inspection.id,
                            stageId: currentStageResult.stageId,
                            onSnagResolved: {
                                loadStageDefects()
                                onRefresh?()
                            },
                            onMarkAsYes: { newStatus in
                                // Update local state immediately
                                selectedStatus = newStatus
                                // Refresh parent views
                                loadStageDefects()
                                onRefresh?()
                            }
                        )
                        .environmentObject(sessionManager)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func loadStageDefects() {
        Task {
            do {
                let allDefects = try await APIClient.fetchInspectionDefects(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    token: currentToken
                )
                await MainActor.run {
                    // Filter defects for this stage - match by stageId since stageResultId might change
                    let stageId = currentStageResult.stageId
                    stageDefects = allDefects.filter { defect in
                        defect.stageResult?.stage.id == stageId || defect.stageResultId == currentStageResult.id
                    }
                    print("Loaded \(stageDefects.count) defects for stage \(stageId) (stageResultId: \(currentStageResult.id))")
                    if !stageDefects.isEmpty {
                        print("Defects found: \(stageDefects.map { "\($0.id) (status: \($0.status))" }.joined(separator: ", "))")
                    }
                }
            } catch {
                print("Failed to load stage defects: \(error)")
            }
        }
    }
    
    private func loadActivityHistory() {
        guard !isLoadingActivities else { return }
        isLoadingActivities = true
        
        Task {
            do {
                let fetchedActivities = try await APIClient.fetchStageActivity(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    stageId: stageResult.stageId,
                    token: currentToken
                )
                await MainActor.run {
                    activities = fetchedActivities
                    isLoadingActivities = false
                }
            } catch {
                await MainActor.run {
                    isLoadingActivities = false
                    print("Failed to load activity history: \(error)")
                }
            }
        }
    }
    
    private var submitButton: some View {
        Button(action: {
            submitStageResult()
        }) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Save Changes")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(hasChanges ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(isSubmitting || !hasChanges)
    }
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Photos")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    showPhotoActionSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            
            if isLoadingPhotos {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if isUploadingPhoto {
                HStack {
                    ProgressView()
                    Text("Uploading photo...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if photos.isEmpty {
                Text("No photos")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(photos) { photo in
                            PhotoThumbnailView(photo: photo) {
                                selectedPhoto = photo
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var hasChanges: Bool {
        return selectedStatus != stageResult.status || notes != (stageResult.notes ?? "")
    }
    
    private func loadPhotos() {
        guard !isLoadingPhotos else { return }
        isLoadingPhotos = true
        
        Task {
            do {
                let fetchedPhotos = try await APIClient.fetchStagePhotos(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    stageId: stageResult.stageId,
                    token: currentToken
                )
                await MainActor.run {
                    photos = fetchedPhotos
                    isLoadingPhotos = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPhotos = false
                    errorMessage = "Failed to load photos: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await uploadPhoto(data: data, fileName: "photo_\(UUID().uuidString).jpg")
            }
        }
        await MainActor.run {
            photosPickerItems = []
        }
    }
    
    private func uploadPhotoFromCamera(_ photoWithLocation: PhotoWithLocation) async {
        let fileName = "photo_\(UUID().uuidString).jpg"
        await uploadPhoto(
            data: photoWithLocation.image,
            fileName: fileName,
            latitude: photoWithLocation.location?.coordinate.latitude,
            longitude: photoWithLocation.location?.coordinate.longitude,
            accuracy: photoWithLocation.location?.horizontalAccuracy,
            locationTimestamp: photoWithLocation.capturedAt
        )
    }
    
    private func uploadPhoto(data: Data, fileName: String, latitude: Double? = nil, longitude: Double? = nil, accuracy: Double? = nil, locationTimestamp: Date? = nil) async {
        await MainActor.run {
            isUploadingPhoto = true
        }
        
        do {
            let uploadedPhoto = try await APIClient.uploadStagePhoto(
                projectId: projectId,
                inspectionId: inspection.id,
                stageId: stageResult.stageId,
                imageData: data,
                fileName: fileName,
                caption: nil,
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                locationTimestamp: locationTimestamp,
                token: currentToken
            )
            
            await MainActor.run {
                photos.append(uploadedPhoto)
                isUploadingPhoto = false
            }
        } catch {
            await MainActor.run {
                isUploadingPhoto = false
                errorMessage = "Failed to upload photo: \(error.localizedDescription)"
            }
        }
    }
    
    private func submitStageResult() {
        guard !isSubmitting else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                let updatedResult: InspectionStageResult
                
                if currentStageResult.status == "PENDING" {
                    // First time submission
                    updatedResult = try await APIClient.submitStageResult(
                        projectId: projectId,
                        inspectionId: inspection.id,
                        stageId: stageResult.stageId,
                        status: selectedStatus,
                        notes: notes.isEmpty ? nil : notes,
                        token: currentToken
                    )
                } else {
                    // Update existing result
                    updatedResult = try await APIClient.updateStageResult(
                        projectId: projectId,
                        inspectionId: inspection.id,
                        stageId: stageResult.stageId,
                        status: selectedStatus,
                        notes: notes.isEmpty ? nil : notes,
                        token: currentToken
                    )
                }
                
                await MainActor.run {
                    currentStageResult = updatedResult
                    isSubmitting = false
                    
                    // If status is NO, prompt user to create a snag log with photo
                    if selectedStatus == "NO" {
                        pendingStageResultForSnag = updatedResult
                        showSnagCreation = true
                    } else {
                        showSuccessAlert = true
                    }
                }
                
                // Also refresh the inspection details
                await MainActor.run {
                    onRefresh?()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to update stage result: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// Reuse DetailRow from LogDetailView
// struct DetailRow: View { ... } - already defined in LogDetailView.swift

// MARK: - Inspection Section View

struct InspectionSectionView: View {
    let section: InspectionTemplateSection
    let stageResults: [InspectionStageResult]
    let inspection: Inspection
    let projectId: Int
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let description = section.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Progress indicator
                    if !stageResults.isEmpty {
                        let completedCount = stageResults.filter { $0.status != "PENDING" }.count
                        Text("\(completedCount)/\(stageResults.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Section stages - nested under section header
            if isExpanded && !stageResults.isEmpty {
                VStack(spacing: 8) {
                    ForEach(stageResults.sorted(by: { $0.stage.order < $1.stage.order }), id: \.id) { stageResult in
                        NavigationLink(
                            destination: InspectionStageDetailView(
                                inspection: inspection,
                                projectId: projectId,
                                stageResult: stageResult,
                                token: sessionManager.token ?? token,
                                onRefresh: onRefresh
                            )
                            .environmentObject(sessionManager)
                        ) {
                            InspectionStageRowView(stageResult: stageResult)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Photo Views

struct PhotoThumbnailView: View {
    let photo: InspectionStagePhoto
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: photo.fileUrl)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 100, height: 100)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 100, height: 100)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PhotoPreviewView: View {
    let photo: InspectionStagePhoto
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    AsyncImage(url: URL(string: photo.fileUrl)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding()
                    }
                    
                    Text("Uploaded: \(formatDate(photo.uploadedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let latitude = photo.latitude, let longitude = photo.longitude {
                        Text("Location: \(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Linked Snag Row View

struct LinkedSnagRowView: View {
    let defect: InspectionDefect
    let projectId: Int
    let inspectionId: Int
    let stageId: Int
    var onSnagResolved: (() -> Void)? = nil
    var onMarkAsYes: ((_ newStatus: String) -> Void)? = nil
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isExpanded = false
    @State private var log: Log?
    @State private var isLoadingLog = false
    @State private var isMarkingAsYes = false
    @State private var markAsYesError: String?
    
    // Get the linked log ID - either from logId (new style) or snag.id (old style)
    private var linkedLogId: Int? {
        defect.logId ?? defect.log?.id ?? defect.snag?.id
    }
    
    // Check if there's any link (log or snag)
    private var hasLink: Bool {
        defect.logId != nil || defect.log != nil || defect.snag != nil
    }
    
    // Get display title from either log or snag
    private var displayTitle: String {
        if let logTitle = defect.log?.title {
            return logTitle
        }
        if let snagTitle = defect.snag?.title {
            return snagTitle
        }
        return defect.description ?? "Issue recorded"
    }
    
    // Get display status from either log or snag
    private var displayStatus: String {
        if let logStatus = defect.log?.status?.name {
            return logStatus
        }
        if let snagStatus = defect.snag?.status {
            return snagStatus
        }
        return defect.displayStatus
    }
    
    private var statusColor: Color {
        let status = displayStatus.uppercased()
        switch status {
        case "OPEN": return .orange
        case "IN_PROGRESS", "IN PROGRESS": return .blue
        case "RESOLVED", "COMPLETED", "CLOSED": return .green
        case "RECTIFIED": return .green
        case "APPROVED", "ACCEPTED": return .blue
        case "REJECTED": return .red
        default: return .gray
        }
    }
    
    private var isResolved: Bool {
        let status = displayStatus.uppercased()
        return ["RESOLVED", "COMPLETED", "CLOSED"].contains(status) ||
               defect.status == "APPROVED" || defect.status == "ACCEPTED"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isResolved ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 8) {
                            Text(displayStatus)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor)
                                .cornerRadius(4)
                            
                            if let logNumber = defect.log?.number {
                                Text("Log #\(logNumber)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if let priority = defect.snag?.priority {
                                Text(priority)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            
            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Log details
                    if isLoadingLog {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if let log = log {
                        // Description
                        if let description = log.description, !description.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        // Assignee
                        if let assignee = log.assignee {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Assigned to: \(assignee.firstName ?? "") \(assignee.lastName ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Due date
                        if let dueDate = log.dueDate {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Due: \(formatDate(dueDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Photos
                        if let attachments = log.attachments, !attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Photos")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(attachments, id: \.id) { attachment in
                                            AsyncImage(url: URL(string: attachment.fileUrl)) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().scaledToFill()
                                                case .failure:
                                                    Image(systemName: "photo").foregroundColor(.gray)
                                                case .empty:
                                                    ProgressView()
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(6)
                                            .clipped()
                                        }
                                    }
                                }
                            }
                        }
                    } else if !hasLink {
                        Text("No linked log found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                    
                    // Mark as Yes prompt when log is closed
                    if isResolved {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This log is closed. Mark this inspection item as Yes?")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Button(action: { markInspectionAsYes() }) {
                                HStack {
                                    if isMarkingAsYes {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                    }
                                    Text("Mark as Yes")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(6)
                            }
                            .disabled(isMarkingAsYes)
                            
                            if let error = markAsYesError {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Action button
                    if let logId = linkedLogId {
                        NavigationLink(destination: LogDetailFromSnagView(snagId: logId, projectId: projectId).environmentObject(sessionManager)) {
                            HStack {
                                Image(systemName: isResolved ? "eye" : "checkmark.circle")
                                Text(isResolved ? "View Details" : "Resolve")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isResolved ? Color.blue : Color.green)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isResolved ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1))
        .onChange(of: isExpanded) { _, expanded in
            if expanded && log == nil && hasLink {
                loadLog()
            }
        }
    }
    
    private func markInspectionAsYes() {
        isMarkingAsYes = true
        markAsYesError = nil
        
        Task {
            do {
                // Update the stage result to YES
                _ = try await APIClient.updateStageResult(
                    projectId: projectId,
                    inspectionId: inspectionId,
                    stageId: stageId,
                    status: "YES",
                    notes: nil,
                    token: sessionManager.token ?? ""
                )
                
                await MainActor.run {
                    isMarkingAsYes = false
                    onMarkAsYes?("YES")
                }
            } catch {
                await MainActor.run {
                    isMarkingAsYes = false
                    markAsYesError = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loadLog() {
        guard let logId = linkedLogId else { return }
        isLoadingLog = true
        
        Task {
            do {
                // Try to fetch the specific log
                let fetchedLog = try await APIClient.fetchLog(projectId: projectId, logId: logId, token: sessionManager.token ?? "")
                await MainActor.run {
                    log = fetchedLog
                    isLoadingLog = false
                }
            } catch {
                // Fallback: search in all logs
                do {
                    let logs = try await APIClient.fetchLogs(projectId: projectId, token: sessionManager.token ?? "")
                    await MainActor.run {
                        log = logs.first(where: { $0.id == logId })
                        isLoadingLog = false
                    }
                } catch {
                    await MainActor.run {
                        isLoadingLog = false
                    }
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Log Detail from Snag View

struct LogDetailFromSnagView: View {
    let snagId: Int
    let projectId: Int
    @EnvironmentObject var sessionManager: SessionManager
    @State private var log: Log?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading log...")
            } else if let log = log {
                LogDetailView(log: log, token: sessionManager.token ?? "", onRefresh: nil)
                    .environmentObject(sessionManager)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Snag Details")
        .onAppear { loadLog() }
    }
    
    private func loadLog() {
        Task {
            do {
                let logs = try await APIClient.fetchLogs(projectId: projectId, token: sessionManager.token ?? "")
                await MainActor.run {
                    log = logs.first(where: { $0.id == snagId })
                    isLoading = false
                    if log == nil { errorMessage = "Log not found" }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Activity History View

struct ActivityHistoryView: View {
    let activities: [StageActivity]
    let isLoading: Bool
    let stageName: String
    let projectId: Int
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading history...").font(.caption).foregroundColor(.secondary)
                    }
                } else if activities.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock").font(.largeTitle).foregroundColor(.secondary)
                        Text("No activity yet").font(.headline).foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(activities) { activity in
                                ActivityRowView(activity: activity, projectId: projectId).environmentObject(sessionManager)
                                if activity.id != activities.last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Activity Row View

struct ActivityRowView: View {
    let activity: StageActivity
    let projectId: Int
    @EnvironmentObject var sessionManager: SessionManager
    
    private var icon: String {
        switch activity.type {
        case "completion": return "checkmark.circle.fill"
        case "stage_photo", "form_photo": return "camera.fill"
        case "form_response": return "doc.text.fill"
        case "response_change": return "arrow.triangle.2.circlepath"
        case "status_change": return "arrow.right.circle.fill"
        case "defect_created": return "exclamationmark.triangle.fill"
        case "log_created": return "doc.badge.plus"
        case "log_closed": return "checkmark.seal.fill"
        default: return "circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch activity.type {
        case "completion": return statusToColor(activity.status)
        case "stage_photo", "form_photo": return .blue
        case "form_response": return responseToColor(activity.response)
        case "response_change": return .orange
        case "status_change": return statusToColor(activity.newStatus)
        case "defect_created": return .orange
        case "log_created": return .blue
        case "log_closed": return .green
        default: return .gray
        }
    }
    
    private func statusToColor(_ status: String?) -> Color {
        switch status?.uppercased() {
        case "YES": return .green
        case "NO": return .red
        case "N_A", "SKIPPED": return .orange
        default: return .gray
        }
    }
    
    private func responseToColor(_ response: String?) -> Color {
        switch response?.uppercased() {
        case "YES": return .green
        case "NO": return .red
        case "N_A": return .orange
        default: return .gray
        }
    }
    
    private var title: String {
        switch activity.type {
        case "completion": return "Stage completed: \(activity.status ?? "Unknown")"
        case "stage_photo": return "Photo added"
        case "form_response": return "Response: \(activity.response ?? "Unknown")"
        case "response_change": return "Changed: \(activity.oldResponse ?? "?") → \(activity.newResponse ?? "?")"
        case "form_photo": return "Photo added to item"
        case "status_change": return "Status: \(activity.oldStatus ?? "?") → \(activity.newStatus ?? "?")"
        case "defect_created": return "Defect created"
        case "log_created": return activity.logTitle != nil ? "Snag: \(activity.logTitle!)" : "Snag #\(activity.logNumber ?? 0) created"
        case "log_closed": return "Snag resolved: \(activity.logStatus ?? "Closed")"
        default: return activity.type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(iconColor)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: icon).font(.system(size: 14)).foregroundColor(.white))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundColor(.primary)
                
                if let notes = activity.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundColor(.secondary).padding(8).background(Color(.systemGray6)).cornerRadius(6)
                }
                
                HStack(spacing: 8) {
                    if let user = activity.user {
                        Text(user.displayName).font(.caption).foregroundColor(.secondary)
                    }
                    Text(formatActivityDate(activity.timestamp)).font(.caption).foregroundColor(.secondary)
                }
                
                if let photo = activity.photo {
                    AsyncImage(url: URL(string: photo.fileUrl)) { phase in
                        switch phase {
                        case .empty: ProgressView().frame(width: 80, height: 80)
                        case .success(let image): image.resizable().scaledToFill().frame(width: 80, height: 80).cornerRadius(8)
                        case .failure: Image(systemName: "photo").frame(width: 80, height: 80).foregroundColor(.gray)
                        @unknown default: EmptyView()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    private func formatActivityDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}