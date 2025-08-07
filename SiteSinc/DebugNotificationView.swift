import SwiftUI

struct DebugNotificationView: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Debug Controls
                VStack(spacing: 12) {
                    Button("🧪 Test Notification Setup") {
                        notificationManager.testNotificationRegistration()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("🔄 Force Token Refresh") {
                        notificationManager.forceTokenRefresh()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("🔍 Debug Current Status") {
                        notificationManager.debugNotificationSetup()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("🗑️ Clear Messages") {
                        notificationManager.clearDebugMessages()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()
                
                Divider()
                
                // Debug Messages
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Debug Messages")
                            .font(.headline)
                        Spacer()
                        Text("\(notificationManager.debugMessages.count) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(notificationManager.debugMessages, id: \.self) { message in
                                Text(message)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Notification Debug")
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
}

#Preview {
    DebugNotificationView()
        .environmentObject(NotificationManager.shared)
} 