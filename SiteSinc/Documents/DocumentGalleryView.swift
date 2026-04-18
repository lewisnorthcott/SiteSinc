//
//  DocumentGalleryView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI

struct DocumentGalleryView: View {
    let documents: [Document]
    let isProjectOffline: Bool
    let projectName: String
    @State private var selectedIndex: Int
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added
    
    init(documents: [Document], initialDocument: Document, projectName: String, isProjectOffline: Bool) {
        self.documents = documents
        self.projectName = projectName
        self.isProjectOffline = isProjectOffline
        _selectedIndex = State(initialValue: documents.firstIndex(where: { $0.id == initialDocument.id }) ?? 0)
    }
    
    var body: some View {
        // A single DocumentViewer handles swipe-paging between documents internally
        // via its drag gesture, so we no longer wrap it in a TabView. Having a TabView
        // here caused SwiftUI to instantiate multiple DocumentViewers whose toolbars
        // merged, resulting in duplicate Share / Info buttons appearing in the nav bar.
        DocumentViewer(
            documents: documents,
            documentIndex: $selectedIndex,
            isProjectOffline: isProjectOffline
        )
        .environmentObject(networkStatusManager)
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
