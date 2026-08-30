import SwiftUI
import UserNotifications

struct NotificationItem: Identifiable, Codable {
    let id: String
    let title: String
    let body: String
    let timestamp: Date
    let type: String
    let userInfo: [String: String]
    var isRead: Bool
    
    init(from notification: UNNotification) {
        self.id = notification.request.identifier
        self.title = notification.request.content.title
        self.body = notification.request.content.body
        self.timestamp = notification.date
        self.type = notification.request.content.userInfo["type"] as? String ?? "general"
        // Fix the type conversion by properly handling AnyHashable keys and converting Int values to String
        self.userInfo = Dictionary(uniqueKeysWithValues: notification.request.content.userInfo.compactMap { key, value in
            guard let stringKey = key as? String else { return nil }
            // Convert value to String, handling Int, String, and other types
            let stringValue: String
            if let intValue = value as? Int {
                stringValue = String(intValue)
            } else if let strValue = value as? String {
                stringValue = strValue
            } else {
                // Fallback: convert to string representation
                stringValue = "\(value)"
            }
            return (stringKey, stringValue)
        })
        self.isRead = false
    }
}

class NotificationCenterViewModel: ObservableObject {
    @Published var notifications: [NotificationItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: NotificationFilter = .all
    
    private let notificationManager = NotificationManager.shared
    
    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case drawings = "Drawings"
        case projects = "Projects"
        case forms = "Forms"
        case rfi = "RFI"
        case requisitions = "Requisitions"
        
        var icon: String {
            switch self {
            case .all: return "bell"
            case .drawings: return "doc.text"
            case .projects: return "folder"
            case .forms: return "list.clipboard"
            case .rfi: return "message"
            case .requisitions: return "cart"
            }
        }
    }
    
    var filteredNotifications: [NotificationItem] {
        switch selectedFilter {
        case .all:
            return notifications
        case .drawings:
            return notifications.filter { 
                $0.type == "drawing_upload" || 
                $0.type == "drawing" || 
                $0.type == "drawing_update" ||
                $0.type == "document_upload" ||
                $0.type == "document" ||
                $0.type == "document_update"
            }
        case .projects:
            return notifications.filter { $0.type == "project_update" }
        case .forms:
            return notifications.filter { $0.type == "form" }
        case .rfi:
            return notifications.filter { 
                $0.type == "rfi" || 
                $0.type == "rfi_update" ||
                $0.type == "rfi_reminder"
            }
        case .requisitions:
            return notifications.filter { 
                $0.type == "material_requisition" || 
                $0.type == "requisition" ||
                $0.type == "material_requisition_update"
            }
        }
    }
    
