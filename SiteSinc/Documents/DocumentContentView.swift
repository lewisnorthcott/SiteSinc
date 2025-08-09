//
//  DocumentContentView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI
import WebKit

struct DocumentContentView: View {
    let document: Document
    let documents: [Document]
    let isProjectOffline: Bool
    @Binding var selectedRevision: DocumentRevision?
    @Binding var documentIndex: Int
    let documentsCount: Int
    let preparePDFForSharing: (@escaping (URL?) -> Void) -> Void
    @Binding var showShareSheet: Bool
    @Binding var itemToShare: Any?
    @Binding var isDownloadingForShare: Bool
    @Binding var isSidePanelOpen: Bool
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    
    @State private var urlToDisplayInWebView: URL?
    @State private var isLoadingPDFForView: Bool = false
    @State private var pdfLoadError: String?
    @State private var rotationAngle: Angle = .degrees(0)

    private func determineURLForDisplay() {
        urlToDisplayInWebView = nil
        pdfLoadError = nil
        isLoadingPDFForView = true

        guard let revision = selectedRevision ?? document.revisions.max(by: { $0.versionNumber < $1.versionNumber }) else {
            pdfLoadError = "No revision available for this document."
            isLoadingPDFForView = false
            return
        }

        var pdfFile: DocumentFile?
        if let documentFiles = revision.documentFiles,
           let foundFile = documentFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) {
            pdfFile = foundFile
        } else {
            let fileUrl = revision.fileUrl
            if fileUrl.isEmpty {
                pdfLoadError = "Invalid PDF file URL."
                isLoadingPDFForView = false
                return
            }
            let fileName = fileUrl.split(separator: "/").last?.removingPercentEncoding ?? "document.pdf"
            pdfFile = DocumentFile(
                id: revision.id,
                fileName: fileName,
                fileUrl: fileUrl,
                downloadUrl: revision.downloadUrl
            )
        }

        guard let pdfFile = pdfFile else {
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
        let projectDocumentsDirectory = documentsDirectory.appendingPathComponent("Project_\(document.projectId)/documents")
        let localFilePath = projectDocumentsDirectory.appendingPathComponent(pdfFile.fileName)

        if isProjectOffline && !networkStatusManager.isNetworkAvailable {
            if FileManager.default.fileExists(atPath: localFilePath.path) {
                urlToDisplayInWebView = localFilePath
                print("Offline mode: Loading PDF from local cache: \(localFilePath.path)")
            } else {
                pdfLoadError = "Document not available offline. Please sync the project while online."
                print("Offline mode: PDF not found at: \(localFilePath.path)")
            }
            isLoadingPDFForView = false
        } else {
            if networkStatusManager.isNetworkAvailable {
                if let downloadUrlString = pdfFile.downloadUrl, let downloadUrl = URL(string: downloadUrlString) {
                    urlToDisplayInWebView = downloadUrl
                    print("Online mode: Streaming PDF from: \(downloadUrl.absoluteString)")
                } else {
                    pdfLoadError = "PDF download URL is invalid."
                    isLoadingPDFForView = false
                }
            } else if FileManager.default.fileExists(atPath: localFilePath.path) {
                urlToDisplayInWebView = localFilePath
                print("Offline fallback: Loading PDF from local cache: \(localFilePath.path)")
                isLoadingPDFForView = false
            } else {
                pdfLoadError = "No network available and document not cached offline."
                print("Offline fallback: PDF not found at: \(localFilePath.path)")
                isLoadingPDFForView = false
            }
        }
    }

    @ViewBuilder
    private var pdfDisplayArea: some View {
        if isLoadingPDFForView && urlToDisplayInWebView == nil {
            ProgressView("Preparing document...")
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
                if error.contains("not available offline") || error.contains("no network available") {
                    Text("Please ensure the project is fully downloaded for offline access or connect to the internet.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if !networkStatusManager.isNetworkAvailable {
                    Text("No internet connection.")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else if !error.contains("not available offline") {
                    Button("Retry") { determineURLForDisplay() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#3B82F6"))
                }
            }
            .padding()
        } else if let validURL = urlToDisplayInWebView {
            let revisionForAccessibility = selectedRevision ?? document.revisions.max(by: { $0.versionNumber < $1.versionNumber })
            WebView(url: validURL, isLoading: $isLoadingPDFForView, loadError: $pdfLoadError)
                .rotationEffect(rotationAngle)
                .accessibilityLabel("Document \(document.name), Revision \(revisionForAccessibility?.versionNumber ?? 0)")
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

    @ViewBuilder
    private var notLatestBannerView: some View {
        if let latest = document.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
           let currentSelected = selectedRevision,
           currentSelected.id != latest.id {
            VStack {
                Text("Not Latest: Rev \(currentSelected.versionNumber) (Latest: \(latest.versionNumber))")
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
        }
    }

    @ViewBuilder
    private var revisionSelectionButtonsView: some View {
        if !document.revisions.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(document.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                        Button(action: {
                            withAnimation(.easeInOut) {
                                if selectedRevision?.id != revision.id {
                                    selectedRevision = revision
                                }
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }) {
                            VStack(spacing: 2) {
                                Text("Rev \(revision.versionNumber)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                Text(revision.status?.prefix(10) ?? "")
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
                    }
                }
            }
            .frame(maxWidth: 100)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                pdfDisplayArea
                notLatestBannerView
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let horizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
                        let swipeThreshold: CGFloat = 50

                        if horizontalSwipe {
                            if value.translation.width < -swipeThreshold {
                                if documentIndex < documentsCount - 1 {
                                    withAnimation(.easeInOut) { documentIndex += 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else if value.translation.width > swipeThreshold {
                                if documentIndex > 0 {
                                    withAnimation(.easeInOut) { documentIndex -= 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        } else {
                            guard !document.revisions.isEmpty else { return }
                            let sortedRevisions = document.revisions.sorted { $0.versionNumber > $1.versionNumber }
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
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        rotationAngle = value
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
        }
        .onAppear { determineURLForDisplay() }
        .onChange(of: documentIndex) {
            let newDocument = documents[documentIndex]
            selectedRevision = newDocument.revisions.max(by: { $0.versionNumber < $1.versionNumber })
            determineURLForDisplay()
        }
        .onChange(of: selectedRevision?.id) {
            determineURLForDisplay()
        }
        .onChange(of: networkStatusManager.isNetworkAvailable) { oldValue, newValue in
            determineURLForDisplay()
        }
    }
}
