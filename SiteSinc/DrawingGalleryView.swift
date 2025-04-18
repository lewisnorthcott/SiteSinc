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
                DrawingViewer(drawing: drawings[index])
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        // Swipe left: next drawing
                        if selectedIndex < drawings.count - 1 {
                            selectedIndex += 1
                        }
                    } else if value.translation.width > 50 {
                        // Swipe right: previous drawing
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                    }
                }
        )
    }
}
