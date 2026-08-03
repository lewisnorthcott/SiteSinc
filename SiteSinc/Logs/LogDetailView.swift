import SwiftUI
import WebKit
import PhotosUI

struct LogDetailView: View {
    let log: Log
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentLog: Log
    @State private var responseText = ""
    @State private var isSubmittingResponse = false
    @State private var responses: [Log.ResponseItem] = []
    @State private var isLoadingResponses = false
    @State private var errorMessage: String?
    @State private var showEditLog = false
    @State private var showInvestigation = false
    @State private var shareSheetItem: ShareSheetItem?
    @State private var isExportingPDF = false
    @State private var savedResponseOffline = false
    
    // Response attachment states
    @State private var responsePhotos: [UIImage] = []
    @State private var responsePhotoPickerItems: [PhotosPickerItem] = []
    @State private var showResponseCamera = false

    @State private var responsePhotoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var responsePhotoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var responsePhotoMarkupEditorOnCancel: (() -> Void)?
    @State private var responsePhotoGateImage: UIImage?
    @State private var showResponsePhotoGate = false
    @State private var responsePhotoGateApplyJPEG: ((Data) -> Void)?
    
    // Location hierarchy
    @State private var allLocations: [ProjectLocation] = []
    
    // Use current token from session manager to avoid stale token issues
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    // Permission checks
    private var canEditLog: Bool {
        LogPermissions.canEditLog(sessionManager.user, log: currentLog)
    }

    private var canRespondToLog: Bool {
        guard let currentUser = sessionManager.user else { return false }
        let isAssignee = currentLog.assignee?.id == currentUser.id
        let onDistribution = currentLog.distributions?.contains(where: { $0.userId == currentUser.id }) == true
        let hasManageAllLogs = LogPermissions.canManageAllLogs(currentUser)
        let hasRespondPermission = LogPermissions.canRespondToLogs(currentUser)
        return isAssignee || onDistribution || hasManageAllLogs || hasRespondPermission
    }
    
    private var canAcceptResponse: Bool {
        // Creator or users with manage_all_logs permission can accept responses
        guard let currentUser = sessionManager.user else { return false }
        let isLogCreator = currentLog.createdById == currentUser.id
        let hasManageAllLogs = currentUser.permissions?.contains { $0.name == "manage_all_logs" } ?? false
        return isLogCreator || hasManageAllLogs
    }
    
