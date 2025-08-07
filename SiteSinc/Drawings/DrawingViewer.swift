import SwiftUI
import WebKit
import Foundation
import Network

struct DrawingViewer: View {
    let drawings: [Drawing]
    @Binding var drawingIndex: Int
    let isProjectOffline: Bool
    @EnvironmentObject var sessionManager: SessionManager // Added
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added for debugging
    
    @State private var selectedRevision: Revision?
    @State private var isSidePanelOpen: Bool = false
    @State private var showShareSheet = false
    @State private var itemToShare: Any?
    @State private var isDownloadingForShare = false

    private var currentDrawing: Drawing {
        guard drawingIndex >= 0, drawingIndex < drawings.count else {
            fatalError("Drawing index out of bounds: \(drawingIndex). Available: \(drawings.count)")
        }
        return drawings[drawingIndex]
    }
    
    private var currentPdfFile: DrawingFile? {
        guard let revision = selectedRevision ?? currentDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) else {
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
            DrawingContentView(
                drawing: currentDrawing,
                drawings: drawings,
                isProjectOffline: isProjectOffline,
                selectedRevision: $selectedRevision,
                drawingIndex: $drawingIndex,
                drawingsCount: drawings.count,
                preparePDFForSharing: preparePDFForSharing,
                showShareSheet: $showShareSheet,
                itemToShare: $itemToShare,
                isDownloadingForShare: $isDownloadingForShare,
                isSidePanelOpen: $isSidePanelOpen
            )

            if isSidePanelOpen {
                SidePanelView(
                    drawing: currentDrawing,
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
        .navigationTitle(currentDrawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(currentDrawing.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(currentDrawing.number)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Drawing title: \(currentDrawing.title), number: \(currentDrawing.number)")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Compact Revision Picker
                if !currentDrawing.revisions.isEmpty {
                    Menu {
                        let sorted = currentDrawing.revisions.sorted { $0.versionNumber > $1.versionNumber }
                        ForEach(sorted, id: \.id) { rev in
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    selectedRevision = rev
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }) {
                                HStack {
                                    Text("Rev \(rev.revisionNumber ?? String(rev.versionNumber))")
                                    if sorted.first?.id == rev.id {
                                        Text("Latest").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Rev \( (selectedRevision?.revisionNumber) ?? String( selectedRevision?.versionNumber ?? currentDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber ?? 0))")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                    }
                }
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
            // Log the view event for the drawing file
            if let fileId = currentPdfFile?.id, let token = sessionManager.token {
                DrawingAccessLogger.shared.logAccess(fileId: fileId, type: "view", token: token)
            }
            // Flush any queued logs if network is available
            DrawingAccessLogger.shared.flushQueue()
            print("DrawingViewer: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
            if selectedRevision == nil, let latestRevision = currentDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                selectedRevision = latestRevision
            }
        }
        .onChange(of: drawingIndex) {
            guard drawingIndex >= 0, drawingIndex < drawings.count else { return }
            let newDrawing = drawings[drawingIndex]
            if let latestRevision = newDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                selectedRevision = latestRevision
            } else {
                selectedRevision = nil
            }
        }
    }
}

struct DrawingContentView: View {
    let drawing: Drawing
    let drawings: [Drawing]
    let isProjectOffline: Bool
    @Binding var selectedRevision: Revision?
    @Binding var drawingIndex: Int
    let drawingsCount: Int
    let preparePDFForSharing: (@escaping (URL?) -> Void) -> Void
    @Binding var showShareSheet: Bool
    @Binding var itemToShare: Any?
    @Binding var isDownloadingForShare: Bool
    @Binding var isSidePanelOpen: Bool
    @EnvironmentObject var sessionManager: SessionManager
    
    @State private var urlToDisplayInWebView: URL?
    @State private var isLoadingPDFForView: Bool = false
    @State private var pdfLoadError: String?

    private func determineURLForDisplay() {
        urlToDisplayInWebView = nil
        pdfLoadError = nil
        isLoadingPDFForView = true

        guard let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
              let pdfFile = revision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) else {
            pdfLoadError = "No PDF available for this revision."
            isLoadingPDFForView = false
            return
        }
        
        guard !pdfFile.fileName.isEmpty, !pdfFile.fileName.contains("/") else {
            pdfLoadError = "Invalid PDF filename."
            isLoadingPDFForView = false
            return
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectDrawingsDirectory = documentsDirectory.appendingPathComponent("Project_\(drawing.projectId)/drawings")
        let localFilePath = projectDrawingsDirectory.appendingPathComponent(pdfFile.fileName)

        if isProjectOffline {
            if FileManager.default.fileExists(atPath: localFilePath.path) {
                urlToDisplayInWebView = localFilePath
                print("Offline mode: Loading PDF from local cache: \(localFilePath.lastPathComponent)")
            } else {
                pdfLoadError = "Drawing not available offline. Please sync the project."
                print("Offline mode: PDF not found in local cache: \(localFilePath.lastPathComponent)")
            }
            isLoadingPDFForView = false
        } else {
            if let downloadUrlString = pdfFile.downloadUrl, let downloadUrl = URL(string: downloadUrlString) {
                urlToDisplayInWebView = downloadUrl
                print("Online mode: Streaming PDF from remote URL: \(downloadUrl.absoluteString)")
            } else {
                pdfLoadError = "PDF download URL is invalid."
                isLoadingPDFForView = false
            }
        }
    }

    @ViewBuilder
    private var pdfDisplayArea: some View {
        GeometryReader { geometry in
            ZStack {
                if isLoadingPDFForView && urlToDisplayInWebView == nil {
                    ProgressView("Preparing drawing...")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                        .padding()
                } else if let error = pdfLoadError {
                    VStack(spacing: 15) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        if isProjectOffline && error.contains("not available offline") {
                            Text("Please ensure the project is fully downloaded for offline access.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else if !isProjectOffline {
                            Button("Retry") {
                                determineURLForDisplay()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "#3B82F6"))
                        }
                    }
                    .padding()
                } else if let validURL = urlToDisplayInWebView,
                          let currentPdf = (selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }))?.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) {
                    PDFMarkupViewer(
                        pdfURL: validURL,
                        drawingId: drawing.id,
                        drawingFileId: currentPdf.id,
                        token: sessionManager.token ?? "",
                        page: 1
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.5))
                        Text("Select a revision to view PDF.")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(Color(hex: "#6B7280"))
                    }
                    .padding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private var notLatestBannerView: some View {
        if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
           let currentSelected = selectedRevision,
           currentSelected.id != latest.id {
            VStack {
                Text("Not Latest: Rev \(currentSelected.revisionNumber ?? String(currentSelected.versionNumber)) (Latest: \(latest.revisionNumber ?? String(latest.versionNumber)))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(6)
                    .shadow(radius: 3)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var revisionSelectionButtonsView: some View {
        if !drawing.revisions.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(drawing.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                        Button(action: {
                            withAnimation(.easeInOut) {
                                if selectedRevision?.id != revision.id {
                                    selectedRevision = revision
                                }
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }) {
                            VStack(spacing: 2) {
                                Text("Rev \(revision.revisionNumber ?? String(revision.versionNumber))")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                Text(revision.status.prefix(10))
                                    .font(.system(size: 9, weight: .regular))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .foregroundColor((selectedRevision?.id == revision.id) ? .white : Color(hex: "#1F2A44"))
                            .background(
                                (selectedRevision?.id == revision.id)
                                ? Color(hex: "#3B82F6")
                                : Color.white.opacity(0.7)
                            )
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                        .accessibilityLabel("Revision \(revision.revisionNumber ?? String(revision.versionNumber)), status \(revision.status)")
                    }
                }
            }
            .frame(maxWidth: 100)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
        } else {
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                pdfDisplayArea
                notLatestBannerView
                // Replaced the sidebar revision list with a toolbar menu
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let horizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
                        let swipeThreshold: CGFloat = 50

                        if horizontalSwipe {
                            if value.translation.width < -swipeThreshold {
                                if drawingIndex < drawingsCount - 1 {
                                    withAnimation(.easeInOut) { drawingIndex += 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else if value.translation.width > swipeThreshold {
                                if drawingIndex > 0 {
                                    withAnimation(.easeInOut) { drawingIndex -= 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        } else {
                            guard !drawing.revisions.isEmpty else { return }
                            let sortedRevisions = drawing.revisions.sorted { $0.versionNumber > $1.versionNumber }
                            guard let currentActualRevision = selectedRevision ?? sortedRevisions.first,
                                  let currentIndex = sortedRevisions.firstIndex(where: { $0.id == currentActualRevision.id }) else { return }

                            if value.translation.height < -swipeThreshold {
                                if currentIndex > 0 {
                                    withAnimation(.easeInOut) {
                                        selectedRevision = sortedRevisions[currentIndex - 1]
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else if value.translation.height > swipeThreshold {
                                if currentIndex < sortedRevisions.count - 1 {
                                    withAnimation(.easeInOut) {
                                        selectedRevision = sortedRevisions[currentIndex + 1]
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }
                    }
            )
        }
        .onAppear {
            determineURLForDisplay()
        }
        .onChange(of: drawingIndex) {
            let newDrawing = drawings[drawingIndex]
            selectedRevision = newDrawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })
            determineURLForDisplay()
        }
        .onChange(of: selectedRevision?.id) {
            determineURLForDisplay()
        }
    }
}

struct SidePanelView: View {
    let drawing: Drawing
    let selectedRevision: Revision?
    @Binding var isSidePanelOpen: Bool

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString, !dateString.isEmpty else { return "N/A" }
        if let date = isoDateFormatter.date(from: dateString) {
            return displayDateFormatter.string(from: date)
        }
        let simplerIsoFormatter = ISO8601DateFormatter()
        simplerIsoFormatter.formatOptions = .withInternetDateTime
        if let date = simplerIsoFormatter.date(from: dateString) {
            return displayDateFormatter.string(from: date)
        }
        return "Invalid Date"
    }
    
    private var revisionToDisplay: Revision? {
        selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack {
            Text("Drawing Information")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            Spacer()
            Button(action: {
                withAnimation(.easeInOut) { isSidePanelOpen = false }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#9CA3AF"))
            }
        }
        .padding([.top, .horizontal])
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var revisionDetailsSection: some View {
        if let revision = revisionToDisplay {
            InfoRow(label: "Revision Number", value: revision.revisionNumber ?? String(revision.versionNumber))
            InfoRow(label: "Revision Status", value: revision.status)
            InfoRow(label: "Revision Date", value: formatDate(revision.uploadedAt))
        } else {
            InfoRow(label: "Revision", value: "Not Available")
        }
    }
    
    @ViewBuilder
    private var uploaderInfoSection: some View {
        let uploaderNameValue: String = {
            if let rev = revisionToDisplay, let uploadedBy = rev.uploadedBy, !uploadedBy.isEmpty {
                return uploadedBy
            } else if let user = drawing.user {
                let name = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? "N/A" : name
            }
            return "N/A"
        }()
        
        let uploadedAtValue = formatDate(revisionToDisplay?.uploadedAt ?? drawing.createdAt)

        InfoRow(label: "Uploaded By", value: uploaderNameValue)
        InfoRow(label: "Uploaded At", value: uploadedAtValue)
    }

    @ViewBuilder
    private var disciplineAndTypeSection: some View {
        if let discipline = drawing.projectDiscipline?.name, !discipline.isEmpty {
            InfoRow(label: "Discipline", value: discipline)
        }
        if let type = drawing.projectDrawingType?.name, !type.isEmpty {
            InfoRow(label: "Type", value: type)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    Divider().padding(.horizontal)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            revisionDetailsSection
                            
                            InfoRow(label: "Drawing Title", value: drawing.title)
                            InfoRow(label: "Drawing Number", value: drawing.number)
                            
                            uploaderInfoSection
                            disciplineAndTypeSection
                            
                            InfoRow(label: "Project ID", value: "\(drawing.projectId)")
                            InfoRow(label: "Offline Available", value: drawing.isOffline ?? false ? "Yes" : "No")
                        }
                        .padding()
                    }
                }
                .frame(width: min(geometry.size.width * 0.85, 350))
                .background(Color(hex: "#F9FAFB").edgesIgnoringSafeArea(.bottom))
                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: -5, y: 0)
                .transition(.move(edge: .trailing))
            }
        }
        .background(
            Color.black.opacity(isSidePanelOpen ? 0.4 : 0)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut) {
                        isSidePanelOpen = false
                    }
                }
        )
        .animation(.easeInOut, value: isSidePanelOpen)
        .edgesIgnoringSafeArea(.all)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#4B5563"))
            Text(value)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .textSelection(.enabled)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 3.0
        webView.scrollView.bouncesZoom = true
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            print("WebView: Loading URL: \(url.absoluteString)")
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            uiView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("WebView Coordinator: didStartProvisionalNavigation for \(webView.url?.absoluteString ?? "unknown URL")")
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView Coordinator: didFinish navigation for \(webView.url?.absoluteString ?? "unknown URL")")
            parent.isLoading = false
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView Coordinator: didFail navigation for \(webView.url?.absoluteString ?? "unknown URL") with error: \(error.localizedDescription)")
            parent.isLoading = false
            parent.loadError = "Failed to load drawing: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView Coordinator: didFailProvisionalNavigation for \(webView.url?.absoluteString ?? "unknown URL") with error: \(error.localizedDescription)")
            parent.isLoading = false
            parent.loadError = "Failed to load drawing (provisional): \(error.localizedDescription)"
        }
    }
}
