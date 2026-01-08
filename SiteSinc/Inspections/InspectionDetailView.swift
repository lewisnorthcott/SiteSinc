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
    @State private var defects: [InspectionDefect] = []
    @State private var isLoadingDefects = false
    
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
                    
                    // Defects section - show if there are any defects
                    if !defects.isEmpty || (currentInspection.stageResults?.contains(where: { $0._count?.defects ?? 0 > 0 }) ?? false) {
                        defectsSection
                            .padding(.bottom, 24)
                    }
                }
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
    
    private var defectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Defects (\(defects.count))")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if defects.count > 0 {
                    NavigationLink(destination: InspectionDefectsView(
                        inspection: currentInspection,
                        projectId: projectId,
                        token: currentToken,
                        onRefresh: {
                            loadInspectionDetails()
                            loadDefects()
                        }
                    )
                    .environmentObject(sessionManager)
                    ) {
                        Text("View All")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if isLoadingDefects {
                ProgressView()
                    .padding()
            } else if defects.isEmpty {
                Text("No defects")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(defects.prefix(5)) { defect in
                        DefectRowView(
                            defect: defect,
                            inspection: currentInspection,
                            projectId: projectId,
                            token: currentToken,
                            onRefresh: {
                                loadDefects()
                                loadInspectionDetails()
                            }
                        )
                        .environmentObject(sessionManager)
                    }
                    
                    if defects.count > 5 {
                        NavigationLink(destination: InspectionDefectsView(
                            inspection: currentInspection,
                            projectId: projectId,
                            token: currentToken,
                            onRefresh: {
                                loadInspectionDetails()
                                loadDefects()
                            }
                        )
                        .environmentObject(sessionManager)
                        ) {
                            Text("View All \(defects.count) Defects")
                                .font(.body)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            if defects.isEmpty {
                loadDefects()
            }
        }
    }
    
    private func loadDefects() {
        guard !isLoadingDefects else { return }
        isLoadingDefects = true
        
        Task {
            do {
                let fetchedDefects = try await APIClient.fetchInspectionDefects(
                    projectId: projectId,
                    inspectionId: currentInspection.id,
                    token: currentToken
                )
                await MainActor.run {
                    defects = fetchedDefects
                    isLoadingDefects = false
                }
            } catch {
                await MainActor.run {
                    isLoadingDefects = false
                    print("Failed to load defects: \(error)")
                }
            }
        }
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
                    
                    // Defects section - always show if status is NO, or if there are defects
                    if selectedStatus == "NO" || !stageDefects.isEmpty || (currentStageResult._count?.defects ?? 0) > 0 {
                        stageDefectsSection
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
    
    private var stageDefectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Defects")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if stageDefects.isEmpty {
                if (selectedStatus == "NO" || currentStageResult.status == "NO") && (currentStageResult._count?.defects ?? 0) > 0 {
                    // Status is NO and defect count > 0, but defects not loaded - show loading
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading defects...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                    .task {
                        // Try loading again if defect should exist
                        loadStageDefects()
                    }
                } else if selectedStatus == "NO" {
                    Text("Defect will be created when you save with 'NO' status")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("No defects")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(stageDefects) { defect in
                        DefectRowView(
                            defect: defect,
                            inspection: inspection,
                            projectId: projectId,
                            token: currentToken,
                            onRefresh: {
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
    
    private func createDefectIfNeeded() async throws {
        // Check if status is NO and no defects exist
        if selectedStatus == "NO" {
            let allDefects = try await APIClient.fetchInspectionDefects(
                projectId: projectId,
                inspectionId: inspection.id,
                token: currentToken
            )
            // Check for defects matching this stage ID (not stageResultId, as defect might be created before stage result is updated)
            let existingDefects = allDefects.filter { defect in
                defect.stageResult?.stage.id == currentStageResult.stageId
            }
            
            if existingDefects.isEmpty {
                // Automatically create defect when status is NO
                print("Creating defect for stage \(currentStageResult.stageId)")
                let createdDefect = try await APIClient.createDefect(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    stageId: currentStageResult.stageId,
                    description: nil,
                    assignedToId: nil,
                    token: currentToken
                )
                print("Defect created: \(createdDefect.id)")
            } else {
                print("Defect already exists for this stage")
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
                
                // Automatically create defect if status is NO
                if selectedStatus == "NO" {
                    try await createDefectIfNeeded()
                }
                
                await MainActor.run {
                    currentStageResult = updatedResult
                    isSubmitting = false
                    showSuccessAlert = true
                }
                
                // Refresh defects after saving - wait a bit for defect to be created
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                await loadStageDefects()
                
                // Also refresh the inspection details to get updated defect count
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

