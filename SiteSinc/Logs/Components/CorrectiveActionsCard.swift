import SwiftUI

struct CorrectiveActionsCard: View {
    let projectId: Int
    let logId: Int
    let token: String
    let actions: [LogAction]
    let canEdit: Bool
    let onRefresh: () -> Void

    @State private var showAddAction = false
    @State private var newTitle = ""
    @State private var newDescription = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Corrective actions")
                    .font(.headline)
                Spacer()
                if canEdit {
                    Button {
                        showAddAction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }

            if actions.isEmpty {
                Text("No corrective actions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(actions) { action in
                    actionRow(action)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showAddAction) {
            NavigationStack {
                Form {
                    TextField("Title", text: $newTitle)
                    TextField("Description (optional)", text: $newDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                .navigationTitle("New action")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddAction = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await createAction() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func actionRow(_ action: LogAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(!action.isOpen)
                if let desc = action.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Text(action.isOpen ? "Open" : "Done")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(action.isOpen ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(action.isOpen ? .orange : .green)
                        .cornerRadius(4)
                    if action.isOverdue {
                        Text("Overdue")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    if let assignee = action.assignee {
                        Text(assignee.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if canEdit {
                Button {
                    Task { await toggleAction(action) }
                } label: {
                    Image(systemName: action.isOpen ? "checkmark.circle" : "arrow.uturn.backward.circle")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func createAction() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await APIClient.createLogAction(
                projectId: projectId, logId: logId,
                title: newTitle.trimmingCharacters(in: .whitespaces),
                description: newDescription.isEmpty ? nil : newDescription,
                assigneeId: nil, dueDate: nil, token: token
            )
            await MainActor.run {
                showAddAction = false
                newTitle = ""
                newDescription = ""
                isSaving = false
                onRefresh()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func toggleAction(_ action: LogAction) async {
        do {
            _ = try await APIClient.updateLogAction(
                projectId: projectId, logId: logId, actionId: action.id,
                title: nil, description: nil, assigneeId: nil, dueDate: nil,
                status: action.isOpen ? "DONE" : "OPEN", token: token
            )
            await MainActor.run { onRefresh() }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
