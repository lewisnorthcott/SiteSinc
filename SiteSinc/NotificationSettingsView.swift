import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    let projectId: Int
    let projectName: String
    
    // Drawing & Document Preferences
    @State private var drawingUpdatesPreference = "instant"
    @State private var documentUpdatesPreference = "instant"
    
    // RFI Notification Preferences
    @State private var rfiNotifyOnAll: String = "none"
    @State private var rfiNotifyOnCreate: String = "none"
    @State private var rfiNotifyOnResponse: String = "none"
    @State private var rfiNotifyOnStatus: String = "none"
    @State private var rfiNotifyOnReminder: String = "daily"
    
    // Log Notification Preferences
    @State private var logNotifyOnCreate: String = "none"
    @State private var logNotifyOnUpdate: String = "none"
    @State private var logNotifyOnStatus: String = "none"
    @State private var logNotifyOnResponse: String = "none"
    
    // Requisition Notification Preferences
    @State private var requisitionNotifyOnSubmit: String = "instant"
    @State private var requisitionNotifyOnAccepted: String = "instant"
    @State private var requisitionNotifyOnProcessing: String = "instant"
    @State private var requisitionNotifyOnOrdered: String = "instant"
    @State private var requisitionNotifyOnDelivered: String = "instant"
    @State private var requisitionNotifyOnCompleted: String = "instant"
    @State private var requisitionNotifyOnCancelled: String = "instant"
    @State private var requisitionNotifyOnRejected: String = "instant"
    
    // UI State
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var showSavedIndicator = false
    @State private var expandedSections: Set<String> = ["drawings"]
    @State private var saveTask: Task<Void, Never>?
    
    // Combined hash for change detection
    private var preferencesHash: Int {
        var hasher = Hasher()
        hasher.combine(drawingUpdatesPreference)
        hasher.combine(documentUpdatesPreference)
        hasher.combine(rfiNotifyOnAll)
        hasher.combine(rfiNotifyOnCreate)
        hasher.combine(rfiNotifyOnResponse)
        hasher.combine(rfiNotifyOnStatus)
        hasher.combine(rfiNotifyOnReminder)
        hasher.combine(logNotifyOnCreate)
        hasher.combine(logNotifyOnUpdate)
        hasher.combine(logNotifyOnStatus)
        hasher.combine(logNotifyOnResponse)
        hasher.combine(requisitionNotifyOnSubmit)
        hasher.combine(requisitionNotifyOnAccepted)
        hasher.combine(requisitionNotifyOnProcessing)
        hasher.combine(requisitionNotifyOnOrdered)
        hasher.combine(requisitionNotifyOnDelivered)
        hasher.combine(requisitionNotifyOnCompleted)
        hasher.combine(requisitionNotifyOnCancelled)
        hasher.combine(requisitionNotifyOnRejected)
        return hasher.finalize()
    }
    
    // Computed permissions
    private var hasDrawingPermissions: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_drawings") || permissions.contains("manage_drawings")
    }
    
    private var hasDocumentPermissions: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_documents") || permissions.contains("manage_documents")
    }
    
    private var hasRfiPermissions: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_rfis") || permissions.contains("manage_rfis") || permissions.contains("view_all_rfis")
    }
    
    private var hasLogPermissions: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_logs") || permissions.contains("manage_all_logs")
    }
    
    private var hasRequisitionPermissions: Bool {
        let permissions = sessionManager.user?.permissions?.map { $0.name } ?? []
        return permissions.contains("view_requisitions") || permissions.contains("manage_requisitions") || permissions.contains("process_requisitions")
    }
    
    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .onAppear { loadCurrentPreferences() }
                .onChange(of: preferencesHash) { _, _ in scheduleAutoSave() }
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            loadingView
        } else {
            formContent
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading preferences...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var formContent: some View {
        Form {
            headerSection
            
            if hasDrawingPermissions {
                drawingNotificationsSection
            }
            
            if hasDocumentPermissions {
                documentNotificationsSection
            }
            
            if hasRfiPermissions {
                rfiNotificationsSection
            }
            
            if hasLogPermissions {
                logNotificationsSection
            }
            
            if hasRequisitionPermissions {
                requisitionNotificationsSection
            }
            
            if !notificationManager.isAuthorized {
                notificationDisabledSection
            }
        }
    }
    
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            savingIndicator
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
                dismiss()
            }
            .fontWeight(.medium)
        }
    }
    
    @ViewBuilder
    private var savingIndicator: some View {
        if isSaving {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Saving...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if showSavedIndicator {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Saved")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - Auto Save
    private func scheduleAutoSave() {
        guard hasLoaded else { return }
        
        saveTask?.cancel()
        
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if !Task.isCancelled {
                await savePreferences()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        Section {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(Color(hex: "#3B82F6"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notification Settings")
                        .font(.headline)
                    Text(projectName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Auto-saves")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Drawing Notifications
    private var drawingNotificationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains("drawings") },
                    set: { if $0 { expandedSections.insert("drawings") } else { expandedSections.remove("drawings") } }
                )
            ) {
                notificationPicker(
                    title: "Drawing Uploads",
                    description: "Get notified when new drawings are uploaded",
                    selection: $drawingUpdatesPreference
                )
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Drawing Notifications")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - Document Notifications
    private var documentNotificationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains("documents") },
                    set: { if $0 { expandedSections.insert("documents") } else { expandedSections.remove("documents") } }
                )
            ) {
                notificationPicker(
                    title: "Document Uploads",
                    description: "Get notified when new documents are uploaded",
                    selection: $documentUpdatesPreference
                )
            } label: {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    Text("Document Notifications")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - RFI Notifications
    private var rfiNotificationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains("rfis") },
                    set: { if $0 { expandedSections.insert("rfis") } else { expandedSections.remove("rfis") } }
                )
            ) {
                rfiNotificationOptions
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.red)
                        .frame(width: 24)
                    Text("RFI Notifications")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private var rfiNotificationOptions: some View {
        VStack(spacing: 16) {
            notificationPicker(title: "All RFI Activity", description: "Receive notifications for any RFI activity", selection: $rfiNotifyOnAll)
            Divider()
            notificationPicker(title: "Notify on Creation", description: "When a new RFI is created", selection: $rfiNotifyOnCreate)
            Divider()
            notificationPicker(title: "Notify on Response", description: "When an RFI receives a response", selection: $rfiNotifyOnResponse)
            Divider()
            notificationPicker(title: "Notify on Status Change", description: "When RFI status changes (accepted/rejected)", selection: $rfiNotifyOnStatus)
            Divider()
            reminderPicker
        }
        .padding(.vertical, 4)
    }
    
    private var reminderPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notify on Reminder")
                .font(.subheadline)
                .fontWeight(.medium)
            Picker("Reminder", selection: $rfiNotifyOnReminder) {
                Text("Daily").tag("daily")
                Text("None").tag("none")
            }
            .pickerStyle(SegmentedPickerStyle())
            Text("Daily reminders for RFIs approaching or past due date")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Log Notifications
    private var logNotificationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains("logs") },
                    set: { if $0 { expandedSections.insert("logs") } else { expandedSections.remove("logs") } }
                )
            ) {
                logNotificationOptions
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    Text("Log Notifications")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private var logNotificationOptions: some View {
        VStack(spacing: 16) {
            notificationPicker(title: "Notify on Creation", description: "When a new log is created", selection: $logNotifyOnCreate)
            Divider()
            notificationPicker(title: "Notify on Update", description: "When a log is updated", selection: $logNotifyOnUpdate)
            Divider()
            notificationPicker(title: "Notify on Status Change", description: "When a log status changes", selection: $logNotifyOnStatus)
            Divider()
            notificationPicker(title: "Notify on Response", description: "When a log receives a response", selection: $logNotifyOnResponse)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Requisition Notifications
    private var requisitionNotificationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains("requisitions") },
                    set: { if $0 { expandedSections.insert("requisitions") } else { expandedSections.remove("requisitions") } }
                )
            ) {
                requisitionNotificationOptions
            } label: {
                HStack {
                    Image(systemName: "cart.fill")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    Text("Material Requisition Notifications")
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private var requisitionNotificationOptions: some View {
        VStack(spacing: 16) {
            notificationPicker(title: "Notify on Submission", description: "When a requisition is submitted", selection: $requisitionNotifyOnSubmit)
            Divider()
            notificationPicker(title: "Notify on Accepted", description: "When a requisition is accepted", selection: $requisitionNotifyOnAccepted)
            Divider()
            notificationPicker(title: "Notify on Processing", description: "When a requisition is being processed", selection: $requisitionNotifyOnProcessing)
            Divider()
            notificationPicker(title: "Notify on Ordered", description: "When materials are ordered", selection: $requisitionNotifyOnOrdered)
            Divider()
            notificationPicker(title: "Notify on Delivered", description: "When materials are delivered", selection: $requisitionNotifyOnDelivered)
            Divider()
            notificationPicker(title: "Notify on Completed", description: "When a requisition is completed", selection: $requisitionNotifyOnCompleted)
            Divider()
            notificationPicker(title: "Notify on Cancelled", description: "When a requisition is cancelled", selection: $requisitionNotifyOnCancelled)
            Divider()
            notificationPicker(title: "Notify on Rejected", description: "When a requisition is rejected", selection: $requisitionNotifyOnRejected)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Notification Disabled Section
    private var notificationDisabledSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Notifications Disabled")
                        .font(.headline)
                }
                
                Text("Enable notifications in Settings to receive updates about this project")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Enable Notifications") {
                    Task {
                        await notificationManager.requestNotificationPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#3B82F6"))
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Reusable Notification Picker
    private func notificationPicker(title: String, description: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Picker(title, selection: selection) {
                Text("Instant").tag("instant")
                Text("Daily").tag("daily")
                Text("None").tag("none")
            }
            .pickerStyle(SegmentedPickerStyle())
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Load Preferences
    private func loadCurrentPreferences() {
        isLoading = true
        
        Task {
            await notificationManager.fetchNotificationPreferences(projectId: projectId)
            
            await MainActor.run {
                parsePreferences()
                isLoading = false
                hasLoaded = true
            }
        }
    }
    
    private func parsePreferences() {
        guard let projectSpecificPreferences = notificationManager.notificationPreferences["projectSpecificPreferences"] as? [[String: Any]] else {
            return
        }
        
        guard let projectPrefs = projectSpecificPreferences.first(where: { prefs in
            if let prefProjectId = prefs["projectId"] as? String {
                return prefProjectId == String(projectId)
            } else if let prefProjectId = prefs["projectId"] as? Int {
                return prefProjectId == projectId
            }
            return false
        }) else {
            return
        }
        
        // Drawing & Document preferences
        drawingUpdatesPreference = projectPrefs["drawingUpdatesPreference"] as? String ?? "none"
        documentUpdatesPreference = projectPrefs["documentUpdatesPreference"] as? String ?? "none"
        
        // RFI notification preferences
        if let rfiNotifications = projectPrefs["rfiNotifications"] as? [String: Any] {
            rfiNotifyOnAll = rfiNotifications["notifyOnAll"] as? String ?? "none"
            rfiNotifyOnCreate = rfiNotifications["notifyOnCreate"] as? String ?? "none"
            rfiNotifyOnResponse = rfiNotifications["notifyOnResponse"] as? String ?? "none"
            rfiNotifyOnStatus = rfiNotifications["notifyOnStatus"] as? String ?? "none"
            rfiNotifyOnReminder = rfiNotifications["notifyOnReminder"] as? String ?? "daily"
        }
        
        // Log notification preferences
        if let logNotifications = projectPrefs["logNotifications"] as? [String: Any] {
            logNotifyOnCreate = logNotifications["notifyOnCreate"] as? String ?? "none"
            logNotifyOnUpdate = logNotifications["notifyOnUpdate"] as? String ?? "none"
            logNotifyOnStatus = logNotifications["notifyOnStatus"] as? String ?? "none"
            logNotifyOnResponse = logNotifications["notifyOnResponse"] as? String ?? "none"
        }
        
        // Requisition notification preferences
        if let requisitionNotifications = projectPrefs["requisitionNotifications"] as? [String: Any] {
            requisitionNotifyOnSubmit = requisitionNotifications["notifyOnSubmit"] as? String ?? "instant"
            requisitionNotifyOnAccepted = requisitionNotifications["notifyOnAccepted"] as? String ?? "instant"
            requisitionNotifyOnProcessing = requisitionNotifications["notifyOnProcessing"] as? String ?? "instant"
            requisitionNotifyOnOrdered = requisitionNotifications["notifyOnOrdered"] as? String ?? "instant"
            requisitionNotifyOnDelivered = requisitionNotifications["notifyOnDelivered"] as? String ?? "instant"
            requisitionNotifyOnCompleted = requisitionNotifications["notifyOnCompleted"] as? String ?? "instant"
            requisitionNotifyOnCancelled = requisitionNotifications["notifyOnCancelled"] as? String ?? "instant"
            requisitionNotifyOnRejected = requisitionNotifications["notifyOnRejected"] as? String ?? "instant"
        }
    }
    
    // MARK: - Save Preferences
    private func savePreferences() async {
        await MainActor.run {
            isSaving = true
            showSavedIndicator = false
        }
        
        let preferences = buildPreferencesPayload()
        
        await notificationManager.updateNotificationPreferences(projectId: projectId, preferences: preferences)
        
        // Cancel any existing local RFI reminder notifications (now handled via backend push)
        await MainActor.run {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rfi_daily_reminder"])
            isSaving = false
            
            withAnimation {
                showSavedIndicator = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSavedIndicator = false
                }
            }
        }
    }
    
    private func buildPreferencesPayload() -> [String: Any] {
        let rfiNotifications: [String: Any] = [
            "notifyOnAll": rfiNotifyOnAll,
            "notifyOnCreate": rfiNotifyOnCreate,
            "notifyOnResponse": rfiNotifyOnResponse,
            "notifyOnStatus": rfiNotifyOnStatus,
            "notifyOnReminder": rfiNotifyOnReminder
        ]
        
        let logNotifications: [String: Any] = [
            "notifyOnCreate": logNotifyOnCreate,
            "notifyOnUpdate": logNotifyOnUpdate,
            "notifyOnStatus": logNotifyOnStatus,
            "notifyOnResponse": logNotifyOnResponse
        ]
        
        let requisitionNotifications: [String: Any] = [
            "notifyOnSubmit": requisitionNotifyOnSubmit,
            "notifyOnAccepted": requisitionNotifyOnAccepted,
            "notifyOnProcessing": requisitionNotifyOnProcessing,
            "notifyOnOrdered": requisitionNotifyOnOrdered,
            "notifyOnDelivered": requisitionNotifyOnDelivered,
            "notifyOnCompleted": requisitionNotifyOnCompleted,
            "notifyOnCancelled": requisitionNotifyOnCancelled,
            "notifyOnRejected": requisitionNotifyOnRejected
        ]
        
        // Snag notifications (default to instant if not set)
        let snagNotifications: [String: Any] = [
            "notifyOnCreate": "instant",
            "notifyOnStatusChange": "instant"
        ]
        
        // Match frontend format exactly: projectId as string, all notification types included
        return [
            "projectSpecificPreferences": [[
                "projectId": String(projectId),
                "drawingUpdatesPreference": drawingUpdatesPreference,
                "documentUpdatesPreference": documentUpdatesPreference,
                "snagNotifications": snagNotifications,
                "rfiNotifications": rfiNotifications,
                "logNotifications": logNotifications,
                "requisitionNotifications": requisitionNotifications
            ]]
        ]
    }
}

#Preview {
    NotificationSettingsView(projectId: 1, projectName: "Sample Project")
        .environmentObject(NotificationManager.shared)
        .environmentObject(SessionManager())
}