    init(log: Log, token: String, onRefresh: (() -> Void)?) {
        self.log = log
        self.token = token
        self.onRefresh = onRefresh
        self._currentLog = State(initialValue: log)
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
                            Text("Offline Mode - Responses will be saved locally")
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
                    
                    if let description = currentLog.description {
                        descriptionSection(description)
                            .padding(.bottom, 24)
                    }
                    
                    detailsSection
                        .padding(.bottom, 24)
                    
                    if shouldShowSafetySection && !safetyItems.isEmpty {
                        safetySection
                            .padding(.bottom, 24)
                    }

                    if currentLog.isIncidentType {
                        incidentSection
                            .padding(.bottom, 24)

                        CorrectiveActionsCard(
                            projectId: currentLog.projectId,
                            logId: currentLog.id,
                            token: currentToken,
                            actions: currentLog.actions ?? [],
                            canEdit: canEditLog,
                            onRefresh: { refreshLogData() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                        if let witnesses = currentLog.witnessStatements, !witnesses.isEmpty {
                            witnessSection(witnesses)
                                .padding(.bottom, 24)
                        }
                        if let people = currentLog.involvedPeople, !people.isEmpty {
                            involvedPeopleSection(people)
                                .padding(.bottom, 24)
                        }
                    }
                    
                    if let assignee = currentLog.assignee {
                        assignmentSection(assignee)
                            .padding(.bottom, 24)
                    }
                    
                    if let distributions = currentLog.distributions, !distributions.isEmpty {
                        distributionSection(distributions)
                            .padding(.bottom, 24)
                    }
                    
                    if let attachments = currentLog.attachments, !attachments.isEmpty {
                        attachmentsSection(attachments)
                            .padding(.bottom, 24)
                    }
                    
                    responsesSection
                        .padding(.bottom, 24)
                    
                    if canRespondToLog {
                        responseInputSection
                            .padding(.bottom, 24)
                    }
                }
            }
            
            // Saved offline success toast
            if savedResponseOffline {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Response saved offline")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: savedResponseOffline)
            }
        }
        .navigationTitle("\(AppBrand.current.terminology.log) #\(currentLog.number)")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button("Export PDF") { Task { await exportPDF(riddor: false) } }
                    if currentLog.isIncidentType {
                        Button("Export RIDDOR PDF") { Task { await exportPDF(riddor: true) } }
                    }
                } label: {
                    if isExportingPDF {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if canEditLog {
                    Button("Edit") { showEditLog = true }
                }
                if currentLog.isIncidentType && canEditLog {
                    Button("Investigate") { showInvestigation = true }
                }
            }
        }
        .sheet(item: $shareSheetItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .onAppear {
            loadResponses()
            loadLocations()
        }
        .sheet(isPresented: $showEditLog) {
            CreateLogView(
                projectId: currentLog.projectId,
                token: currentToken,
                projectName: "",
                editingLog: currentLog,
                onSuccess: {
                    showEditLog = false
                    refreshLogData()
                }
            )
            .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showInvestigation) {
            LogInvestigationView(
                log: currentLog,
                projectId: currentLog.projectId,
                token: currentToken,
                onSuccess: { refreshLogData() }
            )
            .environmentObject(sessionManager)
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
        .confirmationDialog("Photo", isPresented: $showResponsePhotoGate, titleVisibility: .visible) {
            Button("Use photo") {
                if let img = responsePhotoGateImage, let d = img.jpegData(compressionQuality: 0.8) {
                    responsePhotoGateApplyJPEG?(d)
                }
                responsePhotoGateImage = nil
                responsePhotoGateApplyJPEG = nil
                showResponsePhotoGate = false
            }
            Button("Mark up") {
                let img = responsePhotoGateImage
                let apply = responsePhotoGateApplyJPEG
                responsePhotoGateImage = nil
                responsePhotoGateApplyJPEG = nil
                showResponsePhotoGate = false
                responsePhotoMarkupEditorOnDone = { data in
                    apply?(data)
                    dismissResponsePhotoMarkupEditor()
                }
                responsePhotoMarkupEditorOnCancel = {
                    if let i = img, let d = i.jpegData(compressionQuality: 0.8) {
                        apply?(d)
                    }
                    dismissResponsePhotoMarkupEditor()
                }
                if let ui = img {
                    responsePhotoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
                }
            }
            Button("Cancel", role: .cancel) {
                responsePhotoGateImage = nil
                responsePhotoGateApplyJPEG = nil
                showResponsePhotoGate = false
            }
        } message: {
            Text("Use this photo as captured, or mark it up before adding.")
        }
        .fullScreenCover(item: $responsePhotoMarkupPresentation) { item in
            PhotoMarkupEditorScreen(
                image: item.image,
                onDone: { data in
                    responsePhotoMarkupEditorOnDone?(data)
                },
                onCancel: {
                    responsePhotoMarkupEditorOnCancel?()
                }
            )
        }
    }

    private func dismissResponsePhotoMarkupEditor() {
        responsePhotoMarkupPresentation = nil
        responsePhotoMarkupEditorOnDone = nil
        responsePhotoMarkupEditorOnCancel = nil
    }

    private func openResponsePhotoMarkupEditor(at index: Int) {
        guard index < responsePhotos.count else { return }
        let ui = responsePhotos[index]
        responsePhotoMarkupEditorOnDone = { data in
            if let img = UIImage(data: data) {
                responsePhotos[index] = img
            }
            dismissResponsePhotoMarkupEditor()
        }
        responsePhotoMarkupEditorOnCancel = {
            dismissResponsePhotoMarkupEditor()
        }
        responsePhotoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
    }
    
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = currentLog.title {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.secondary)
                        Text("Created by \(LogPermissions.reporterDisplayName(currentLog, currentUser: sessionManager.user))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Created: \(formatDate(currentLog.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    if let status = currentLog.status {
                        LogStatusBadge(status: status)
                    }
                    
                    if let priority = currentLog.logPriority {
                        PriorityBadge(priority: priority)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(description)
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
                if let type = currentLog.type {
                    DetailRow(label: "Type", value: type.name, icon: "tag.fill")
                }
                
                if let trade = currentLog.trade {
                    DetailRow(label: "Trade", value: trade.name, icon: "hammer.fill")
                }
                
                if let projectLocation = currentLog.projectLocation {
                    DetailRow(label: "Location", value: buildLocationPath(for: projectLocation), icon: "mappin.circle.fill")
                } else if let location = currentLog.location {
                    DetailRow(label: "Location", value: location, icon: "location.fill")
                }
                
                if let specification = currentLog.specification {
                    DetailRow(label: "Specification", value: specification, icon: "doc.text.fill")
                }
                
                if let dueDate = currentLog.dueDate {
                    DetailRow(label: "Due Date", value: formatDate(dueDate), icon: "calendar.fill")
                }
                
                DetailRow(label: "Private", value: currentLog.isPrivate ? "Yes" : "No", icon: "eye.slash.fill")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func buildLocationPath(for location: ProjectLocation) -> String {
        var pathComponents: [String] = []
        var currentLocation: ProjectLocation? = location
        
        // Build a lookup map of all locations by ID
        var locationMap: [Int: ProjectLocation] = [:]
        func buildMap(_ locations: [ProjectLocation]) {
            for loc in locations {
                locationMap[loc.id] = loc
                if let children = loc.children {
                    buildMap(children)
                }
            }
        }
        buildMap(allLocations)
        
        // Traverse up the parent hierarchy
        while let loc = currentLocation {
            let displayName = loc.code != nil ? "\(loc.name) (\(loc.code!))" : loc.name
            pathComponents.insert(displayName, at: 0)
            
            if let parentId = loc.parentId, let parent = locationMap[parentId] {
                currentLocation = parent
            } else {
                break
            }
        }
        
        // If we couldn't build a path (no locations loaded), just show the location name
        if pathComponents.isEmpty {
            return location.code != nil ? "\(location.name) (\(location.code!))" : location.name
        }
        
        return pathComponents.joined(separator: " -> ")
    }
    
    private func loadLocations() {
        Task {
            do {
                let locations = try await APIClient.fetchProjectLocations(
                    projectId: currentLog.projectId,
                    token: currentToken
                )
                await MainActor.run {
                    self.allLocations = locations
                }
            } catch {
                // Silently fail - locations are optional
                print("Failed to load locations for path building: \(error.localizedDescription)")
            }
        }
    }
    
    private var shouldShowSafetySection: Bool {
        guard let typeName = currentLog.type?.name else { return false }
        return typeName.lowercased().contains("safety")
    }
    
    private var safetyItems: [(String, String, Color)] {
        var items: [(String, String, Color)] = []
        
        if let hazard = currentLog.hazard {
            items.append(("Hazard", hazard.name, .red))
        }
        
        if let condition = currentLog.contributingCondition {
            items.append(("Contributing Condition", condition.name, .orange))
        }
        
        if let behaviour = currentLog.contributingBehaviour {
            items.append(("Contributing Behaviour", behaviour.name, .yellow))
        }
        
        return items
    }
    
    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(safetyItems, id: \.0) { item in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(item.2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.1)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func assignmentSection(_ assignee: Log.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assigned To")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignee.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let companyName = assignee.companyName {
                        Text(companyName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func distributionSection(_ distributions: [Log.LogDistribution]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribution List")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                // Use a stable composite key since distribution.id can be missing in some payloads
                ForEach(distributions, id: \.userId) { distribution in
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(distribution.user.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            if let companyName = distribution.user.companyName {
                                Text(companyName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func attachmentsSection(_ attachments: [Log.LogAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(attachments.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                
                Spacer()
            }
            
            // Separate image attachments from other files
            let imageAttachments = attachments.filter { isImageFile($0.fileType, fileName: $0.fileName) }
            let otherAttachments = attachments.filter { !isImageFile($0.fileType, fileName: $0.fileName) }
            
            if !imageAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // Display image attachments as larger previews
                    if imageAttachments.count == 1 {
                        // Single image - show larger
                        LogImageAttachmentView(
                            attachment: imageAttachments[0],
                            height: 250,
                            projectId: currentLog.projectId,
                            logId: currentLog.id,
                            token: currentToken
                        )
                    } else if imageAttachments.count == 2 {
                        // Two images - show side by side
                        HStack(spacing: 8) {
                            ForEach(imageAttachments, id: \.id) { attachment in
                                LogImageAttachmentView(
                                    attachment: attachment,
                                    height: 180,
                                    projectId: currentLog.projectId,
                                    logId: currentLog.id,
                                    token: currentToken
                                )
                            }
                        }
                    } else {
                        // Multiple images - grid layout
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(imageAttachments, id: \.id) { attachment in
                                LogImageAttachmentView(
                                    attachment: attachment,
                                    height: 150,
                                    projectId: currentLog.projectId,
                                    logId: currentLog.id,
                                    token: currentToken
                                )
                            }
                        }
                    }
                }
            }
            
            if !otherAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !imageAttachments.isEmpty {
                        Text("Files")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    
                    // Display other attachments as list items
                    ForEach(otherAttachments, id: \.id) { attachment in
                        HStack(spacing: 12) {
                            Image(systemName: fileIcon(for: attachment.fileType))
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.fileName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(attachment.fileType.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let url = URL(string: attachment.fileUrl) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Download")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
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
    
    
    private func isImageFile(_ fileType: String, fileName: String? = nil) -> Bool {
        // Check MIME type first
        let imageTypes = ["image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif"]
        if imageTypes.contains(fileType.lowercased()) {
            return true
        }
        
        // Fallback: check file extension when MIME type is generic (e.g., application/octet-stream)
        if let fileName = fileName {
            let lowercasedName = fileName.lowercased()
            let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".bmp", ".tiff"]
            for ext in imageExtensions {
                if lowercasedName.hasSuffix(ext) {
                    return true
                }
            }
            // Also check if filename starts with "photo_" (common pattern for uploaded photos)
            if lowercasedName.hasPrefix("photo_") || lowercasedName.hasPrefix("img_") || lowercasedName.hasPrefix("image_") {
                return true
            }
        }
        
        return false
    }
    
    private func fileIcon(for fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            return "photo.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        default:
            return "paperclip"
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
    
    private func loadResponses() {
        guard !isLoadingResponses else { return }
        
        Task {
            await MainActor.run {
                isLoadingResponses = true
            }
            
            do {
                let fetchedResponses = try await APIClient.fetchLogResponses(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responses = fetchedResponses.sorted { $0.createdAt > $1.createdAt }
                    self.isLoadingResponses = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingResponses = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to view responses."
                        default:
                            self.errorMessage = "Failed to load responses: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func submitResponse() {
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // If offline, save for later
        if offlineManager.isOffline {
            saveResponseOffline(accepted: false)
            return
        }
        
        Task {
            await MainActor.run {
                isSubmittingResponse = true
            }
            
            do {
                try await APIClient.submitLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    response: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responseText = ""
                    self.isSubmittingResponse = false
                    self.loadResponses()
                }
            } catch {
                await MainActor.run {
                    self.isSubmittingResponse = false
                    
                    // If network error, save offline
                    if let apiError = error as? APIError, case .networkError = apiError {
                        self.saveResponseOffline(accepted: false)
                        return
                    }
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to respond to this log."
                        default:
                            self.errorMessage = "Failed to submit response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private var incidentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Incident investigation")
                .font(.headline)

            if currentLog.regulatoryNotifiable == true {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Likely RIDDOR reportable")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }

            IncidentPayloadSummaryView(log: currentLog)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func witnessSection(_ witnesses: [WitnessStatement]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Witness statements")
                .font(.headline)
            ForEach(witnesses) { witness in
                VStack(alignment: .leading, spacing: 4) {
                    Text(witness.witnessName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(witness.statement)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    private func involvedPeopleSection(_ people: [InvolvedPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Involved people")
                .font(.headline)
            ForEach(people) { person in
                HStack {
                    Text(person.name)
                        .font(.subheadline)
                    if person.injured == true {
                        Text("Injured")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                    Spacer()
                    if let role = person.role {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    private func exportPDF(riddor: Bool) async {
        await MainActor.run { isExportingPDF = true }
        do {
            let url: URL
            if riddor {
                url = try await APIClient.fetchRiddorPDF(projectId: currentLog.projectId, logId: currentLog.id, token: currentToken)
            } else {
                url = try await APIClient.fetchLogPDF(projectId: currentLog.projectId, logId: currentLog.id, token: currentToken)
            }
            await MainActor.run {
                shareSheetItem = ShareSheetItem(url: url)
                isExportingPDF = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isExportingPDF = false
            }
        }
    }

    private func refreshLogData() {
        Task {
            if let updated = try? await APIClient.fetchLog(projectId: currentLog.projectId, logId: currentLog.id, token: currentToken) {
                await MainActor.run { currentLog = updated }
            }
            onRefresh?()
        }
    }
    
    // MARK: - Response Sections
    
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Responses")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !responses.isEmpty {
                    Text("\(responses.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Spacer()
            }
            
            if isLoadingResponses {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading responses...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if responses.isEmpty {
                Text("No responses yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(responses, id: \.id) { response in
                        ResponseRowView(
                            response: response,
                            canAccept: canAcceptResponse && !response.accepted,
                            onAccept: {
                                acceptResponse(response.id)
                            },
                            projectId: currentLog.projectId,
                            logId: currentLog.id,
                            token: currentToken
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var responseInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Submit Response")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Response")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $responseText)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    
                    // Placeholder text
                    if responseText.isEmpty {
                        Text("Enter your response here (required)")
                            .font(.body)
                            .foregroundColor(Color(.placeholderText))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                
                // Helper text
                if responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("A response is required before submitting")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                // Attachment section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Attachments")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if !responsePhotos.isEmpty {
                            Text("\(responsePhotos.count)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            // Camera button
                            Button(action: {
                                showResponseCamera = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                    Text("Camera")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            
                            // Photo library picker
                            PhotosPicker(selection: $responsePhotoPickerItems,
                                        maxSelectionCount: 5,
                                        matching: .images) {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.on.rectangle")
                                    Text("Photos")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .onChange(of: responsePhotoPickerItems) { _, newItems in
                                Task {
                                    await loadResponsePhotos(from: newItems)
                                }
                            }
                        }
                    }
                    
                    // Display selected photos
                    if !responsePhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(responsePhotos.indices, id: \.self) { index in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: responsePhotos[index])
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                            .cornerRadius(8)

                                        VStack {
                                            Spacer()
                                            HStack {
                                                Button {
                                                    openResponsePhotoMarkupEditor(at: index)
                                                } label: {
                                                    Image(systemName: "pencil.tip.crop.circle")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white)
                                                        .padding(5)
                                                        .background(.ultraThinMaterial, in: Circle())
                                                }
                                                .accessibilityLabel("Mark up photo")
                                                Spacer()
                                            }
                                        }
                                        .padding(4)
                                        
                                        // Remove button
                                        Button(action: {
                                            responsePhotos.remove(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("Add photos to show the resolved issue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Submit buttons
                HStack(spacing: 12) {
                    let isDisabled = responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingResponse
                    
                    Button(action: {
                        submitResponse(accepted: true)
                    }) {
                        HStack(spacing: 6) {
                            if isSubmittingResponse {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            VStack(spacing: 0) {
                                Text("Accept")
                                Text("& Close")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 8)
                        .background(isDisabled ? Color.gray : Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .opacity(isDisabled ? 0.5 : 1.0)
                    }
                    .disabled(isDisabled)
                    
                    Button(action: {
                        submitResponse(accepted: false)
                    }) {
                        HStack(spacing: 6) {
                            if isSubmittingResponse {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text("Submit")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .opacity(isDisabled ? 0.5 : 1.0)
                    }
                    .disabled(isDisabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showResponseCamera) {
            ResponseCameraView { image in
                responsePhotoGateImage = image
                responsePhotoGateApplyJPEG = { jpeg in
                    guard responsePhotos.count < 5, let img = UIImage(data: jpeg) else { return }
                    responsePhotos.append(img)
                }
                showResponsePhotoGate = true
            }
        }
    }
    
    private func loadResponsePhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    // Limit to 5 total photos
                    if responsePhotos.count < 5 {
                        responsePhotos.append(image)
                    }
                }
            }
        }
        await MainActor.run {
            responsePhotoPickerItems.removeAll()
        }
    }
    
    private func submitResponse(accepted: Bool) {
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // If offline, save for later
        if offlineManager.isOffline {
            saveResponseOffline(accepted: accepted)
            return
        }
        
        Task {
            await MainActor.run {
                isSubmittingResponse = true
            }
            
            do {
                // Convert photos to JPEG data
                var attachmentData: [Data] = []
                var attachmentNames: [String] = []
                
                for (index, photo) in responsePhotos.enumerated() {
                    if let jpegData = photo.jpegData(compressionQuality: 0.8) {
                        attachmentData.append(jpegData)
                        attachmentNames.append("response_photo_\(index + 1).jpg")
                    }
                }
                
                try await APIClient.submitLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    response: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                    accepted: accepted,
                    attachments: attachmentData,
                    attachmentNames: attachmentNames,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.responseText = ""
                    self.responsePhotos.removeAll()
                    self.isSubmittingResponse = false
                    self.loadResponses()
                    self.refreshLogData()
                }
            } catch {
                await MainActor.run {
                    self.isSubmittingResponse = false
                    
                    // If network error, save offline
                    if let apiError = error as? APIError, case .networkError = apiError {
                        self.saveResponseOffline(accepted: accepted)
                        return
                    }
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to respond to this log."
                        default:
                            self.errorMessage = "Failed to submit response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func saveResponseOffline(accepted: Bool) {
        // Convert photos to offline format
        var offlinePhotos: [OfflineLogResponse.OfflineResponsePhoto] = []
        for (index, photo) in responsePhotos.enumerated() {
            if let jpegData = photo.jpegData(compressionQuality: 0.8) {
                offlinePhotos.append(OfflineLogResponse.OfflineResponsePhoto(
                    fileName: "response_photo_\(index + 1).jpg",
                    fileData: jpegData
                ))
            }
        }
        
        let offlineResponse = OfflineLogResponse(
            id: UUID().uuidString,
            projectId: currentLog.projectId,
            logId: currentLog.id,
            response: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
            accepted: accepted,
            photos: offlinePhotos,
            createdAt: Date()
        )
        
        offlineManager.saveResponse(offlineResponse)
        
        // Clear form and show success
        responseText = ""
        responsePhotos.removeAll()
        savedResponseOffline = true
        
        // Hide the success message after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            savedResponseOffline = false
        }
    }
    
    private func acceptResponse(_ responseId: Int) {
        Task {
            do {
                try await APIClient.acceptLogResponse(
                    projectId: currentLog.projectId,
                    logId: currentLog.id,
                    responseId: responseId,
                    token: currentToken
                )
                
                await MainActor.run {
                    self.loadResponses()
                    self.refreshLogData()
                }
            } catch {
                await MainActor.run {
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .tokenExpired:
                            self.errorMessage = "Session expired. Please log in again."
                        case .forbidden:
                            self.errorMessage = "You don't have permission to accept responses."
                        default:
                            self.errorMessage = "Failed to accept response: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

struct ResponseRowView: View {
    let response: Log.ResponseItem
    let canAccept: Bool
    let onAccept: () -> Void
    let projectId: Int
    let logId: Int
    let token: String
    
    private var hasAttachments: Bool {
        guard let attachments = response.attachments else { return false }
        return !attachments.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(response.user.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let companyName = response.user.companyName {
                        Text(companyName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatResponseDate(response.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if response.accepted {
                        Text("ACCEPTED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if canAccept {
                        Button(action: onAccept) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("Accept")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            Text(response.response)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Display attachments if any
            if let attachments = response.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Attachments (\(attachments.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments, id: \.id) { attachment in
                                ResponseAttachmentThumbnail(
                                    attachment: attachment,
                                    projectId: projectId,
                                    logId: logId,
                                    responseId: response.id,
                                    token: token
                                )
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatResponseDate(_ dateString: String) -> String {
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

struct LogStatusBadge: View {
    let status: Log.LogStatus
    
    var body: some View {
        Text(status.name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: status.color ?? "#64748B"))
            .cornerRadius(6)
    }
}

struct PriorityBadge: View {
    let priority: Log.LogPriority
    
    var body: some View {
        Text(priority.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: priority.color ?? "#64748B"))
            .cornerRadius(4)
    }
}

// Color(hex:) extension lives elsewhere in the project; avoid redefining here to prevent ambiguity.

struct LogImageAttachmentView: View {
    let attachment: Log.LogAttachment
    let height: CGFloat
    let projectId: Int
    let logId: Int
    let token: String
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var urlMissing = false
    @State private var showFullScreen = false
    
    var body: some View {
        Button(action: {
            if image != nil {
                showFullScreen = true
            }
        }) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                    
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: height)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                // Tap to view overlay
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                .font(.caption2)
                                            Text("Tap to view")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(6)
                                        .padding(8)
                                    }
                                }
                            )
                    } else if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.0)
                            Text("Loading image...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if urlMissing {
                        // URL is missing - this is a backend issue
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title)
                                .foregroundColor(.gray)
                            Text("Image not available")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Text(attachment.fileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text("Upload incomplete")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding()
                    } else if loadError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("Failed to load image")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(attachment.fileName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            // Retry button
                            Button(action: {
                                loadError = false
                                isLoading = true
                                loadImage()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                    }
                }
            }
            .frame(height: height)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let image = image {
                FullScreenImageView(image: image, attachment: attachment)
            }
        }
    }
    
    private func loadImage() {
        // Check if fileUrl is empty
        guard !attachment.fileUrl.isEmpty else {
            print("Image URL is empty for \(attachment.fileName)")
            isLoading = false
            urlMissing = true
            return
        }
        
        // If fileUrl is a full URL (starts with http), use it directly
        // Otherwise, fetch presigned URL from backend
        if attachment.fileUrl.hasPrefix("http") {
            loadImageFromURL(attachment.fileUrl)
        } else {
            // Fetch presigned URL from backend
            fetchPresignedURLAndLoad()
        }
    }
    
    private func fetchPresignedURLAndLoad() {
        Task {
            do {
                let downloadInfo = try await APIClient.fetchLogAttachmentDownloadURL(
                    projectId: projectId,
                    logId: logId,
                    attachmentId: attachment.id,
                    token: token
                )
                
                await MainActor.run {
                    loadImageFromURL(downloadInfo.downloadUrl)
                }
            } catch {
                await MainActor.run {
                    print("Failed to fetch presigned URL for \(attachment.fileName): \(error)")
                    isLoading = false
                    loadError = true
                }
            }
        }
    }
    
    private func loadImageFromURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL for \(attachment.fileName): \(urlString)")
            isLoading = false
            loadError = true
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("Image load error for \(attachment.fileName): \(error.localizedDescription)")
                    loadError = true
                    return
                }
                
                guard let data = data, let loadedImage = UIImage(data: data) else {
                    print("Failed to create image from data for \(attachment.fileName)")
                    loadError = true
                    return
                }
                
                self.image = loadedImage
            }
        }.resume()
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    let attachment: Log.LogAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            },
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
            
            VStack {
                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Button("Download") {
                        // TODO: Implement download functionality
                    }
                    .foregroundColor(.white)
                    .padding()
                }
                
                Spacer()
                
                VStack {
                    Text(attachment.fileName)
                        .foregroundColor(.white)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text(attachment.fileType.uppercased())
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding()
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = scale == 1.0 ? 2.0 : 1.0
                offset = .zero
                lastOffset = .zero
            }
        }
    }
}

// MARK: - Response Camera View
struct ResponseCameraView: UIViewControllerRepresentable {
    let onPhotoTaken: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ResponseCameraView
        
        init(_ parent: ResponseCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhotoTaken(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Response Attachment Thumbnail
struct ResponseAttachmentThumbnail: View {
    let attachment: Log.ResponseItem.ResponseAttachment
    let projectId: Int
    let logId: Int
    let responseId: Int
    let token: String
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var showFullScreen = false
    
    private var isImageFile: Bool {
        let imageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif"]
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"]
        
        let lowercaseType = attachment.fileType.lowercased()
        if imageTypes.contains(lowercaseType) {
            return true
        }
        
        let lowercaseName = attachment.fileName.lowercased()
        if imageExtensions.contains(where: { lowercaseName.hasSuffix($0) }) {
            return true
        }
        
        if lowercaseName.hasPrefix("photo_") || lowercaseName.hasPrefix("image_") {
            return true
        }
        
        return false
    }
    
    var body: some View {
        Button(action: {
            if image != nil {
                showFullScreen = true
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                
                if isImageFile {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if loadError {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                } else {
                    // Non-image file icon
                    VStack(spacing: 2) {
                        Image(systemName: "doc.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        Text(getFileExtension())
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if isImageFile {
                loadImage()
            } else {
                isLoading = false
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let image = image {
                ResponseFullScreenImageView(image: image, fileName: attachment.fileName)
            }
        }
    }
    
    private func getFileExtension() -> String {
        let components = attachment.fileName.components(separatedBy: ".")
        return components.last?.uppercased() ?? "FILE"
    }
    
    private func loadImage() {
        Task {
            do {
                let downloadResponse = try await APIClient.fetchLogResponseAttachmentDownloadURL(
                    projectId: projectId,
                    logId: logId,
                    responseId: responseId,
                    attachmentId: attachment.id,
                    token: token
                )
                await loadActualImage(from: downloadResponse.downloadUrl)
            } catch {
                await MainActor.run {
                    print("Failed to get presigned URL for response attachment \(attachment.fileName): \(error.localizedDescription)")
                    isLoading = false
                    loadError = true
                }
            }
        }
    }
    
    private func loadActualImage(from urlString: String) async {
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                isLoading = false
                loadError = true
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let loadedImage = UIImage(data: data) {
                await MainActor.run {
                    self.image = loadedImage
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                    loadError = true
                }
            }
        } catch {
            await MainActor.run {
                print("Image load error for \(attachment.fileName): \(error.localizedDescription)")
                isLoading = false
                loadError = true
            }
        }
    }
}

struct ResponseFullScreenImageView: View {
    let image: UIImage
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
