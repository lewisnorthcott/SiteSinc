import SwiftUI

struct ConversationSelectionView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let onConversationSelected: (ChatConversation?) -> Void
    
    @State private var conversations: [ChatConversation] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                if isLoading {
                    loadingView
                } else if conversations.isEmpty {
                    emptyStateView
                } else {
                    conversationsListView
                }
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadConversations()
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            // Project info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(projectName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Choose a conversation or start new")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // New conversation button
            Button(action: startNewConversation) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text("Start New Chat")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading conversations...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Previous Chats")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a new conversation to begin chatting with AI about your project.")
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
                .background(Color.blue)
                .cornerRadius(10)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Conversations List View
    private var conversationsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(conversations) { conversation in
                    ConversationRowView(conversation: conversation) {
                        openConversation(conversation)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helper Methods
    private func loadConversations() {
        print("🔍 [ConversationSelection] Loading conversations for project \(projectId)")
        
        Task {
            do {
                let fetchedConversations = try await APIClient.fetchConversations(projectId: projectId, token: token, limit: 20)
                
                await MainActor.run {
                    self.conversations = fetchedConversations.sorted { $0.updatedAt > $1.updatedAt }
                    self.isLoading = false
                    print("🔍 [ConversationSelection] Loaded \(self.conversations.count) conversations")
                }
            } catch {
                print("❌ [ConversationSelection] Error loading conversations: \(error)")
                
                await MainActor.run {
                    self.isLoading = false
                    if case APIError.tokenExpired = error {
                        self.errorMessage = "Your session has expired. Please log in again."
                    } else {
                        self.errorMessage = "Failed to load conversations: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func startNewConversation() {
        print("🔍 [ConversationSelection] Starting new conversation")
        onConversationSelected(nil)
        dismiss()
    }
    
    private func openConversation(_ conversation: ChatConversation) {
        print("🔍 [ConversationSelection] Opening conversation: \(conversation.id)")
        onConversationSelected(conversation)
        dismiss()
    }
}

// MARK: - Conversation Row View
struct ConversationRowView: View {
    let conversation: ChatConversation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title ?? "Untitled Chat")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(formatDate(conversation.updatedAt))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
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
        projectId: 1, 
        token: "preview-token", 
        projectName: "Sample Project",
        onConversationSelected: { _ in }
    )
}
