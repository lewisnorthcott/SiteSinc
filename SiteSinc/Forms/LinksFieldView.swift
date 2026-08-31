import SwiftUI

struct FormYesNoNAControl: View {
    @Binding var value: String

    private let options = ["Yes", "No", "N/A"]

    private var normalized: String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes": return "Yes"
        case "no": return "No"
        case "n/a", "na": return "N/A"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = normalized == option
                Button {
                    value = option
                } label: {
                    Text(option)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? BrandChrome.accent : BrandChrome.searchFieldFill)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FormHeadingView: View {
    let field: FormField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.system(size: BrandChrome.isMcPhillips ? 20 : 17, weight: .semibold, design: BrandChrome.displayDesign))
                .foregroundColor(BrandChrome.titleColor)
                .fixedSize(horizontal: false, vertical: true)
            if let description = field.description?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormLinksListView: View {
    let items: [FormLinkItem]
    var onRemove: ((FormLinkItem) -> Void)?

    var body: some View {
        if items.isEmpty {
            Text("No linked records")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 8) {
                ForEach(items, id: \.itemKey) { item in
                    FormLinkChip(item: item, onRemove: onRemove.map { handler in
                        { handler(item) }
                    })
                }
            }
        }
    }
}

struct FormLinkChip: View {
    let item: FormLinkItem
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(BrandChrome.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayLabel)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.typeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.displayLabel)")
            }
        }
        .padding(10)
        .background(BrandChrome.secondaryCardBackground)
        .cornerRadius(8)
    }
}

struct LinksFieldView: View {
    let field: FormField
    let projectId: Int
    let token: String
    var isDisabled: Bool = false
    @Binding var jsonValue: String

    @State private var showingPicker = false

    private var items: [FormLinkItem] {
        FormLinkItem.decodeArray(from: jsonValue)
    }

    private var typeSummary: String {
        field.resolvedLinkTypes
            .map { FormLinkItem.typeLabel(for: $0) }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = field.description?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Search and attach \(typeSummary.lowercased()).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FormLinksListView(items: items, onRemove: isDisabled ? nil : remove)

            if !isDisabled {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add link", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showingPicker) {
            LinksPickerSheet(
                projectId: projectId,
                token: token,
                allowedTypes: field.resolvedLinkTypes,
                selectedKeys: Set(items.map(\.itemKey)),
                onSelect: add
            )
        }
    }

    private func add(_ result: ProjectEntitySearchResult) {
        var next = items
        let item = FormLinkItem(from: result)
        guard !next.contains(where: { $0.itemKey == item.itemKey }) else { return }
        next.append(item)
        jsonValue = FormLinkItem.encodeArray(next)
    }

    private func remove(_ item: FormLinkItem) {
        jsonValue = FormLinkItem.encodeArray(items.filter { $0.itemKey != item.itemKey })
    }
}

private struct LinksPickerSheet: View {
    let projectId: Int
    let token: String
    let allowedTypes: [String]
    let selectedKeys: Set<String>
    let onSelect: (ProjectEntitySearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ProjectEntitySearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            Group {
                if isLoading && results.isEmpty {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await search(query) }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No matching records",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or leave the field empty to browse recent records.")
                    )
                } else {
                    List(results, id: \.itemKey) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.displayText.isEmpty ? result.title : result.displayText)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(FormLinkItem.typeLabel(for: result.entityType))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedKeys.contains(result.itemKey) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(BrandChrome.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(selectedKeys.contains(result.itemKey))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search project records")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task { await search(query) }
            }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await search(newValue)
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private func search(_ text: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let rows = try await APIClient.searchProjectEntities(
                projectId: projectId,
                query: text,
                types: allowedTypes,
                token: token
            )
            let allowed = Set(allowedTypes.map { $0.uppercased() })
            let filtered = rows.filter { allowed.contains($0.entityType.uppercased()) }
            await MainActor.run {
                results = filtered
                isLoading = false
            }
        } catch {
            await MainActor.run {
                results = []
                isLoading = false
                errorMessage = "Couldn't search project records. Check your connection and try again."
            }
        }
    }
}
