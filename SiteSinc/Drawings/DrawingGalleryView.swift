import SwiftUI

struct DrawingGalleryView: View {
    let drawings: [Drawing]
    let isProjectOffline: Bool
    @State private var selectedIndex: Int
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager

    init(drawings: [Drawing], initialDrawing: Drawing, isProjectOffline: Bool) {
        self.drawings = drawings
        self.isProjectOffline = isProjectOffline
        _selectedIndex = State(initialValue: drawings.firstIndex(where: { $0.id == initialDrawing.id }) ?? 0)
    }

    private var currentDrawing: Drawing {
        guard selectedIndex >= 0, selectedIndex < drawings.count else {
            return drawings[0]
        }
        return drawings[selectedIndex]
    }

    var body: some View {
        // Intentionally NOT wrapping DrawingViewer in a TabView / PageTabViewStyle.
        // The outer page-swipe gesture previously caused two problems:
        //   1. Multiple DrawingViewer instances were alive simultaneously, which
        //      merged their toolbars and produced duplicate Share / Info buttons.
        //   2. The page gesture did not know about the markup UI inside
        //      PDFMarkupViewer, so tapping buttons in the markup selection
        //      action bar (e.g. Delete) with the slightest horizontal drift was
        //      interpreted as a page swipe and flipped to another drawing.
        // DrawingContentView already handles edge-swipe navigation between
        // drawings and guards it with `isMarkupUIActive`, so a single viewer is
        // all we need here.
        DrawingViewer(
            drawings: drawings,
            drawingIndex: $selectedIndex,
            isProjectOffline: isProjectOffline
        )
        .environmentObject(sessionManager)
        .environmentObject(networkStatusManager)
        .navigationTitle(currentDrawing.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
