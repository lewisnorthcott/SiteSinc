// Placeholder if needed for future refactors; left intentionally minimal.

import SwiftUI

struct RFIRow: View {
    let unifiedRFI: UnifiedRFI
    
    private var title: String {
        return unifiedRFI.title ?? "Untitled"
    }
    
    private var number: Int {
        return unifiedRFI.number
    }
    
    private var status: String {
        return unifiedRFI.status?.capitalized ?? "Unknown"
    }
    
    private var createdAt: String {
        if let createdAtStr = unifiedRFI.createdAt, let date = ISO8601DateFormatter().date(from: createdAtStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return "Unknown"
    }
    
    private var dueDate: String? {
        if let dueDateStr = unifiedRFI.returnDate, let date = ISO8601DateFormatter().date(from: dueDateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return nil
    }
    
    private var assignedUsers: String {
        if let users = unifiedRFI.assignedUsers, !users.isEmpty {
            return users.map { "\($0.user.firstName) \($0.user.lastName)" }.joined(separator: ", ")
        }
        return "Unassigned"
    }
    
    private var statusColor: Color {
        switch unifiedRFI.status?.lowercased() {
        case "draft": return .gray
        case "submitted": return .blue
        case "in_review": return .orange
        case "responded": return .green
        case "closed": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("RFI #\(number)")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text(status)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.2))
                            .foregroundColor(statusColor)
                            .cornerRadius(4)
                    }
                    
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(createdAt)
                        .font(.caption)
                }
                
                Spacer()
                
                if let dueDate = dueDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Due")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dueDate)
                            .font(.caption)
                    }
                }
            }
            
                            HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assigned To")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(assignedUsers)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Show manager indicator if available
                                if unifiedRFI.managerId != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.caption2)
                            Text("Mgr")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                    
                    // Show attachment and drawing counts
                    HStack(spacing: 8) {
                        if let attachments = unifiedRFI.attachments, !attachments.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                Text("\(attachments.count)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if let drawings = unifiedRFI.drawings, !drawings.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.text")
                                    .font(.caption2)
                                Text("\(drawings.count)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        }
                    }
                }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

