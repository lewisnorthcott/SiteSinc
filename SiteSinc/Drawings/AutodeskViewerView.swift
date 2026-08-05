import SwiftUI
import WebKit

/// Hosts Autodesk APS Viewer (same JS stack as web `ForgeViewer.tsx`) for DWG/RVT/IFC drawing files.
/// Forge upload/status/token run natively to avoid WKWebView CORS against the SiteSinc API.
struct AutodeskViewerView: View {
    let fileId: Int
    let fileName: String
    let fileType: String
    let authToken: String

    @Binding var statusMessage: String?
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    @State private var viewerBootstrap: ViewerBootstrap?
    @State private var loadTask: Task<Void, Never>?
    @State private var activeFileId: Int?

    struct ViewerBootstrap: Equatable {
        let urn: String
        let accessToken: String
    }

    var body: some View {
        ZStack {
            if let bootstrap = viewerBootstrap {
                AutodeskViewerWebView(bootstrap: bootstrap) { event in
                    switch event {
                    case .ready:
                        isLoading = false
                        statusMessage = nil
                        errorMessage = nil
                    case .error(let message):
                        isLoading = false
                        statusMessage = nil
                        errorMessage = message
                    case .status(let message):
                        isLoading = true
                        statusMessage = message
                        errorMessage = nil
                    }
                }
            } else {
                Color(UIColor.secondarySystemBackground)
            }
        }
        .onAppear { startPipelineIfNeeded() }
        .onChange(of: fileId) { _, _ in
            restartPipeline()
        }
        .onDisappear {
            // Do not cancel an in-flight forge upload on disappear — SwiftUI can
            // briefly detach the view during layout. Cancellation is only for file changes / retry.
        }
    }

    private func restartPipeline() {
        loadTask?.cancel()
        loadTask = nil
        activeFileId = nil
        viewerBootstrap = nil
        startPipelineIfNeeded()
    }

    private func startPipelineIfNeeded() {
        // Avoid duplicate pipelines when SwiftUI calls onAppear more than once.
        if activeFileId == fileId, loadTask != nil || viewerBootstrap != nil {
            return
        }
        startPipeline()
    }

