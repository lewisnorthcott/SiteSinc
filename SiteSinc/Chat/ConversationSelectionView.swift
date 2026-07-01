import SwiftUI

/// Conversation history sheet — mirrors the web app's slide-out "Conversations"
/// panel (purple accent for the active row, swipe-to-archive instead of a
/// hover trash icon).
struct ConversationSelectionView: View {
    let projectName: String
    let conversations: [ChatConversation]
    let isLoading: Bool
    let currentConversationId: Int?
    let onSelect: (ChatConversation?) -> Void
    let onArchive: (ChatConversation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if conversations.isEmpty {
                    emptyStateView
                } else {
                    conversationsListView
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        startNewConversation()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(ChatTheme.purple)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text("Loading conversations...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ChatBrandAvatar(size: 56, showOnlineDot: false)

            VStack(spacing: 8) {
                Text("No Previous Chats")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start a new conversation to begin chatting with AI about \(projectName).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(action: startNewConversation) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Start Your First Chat")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(ChatTheme.brandGradient)
                .clipShape(Capsule())
                .shadow(color: ChatTheme.purple.opacity(0.3), radius: 10, x: 0, y: 4)
            }

            Spacer()
        }
    }

    // MARK: - List

    private var conversationsListView: some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    openConversation(conversation)
                } label: {
                    ConversationRowView(
                        conversation: conversation,
                        isActive: conversation.id == currentConversationId
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onArchive(conversation)
                    } label: {
                        Label("Archive", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func startNewConversation() {
        onSelect(nil)
        dismiss()
    }

    private func openConversation(_ conversation: ChatConversation) {
        onSelect(conversation)
        dismiss()
    }
}

// MARK: - Conversation Row

private struct ConversationRowView: View {
    let conversation: ChatConversation
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? ChatTheme.purple.opacity(0.12) : Color(.systemGray6))
                    .frame(width: 36, height: 36)
                Image(systemName: "message.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? ChatTheme.purple : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title ?? "New Conversation")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(formatDate(conversation.updatedAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isActive ? ChatTheme.purple.opacity(0.06) : Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ConversationSelectionView(
        projectName: "Sample Project",
        conversations: [],
        isLoading: false,
        currentConversationId: nil,
        onSelect: { _ in },
        onArchive: { _ in }
    )
}