    func loadNotifications() {
        isLoading = true
        errorMessage = nil
        
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            DispatchQueue.main.async {
                self?.notifications = notifications.map { NotificationItem(from: $0) }
                    .sorted { $0.timestamp > $1.timestamp }
                self?.isLoading = false
                // Update badge count after loading notifications
                self?.notificationManager.updateBadgeCount()
            }
        }
    }
    
    func markAsRead(_ notification: NotificationItem) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }
    
    func deleteNotification(_ notification: NotificationItem) {
        // Remove from delivered notifications
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notification.id])
        
        // Remove from local array
        notifications.removeAll { $0.id == notification.id }
        
        // Update badge count
        notificationManager.updateBadgeCount()
    }
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        notifications.removeAll()
        clearBadge()
    }
    
    func clearBadge() {
        notificationManager.clearBadgeCount()
    }
    
    func handleNotificationTap(_ notification: NotificationItem, dismissHandler: @escaping () -> Void) {
        markAsRead(notification)
        clearBadge()
        
        // Dismiss the notification center first, then navigate
        dismissHandler()
        
        // Small delay to ensure sheet is dismissed before navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Handle navigation based on notification type
            // Helper function to extract Int from Any (handles both Int and String)
            func extractInt(from value: Any?) -> Int? {
                if let intValue = value as? Int {
                    return intValue
                } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                    return intValue
                }
                return nil
            }
            
            switch notification.type {
            case "drawing_upload", "drawing", "drawing_update":
                // Try to navigate to specific drawing using drawingId and projectId first
                if let drawingId = extractInt(from: notification.userInfo["drawingId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingId": drawingId]
                    )
                } else if let drawingNumber = notification.userInfo["drawingNumber"],
                          let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingNumber": drawingNumber]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Backend sends drawing_update - navigate to drawings list
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawings"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "document_upload", "document", "document_update":
                // Navigate to specific document
                if let documentId = extractInt(from: notification.userInfo["documentId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocument"),
                        object: nil,
                        userInfo: ["projectId": projectId, "documentId": documentId]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Backend sends document_update - navigate to documents list
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocuments"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "rfi_update", "rfi":
                // Navigate to specific RFI
                if let rfiId = extractInt(from: notification.userInfo["rfiId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiId": rfiId]
                    )
                } else if let rfiNumber = notification.userInfo["rfiNumber"],
                          let projectId = extractInt(from: notification.userInfo["projectId"]),
                          let rfiNumberInt = Int(rfiNumber) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiNumber": rfiNumberInt]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Navigate to RFI list if no specific RFI ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFIs"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "material_requisition_update", "material_requisition", "requisition":
                // Navigate to specific Requisition
                if let requisitionId = extractInt(from: notification.userInfo["requisitionId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRequisition"),
                        object: nil,
                        userInfo: ["projectId": projectId, "requisitionId": requisitionId]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Navigate to requisitions list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRequisitions"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "log_update", "log":
                // Navigate to specific log
                if let logId = extractInt(from: notification.userInfo["logId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToLog"),
                        object: nil,
                        userInfo: ["projectId": projectId, "logId": logId]
                    )
                } else if let logNumber = notification.userInfo["logNumber"],
                          let projectId = extractInt(from: notification.userInfo["projectId"]),
                          let logNumberInt = Int(logNumber) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToLog"),
                        object: nil,
                        userInfo: ["projectId": projectId, "logNumber": logNumberInt]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Navigate to logs list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToLogs"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "permit":
                if let permitId = extractInt(from: notification.userInfo["permitId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToPermit"),
                        object: nil,
                        userInfo: ["projectId": projectId, "permitId": permitId]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToPermit"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "snag_update", "snag":
                // Navigate to specific snag
                if let snagId = extractInt(from: notification.userInfo["snagId"]),
                   let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToSnag"),
                        object: nil,
                        userInfo: ["projectId": projectId, "snagId": snagId]
                    )
                } else if let projectId = extractInt(from: notification.userInfo["projectId"]) {
                    // Navigate to snags list if no specific ID
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToSnags"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }
            case "project_update":
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToProject"),
                    object: nil,
                    userInfo: notification.userInfo
                )
            default:
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToDrawings"),
                    object: nil,
                    userInfo: notification.userInfo
                )
            }
        }
    }
}

struct NotificationCenterView: View {
    @StateObject private var viewModel = NotificationCenterViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(NotificationCenterViewModel.NotificationFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                viewModel.selectedFilter = filter
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: filter.icon)
                                        .font(.caption)
                                    Text(filter.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedFilter == filter ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(viewModel.selectedFilter == filter ? .white : .primary)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                
                if viewModel.isLoading {
                    ProgressView("Loading notifications...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredNotifications.isEmpty {
                    emptyStateView
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.notifications.isEmpty {
                        Button("Clear All") {
                            viewModel.clearAllNotifications()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadNotifications()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("You're all caught up! No new notifications to show.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notificationList: some View {
        List {
            ForEach(viewModel.filteredNotifications) { notification in
                NotificationRowView(notification: notification) {
                    viewModel.handleNotificationTap(notification) {
                        dismiss()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteNotification(notification)
                    }
                    
                    if !notification.isRead {
                        Button("Mark Read") {
                            viewModel.markAsRead(notification)
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            viewModel.loadNotifications()
        }
    }
}

struct NotificationRowView: View {
    let notification: NotificationItem
    let onTap: () -> Void
    
    private var displayBody: String {
        let bodyText = notification.body
        if let projectName = notification.userInfo["projectName"], !bodyText.contains(projectName) {
            return "\(bodyText) - \(projectName)"
        }
        return bodyText
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Notification icon
                Image(systemName: iconForType(notification.type))
                    .font(.title2)
                    .foregroundColor(colorForType(notification.type))
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(displayBody)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                    
                    Text(timeAgoString(from: notification.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForType(_ type: String) -> String {
        switch type {
        case "drawing_upload", "drawing", "drawing_update":
            return "doc.text"
        case "document_upload", "document", "document_update":
            return "doc.fill"
        case "project_update":
            return "folder"
        case "rfi", "rfi_update", "rfi_reminder":
            return "message"
        case "form":
            return "list.clipboard"
        case "material_requisition", "requisition", "material_requisition_update":
            return "cart"
        case "log_update", "log":
            return "book"
        case "snag_update", "snag":
            return "exclamationmark.triangle"
        default:
            return "bell"
        }
    }
    
    private func colorForType(_ type: String) -> Color {
        switch type {
        case "drawing_upload":
            return .blue
        case "project_update":
            return .green
        case "rfi":
            return .orange
        case "form":
            return .purple
        case "material_requisition", "requisition":
            return .green
        default:
            return .gray
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NotificationCenterView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationCenterView()
    }
} 