    private func startPipeline() {
        loadTask?.cancel()
        errorMessage = nil
        statusMessage = "Preparing Autodesk Viewer…"
        isLoading = true
        viewerBootstrap = nil
        activeFileId = fileId

        guard !authToken.isEmpty else {
            isLoading = false
            errorMessage = "Sign in required to view CAD files."
            return
        }

        let fileId = self.fileId
        let fileName = self.fileName
        let fileType = self.fileType
        let authToken = self.authToken

        loadTask = Task { @MainActor in
            do {
                statusMessage = "Uploading model to Autodesk… Large RVT files can take several minutes."
                let urn = try await APIClient.uploadDrawingFileToForge(
                    fileId: fileId,
                    fileName: fileName,
                    fileType: fileType,
                    token: authToken
                )
                try Task.checkCancellation()

                statusMessage = "Authenticating with Autodesk…"
                let apsToken = try await APIClient.fetchForgeViewerToken(token: authToken)
                try Task.checkCancellation()

                statusMessage = "Processing CAD model…"
                try await pollTranslation(urn: urn, fileId: fileId, authToken: authToken)
                try Task.checkCancellation()

                statusMessage = "Loading model into viewer…"
                viewerBootstrap = ViewerBootstrap(urn: urn, accessToken: apsToken)
            } catch is CancellationError {
                // Ignore intentional cancellations (file change / retry).
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URLSession maps task cancel to URLError.cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                if let apiError = error as? APIError {
                    // Ignore cancelled network work surfaced as APIError.networkError
                    if case .networkError(let underlying) = apiError,
                       let urlError = underlying as? URLError,
                       urlError.code == .cancelled {
                        return
                    }
                    isLoading = false
                    statusMessage = nil
                    errorMessage = apiError.displayMessage
                } else {
                    isLoading = false
                    statusMessage = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func pollTranslation(urn: String, fileId: Int, authToken: String) async throws {
        let maxRetries = 40
        for attempt in 0..<maxRetries {
            try Task.checkCancellation()
            let status = try await APIClient.fetchForgeTranslationStatus(
                urn: urn,
                fileId: fileId,
                token: authToken
            )

            let hasViewable = Self.hasViewableContent(status)
            if status.status == "failed" {
                throw APIError.badRequest(
                    message: "CAD translation failed. Download the file to open in Autodesk software."
                )
            }
            if status.status == "success" || hasViewable {
                return
            }

            let progress = status.progress.map { " \($0)" } ?? ""
            await MainActor.run {
                statusMessage = "Processing CAD model…\(progress) (\(attempt + 1)/\(maxRetries))"
            }
            let delay = min(5.0 * pow(1.4, Double(attempt)), 30.0)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        throw APIError.badRequest(
            message: "Model processing is taking longer than expected. Try again later."
        )
    }

    private static func hasViewableContent(_ status: APIClient.ForgeManifestStatus) -> Bool {
        guard let derivatives = status.derivatives else { return false }
        return derivatives.contains { derivative in
            guard derivative.status == "success", derivative.outputType == "svf" else { return false }
            return derivative.children?.contains { child in
                child.type == "geometry" && child.status == "success"
            } ?? false
        }
    }

    static func isCadFile(_ file: DrawingFile) -> Bool {
        let name = file.fileName.lowercased()
        let type = file.fileType.lowercased()
        let cadExtensions = ["dwg", "dxf", "rvt", "ifc"]
        if cadExtensions.contains(type) { return true }
        return cadExtensions.contains { name.hasSuffix(".\($0)") }
    }

    static func cadFileType(for file: DrawingFile) -> String {
        let name = file.fileName.lowercased()
        let type = file.fileType.lowercased()
        for ext in ["rvt", "ifc", "dwg", "dxf"] {
            if type == ext || name.hasSuffix(".\(ext)") { return ext }
        }
        return type.isEmpty ? "dwg" : type
    }
}

// MARK: - WebView (Autodesk Viewer JS only)

private enum AutodeskViewerEvent {
    case ready
    case status(String)
    case error(String)
}

private struct AutodeskViewerWebView: UIViewRepresentable {
    let bootstrap: AutodeskViewerView.ViewerBootstrap
    let onEvent: (AutodeskViewerEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "sitesincViewer")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .secondarySystemBackground
        webView.scrollView.isScrollEnabled = false
        context.coordinator.webView = webView
        context.coordinator.bootstrap = bootstrap

        webView.loadHTMLString(Self.viewerHTML, baseURL: URL(string: "https://developer.api.autodesk.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        if context.coordinator.bootstrap != bootstrap {
            context.coordinator.bootstrap = bootstrap
            context.coordinator.didStart = false
            context.coordinator.startViewerIfNeeded()
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "sitesincViewer")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onEvent: (AutodeskViewerEvent) -> Void
        var bootstrap: AutodeskViewerView.ViewerBootstrap?
        weak var webView: WKWebView?
        var didStart = false
        private var pageReady = false

        init(onEvent: @escaping (AutodeskViewerEvent) -> Void) {
            self.onEvent = onEvent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            startViewerIfNeeded()
        }

        func startViewerIfNeeded() {
            guard pageReady, !didStart, let webView, let bootstrap else { return }
            didStart = true

            let payload: [String: Any] = [
                "urn": bootstrap.urn,
                "accessToken": bootstrap.accessToken
            ]
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else { return }

            webView.evaluateJavaScript("window.__startSiteSincViewer(\(json));") { _, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onEvent(.error("Failed to start viewer: \(error.localizedDescription)"))
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "sitesincViewer",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            DispatchQueue.main.async {
                switch type {
                case "status":
                    self.onEvent(.status(body["message"] as? String ?? ""))
                case "ready":
                    self.onEvent(.ready)
                case "error":
                    self.onEvent(.error(body["message"] as? String ?? "Failed to load CAD model."))
                default:
                    break
                }
            }
        }
    }

    private static let viewerHTML = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
      <link rel="stylesheet" href="https://developer.api.autodesk.com/modelderivative/v2/viewers/7.*/style.min.css" />
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #1f2937; }
        #viewer { position: absolute; inset: 0; }
        #overlay {
          position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
          color: #e5e7eb; font: 15px -apple-system, BlinkMacSystemFont, sans-serif;
          background: rgba(17, 24, 39, 0.72); z-index: 10; text-align: center; padding: 24px;
        }
        #overlay.hidden { display: none; }
      </style>
    </head>
    <body>
      <div id="viewer"></div>
      <div id="overlay">Loading Autodesk Viewer…</div>
      <script src="https://developer.api.autodesk.com/modelderivative/v2/viewers/7.*/viewer3D.js"></script>
      <script>
        let viewer = null;

        function post(type, message) {
          try {
            window.webkit.messageHandlers.sitesincViewer.postMessage({ type: type, message: message || '' });
          } catch (e) {}
        }

        function setOverlay(text, hide) {
          var el = document.getElementById('overlay');
          if (!el) return;
          if (hide) { el.classList.add('hidden'); return; }
          el.classList.remove('hidden');
          el.textContent = text || '';
        }

        function loadDocument(fileUrn) {
          return new Promise(function (resolve, reject) {
            Autodesk.Viewing.Document.load('urn:' + fileUrn, function (doc) {
              var viewables = doc.getRoot().getDefaultGeometry() || doc.getRoot();
              if (!viewables) {
                reject(new Error('No viewable content found in translated model.'));
                return;
              }
              viewer.loadDocumentNode(doc, viewables).then(resolve).catch(reject);
            }, function (err) {
              reject(new Error('Document.load failed: ' + (err && err.message ? err.message : err)));
            });
          });
        }

        window.__startSiteSincViewer = async function (cfg) {
          try {
            if (!window.Autodesk || !Autodesk.Viewing) {
              throw new Error('Autodesk Viewer script failed to load.');
            }

            setOverlay('Initializing viewer…');
            post('status', 'Initializing viewer…');

            await new Promise(function (resolve) {
              Autodesk.Viewing.Initializer({
                env: 'AutodeskProduction',
                api: 'modelDerivativeV2',
                getAccessToken: function (cb) { cb(cfg.accessToken, 3600); }
              }, function () {
                if (viewer) {
                  try { viewer.finish(); } catch (e) {}
                  viewer = null;
                }
                viewer = new Autodesk.Viewing.GuiViewer3D(document.getElementById('viewer'));
                viewer.start();
                resolve();
              });
            });

            setOverlay('Loading model…');
            post('status', 'Loading model…');
            await loadDocument(cfg.urn);
            setOverlay('', true);
            post('ready', '');
          } catch (err) {
            var msg = (err && err.message) ? err.message : String(err);
            setOverlay(msg);
            post('error', msg);
          }
        };
      </script>
    </body>
    </html>
    """
}
