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
        // Fix the type conversion by properly handling AnyHashable keys
        self.userInfo = Dictionary(uniqueKeysWithValues: notification.request.content.userInfo.compactMap { key, value in
            guard let stringKey = key as? String, let stringValue = value as? String else { return nil }
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
        
        var icon: String {
            switch self {
            case .all: return "bell"
            case .drawings: return "doc.text"
            case .projects: return "folder"
            case .forms: return "list.clipboard"
            case .rfi: return "message"
            }
        }
    }
    
    var filteredNotifications: [NotificationItem] {
        switch selectedFilter {
        case .all:
            return notifications
        case .drawings:
            return notifications.filter { $0.type == "drawing_upload" }
        case .projects:
            return notifications.filter { $0.type == "project_update" }
        case .forms:
            return notifications.filter { $0.type == "form" }
        case .rfi:
            return notifications.filter { $0.type == "rfi" }
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
            switch notification.type {
            case "drawing_upload", "drawing":
                // Try to navigate to specific drawing using drawingId and projectId first
                if let drawingIdStr = notification.userInfo["drawingId"],
                   let drawingId = Int(drawingIdStr),
                   let projectIdStr = notification.userInfo["projectId"],
                   let projectId = Int(projectIdStr) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingId": drawingId]
                    )
                } else if let drawingNumber = notification.userInfo["drawingNumber"],
                          let projectIdStr = notification.userInfo["projectId"],
                          let projectId = Int(projectIdStr) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["projectId": projectId, "drawingNumber": drawingNumber]
                    )
                } else if let drawingNumber = notification.userInfo["drawingNumber"] {
                    // Fallback to drawing number only
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDrawing"),
                        object: nil,
                        userInfo: ["drawingNumber": drawingNumber]
                    )
                }
            case "document_upload", "document":
                // Navigate to specific document
                if let documentIdStr = notification.userInfo["documentId"],
                   let documentId = Int(documentIdStr),
                   let projectIdStr = notification.userInfo["projectId"],
                   let projectId = Int(projectIdStr) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToDocument"),
                        object: nil,
                        userInfo: ["projectId": projectId, "documentId": documentId]
                    )
                }
            case "rfi":
                // Navigate to specific RFI
                if let rfiIdStr = notification.userInfo["rfiId"],
                   let rfiId = Int(rfiIdStr),
                   let projectIdStr = notification.userInfo["projectId"],
                   let projectId = Int(projectIdStr) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToRFI"),
                        object: nil,
                        userInfo: ["projectId": projectId, "rfiId": rfiId]
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
                    
                    Text(notification.body)
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
        case "drawing_upload":
            return "doc.text"
        case "project_update":
            return "folder"
        case "rfi":
            return "message"
        case "form":
            return "list.clipboard"
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