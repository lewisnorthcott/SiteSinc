import SwiftUI

struct ToolboxTalkStatusPill: View {
    let status: ToolboxTalkRollupStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(foreground)
            .background(background)
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch status.tone {
        case .success: return Color(red: 0.06, green: 0.4, blue: 0.28)
        case .info: return Color(red: 0.12, green: 0.35, blue: 0.65)
        case .warn: return Color(red: 0.55, green: 0.35, blue: 0.05)
        case .muted: return .secondary
        case .neutral: return .secondary
        }
    }

    private var background: Color {
        switch status.tone {
        case .success: return Color.green.opacity(0.12)
        case .info: return Color.blue.opacity(0.12)
        case .warn: return Color.orange.opacity(0.12)
        case .muted: return Color.gray.opacity(0.12)
        case .neutral: return Color(.systemBackground)
        }
    }

    private var border: Color {
        switch status.tone {
        case .success: return Color.green.opacity(0.35)
        case .info: return Color.blue.opacity(0.35)
        case .warn: return Color.orange.opacity(0.35)
        case .muted: return Color.gray.opacity(0.25)
        case .neutral: return Color.gray.opacity(0.25)
        }
    }
}

struct ToolboxTalkSessionStatusChip: View {
    let status: String

    var body: some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(foreground)
            .background(background)
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch status {
        case "COMPLETED": return Color(red: 0.06, green: 0.4, blue: 0.28)
        case "IN_PROGRESS": return Color(red: 0.12, green: 0.35, blue: 0.65)
        case "CANCELLED": return .secondary
        default: return Color(red: 0.55, green: 0.35, blue: 0.05)
        }
    }

    private var background: Color {
        switch status {
        case "COMPLETED": return Color.green.opacity(0.12)
        case "IN_PROGRESS": return Color.blue.opacity(0.12)
        case "CANCELLED": return Color.gray.opacity(0.08)
        default: return Color.orange.opacity(0.12)
        }
    }

    private var border: Color {
        switch status {
        case "COMPLETED": return Color.green.opacity(0.4)
        case "IN_PROGRESS": return Color.blue.opacity(0.4)
        case "CANCELLED": return Color.gray.opacity(0.25)
        default: return Color.orange.opacity(0.4)
        }
    }
}

struct ToolboxTalkContentEditor: View {
    @Binding var content: ToolboxTalkContent
    var readOnly: Bool = false
    var token: String

