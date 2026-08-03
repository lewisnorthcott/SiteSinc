import SwiftUI

/// Example prompt shown in the empty-state pill row.
private struct ChatStarterPrompt: Identifiable {
    let id = UUID()
    let icon: String
    let category: String
    let text: String
}

private let sitesincStarterPrompts: [ChatStarterPrompt] = [
    ChatStarterPrompt(icon: "doc.text", category: "RFIs", text: "What's the status of all open RFIs?"),
    ChatStarterPrompt(icon: "photo.on.rectangle", category: "Drawings", text: "Show me the latest drawings uploaded to this project"),
    ChatStarterPrompt(icon: "doc.on.doc", category: "Documents", text: "Summarize recent document changes"),
    ChatStarterPrompt(icon: "questionmark.circle", category: "Help", text: "How do I create an RFI?"),
]

/// McPhillips — civil/site-led phrasing, mirrors `MCPHILLIPS_EXAMPLE_PROMPTS` on web.
private let mcphillipsStarterPrompts: [ChatStarterPrompt] = [
    ChatStarterPrompt(icon: "exclamationmark.triangle", category: "Observations", text: "Which site observations are still open from this week?"),
    ChatStarterPrompt(icon: "photo.on.rectangle", category: "Drawings", text: "Find the current setting-out drawings for the drainage works"),
    ChatStarterPrompt(icon: "doc.text", category: "RFIs", text: "Who still owes a response on RFIs raised against the temporary works?"),
    ChatStarterPrompt(icon: "chart.bar", category: "Briefing", text: "Prepare a short site brief ahead of tomorrow's progress meeting"),
    ChatStarterPrompt(icon: "doc.on.doc", category: "Documents", text: "What method statements were uploaded in the last fortnight?"),
    ChatStarterPrompt(icon: "hammer", category: "Permits", text: "Are there any live permits to dig on the southern compound?"),
]

private var starterPrompts: [ChatStarterPrompt] {
    ChatTheme.isEditorial ? mcphillipsStarterPrompts : sitesincStarterPrompts
}

private let demoQuestions: [String] = [
    "What's the status of all open RFIs?",
    "Show me the latest drawings from this project",
    "How do I upload a new drawing revision?",
    "Summarize recent document changes",
]

