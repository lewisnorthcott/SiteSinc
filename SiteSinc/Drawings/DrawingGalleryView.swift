import SwiftUI

struct DrawingGalleryView: View {
    let drawings: [Drawing]
    @State private var selectedIndex: Int

    init(drawings: [Drawing], initialDrawing: Drawing) {
        self.drawings = drawings
        _selectedIndex = State(initialValue: drawings.firstIndex(where: { $0.id == initialDrawing.id }) ?? 0)
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(drawings.indices, id: \.self) { index in
                DrawingViewer(drawings: drawings, drawingIndex: $selectedIndex)
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
    }
}
