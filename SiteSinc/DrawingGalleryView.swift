import SwiftUI

struct DrawingGalleryView: View {
    let drawings: [Drawing]  // All drawings in the group
    @State private var selectedIndex: Int  // Index of the currently selected drawing

    init(drawings: [Drawing], initialDrawing: Drawing) {
        self.drawings = drawings
        _selectedIndex = State(initialValue: drawings.firstIndex(where: { $0.id == initialDrawing.id }) ?? 0)
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(drawings.indices, id: \.self) { index in
                DrawingViewer(drawing: drawings[index])
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle())  // Enables swipe navigation
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))  // Shows page dots
        .navigationTitle(drawings[selectedIndex].title)  // Dynamic title based on current drawing
    }
}
