import SwiftUI

struct ProjectChatView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let initialConversation: ChatConversation?
    
    @State private var messages: [ChatMessage] = []
    @State private var currentConversation: ChatConversation?
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showingConversationSelection: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    // Convenience initializer for new conversations
    init(projectId: Int, token: String, projectName: String) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.initialConversation = nil
    }
    
    // Initializer for existing conversations
    init(projectId: Int, token: String, projectName: String, conversation: ChatConversation) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.initialConversation = conversation
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Experimental Feature Warning
                warningBanner
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    MessageBubble(message: message, projectId: projectId, token: token)
                        .id(message.id)
                }
                            
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AI is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .id("loading")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if isLoading {
                                proxy.scrollTo("loading", anchor: .bottom)
                            } else if let lastMessage = messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { _, _ in
                        if isLoading {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                inputArea
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Chats") {
                            showingConversationSelection = true
                        }
                        
                        if currentConversation != nil {
                            Button("Archive") {
                                archiveConversation()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .onAppear {
            if let conversation = initialConversation {
                loadExistingConversation(conversation)
            } else {
                createNewConversation()
            }
        }
        .sheet(isPresented: $showingConversationSelection) {
            ConversationSelectionView(
                projectId: projectId, 
                token: token, 
                projectName: projectName,
                onConversationSelected: { selectedConversation in
                    if let conversation = selectedConversation {
                        loadExistingConversation(conversation)
                    } else {
                        createNewConversation()
                    }
                }
            )
            .environmentObject(sessionManager)
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
    
    // MARK: - Warning Banner
    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Experimental Feature")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                Text("This AI chat feature is experimental and may not always provide accurate responses.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("Note: AI only has access to data uploaded after 20 October 2025.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Ask about your project...", text: $inputText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...4)
                    .disabled(isLoading)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        .font(.system(size: 18))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Message Bubble
    private struct MessageBubble: View {
        let message: ChatMessage
        let projectId: Int
        let token: String
        
        var body: some View {
            HStack {
                if message.role == "user" {
                    Spacer(minLength: 50)
                }
                
                VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
                    // Message Content
                    Text(parseMarkdown(cleanMessageContent(message.content)))
                        .font(.system(size: 16))
                        .foregroundColor(message.role == "user" ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(message.role == "user" ? Color.blue : Color(.systemGray5))
                        )
                        .textSelection(.enabled)
                        .onAppear {
                            if message.role == "assistant" {
                                print("🔍 [Chat] Displaying assistant message with \(message.content.count) characters")
                                print("🔍 [Chat] Message content: \(message.content)")
                            }
                        }
                    
                    // Sources (only for assistant messages)
                    if message.role == "assistant", let sources = message.metadata?.sources, !sources.isEmpty {
                        sourcesView(sources: sources)
                    }
                    
                    // Timestamp
                    Text(formatTimestamp(message.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                
                if message.role == "assistant" {
                    Spacer(minLength: 50)
                }
            }
        }
        
        @ViewBuilder
        private func sourcesView(sources: [SimpleChatSource]) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 4) {
                    ForEach(sources) { source in
                        SimpleSourceChip(source: source, projectId: projectId, token: token)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        
        private func formatTimestamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        private func parseMarkdown(_ text: String) -> AttributedString {
            do {
                let attributedString = try AttributedString(markdown: text)
                return attributedString
            } catch {
                print("❌ [Chat] Markdown parsing error: \(error)")
                return AttributedString(text)
            }
        }
        
        private func cleanMessageContent(_ content: String) -> String {
            // Remove source references from the message content
            // Pattern: "Sources: [Source X] (description); [Source Y] (description)"
            let sourcePattern = #"Sources:\s*(\[Source\s+\d+\][^;]*;?\s*)*"#
            let regex = try? NSRegularExpression(pattern: sourcePattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: content.utf16.count)
            let cleanedContent = regex?.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "") ?? content
            
            return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    // MARK: - Source Chip
    private struct SourceChip: View {
        let source: ChatSource
        let projectId: Int
        let token: String
        
        var body: some View {
            NavigationLink(destination: destinationView) {
                HStack(spacing: 4) {
                    Image(systemName: iconForSourceType(source.sourceType))
                        .font(.caption)
                    
                    Text(source.title)
                        .font(.caption)
                        .lineLimit(1)
                    
                    if let similarity = source.similarity {
                        Text("\(Int(similarity * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        @ViewBuilder
        private var destinationView: some View {
            switch source.sourceType {
            case "drawing":
                DrawingDetailView(
                    projectId: projectId,
                    token: token,
                    drawingId: source.sourceId,
                    drawingTitle: source.title
                )
            case "document":
                DocumentListView(
                    projectId: projectId,
                    token: token,
                    projectName: ""
                )
            case "rfi":
                // Navigate to RFI detail view
                Text("RFI Details")
                    .navigationTitle("RFI \(source.sourceId)")
            case "log":
                // Navigate to log detail view
                Text("Log Details")
                    .navigationTitle("Log \(source.sourceId)")
            default:
                Text("Unknown Source Type")
                    .navigationTitle(source.title)
            }
        }
        
        private func openSource(_ source: ChatSource) {
            print("🔍 [Chat] Opening source: \(source.title) (Type: \(source.sourceType), ID: \(source.sourceId))")
        }
        
        private func iconForSourceType(_ sourceType: String) -> String {
            switch sourceType {
            case "drawing":
                return "doc.text.fill"
            case "document":
                return "doc.fill"
            case "rfi":
                return "questionmark.circle.fill"
            case "form":
                return "list.clipboard.fill"
            default:
                return "doc.fill"
            }
        }
    }
    
    // MARK: - Simple Source Chip
    private struct SimpleSourceChip: View {
        let source: SimpleChatSource
        let projectId: Int
        let token: String
        
        var body: some View {
            NavigationLink(destination: destinationView) {
                HStack(spacing: 4) {
                    Image(systemName: iconForSourceType(source.sourceType))
                        .font(.caption)
                    
                    Text(source.title)
                        .font(.caption)
                        .lineLimit(1)
                    
                    if let similarity = source.similarity {
                        Text("\(Int(similarity * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        @ViewBuilder
        private var destinationView: some View {
            switch source.sourceType {
            case "drawing":
                DrawingDetailView(
                    projectId: projectId,
                    token: token,
                    drawingId: source.sourceId,
                    drawingTitle: source.title
                )
            case "document":
                DocumentListView(
                    projectId: projectId,
                    token: token,
                    projectName: ""
                )
            case "rfi":
                // Navigate to RFI detail view
                Text("RFI Details")
                    .navigationTitle("RFI \(source.sourceId)")
            case "log":
                // Navigate to log detail view
                Text("Log Details")
                    .navigationTitle("Log \(source.sourceId)")
            default:
                Text("Unknown Source Type")
                    .navigationTitle(source.title)
            }
        }
        
        private func openSource(_ source: SimpleChatSource) {
            print("🔍 [Chat] Opening source: \(source.title) (Type: \(source.sourceType), ID: \(source.sourceId))")
        }
        
        private func iconForSourceType(_ sourceType: String) -> String {
            switch sourceType {
            case "drawing":
                return "doc.text.fill"
            case "document":
                return "doc.fill"
            case "rfi":
                return "questionmark.circle.fill"
            case "form":
                return "list.clipboard.fill"
            default:
                return "doc.fill"
            }
        }
    }
    
    // MARK: - Drawing Detail View
    private struct DrawingDetailView: View {
        let projectId: Int
        let token: String
        let drawingId: Int
        let drawingTitle: String
        
        @State private var drawings: [Drawing] = []
        @State private var isLoading = true
        @State private var errorMessage: String?
        @EnvironmentObject var sessionManager: SessionManager
        @EnvironmentObject var networkStatusManager: NetworkStatusManager
        
        var body: some View {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading drawing...")
                            .foregroundColor(.secondary)
                    }
                } else if let errorMessage = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Error loading drawing")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let targetDrawing = drawings.first(where: { $0.id == drawingId }) {
                    DrawingGalleryView(
                        drawings: drawings,
                        initialDrawing: targetDrawing,
                        isProjectOffline: !networkStatusManager.isNetworkAvailable
                    )
                    .environmentObject(sessionManager)
                    .environmentObject(networkStatusManager)
                } else {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Drawing not found")
                            .font(.headline)
                        Text("The requested drawing could not be found.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle(drawingTitle)
            .onAppear {
                fetchDrawings()
            }
        }
        
        private func fetchDrawings() {
            Task {
                do {
                    let fetchedDrawings = try await APIClient.fetchDrawings(projectId: projectId, token: token)
                    await MainActor.run {
                        self.drawings = fetchedDrawings
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func createNewConversation() {
        print("🔍 [Chat] Starting createNewConversation for projectId: \(projectId)")
        
        Task {
            do {
                print("🔍 [Chat] Creating new conversation for project \(projectId)")
                // Always create a new conversation for a fresh start
                let newConversation = try await APIClient.createConversation(projectId: projectId, token: token, title: "Chat \(Date().formatted(date: .abbreviated, time: .shortened))")
                print("🔍 [Chat] Created new conversation: \(newConversation.id)")
                
                await MainActor.run {
                    self.currentConversation = newConversation
                    self.messages = []
                    print("🔍 [Chat] Updated UI with new conversation")
                }
            } catch {
                print("❌ [Chat] Error in createNewConversation: \(error)")
                print("❌ [Chat] Error type: \(type(of: error))")
                if let apiError = error as? APIError {
                    print("❌ [Chat] APIError case: \(apiError)")
                }
                
                await MainActor.run {
                    // If it's a token expired error, show a more user-friendly message
                    if case APIError.tokenExpired = error {
                        self.errorMessage = "Your session has expired. Please log in again."
                    } else if case APIError.invalidResponse(let statusCode) = error {
                        self.errorMessage = "Server error (HTTP \(statusCode)). Please try again."
                    } else if case APIError.decodingError(let decodingError) = error {
                        self.errorMessage = "Failed to parse server response. Please try again."
                        print("❌ [Chat] Decoding error details: \(decodingError)")
                    } else if case APIError.networkError(let networkError) = error {
                        self.errorMessage = "Network error. Please check your connection and try again."
                        print("❌ [Chat] Network error details: \(networkError)")
                    } else {
                        self.errorMessage = "Failed to load conversation: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func loadExistingConversation(_ conversation: ChatConversation) {
        print("🔍 [Chat] Loading existing conversation: \(conversation.id)")
        
        Task {
            do {
                currentConversation = conversation
                
                print("🔍 [Chat] Fetching messages for conversation \(conversation.id)")
                let conversationMessages = try await APIClient.fetchConversationMessages(conversationId: conversation.id, token: token)
                print("🔍 [Chat] Fetched \(conversationMessages.count) messages")
                
                await MainActor.run {
                    self.messages = conversationMessages
                    print("🔍 [Chat] Updated UI with \(self.messages.count) messages")
                }
            } catch {
                print("❌ [Chat] Error in loadExistingConversation: \(error)")
                print("❌ [Chat] Error type: \(type(of: error))")
                if let apiError = error as? APIError {
                    print("❌ [Chat] APIError case: \(apiError)")
                }
                
                await MainActor.run {
                    // If it's a token expired error, show a more user-friendly message
                    if case APIError.tokenExpired = error {
                        self.errorMessage = "Your session has expired. Please log in again."
                    } else if case APIError.invalidResponse(let statusCode) = error {
                        self.errorMessage = "Server error (HTTP \(statusCode)). Please try again."
                    } else if case APIError.decodingError(let decodingError) = error {
                        self.errorMessage = "Failed to parse server response. Please try again."
                        print("❌ [Chat] Decoding error details: \(decodingError)")
                    } else if case APIError.networkError(let networkError) = error {
                        self.errorMessage = "Network error. Please check your connection and try again."
                        print("❌ [Chat] Network error details: \(networkError)")
                    } else {
                        self.errorMessage = "Failed to load conversation: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, let conversation = currentConversation else { return }
        
        inputText = ""
        isLoading = true
        
        Task {
            do {
                print("🔍 [Chat] Sending message: \(messageText)")
                let response = try await APIClient.sendMessage(conversationId: conversation.id, message: messageText, token: token)
                print("🔍 [Chat] Successfully got response with \(response.sources.count) sources")
                
                await MainActor.run {
                    self.messages.append(response.message)
                    self.messages.append(response.response)
                    self.isLoading = false
                    print("🔍 [Chat] Updated UI with new messages")
                    print("🔍 [Chat] Assistant message content length: \(response.response.content.count)")
                    print("🔍 [Chat] Assistant message content preview: \(String(response.response.content.prefix(200)))...")
                }
            } catch {
                print("❌ [Chat] Error sending message: \(error)")
                print("❌ [Chat] Error type: \(type(of: error))")
                if let apiError = error as? APIError {
                    print("❌ [Chat] APIError case: \(apiError)")
                }
                
                await MainActor.run {
                    if case APIError.tokenExpired = error {
                        self.errorMessage = "Your session has expired. Please log in again."
                    } else if case APIError.invalidResponse(let statusCode) = error {
                        self.errorMessage = "Server error (HTTP \(statusCode)). Please try again."
                    } else if case APIError.decodingError(let decodingError) = error {
                        self.errorMessage = "Failed to parse server response. Please try again."
                        print("❌ [Chat] Decoding error details: \(decodingError)")
                    } else if case APIError.networkError(let networkError) = error {
                        self.errorMessage = "Network error. Please check your connection and try again."
                        print("❌ [Chat] Network error details: \(networkError)")
                    } else {
                        self.errorMessage = "Failed to send message: \(error.localizedDescription)"
                    }
                    self.isLoading = false
                }
            }
        }
    }
    
    private func archiveConversation() {
        guard let conversation = currentConversation else { return }
        
        Task {
            do {
                try await APIClient.archiveConversation(conversationId: conversation.id, token: token)
                
                await MainActor.run {
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to archive conversation: \(error.localizedDescription)"
                }
            }
        }
    }
    
}

#Preview {
    ProjectChatView(projectId: 1, token: "preview-token", projectName: "Sample Project")
        .environmentObject(SessionManager())
}
