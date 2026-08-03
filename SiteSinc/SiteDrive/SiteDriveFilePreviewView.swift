import SwiftUI
import PDFKit

/// Previews a SiteDrive file: PDFs via PDFKit, images natively, and a
/// share/open-online fallback for everything else. Downloads go through the
/// revision-keyed disk cache so repeat opens work offline.
struct SiteDriveFilePreviewView: View {
    let projectId: Int
    let scope: SiteDriveScope
    let item: SiteDriveItem
    let token: String

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.openURL) private var openURL

    @State private var detail: SiteDriveItem?
    @State private var selectedRevision: SiteDriveRevision?
    @State private var localFileURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showVersions = false
    @State private var isFetchingOnlineUrl = false

    private var effectiveToken: String { sessionManager.token ?? token }

    private var revisions: [SiteDriveRevision] {
        (detail?.revisions ?? []).sorted { $0.versionNumber > $1.versionNumber }
    }

    var body: some View {
        content
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .brandPageBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let localFileURL {
                        ShareLink(item: localFileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showVersions = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(revisions.isEmpty)
                }
            }
            .sheet(isPresented: $showVersions) {
                SiteDriveVersionsSheet(
                    revisions: revisions,
                    selectedRevisionId: selectedRevision?.id,
                    onSelect: { revision in
                        showVersions = false
                        guard revision.id != selectedRevision?.id else { return }
                        selectedRevision = revision
                        Task { await downloadRevision(revision) }
                    }
                )
            }
            .task { await loadDetail() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(item.name)…")
                    .font(.subheadline)
                    .foregroundColor(BrandChrome.mutedLabel)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
                Text(errorMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") {
                    Task { await loadDetail() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandChrome.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let localFileURL {
            previewBody(for: localFileURL)
        } else {
            fallbackView
        }
    }

    @ViewBuilder
    private func previewBody(for url: URL) -> some View {
        if item.isPdf {
            SiteDrivePDFView(url: url)
                .ignoresSafeArea(edges: .bottom)
        } else if item.isImage, let uiImage = UIImage(contentsOfFile: url.path) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 16) {
            Image(systemName: item.iconName)
                .font(.system(size: 52))
                .foregroundColor(Color(hex: item.iconColor))
            Text(item.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let revision = selectedRevision, let size = revision.formattedSize {
                Text("Version \(revision.versionNumber) · \(size)")
                    .font(.subheadline)
                    .foregroundColor(BrandChrome.mutedLabel)
            }
            Text("No in-app preview for this file type.")
                .font(.subheadline)
                .foregroundColor(BrandChrome.mutedLabel)

            if let localFileURL {
                ShareLink(item: localFileURL) {
                    Label("Open in…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandChrome.accent)
            }

            if item.isOfficeFile || item.externalWebUrl != nil {
                Button {
                    openOnline()
                } label: {
                    if isFetchingOnlineUrl {
                        ProgressView()
                    } else {
                        Label("Open Online", systemImage: "globe")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFetchingOnlineUrl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await APIClient.fetchSiteDriveItem(itemId: item.id, token: effectiveToken)
            detail = fetched
            let revision = (fetched.revisions ?? []).max { $0.versionNumber < $1.versionNumber } ?? fetched.latestRevision
            selectedRevision = revision
            if let revision {
                await downloadRevision(revision)
            } else {
                errorMessage = "This file has no uploaded versions."
                isLoading = false
            }
        } catch {
            // Offline fallback: use a cached copy of the latest known revision.
            if let known = item.latestRevision,
               let cached = SiteDriveFileCache.cachedURL(scope: scope, projectId: projectId, itemName: item.name, revisionId: known.id) {
                selectedRevision = known
                localFileURL = cached
                isLoading = false
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
                isLoading = false
            }
        }
    }

    private func downloadRevision(_ revision: SiteDriveRevision) async {
        isLoading = true
        errorMessage = nil
        localFileURL = nil

        if let cached = SiteDriveFileCache.cachedURL(scope: scope, projectId: projectId, itemName: item.name, revisionId: revision.id) {
            localFileURL = cached
            isLoading = false
            return
        }

        do {
            let urlString: String
            if let embedded = revision.downloadUrl {
                urlString = embedded
            } else {
                urlString = try await APIClient.fetchSiteDriveDownloadUrl(itemId: item.id, revisionId: revision.id, token: effectiveToken)
            }
            guard let url = URL(string: urlString) else {
                throw APIError.badRequest(message: "Invalid download URL.")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw APIError.invalidResponse(statusCode: http.statusCode)
            }
            localFileURL = try SiteDriveFileCache.store(
                data,
                scope: scope,
                projectId: projectId,
                itemName: item.name,
                revisionId: revision.id
            )
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isLoading = false
    }

    private func openOnline() {
        if let external = item.externalWebUrl ?? detail?.externalWebUrl, let url = URL(string: external) {
            openURL(url)
            return
        }
        isFetchingOnlineUrl = true
        Task {
            defer { isFetchingOnlineUrl = false }
            if let webUrl = try? await APIClient.fetchSiteDriveOnlineUrl(itemId: item.id, token: effectiveToken),
               let url = URL(string: webUrl ?? "") {
                openURL(url)
            }
        }
    }
}

// MARK: - PDF wrapper

/// Minimal PDFKit wrapper (the Documents feature's PDFKitView is coupled to
/// its search state, so SiteDrive keeps its own).
struct SiteDrivePDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemGray6
        pdfView.pageShadowsEnabled = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
