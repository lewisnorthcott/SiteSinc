//
//  DocumentViewer.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI
import WebKit

struct DocumentViewer: View {
    let documents: [Document]
    @Binding var documentIndex: Int
    let isProjectOffline: Bool
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added for network status
    
    @State private var selectedRevision: DocumentRevision?
    @State private var isSidePanelOpen: Bool = false
    @State private var showShareSheet = false
    @State private var itemToShare: Any?
    @State private var isDownloadingForShare = false

    private var currentDocument: Document {
        guard documentIndex >= 0, documentIndex < documents.count else {
            fatalError("Document index out of bounds: \(documentIndex). Available: \(documents.count)")
        }
        return documents[documentIndex]
    }
    
    private var currentPdfFile: DocumentFile? {
        guard let revision = selectedRevision ?? currentDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber }) else {
            return nil
        }
        if let documentFiles = revision.documentFiles,
           let pdfFile = documentFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) {
            return pdfFile
        }
        let fileUrl = revision.fileUrl
        if fileUrl.isEmpty {
            return nil
        }
        let fileName = fileUrl.split(separator: "/").last?.removingPercentEncoding ?? "document.pdf"
        return DocumentFile(
            id: revision.id,
            fileName: fileName,
            fileUrl: fileUrl,
            downloadUrl: revision.downloadUrl
        )
    }
    
    private func preparePDFForSharing(completion: @escaping (URL?) -> Void) {
        guard let pdfFile = currentPdfFile else {
            completion(nil)
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shareDownloadsDirectory = documentsDirectory.appendingPathComponent("Project_\(currentDocument.projectId)/shared_downloads")
        let localFilePathForShare = shareDownloadsDirectory.appendingPathComponent(pdfFile.fileName)
        
        if FileManager.default.fileExists(atPath: localFilePathForShare.path) {
            completion(localFilePathForShare)
            return
        }
        
        if isProjectOffline && !networkStatusManager.isNetworkAvailable {
            let primaryOfflineStoragePath = documentsDirectory.appendingPathComponent("Project_\(currentDocument.projectId)/documents/\(pdfFile.fileName)")
            if FileManager.default.fileExists(atPath: primaryOfflineStoragePath.path) {
                do {
                    try FileManager.default.createDirectory(at: shareDownloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                    if FileManager.default.fileExists(atPath: localFilePathForShare.path) {
                        try FileManager.default.removeItem(at: localFilePathForShare)
                    }
                    try FileManager.default.copyItem(at: primaryOfflineStoragePath, to: localFilePathForShare)
                    completion(localFilePathForShare)
                    return
                } catch {
                    completion(nil)
                }
            }
        }
        
        guard let downloadUrlString = pdfFile.downloadUrl, let downloadUrl = URL(string: downloadUrlString) else {
            completion(nil)
            return
        }
        
        isDownloadingForShare = true
        
        let task = URLSession.shared.downloadTask(with: downloadUrl) { tempURL, response, error in
            DispatchQueue.main.async {
                isDownloadingForShare = false
                if let tempURL = tempURL {
                    do {
                        try FileManager.default.createDirectory(at: shareDownloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                        _ = try FileManager.default.replaceItemAt(localFilePathForShare, withItemAt: tempURL)
                        completion(localFilePathForShare)
                    } catch {
                        completion(downloadUrl)
                    }
                } else {
                    completion(nil)
                }
            }
        }
        task.resume()
    }

    // MARK: - Overlays split to help the compiler
    @ViewBuilder
    private var revisionMenuOverlay: some View {
        if let latest = currentDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
            let sortedRevisions = currentDocument.revisions.sorted(by: { $0.versionNumber > $1.versionNumber })
            Menu(content: {
                ForEach(sortedRevisions, id: \.id) { revision in
                    Button(action: {
                        if selectedRevision?.id != revision.id {
                            withAnimation(.easeInOut) { selectedRevision = revision }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }, label: {
                        HStack {
                            Text("Rev \(revision.versionNumber)")
                            if selectedRevision?.id == revision.id { Image(systemName: "checkmark") }
                        }
                    })
                }
            }, label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Rev \(selectedRevision?.versionNumber ?? latest.versionNumber)")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            })
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var notLatestBannerOverlay: some View {
        if let latest = currentDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
           let currentSelected = selectedRevision,
           currentSelected.id != latest.id {
            let msg = "Not Latest: Rev \(currentSelected.versionNumber) (Latest: \(latest.versionNumber))"
            Text(msg)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.85))
                .cornerRadius(6)
                .shadow(radius: 3)
                .padding(.bottom, 8)
        }
    }
    var body: some View {
        ZStack {
            DocumentContentView(
                document: currentDocument,
                documents: documents,
                isProjectOffline: isProjectOffline,
                selectedRevision: $selectedRevision,
                documentIndex: $documentIndex,
                documentsCount: documents.count,
                preparePDFForSharing: preparePDFForSharing,
                showShareSheet: $showShareSheet,
                itemToShare: $itemToShare,
                isDownloadingForShare: $isDownloadingForShare,
                isSidePanelOpen: $isSidePanelOpen
            )

            if isSidePanelOpen {
                DocumentSidePanelView(
                    document: currentDocument,
                    selectedRevision: selectedRevision,
                    isSidePanelOpen: $isSidePanelOpen
                )
            }
            
            if isDownloadingForShare {
                ProgressView("Preparing PDF for Share...")
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                    .padding()
                    .background(Material.thin)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        .overlay(alignment: .top) { revisionMenuOverlay }
        .overlay(alignment: .bottom) { notLatestBannerOverlay }
        .navigationTitle(currentDocument.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(currentDocument.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("ID: \(currentDocument.id)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .lineLimit(1)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    preparePDFForSharing { urlToShare in
                        if let url = urlToShare {
                            itemToShare = url
                            showShareSheet = true
                        }
                    }
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .disabled(currentPdfFile == nil || isDownloadingForShare)
                
                Button(action: {
                    withAnimation(.easeInOut) { isSidePanelOpen.toggle() }
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let item = itemToShare {
                ShareSheet(activityItems: [item])
            }
        }
        .onAppear {
            if selectedRevision == nil, let latestRevision = currentDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                selectedRevision = latestRevision
            }
        }
        .onChange(of: documentIndex) {
            guard documentIndex >= 0, documentIndex < documents.count else { return }
            let newDocument = documents[documentIndex]
            if let latestRevision = newDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                selectedRevision = latestRevision
            } else {
                selectedRevision = nil
            }
        }
    }
}
