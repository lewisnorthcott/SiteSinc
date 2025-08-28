//
//  FilteredDrawingsView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

//
//  FilteredDrawingsView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI

struct FilteredDocumentsView: View {
    let documents: [Document]
    let groupName: String
    let token: String
    let projectId: Int
    let projectName: String
    @Binding var isGridView: Bool
    let onRefresh: () -> Void
    let isProjectOffline: Bool
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    
    @State private var showCreateRFI = false
    @State private var searchText: String = "" // Add state for search text

    // Filter documents based on search text
    private var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents.sorted { (lhs, rhs) in
                let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? ""
                let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? ""
                return lhsDate > rhsDate
            }
        } else {
            return documents
                .filter {
                    $0.name.lowercased().contains(searchText.lowercased()) ||
                    String($0.id).contains(searchText.lowercased())
                }
                .sorted { (lhs, rhs) in
                    let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? ""
                    let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? ""
                    return lhsDate > rhsDate
                }
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Add SearchBar below the navigation bar
                SearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#FFFFFF"))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)

                if filteredDocuments.isEmpty {
                    Text(searchText.isEmpty ? "No documents found for \(groupName)" : "No documents match your search in \(groupName).")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding()
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        if isGridView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                                ForEach(filteredDocuments, id: \.id) { document in
                                    NavigationLink(destination: DocumentGalleryView(
                                        documents: documents,
                                        initialDocument: document,
                                        projectName: projectName,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(networkStatusManager)) {
                                        DocumentCard(document: document)
                                    }
                                }
                            }
                            .padding()
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredDocuments, id: \.id) { document in
                                    NavigationLink(destination: DocumentGalleryView(
                                        documents: documents,
                                        initialDocument: document,
                                        projectName: projectName,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(networkStatusManager)) {
                                        DocumentRow(document: document)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .refreshable { onRefresh() }
                }
            }
            
//            VStack {
//                Spacer()
//                HStack {
//                    Spacer()
//                    Menu {
//                        Button(action: { showCreateRFI = true }) {
//                            Label("New RFI", systemImage: "doc.text.fill")
//                        }
//                    } label: {
//                        Image(systemName: "plus")
//                            .font(.system(size: 24, weight: .semibold))
//                            .foregroundColor(.white)
//                            .frame(width: 56, height: 56)
//                            .background(Color(hex: "#3B82F6"))
//                            .clipShape(Circle())
//                            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
//                    }
//                    .padding(.trailing, 20)
//                    .padding(.bottom, 20)
//                }
//            }
        }
        .navigationTitle("\(groupName)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
            }
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
                showCreateRFI = false
            }, prefilledTitle: nil, prefilledAttachmentData: nil, prefilledDrawing: nil, sourceMarkup: nil)
        }
    }
}
struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))
                    .lineLimit(1)

                Text("ID: \(document.id)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .lineLimit(1)

                if let latestRevision = document.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    Text("Rev: \(latestRevision.versionNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#4B5563"))
                }
            }
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: document.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                    .foregroundColor(document.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                    .font(.system(size: 18))

                Text("\(document.revisions.count) Revs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#3B82F6").opacity(0.8))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            Text(document.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)

            Text("ID: \(document.id)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#6B7280"))
            
            Spacer()

            HStack {
                Image(systemName: document.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                    .foregroundColor(document.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                    .font(.system(size: 16))
                Spacer()
                Text("\(document.revisions.count) Revs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#4B5563"))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, idealHeight: 160, maxHeight: 170)
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}
