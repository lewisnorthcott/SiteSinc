import SwiftUI

struct PendingSubmissionsView: View {
    @StateObject private var offlineManager = OfflineSubmissionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if offlineManager.pendingSubmissions.isEmpty {
                    emptyStateView
                } else {
                    submissionsList
                }
            }
            .navigationTitle("Pending Submissions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        offlineManager.manualSync()
                    }) {
                        if offlineManager.syncInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Sync All")
                        }
                    }
                    .disabled(offlineManager.syncInProgress || offlineManager.pendingSubmissions.isEmpty)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            Text("All Caught Up!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("No pending form submissions. All your offline submissions have been synced.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var submissionsList: some View {
        VStack {
            if let syncError = offlineManager.lastSyncError {
                syncErrorBanner(syncError)
            }
            
            List {
                ForEach(offlineManager.pendingSubmissions) { submission in
                    PendingSubmissionCard(submission: submission)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func syncErrorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sync Failed")
                    .font(.headline)
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct PendingSubmissionCard: View {
    let submission: OfflineSubmission
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        // Since we don't have a creation date, we'll use the ID's timestamp
        return "Offline Submission"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Form Template ID: \(submission.formTemplateId)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Project ID: \(submission.projectId)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(submission.status.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.2))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !submission.formData.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Form Data:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(submission.formData.count) field\(submission.formData.count == 1 ? "" : "s") filled")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            
            if let attachments = submission.fileAttachments, !attachments.isEmpty {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(.blue)
                    Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                }
            }
            
            Text("ID: \(submission.id.uuidString.prefix(8))...")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch submission.status.lowercased() {
        case "draft":
            return .orange
        case "submitted":
            return .green
        default:
            return .gray
        }
    }
}

#Preview {
    PendingSubmissionsView()
} 