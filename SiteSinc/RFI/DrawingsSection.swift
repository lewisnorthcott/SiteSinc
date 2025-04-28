import SwiftUI

struct DrawingsSection: View {
    @Binding var selectedDrawings: [SelectedDrawing]
    @Binding var showDrawingPicker: Bool
    let isLoading: Bool
    
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
                                        selectedDrawings.removeAll { $0.drawingId == drawing.drawingId }
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