    @State private var showLibrary = false
    @State private var ppeDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topicsSection
            highRiskSection
            ppeSection
            declarationSection
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Topics")
                    .font(.headline)
                Spacer()
                if !readOnly {
                    Button {
                        showLibrary = true
                    } label: {
                        Label("Library", systemImage: "books.vertical")
                            .font(.subheadline)
                    }
                    Button {
                        var topics = content.topics ?? []
                        topics.append(ToolboxTalkTopic(title: "", body: ""))
                        content.topics = topics
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }

            let topics = content.topics ?? []
            if topics.isEmpty {
                Text("No topics yet.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                    VStack(alignment: .leading, spacing: 8) {
                        if readOnly {
                            Text(topic.title)
                                .font(.subheadline.weight(.semibold))
                            if let body = topic.body, !body.isEmpty {
                                Text(body)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            TextField("Topic title", text: bindingTopicTitle(at: index))
                                .textFieldStyle(.roundedBorder)
                            TextField("Details", text: bindingTopicBody(at: index), axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                var updated = content.topics ?? []
                                updated.remove(at: index)
                                content.topics = updated
                            } label: {
                                Label("Remove topic", systemImage: "trash")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            ToolboxTalkTopicLibraryPicker(token: token) { picked in
                addLibraryTopics(picked)
            }
        }
    }

    private var highRiskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("High-risk activities")
                .font(.headline)
            let selected = Set(content.highRiskActivities ?? [])
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(ToolboxTalkHighRiskActivity.allCases) { activity in
                    let isOn = selected.contains(activity.rawValue)
                    Button {
                        guard !readOnly else { return }
                        var next = Set(content.highRiskActivities ?? [])
                        if isOn {
                            next.remove(activity.rawValue)
                        } else {
                            next.insert(activity.rawValue)
                        }
                        content.highRiskActivities = Array(next).sorted()
                    } label: {
                        Text(activity.displayName)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(isOn ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                            .foregroundColor(isOn ? .accentColor : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .disabled(readOnly)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ppeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PPE")
                .font(.headline)
            let items = content.ppe ?? []
            if !items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 6) {
                            Text(item)
                                .font(.caption)
                            if !readOnly {
                                Button {
                                    content.ppe = (content.ppe ?? []).filter { $0 != item }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }
                }
            }
            if !readOnly {
                HStack {
                    TextField("Add PPE item", text: $ppeDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = ppeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        var next = content.ppe ?? []
                        if !next.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                            next.append(trimmed)
                            content.ppe = next
                        }
                        ppeDraft = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var declarationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Declaration")
                .font(.headline)
            if readOnly {
                Text(content.declarationText ?? "")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                TextField("Declaration text", text: Binding(
                    get: { content.declarationText ?? "" },
                    set: { content.declarationText = $0 }
                ), axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func bindingTopicTitle(at index: Int) -> Binding<String> {
        Binding(
            get: { content.topics?[safe: index]?.title ?? "" },
            set: { newValue in
                var topics = content.topics ?? []
                guard topics.indices.contains(index) else { return }
                topics[index].title = newValue
                content.topics = topics
            }
        )
    }

    private func bindingTopicBody(at index: Int) -> Binding<String> {
        Binding(
            get: { content.topics?[safe: index]?.body ?? "" },
            set: { newValue in
                var topics = content.topics ?? []
                guard topics.indices.contains(index) else { return }
                topics[index].body = newValue
                content.topics = topics
            }
        )
    }

    private func addLibraryTopics(_ picked: [ToolboxTalkTopicLibraryItem]) {
        var topics = content.topics ?? []
        let existing = Set(topics.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let newTopics = picked
            .filter { !existing.contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            .map { ToolboxTalkTopic(title: $0.title, body: $0.body ?? "") }
        topics.append(contentsOf: newTopics)
        content.topics = topics

        var highRisk = Set(content.highRiskActivities ?? [])
        for item in picked {
            item.defaultHighRiskActivities?.forEach { highRisk.insert($0) }
        }
        content.highRiskActivities = Array(highRisk).sorted()
    }
}

private struct ToolboxTalkTopicLibraryPicker: View {
    let token: String
    let onAdd: ([ToolboxTalkTopicLibraryItem]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var topics: [ToolboxTalkTopicLibraryItem] = []
    @State private var search = ""
    @State private var selected: Set<Int> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filtered: [ToolboxTalkTopicLibraryItem] {
        let q = search.lowercased()
        guard !q.isEmpty else { return topics }
        return topics.filter {
            "\($0.category ?? "") \($0.title) \($0.body ?? "")".lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading library...")
                } else if let errorMessage {
                    Text(errorMessage).foregroundColor(.secondary)
                } else {
                    List(filtered) { topic in
                        Button {
                            if selected.contains(topic.id) {
                                selected.remove(topic.id)
                            } else {
                                selected.insert(topic.id)
                            }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.title).font(.headline).foregroundColor(.primary)
                                    if let category = topic.category {
                                        Text(category).font(.caption).foregroundColor(.secondary)
                                    }
                                    if let body = topic.body, !body.isEmpty {
                                        Text(body).font(.caption).foregroundColor(.secondary).lineLimit(3)
                                    }
                                }
                                Spacer()
                                if selected.contains(topic.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search library...")
                }
            }
            .navigationTitle("Topic library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(topics.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            topics = try await APIClient.fetchToolboxTalkTopics(token: token)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
