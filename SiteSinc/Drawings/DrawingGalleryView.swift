import SwiftUI

struct DrawingGalleryView: View {
    let drawings: [Drawing]
    let isProjectOffline: Bool
    @State private var selectedIndex: Int
    @EnvironmentObject var sessionManager: SessionManager // Added
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added for debugging
    
    init(drawings: [Drawing], initialDrawing: Drawing, isProjectOffline: Bool) {
        self.drawings = drawings
        self.isProjectOffline = isProjectOffline
        _selectedIndex = State(initialValue: drawings.firstIndex(where: { $0.id == initialDrawing.id }) ?? 0)
    }
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(drawings.indices, id: \.self) { index in
                DrawingViewer(
                    drawings: drawings,
                    drawingIndex: $selectedIndex,
                    isProjectOffline: isProjectOffline
                )
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .onAppear {
            print("DrawingGalleryView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
        }
    }
}
