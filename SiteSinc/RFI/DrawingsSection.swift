import SwiftUI
import SwiftData

struct DrawingsSection: View {
    @Binding var selectedDrawings: [SelectedDrawing]
    @Binding var showDrawingPicker: Bool
    let isLoading: Bool
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link Drawings")
                .font(.subheadline)
                .foregroundColor(.gray)
            Button {
                showDrawingPicker = true
            } label: {
                HStack {
                    Text(selectedDrawings.isEmpty ? "Select drawings..." : "\(selectedDrawings.count) drawing\(selectedDrawings.count == 1 ? "" : "s") selected")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.primary)
            }
            .disabled(isLoading)
            if !selectedDrawings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.vertical) {
                        VStack(spacing: 8) {
                            ForEach(selectedDrawings) { drawing in
                                HStack {
                                    Text("\(drawing.number) - Rev \(drawing.revisionNumber)")
                                        .font(.caption)
                                    Spacer()
                                    Button {
                                        if let index = selectedDrawings.firstIndex(where: { $0.id == drawing.id }) {
                                            let drawingToRemove = selectedDrawings[index]
                                            selectedDrawings.remove(at: index)
                                            modelContext.delete(drawingToRemove)
                                            try? modelContext.save()
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
        }
    }
}
