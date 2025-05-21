// Models.swift
import SwiftUI
import SwiftData
//struct SelectedDrawing: Identifiable {
//    let id = UUID()
//    let drawingId: Int
//    let revisionId: Int
//    let number: String
//    let revisionNumber: String
//}

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
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationView {
            List {
                ForEach(drawings, id: \.id) { drawing in
                    if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                        Button(action: {
                            if let existing = selectedDrawings.first(where: { $0.drawingId == drawing.id }) {
                                selectedDrawings.removeAll { $0.drawingId == drawing.id }
                                modelContext.delete(existing)
                            } else {
                                let newDrawing = SelectedDrawing(
                                    drawingId: drawing.id,
                                    revisionId: latestRevision.id,
                                    number: drawing.number,
                                    revisionNumber: latestRevision.revisionNumber ?? "N/A"
                                )
                                modelContext.insert(newDrawing)
                                selectedDrawings.append(newDrawing)
                            }
                            try? modelContext.save()
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

struct UploadedFileResponse: Decodable {
    let fileUrl: String
    let fileName: String
    let fileType: String
    let tenantId: Int
    
}

@Model
final class SelectedDrawing {
    @Attribute(.unique) var id: UUID
    var drawingId: Int
    var revisionId: Int
    var number: String
    var revisionNumber: String

    init(id: UUID = UUID(), drawingId: Int, revisionId: Int, number: String, revisionNumber: String) {
        self.id = id
        self.drawingId = drawingId
        self.revisionId = revisionId
        self.number = number
        self.revisionNumber = revisionNumber
    }
}

@Model
final class RFIDraft {
    @Attribute(.unique) var id: UUID = UUID()
    var projectId: Int
    var title: String
    var query: String
    var managerId: Int?
    var assignedUserIds: [Int]
    var returnDate: Date?
    var selectedFiles: [String]
    @Relationship(deleteRule: .cascade) var selectedDrawings: [SelectedDrawing]
    var createdAt: Date
    
    init(projectId: Int, title: String, query: String, managerId: Int?, assignedUserIds: [Int], returnDate: Date?, selectedFiles: [String], selectedDrawings: [SelectedDrawing] = [], createdAt: Date) {
        self.projectId = projectId
        self.title = title
        self.query = query
        self.managerId = managerId
        self.assignedUserIds = assignedUserIds
        self.returnDate = returnDate
        self.selectedFiles = selectedFiles
        self.selectedDrawings = selectedDrawings
        self.createdAt = createdAt
    }
}


