// Models.swift
import SwiftUI

struct SelectedDrawing: Identifiable {
    let id = UUID()
    let drawingId: Int
    let revisionId: Int
    let number: String
    let revisionNumber: String
}

struct MultiSelectPicker: View {
    let items: [User]
    @Binding var selectedIds: [Int]
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Button(action: {
                        if selectedIds.contains(item.id) {
                            selectedIds.removeAll { $0 == item.id }
                        } else {
                            selectedIds.append(item.id)
                        }
                    }) {
                        HStack {
                            Text("\(item.firstName ?? "") \(item.lastName ?? "")")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedIds.contains(item.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .frame(maxHeight: 150)
    }
}

struct DrawingPickerView: View {
    let drawings: [Drawing]
    @Binding var selectedDrawings: [SelectedDrawing]
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(drawings, id: \.id) { drawing in
                    if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                        Button(action: {
                            if selectedDrawings.contains(where: { $0.drawingId == drawing.id }) {
                                selectedDrawings.removeAll { $0.drawingId == drawing.id }
                            } else {
                                selectedDrawings.append(SelectedDrawing(
                                    drawingId: drawing.id,
                                    revisionId: latestRevision.id,
                                    number: drawing.number,
                                    revisionNumber: latestRevision.revisionNumber ?? "N/A"
                                ))
                            }
                        }) {
                            HStack {
                                Text("\(drawing.number) - \(drawing.title)")
                                Spacer()
                                if selectedDrawings.contains(where: { $0.drawingId == drawing.id }) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Drawings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
