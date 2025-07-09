import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.dismiss) private var dismiss
    
    let projectId: Int
    let projectName: String
    
    @State private var drawingUpdatesPreference = "instant"
    @State private var documentUpdatesPreference = "instant"
    @State private var rfiNotifications = true
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text("Notification Settings")
                            .font(.headline)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Drawing Updates") {
                    Picker("Drawing Uploads", selection: $drawingUpdatesPreference) {
                        Text("Instant").tag("instant")
                        Text("Daily Summary").tag("daily")
                        Text("Weekly Summary").tag("weekly")
                        Text("None").tag("none")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Text("Get notified when new drawings are uploaded to this project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Document Updates") {
                    Picker("Document Uploads", selection: $documentUpdatesPreference) {
                        Text("Instant").tag("instant")
                        Text("Daily Summary").tag("daily")
                        Text("Weekly Summary").tag("weekly")
                        Text("None").tag("none")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Text("Get notified when new documents are uploaded to this project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("RFI Updates") {
                    Toggle("RFI Notifications", isOn: $rfiNotifications)
                    
                    Text("Get notified about RFI updates, responses, and deadlines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: savePreferences) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            Text("Save Preferences")
                                .fontWeight(.medium)
                        }
                    }
                    .disabled(isLoading)
                }
                
                if !notificationManager.isAuthorized {
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
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .alert("Notification Settings", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                loadCurrentPreferences()
            }
        }
    }
    
    private func loadCurrentPreferences() {
        Task {
            await notificationManager.fetchNotificationPreferences(projectId: projectId)
            
            await MainActor.run {
                let preferences = notificationManager.notificationPreferences
                drawingUpdatesPreference = preferences["drawingUpdatesPreference"] as? String ?? "instant"
                documentUpdatesPreference = preferences["documentUpdatesPreference"] as? String ?? "instant"
                
                if let rfiPrefs = preferences["rfiNotifications"] as? [String: Any] {
                    rfiNotifications = rfiPrefs["enabled"] as? Bool ?? true
                }
            }
        }
    }
    
    private func savePreferences() {
        isLoading = true
        
        let preferences: [String: Any] = [
            "drawingUpdatesPreference": drawingUpdatesPreference,
            "documentUpdatesPreference": documentUpdatesPreference,
            "rfiNotifications": [
                "enabled": rfiNotifications
            ]
        ]
        
        Task {
            await notificationManager.updateNotificationPreferences(projectId: projectId, preferences: preferences)
            
            await MainActor.run {
                isLoading = false
                alertMessage = "Notification preferences saved successfully"
                showAlert = true
            }
        }
    }
}

#Preview {
    NotificationSettingsView(projectId: 1, projectName: "Sample Project")
        .environmentObject(NotificationManager.shared)
} 