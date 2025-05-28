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
    
    init(documents: [Document], initialDocument: Document,projectName: String, isProjectOffline: Bool) {
        self.documents = documents
        self.projectName = projectName
        self.isProjectOffline = isProjectOffline
        _selectedIndex = State(initialValue: documents.firstIndex(where: { $0.id == initialDocument.id }) ?? 0)
    }
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(documents.indices, id: \.self) { index in
                DocumentViewer(
                    documents: documents,
                    documentIndex: $selectedIndex,
                    isProjectOffline: isProjectOffline
                )
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
