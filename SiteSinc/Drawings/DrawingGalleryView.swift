import SwiftUI

struct DrawingGalleryView: View {
    let drawings: [Drawing]
    let isProjectOffline: Bool
    @State private var selectedIndex: Int
    @State private var showShareSheet = false
    @State private var itemToShare: Any?
    @State private var isDownloadingForShare = false
    @State private var isSidePanelOpen: Bool = false
    @EnvironmentObject var sessionManager: SessionManager // Added
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added for debugging
    
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
    
    private var currentPdfFile: DrawingFile? {
        guard let revision = currentDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) else {
            return nil
        }
        return revision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") })
    }
    
    private func preparePDFForSharing(completion: @escaping (URL?) -> Void) {
        guard let pdfFile = currentPdfFile else {
            print("No current PDF file to prepare for sharing.")
            completion(nil)
            return
        }
        
        guard !pdfFile.fileName.isEmpty, !pdfFile.fileName.contains("/") else {
            print("Invalid PDF filename for sharing: \(pdfFile.fileName)")
            completion(nil)
            return
        }

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shareDownloadsDirectory = documentsDirectory.appendingPathComponent("Project_\(currentDrawing.projectId)/shared_downloads")
        let localFilePathForShare = shareDownloadsDirectory.appendingPathComponent(pdfFile.fileName)
        
        if FileManager.default.fileExists(atPath: localFilePathForShare.path) {
            print("PDF already downloaded for sharing: \(localFilePathForShare.lastPathComponent)")
            completion(localFilePathForShare)
            return
        }
        
        if isProjectOffline {
            let primaryOfflineStoragePath = documentsDirectory.appendingPathComponent("Project_\(currentDrawing.projectId)/drawings/\(pdfFile.fileName)")
            if FileManager.default.fileExists(atPath: primaryOfflineStoragePath.path) {
                do {
                    try FileManager.default.createDirectory(at: shareDownloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                    if FileManager.default.fileExists(atPath: localFilePathForShare.path) {
                        try FileManager.default.removeItem(at: localFilePathForShare)
                    }
                    try FileManager.default.copyItem(at: primaryOfflineStoragePath, to: localFilePathForShare)
                    print("Copied offline PDF for sharing: \(localFilePathForShare.lastPathComponent)")
                    completion(localFilePathForShare)
                    return
                } catch {
                    print("Error copying offline PDF for sharing: \(error.localizedDescription)")
                }
            }
        }
        
        guard let downloadUrlString = pdfFile.downloadUrl, let downloadUrl = URL(string: downloadUrlString) else {
            print("No valid download URL for PDF (for sharing): \(pdfFile.fileName)")
            completion(nil)
            return
        }
        
        print("Downloading PDF specifically for sharing: \(pdfFile.fileName) from \(downloadUrl.absoluteString)")
        isDownloadingForShare = true
        
        let task = URLSession.shared.downloadTask(with: downloadUrl) { tempURL, response, error in
            DispatchQueue.main.async {
                isDownloadingForShare = false
                if let error = error {
                    print("Download error for sharing: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                guard let tempURL = tempURL else {
                    print("No temporary URL after download for sharing.")
                    completion(nil)
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: shareDownloadsDirectory, withIntermediateDirectories: true, attributes: nil)
                    _ = try FileManager.default.replaceItemAt(localFilePathForShare, withItemAt: tempURL)
                    print("PDF downloaded and saved for sharing: \(localFilePathForShare.lastPathComponent)")
                    completion(localFilePathForShare)
                } catch {
                    print("File save/replace error after download for sharing: \(error.localizedDescription)")
                    completion(downloadUrl)
                }
            }
        }
        task.resume()
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedIndex) {
                ForEach(drawings.indices, id: \.self) { index in
                    DrawingViewer(
                        drawings: drawings,
                        drawingIndex: $selectedIndex,
                        isProjectOffline: isProjectOffline,
                        pageIndex: index,
                        showToolbar: false
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            
            // Side panel overlay
            if isSidePanelOpen {
                DrawingSidePanelView(
                    drawing: currentDrawing,
                    selectedRevision: currentDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                    isSidePanelOpen: $isSidePanelOpen
                )
            }
            
            // Download progress overlay
            if isDownloadingForShare {
                ProgressView("Preparing PDF for Share...")
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                    .padding()
                    .background(Material.thin)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        .navigationTitle(currentDrawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedIndex) {
            // Navigation title will automatically update based on currentDrawing
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: {
                    preparePDFForSharing { urlToShare in
                        if let url = urlToShare {
                            itemToShare = url
                            showShareSheet = true
                        } else {
                            print("Failed to prepare PDF for sharing for drawing: \(currentDrawing.title)")
                        }
                    }
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .disabled(currentPdfFile == nil || isDownloadingForShare)
                .accessibilityLabel("Share drawing")

                Button(action: {
                    withAnimation(.easeInOut) {
                        isSidePanelOpen.toggle()
                    }
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .accessibilityLabel("Toggle drawing information panel")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let item = itemToShare {
                ShareSheet(activityItems: [item])
            } else {
                EmptyView()
            }
        }
        .onAppear {
            print("DrawingGalleryView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
        }
    }
}
