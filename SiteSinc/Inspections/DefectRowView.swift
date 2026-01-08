import SwiftUI

struct DefectRowView: View {
    let defect: InspectionDefect
    let inspection: Inspection
    let projectId: Int
    let token: String
    let onRefresh: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showRectifyView = false
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }
    
    // Check if current user can rectify this defect - now visible to all users
    private var canRectify: Bool {
        return true
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
                
                // Rectify button - only show if status is OPEN and user can rectify
                if defect.status == "OPEN" && canRectify {
                    Button(action: {
                        showRectifyView = true
                    }) {
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
            
            if let createdBy = defect.createdBy {
                Text("Created by \(createdBy.displayName) on \(formatDate(defect.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor, lineWidth: 2)
        )
        .sheet(isPresented: $showRectifyView) {
            RectifyDefectView(
                defect: defect,
                inspection: inspection,
                projectId: projectId,
                token: currentToken,
                onSuccess: {
                    onRefresh()
                    showRectifyView = false
                }
            )
            .environmentObject(sessionManager)
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