struct ProjectChatView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let initialConversation: ChatConversation?

    @State private var messages: [ChatMessage] = []
    @State private var currentConversation: ChatConversation?
    @State private var conversations: [ChatConversation] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var isLoadingConversations: Bool = false
    @State private var errorMessage: String?
    @State private var showingConversationSelection: Bool = false
    @State private var selectedCitation: ChatCitationRecord?
    @State private var typedTitle: String = ""
    @FocusState private var inputFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager

    init(projectId: Int, token: String, projectName: String) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.initialConversation = nil
    }

    init(projectId: Int, token: String, projectName: String, conversation: ChatConversation) {
        self.projectId = projectId
        self.token = token
        self.projectName = projectName
        self.initialConversation = conversation
    }

    private var isEmptyChat: Bool { messages.isEmpty }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var displayTitle: String {
        currentConversation?.title ?? AppBrand.current.assistantName
    }

    /// Placeholder id used for the assistant bubble while a reply is streaming in.
    private var streamingPlaceholderId: Int? {
        guard isLoading,
              let last = messages.last,
              last.role == "assistant",
              last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return last.id
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if !ChatTheme.isEditorial {
                    experimentalBanner
                }

                if isEmptyChat {
                    emptyState
                } else {
                    messagesScrollView
                }

                composer
            }
            .background(chatBackground)
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedCitation) { citation in
                citationDestinationView(citation)
            }
        }
        .onAppear {
            if let conversation = initialConversation {
                loadExistingConversation(conversation)
            } else {
                createNewConversation()
            }
            loadConversations()
        }
        .task(id: displayTitle) {
            await typewriterAnimateTitle()
        }
        .sheet(isPresented: $showingConversationSelection) {
            ConversationSelectionView(
                projectName: projectName,
                conversations: conversations,
                isLoading: isLoadingConversations,
                currentConversationId: currentConversation?.id,
                onSelect: { selected in
                    if let conversation = selected {
                        loadExistingConversation(conversation)
                    } else {
                        createNewConversation()
                    }
                },
                onArchive: { conversation in
                    archiveConversation(conversation)
                }
            )
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var chatBackground: some View {
        if ChatTheme.isEditorial {
            ChatTheme.Editorial.paper.ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(.systemGray6).opacity(0.4), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if ChatTheme.isEditorial {
            editorialHeader
        } else {
            standardHeader
        }
    }

    /// Editorial (McPhillips) header — mirrors the web's docked chat: burgundy
    /// accent strip, greeting eyebrow, serif "Ask the site." title, and
    /// text-only History/New actions.
    private var editorialHeader: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ChatTheme.Editorial.burgundy)
                .frame(height: 6)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editorialEyebrow)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(ChatTheme.Editorial.muted)
                        .lineLimit(1)

                    editorialTitle
                }

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    if !conversations.isEmpty {
                        Button("History") {
                            showingConversationSelection = true
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ChatTheme.Editorial.mutedDark)
                    }

                    Button("New") {
                        createNewConversation()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ChatTheme.Editorial.burgundy)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChatTheme.Editorial.mutedDark)
                    }
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .background(ChatTheme.Editorial.paper)
        .overlay(
            Rectangle().fill(ChatTheme.Editorial.border).frame(height: 1),
            alignment: .bottom
        )
    }

    private var editorialEyebrow: String {
        let name = sessionManager.user?.firstName.map { " · \($0)" } ?? ""
        return "\(greeting)\(name)".uppercased()
    }

    @ViewBuilder
    private var editorialTitle: some View {
        let serif = AppBrand.current.fonts.displayDesign
        if isEmptyChat {
            (
                Text("Ask the ").foregroundColor(ChatTheme.Editorial.ink)
                + Text("site.").foregroundColor(ChatTheme.Editorial.burgundy)
            )
            .font(.system(size: 24, weight: .regular, design: serif))
        } else {
            Text(currentConversation?.title ?? projectName)
                .font(.system(size: 24, weight: .regular, design: serif))
                .foregroundColor(ChatTheme.Editorial.ink)
                .lineLimit(1)
        }
    }

    private var standardHeader: some View {
        HStack(spacing: 12) {
            ChatBrandAvatar(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(typedTitle)
                        .font(.system(
                            size: AppBrand.current.features.editorialChat ? 17 : 15,
                            weight: .semibold,
                            design: AppBrand.current.features.editorialChat
                                ? AppBrand.current.fonts.displayDesign
                                : .default
                        ))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if typedTitle.count < displayTitle.count {
                        Text("|")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ChatTheme.purple)
                    }
                }
                Text(currentConversation != nil ? "AI-powered project insights" : "Start a conversation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                showingConversationSelection = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())

                    if !conversations.isEmpty {
                        Text("\(min(conversations.count, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(ChatTheme.purple)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }

            Button {
                createNewConversation()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Experimental Banner

    private var experimentalBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange)

            Text("Experimental — AI responses may not always be accurate. Only data from after Oct 20, 2025.")
                .font(.caption2)
                .foregroundColor(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if ChatTheme.isEditorial {
            editorialEmptyState
        } else {
            standardEmptyState
        }
    }

    /// Editorial empty state — hairline-separated starter prompt rows with
    /// uppercase burgundy category labels, matching the web's docked chat.
    private var editorialEmptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Start with")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundColor(ChatTheme.Editorial.muted)
                    .textCase(.uppercase)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    ForEach(starterPrompts) { prompt in
                        editorialPromptRow(prompt)
                    }
                }
                .overlay(
                    Rectangle().fill(ChatTheme.Editorial.hairline).frame(height: 1),
                    alignment: .bottom
                )

                Text("Responses are generated from project records and may be incomplete. Verify critical details before acting.")
                    .font(.system(size: 11))
                    .foregroundColor(ChatTheme.Editorial.mutedDark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
    }

    private func editorialPromptRow(_ prompt: ChatStarterPrompt) -> some View {
        Button {
            sendMessage(prompt.text)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(prompt.category.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(ChatTheme.Editorial.burgundy)
                    .frame(width: 96, alignment: .leading)
                    .padding(.top, 3)

                Text(prompt.text)
                    .font(.system(size: 14))
                    .foregroundColor(ChatTheme.Editorial.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ChatTheme.Editorial.placeholder)
                    .padding(.top, 2)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(
                Rectangle().fill(ChatTheme.Editorial.hairline).frame(height: 1),
                alignment: .top
            )
        }
        .buttonStyle(.plain)
    }

    private var standardEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 24)

                ChatBrandAvatar(size: 56, showOnlineDot: false)

                VStack(spacing: 4) {
                    Text("\(greeting)\(sessionManager.user?.firstName.map { ", \($0)" } ?? "")")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Ask anything about \(projectName)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                FlowLayout(spacing: 6) {
                    ForEach(starterPrompts) { prompt in
                        Button {
                            sendMessage(prompt.text)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: prompt.icon)
                                    .font(.system(size: 11))
                                Text(prompt.category)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator).opacity(0.4), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            projectId: projectId,
                            token: token,
                            isStreamingPlaceholder: message.id == streamingPlaceholderId,
                            onCitationTap: { selectedCitation = $0 }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Composer

    /// Single, persistent input bar pinned to the bottom of the screen (matches the
    /// web app's docked composer) — used for both the empty state and active chat.
    @ViewBuilder
    private var composer: some View {
        if ChatTheme.isEditorial {
            editorialComposer
        } else {
            standardComposer
        }
    }

    /// Editorial composer — "Your question" label, underline-style input, and a
    /// round burgundy send button, matching the web's McPhillips ChatComposer skin.
    private var editorialComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your question")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.4)
                .foregroundColor(ChatTheme.Editorial.burgundy)
                .textCase(.uppercase)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(spacing: 8) {
                    TextField("Drawings, RFIs, logs, documents…", text: $inputText, axis: .vertical)
                        .font(.system(size: 17))
                        .foregroundColor(ChatTheme.Editorial.ink)
                        .tint(ChatTheme.Editorial.burgundy)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .disabled(isLoading)

                    Rectangle()
                        .fill(inputFocused ? ChatTheme.Editorial.burgundy : ChatTheme.Editorial.underline)
                        .frame(height: 2)
                }

                editorialSendButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(ChatTheme.Editorial.paper)
        .overlay(
            Rectangle().fill(ChatTheme.Editorial.border).frame(height: 1),
            alignment: .top
        )
    }

    private var editorialSendButton: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !isLoading

        return Button {
            sendMessage()
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? ChatTheme.Editorial.burgundy : ChatTheme.Editorial.border)
                    .frame(width: 48, height: 48)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ChatTheme.Editorial.placeholder))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(canSend ? .white : ChatTheme.Editorial.placeholder)
                }
            }
        }
        .disabled(!canSend)
    }

    private var standardComposer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your project...", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .disabled(isLoading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ChatTheme.purple.opacity(0.2), lineWidth: 1.2)
                    )

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var sendButton: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !isLoading

        return Button {
            sendMessage()
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? ChatTheme.brandGradient : LinearGradient(colors: [Color(.systemGray4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .shadow(color: canSend ? ChatTheme.purple.opacity(0.35) : .clear, radius: 8, x: 0, y: 4)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(!canSend)
    }

    @ViewBuilder
    private func citationDestinationView(_ citation: ChatCitationRecord) -> some View {
        switch citation.sourceType {
        case "drawing", "drawing_live":
            CitationDrawingDetailView(
                projectId: projectId,
                token: token,
                drawingId: citation.sourceId,
                drawingTitle: citation.drawingNumber ?? citation.title ?? "Drawing"
            )
        case "document", "document_live":
            CitationDocumentDetailView(
                projectId: projectId,
                token: token,
                documentId: citation.sourceId,
                documentTitle: citation.documentNumber ?? citation.title ?? "Document"
            )
        case "rfi", "rfi_live":
            VStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.largeTitle)
                    .foregroundColor(ChatTheme.purple)
                Text(citation.rfiNumber.map { "RFI \($0)" } ?? "RFI Details")
                    .font(.headline)
            }
            .navigationTitle("RFI")
        default:
            VStack(spacing: 8) {
                Image(systemName: "doc")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(citation.title ?? "Source")
                    .font(.headline)
            }
            .navigationTitle("Source")
        }
    }

    // MARK: - Typewriter title

    private func typewriterAnimateTitle() async {
        typedTitle = ""
        let full = displayTitle
        for index in full.indices {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 30_000_000)
            typedTitle = String(full[full.startIndex...index])
        }
    }

    // MARK: - Networking

    private func loadConversations() {
        isLoadingConversations = true
        Task {
            do {
                let fetched = try await APIClient.fetchConversations(projectId: projectId, token: token, limit: 20)
                await MainActor.run {
                    self.conversations = fetched.sorted { $0.updatedAt > $1.updatedAt }
                    self.isLoadingConversations = false
                }
            } catch {
                await MainActor.run { self.isLoadingConversations = false }
            }
        }
    }

    private func createNewConversation() {
        currentConversation = nil
        messages = []
        inputText = ""
    }

    private func loadExistingConversation(_ conversation: ChatConversation) {
        Task {
            do {
                currentConversation = conversation
                let conversationMessages = try await APIClient.fetchConversationMessages(conversationId: conversation.id, token: token)
                await MainActor.run {
                    self.messages = conversationMessages
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = friendlyMessage(for: error)
                }
            }
        }
    }

    private func sendMessage(_ overrideText: String? = nil) {
        let messageText = (overrideText ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, !isLoading else { return }

        inputText = ""

        Task {
            do {
                let conversation: ChatConversation
                if let existing = currentConversation {
                    conversation = existing
                } else {
                    let created = try await APIClient.createConversation(projectId: projectId, token: token, title: nil)
                    conversation = created
                    await MainActor.run {
                        self.currentConversation = created
                        if !self.conversations.contains(where: { $0.id == created.id }) {
                            self.conversations.insert(created, at: 0)
                        }
                    }
                }
                await streamMessage(messageText, in: conversation)
            } catch {
                await MainActor.run {
                    self.errorMessage = friendlyMessage(for: error)
                }
            }
        }
    }

    @MainActor
    private func streamMessage(_ text: String, in conversation: ChatConversation) async {
        let now = Date()
        let baseId = Int(Date().timeIntervalSince1970 * 1000)
        let userMessage = ChatMessage(id: baseId, conversationId: conversation.id, role: "user", content: text, metadata: nil, createdAt: now)
        let placeholderId = baseId + 1
        let placeholder = ChatMessage(id: placeholderId, conversationId: conversation.id, role: "assistant", content: "", metadata: nil, createdAt: now)

        messages.append(userMessage)
        messages.append(placeholder)
        isLoading = true

        do {
            let done = try await APIClient.sendMessageStream(conversationId: conversation.id, message: text, token: token) { delta in
                if let idx = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                    let current = self.messages[idx]
                    self.messages[idx] = ChatMessage(
                        id: current.id,
                        conversationId: current.conversationId,
                        role: current.role,
                        content: current.content + delta,
                        metadata: current.metadata,
                        createdAt: current.createdAt
                    )
                }
            }

            if let userIdx = self.messages.firstIndex(where: { $0.id == baseId }) {
                self.messages[userIdx] = done.message ?? userMessage
            }
            if let assistantIdx = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                self.messages[assistantIdx] = done.response
            }
            if let title = done.conversationTitle, title != self.currentConversation?.title {
                updateConversationTitle(title)
            }
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = friendlyMessage(for: error)
            self.messages.removeAll { $0.id == placeholderId && $0.content.isEmpty }
        }
    }

    @MainActor
    private func updateConversationTitle(_ title: String) {
        guard let current = currentConversation else { return }
        currentConversation = ChatConversation(
            id: current.id,
            projectId: current.projectId,
            userId: current.userId,
            tenantId: current.tenantId,
            title: title,
            createdAt: current.createdAt,
            updatedAt: Date(),
            archived: current.archived
        )
        if let idx = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations[idx] = currentConversation!
        }
    }

    private func archiveConversation(_ conversation: ChatConversation) {
        Task {
            do {
                try await APIClient.archiveConversation(conversationId: conversation.id, token: token)
                await MainActor.run {
                    self.conversations.removeAll { $0.id == conversation.id }
                    if self.currentConversation?.id == conversation.id {
                        self.createNewConversation()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to archive conversation: \(error.localizedDescription)"
                }
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if case APIError.tokenExpired = error {
            return "Your session has expired. Please log in again."
        } else if case APIError.invalidResponse(let statusCode) = error {
            return "Server error (HTTP \(statusCode)). Please try again."
        } else if case APIError.decodingError = error {
            return "Failed to parse server response. Please try again."
        } else if case APIError.networkError = error {
            return "Network error. Please check your connection and try again."
        } else if case APIError.badRequest(let message) = error {
            return message
        }
        return "Something went wrong: \(error.localizedDescription)"
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage
    let projectId: Int
    let token: String
    let isStreamingPlaceholder: Bool
    let onCitationTap: (ChatCitationRecord) -> Void

    @State private var sourcesExpanded = false

    private var isUser: Bool { message.role == "user" }

    /// Sources deduplicated by the entity they point to (the API can return several
    /// chunks from the same drawing/document, which otherwise show up as repeat chips).
    private var uniqueSources: [SimpleChatSource] {
        guard let sources = message.metadata?.sources else { return [] }
        var seen = Set<String>()
        var result: [SimpleChatSource] = []
        for source in sources {
            let key = "\(source.sourceType)-\(source.sourceId)"
            if seen.insert(key).inserted {
                result.append(source)
            }
        }
        return result
    }

    var body: some View {
        if ChatTheme.isEditorial {
            editorialBody
        } else {
            standardBody
        }
    }

    /// Editorial (McPhillips) layout — user messages are flat burgundy blocks,
    /// assistant replies are plain full-width text beneath an uppercase
    /// assistant-name eyebrow (no avatars or bubbles), matching the web.
    private var editorialBody: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    Text(AppBrand.current.assistantName.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(ChatTheme.Editorial.burgundy)
                }

                if isUser {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(ChatTheme.Editorial.burgundy)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                } else if isStreamingPlaceholder {
                    ChatThinkingIndicator()
                } else {
                    citationAwareText
                        .textSelection(.enabled)
                }

                if !isUser, !isStreamingPlaceholder, !uniqueSources.isEmpty {
                    sourcesDisclosure(uniqueSources)
                }

                Text(formatTimestamp(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(ChatTheme.Editorial.mutedDark)
            }

            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var standardBody: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 36) }
            if !isUser { ChatBotAvatar() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                bubble
                if !isUser, !isStreamingPlaceholder, !uniqueSources.isEmpty {
                    sourcesDisclosure(uniqueSources)
                }
                Text(formatTimestamp(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 36) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if isUser {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(ChatTheme.brandGradient)
            } else if isStreamingPlaceholder {
                ChatThinkingIndicator()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
            } else {
                citationAwareText
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .textSelection(.enabled)
            }
        }
        .clipShape(ChatBubbleShape(flattenedCorner: isUser ? .bottomRight : .bottomLeft))
        .overlay(
            Group {
                if !isUser {
                    ChatBubbleShape(flattenedCorner: .bottomLeft)
                        .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
                }
            }
        )
        .shadow(color: isUser ? ChatTheme.purple.opacity(0.2) : .black.opacity(0.04), radius: isUser ? 6 : 3, x: 0, y: 2)
        .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
    }

    private var citationAwareText: some View {
        let attributed = ChatMarkdown.attributedString(from: message.content, citations: message.metadata?.citationsByNumber)
        return Text(attributed)
            .font(.system(size: 15))
            .foregroundColor(ChatTheme.isEditorial ? ChatTheme.Editorial.ink : .primary)
            .environment(\.openURL, OpenURLAction { url in
                if let number = ChatMarkdown.citationNumber(from: url),
                   let citation = message.metadata?.citationsByNumber?[number] {
                    onCitationTap(citation)
                    return .handled
                }
                return .systemAction
            })
    }

    /// Matches the web's collapsed "Evidence" card: hidden by default, capped list when expanded.
    private func sourcesDisclosure(_ sources: [SimpleChatSource]) -> some View {
        let capped = Array(sources.prefix(6))
        let remaining = sources.count - capped.count

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { sourcesExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(sources.count) source\(sources.count == 1 ? "" : "s") checked")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(sourcesExpanded ? 180 : 0))
                }
                .foregroundColor(ChatTheme.isEditorial ? ChatTheme.Editorial.mutedDark : .secondary)
            }
            .buttonStyle(.plain)

            if sourcesExpanded {
                FlowLayout(spacing: 6) {
                    ForEach(capped) { source in
                        Button {
                            let citation = ChatCitationRecord(
                                id: source.id,
                                sourceType: source.sourceType,
                                sourceId: source.sourceId,
                                title: source.title,
                                drawingNumber: source.drawingNumber,
                                documentNumber: source.documentNumber,
                                rfiNumber: source.rfiNumber,
                                area: nil
                            )
                            onCitationTap(citation)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: iconName(forSourceType: source.sourceType))
                                    .font(.system(size: 10))
                                Text(source.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .chatSourcePillStyle()
                        }
                        .buttonStyle(.plain)
                    }
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Citation Drawing Detail (reused destination for both source chips + inline citations)

private struct CitationDrawingDetailView: View {
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
            } else if let errorMessage {
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
            } else if let targetDrawing = drawings.first(where: { $0.id == drawingId || $0.number == drawingTitle }) {
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
        .onAppear { fetchDrawings() }
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

// MARK: - Citation Document Detail (opens the actual document viewer, not the document browser)

private struct CitationDocumentDetailView: View {
    let projectId: Int
    let token: String
    let documentId: Int
    let documentTitle: String

    @State private var documents: [Document] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading document...")
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error loading document")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let targetDocument = documents.first(where: { $0.id == documentId || $0.name == documentTitle }) {
                DocumentGalleryView(
                    documents: documents,
                    initialDocument: targetDocument,
                    projectName: documentTitle,
                    isProjectOffline: !networkStatusManager.isNetworkAvailable
                )
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager)
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Document not found")
                        .font(.headline)
                    Text("The requested document could not be found.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle(documentTitle)
        .onAppear { fetchDocuments() }
    }

    private func fetchDocuments() {
        Task {
            do {
                let fetchedDocuments = try await APIClient.fetchDocuments(projectId: projectId, token: token)
                await MainActor.run {
                    self.documents = fetchedDocuments
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

// MARK: - Flow Layout

/// Simple wrapping horizontal layout for pill chips (starter prompts, source chips).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, anchor: .topLeading, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    ProjectChatView(projectId: 1, token: "preview-token", projectName: "Sample Project")
        .environmentObject(SessionManager())
}
