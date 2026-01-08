import SwiftUI
import PhotosUI

struct InspectionDefectsView: View {
    let inspection: Inspection
    let projectId: Int
    let token: String
    let onRefresh: (() -> Void)?
    @EnvironmentObject var sessionManager: SessionManager
    @State private var defects: [InspectionDefect] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDefect: InspectionDefect?
    @State private var showRectifyView = false
    @State private var showRejectSheet = false
    @State private var rejectionNotes = ""
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    var body: some View {
        ZStack {
            if isLoading && defects.isEmpty {
                ProgressView()
            } else if defects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    Text("No Defects")
                        .font(.headline)
                    Text("All inspection items have passed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(defects) { defect in
                            DefectCardView(
                                defect: defect,
                                inspection: inspection,
                                onRectify: {
                                    selectedDefect = defect
                                    showRectifyView = true
                                },
                                onApprove: {
                                    approveDefect(defect)
                                },
                                onReject: {
                                    selectedDefect = defect
                                    showRejectSheet = true
                                }
                            )
                            .environmentObject(sessionManager)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Defects (\(defects.count))")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadDefects()
        }
        .sheet(isPresented: $showRectifyView) {
            if let defect = selectedDefect {
                RectifyDefectView(
                    defect: defect,
                    inspection: inspection,
                    projectId: projectId,
                    token: currentToken,
                    onSuccess: {
                        loadDefects()
                        onRefresh?()
                        showRectifyView = false
                        selectedDefect = nil
                    }
                )
                .environmentObject(sessionManager)
            }
        }
        .alert("Reject Defect", isPresented: $showRejectSheet) {
            TextField("Rejection reason", text: $rejectionNotes)
            Button("Cancel", role: .cancel) {
                rejectionNotes = ""
                selectedDefect = nil
            }
            Button("Reject") {
                if let defect = selectedDefect {
                    rejectDefect(defect, notes: rejectionNotes)
                }
            }
        } message: {
            Text("Please provide a reason for rejecting this rectification.")
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
    
    private func loadDefects() {
        guard !isLoading else { return }
        isLoading = true
        
        Task {
            do {
                let fetchedDefects = try await APIClient.fetchInspectionDefects(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    token: currentToken
                )
                await MainActor.run {
                    defects = fetchedDefects
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load defects: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func approveDefect(_ defect: InspectionDefect) {
        Task {
            do {
                _ = try await APIClient.approveDefect(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    defectId: defect.id,
                    token: currentToken
                )
                await MainActor.run {
                    loadDefects()
                    onRefresh?()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to approve defect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func rejectDefect(_ defect: InspectionDefect, notes: String) {
        guard !notes.isEmpty else {
            errorMessage = "Rejection reason is required"
            return
        }
        
        Task {
            do {
                _ = try await APIClient.rejectDefect(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    defectId: defect.id,
                    rejectionNotes: notes,
                    token: currentToken
                )
                await MainActor.run {
                    rejectionNotes = ""
                    selectedDefect = nil
                    loadDefects()
                    onRefresh?()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to reject defect: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct DefectCardView: View {
    let defect: InspectionDefect
    let inspection: Inspection
    let onRectify: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    
    // Check if current user can rectify this defect - now visible to all users
    private var canRectify: Bool {
        return true
    }
    
    // Check if current user can approve/reject
    private var canApprove: Bool {
        guard let currentUserId = sessionManager.user?.id else { return false }
        
        // User has manage permissions
        if sessionManager.hasPermission("manage_project_inspections") {
            return true
        }
        
        // User is assigned to the inspection
        if let inspectionAssignedToId = inspection.assignedToId, inspectionAssignedToId == currentUserId {
            return true
        }
        
        return false
    }
    
    private var statusColor: Color {
        switch defect.status {
        case "OPEN":
            return .orange
        case "RECTIFIED":
            return .green
        case "APPROVED":
            return .blue
        case "REJECTED":
            return .red
        default:
            return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(defect.stageResult?.stage.name ?? "Unknown Stage")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(defect.displayStatus)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor)
                        .cornerRadius(6)
                }
                
                Spacer()
                
                // Action buttons
                if defect.status == "OPEN" && canRectify {
                    Button(action: onRectify) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.fill")
                            Text("Rectify")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black)
                        .cornerRadius(8)
                    }
                } else if defect.status == "RECTIFIED" && canApprove {
                    VStack(spacing: 8) {
                        Button(action: onApprove) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                Text("Accept")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                        
                        Button(action: onReject) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                Text("Reject")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            if let description = defect.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text("Inspection item \"\(defect.stageResult?.stage.name ?? "Unknown")\" failed")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let createdBy = defect.createdBy {
                    Text("Created by \(createdBy.displayName) on \(formatDate(defect.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let assignedTo = defect.assignedTo {
                    Text("Assigned to: \(assignedTo.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let rectifiedBy = defect.rectifiedBy, let rectifiedAt = defect.rectifiedAt {
                    Text("Rectified by \(rectifiedBy.displayName) on \(formatDate(rectifiedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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

