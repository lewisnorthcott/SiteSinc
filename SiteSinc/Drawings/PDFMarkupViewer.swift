import SwiftUI
import PDFKit

// A SwiftUI PDF viewer with an overlay for drawing and showing markups
struct PDFMarkupViewer: View {
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    let pdfURL: URL
    let drawingId: Int
    let drawingFileId: Int
    let token: String
    let initialPage: Int
    var onMarkupUIActiveChange: ((Bool) -> Void)? = nil
    var onCreateRfiFromMarkup: ((Markup, Data?) -> Void)? = nil

    @State private var pdfDocument: PDFDocument?
    @State private var pdfViewRef: PDFView? = nil
    @State private var pageIndex: Int
    @State private var zoomScale: CGFloat = 1
    @State private var markups: [Markup] = []
    @State private var references: [DrawingReference] = []
    @State private var showMarkups: Bool = false
    @State private var showToolbar: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var activeTool: MarkupType? = nil
    @State private var draftBounds: CGRect? = nil
    @State private var dragStart: CGPoint? = nil

    init(pdfURL: URL, drawingId: Int, drawingFileId: Int, token: String, page: Int, onMarkupUIActiveChange: ((Bool) -> Void)? = nil, onCreateRfiFromMarkup: ((Markup, Data?) -> Void)? = nil) {
        self.pdfURL = pdfURL
        self.drawingId = drawingId
        self.drawingFileId = drawingFileId
        self.token = token
        self.initialPage = max(1, page)
        self.onMarkupUIActiveChange = onMarkupUIActiveChange
        self.onCreateRfiFromMarkup = onCreateRfiFromMarkup
        _pageIndex = State(initialValue: max(0, page - 1))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    if let document = pdfDocument, let page = document.page(at: pageIndex) {
                        PDFKitRepresentedView(document: document, pageIndex: $pageIndex, zoomScale: $zoomScale, onCreated: { view in
                            // Defer state update to avoid modifying state during view update
                            DispatchQueue.main.async {
                                self.pdfViewRef = view
                            }
                        })
                            .overlay(
                                ZStack {
                                    // Reference overlay
                                    ReferencesOverlayView(
                                        page: page,
                                        references: references.filter { ($0.bounds?.page ?? $0.page ?? 0) == pageIndex + 1 },
                                        pdfView: pdfViewRef
                                    )
                                    // Markup overlay
                                    Group {
                                        if showMarkups {
                                            MarkupsCanvasView(
                                                page: page,
                                                markups: markups.filter { ($0.bounds.page) == pageIndex + 1 || ($0.page == pageIndex + 1) },
                                                draftBounds: draftBounds,
                                                zoomScale: zoomScale,
                                                pdfView: pdfViewRef,
                                                onTapMarkup: { m, snapshot in
                                                    // Only allow creating RFI from CLOUD markups (draft or published)
                                                    if m.markupType == .CLOUD {
                                                        onCreateRfiFromMarkup?(m, snapshot)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }
                            )
                            .overlay(
                                Group {
                                    if activeTool != nil {
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .gesture(drawingGesture(in: page))
                                    }
                                }
                            )
                    } else if isLoading {
                        ProgressView()
                    } else if let error = error {
                        Text(error).foregroundColor(.red).padding()
                    }
                }
            }

            if showToolbar {
                toolsBar
                    .padding(8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // Compact reveal button
                Button(action: { withAnimation(.easeInOut) { showToolbar = true } }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 2)
                }
                .padding(8)
                .accessibilityLabel("Show markup tools")
            }
        }
        .onAppear {
            loadDocument()
            Task { await fetchMarkups() }
            Task { await fetchReferences() }
            onMarkupUIActiveChange?(showToolbar || activeTool != nil)
            // Attempt to flush any pending markups for this drawing/file
            if networkStatusManager.isNetworkAvailable {
                Task { await MarkupSyncManager.shared.syncPendingMarkups(drawingId: drawingId, drawingFileId: drawingFileId, token: token, onEachSuccess: { created in
                    if let idx = self.markups.firstIndex(where: { $0.status == "DRAFT" && $0.bounds.page == created.bounds.page }) {
                        self.markups[idx] = created
                    } else {
                        self.markups.append(created)
                    }
                    saveMarkupsToCache(self.markups)
                }) }
            }
        }
        .onChange(of: showToolbar) { _, newValue in
            onMarkupUIActiveChange?(newValue || activeTool != nil)
        }
        .onChange(of: activeTool) { _, newTool in
            onMarkupUIActiveChange?(showToolbar || newTool != nil)
        }
        .onChange(of: networkStatusManager.isNetworkAvailable) { _, isOnline in
            if isOnline {
                Task { await MarkupSyncManager.shared.syncPendingMarkups(drawingId: drawingId, drawingFileId: drawingFileId, token: token, onEachSuccess: { created in
                    if let idx = self.markups.firstIndex(where: { $0.status == "DRAFT" && $0.bounds.page == created.bounds.page }) {
                        self.markups[idx] = created
                    } else {
                        self.markups.append(created)
                    }
                    saveMarkupsToCache(self.markups)
                }) }
            }
        }
    }

    private var toolsBar: some View {
        HStack(spacing: 6) {
            // Hide toolbar
            Button(action: { withAnimation(.easeInOut) { showToolbar = false } }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 16)
            Button(action: { showMarkups.toggle() }) {
                Image(systemName: showMarkups ? "eye" : "eye.slash")
                    .foregroundColor(showMarkups ? .primary : .secondary)
            }
            Divider().frame(height: 16)
            toolButton(.HIGHLIGHT, system: "highlighter")
            toolButton(.RECTANGLE, system: "square")
            toolButton(.CIRCLE, system: "circle")
            toolButton(.ARROW, system: "arrow.right")
            toolButton(.LINE, system: "minus")
            toolButton(.TEXT_NOTE, system: "text.justify")
            toolButton(.CLOUD, system: "cloud")
            if activeTool != nil {
                Button(action: { activeTool = nil; draftBounds = nil; dragStart = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func toolButton(_ type: MarkupType, system: String) -> some View {
        Button(action: { activeTool = (activeTool == type ? nil : type) }) {
            Image(systemName: system)
                .foregroundColor(activeTool == type ? .white : .primary)
                .padding(6)
                .background(activeTool == type ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
    }

    private func loadDocument() {
        isLoading = true
        error = nil
        let doc = PDFDocument(url: pdfURL)
        pdfDocument = doc
        if let pageCount = doc?.pageCount, pageIndex >= pageCount { pageIndex = max(0, pageCount - 1) }
        isLoading = false
    }

    private func fetchMarkups() async {
        do {
            let fetched = try await APIClient.fetchDrawingMarkups(
                drawingId: drawingId,
                drawingFileId: drawingFileId,
                page: nil,
                token: token,
                showPublishedOnly: false,
                showMyMarkupsOnly: false
            )
            await MainActor.run { self.markups = fetched }
            saveMarkupsToCache(fetched)
        } catch {
            if let cached = loadMarkupsFromCache() {
                await MainActor.run { self.markups = cached }
            } else {
                await MainActor.run { self.error = "Failed to load markups" }
            }
        }
    }

    private func fetchReferences() async {
        do {
            let refs = try await APIClient.fetchDrawingReferences(drawingId: drawingId, fileId: drawingFileId, token: token)
            await MainActor.run { self.references = refs }
            saveReferencesToCache(refs)
        } catch {
            if let cached = loadReferencesFromCache() {
                await MainActor.run { self.references = cached }
            }
        }
    }

    // MARK: - Simple Cache for Markups/References
    private var cacheBaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private func markupsCacheURL() -> URL { cacheBaseURL.appendingPathComponent("markups_d\(drawingId)_f\(drawingFileId).json") }
    private func referencesCacheURL() -> URL { cacheBaseURL.appendingPathComponent("references_d\(drawingId)_f\(drawingFileId).json") }

    private func saveMarkupsToCache(_ markups: [Markup]) {
        if let data = try? JSONEncoder().encode(markups) { try? data.write(to: markupsCacheURL()) }
    }
    private func loadMarkupsFromCache() -> [Markup]? {
        guard let data = try? Data(contentsOf: markupsCacheURL()) else { return nil }
        return try? JSONDecoder().decode([Markup].self, from: data)
    }
    private func saveReferencesToCache(_ refs: [DrawingReference]) {
        if let data = try? JSONEncoder().encode(refs) { try? data.write(to: referencesCacheURL()) }
    }
    private func loadReferencesFromCache() -> [DrawingReference]? {
        guard let data = try? Data(contentsOf: referencesCacheURL()) else { return nil }
        return try? JSONDecoder().decode([DrawingReference].self, from: data)
    }

    private func drawingGesture(in page: PDFPage) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard activeTool != nil else { return }
                let location = value.location
                if dragStart == nil { dragStart = location }
                if let start = dragStart {
                    draftBounds = CGRect(x: min(start.x, location.x),
                                         y: min(start.y, location.y),
                                         width: abs(location.x - start.x),
                                         height: abs(location.y - start.y))
                }
            }
            .onEnded { value in
                guard let tool = activeTool, let start = dragStart else { draftBounds = nil; dragStart = nil; return }
                // Convert view points to PDF coordinates using PDFView
                let end = value.location
                if let pdfView = pdfViewRef {
                    let p1 = pdfView.convert(start, to: page)
                    let p2 = pdfView.convert(end, to: page)
                    let isLineLike = (tool == .LINE || tool == .ARROW)
                    var x1 = Double(p1.x)
                    var y1 = Double(p1.y)
                    var x2 = Double(p2.x)
                    var y2 = Double(p2.y)
                    // Preserve direction for line/arrow; normalize only for area shapes
                    if !isLineLike {
                        let nx1 = min(x1, x2), ny1 = min(y1, y2), nx2 = max(x1, x2), ny2 = max(y1, y2)
                        x1 = nx1; y1 = ny1; x2 = nx2; y2 = ny2
                    }
                    let bounds = MarkupBounds(x1: x1, y1: y1, x2: x2, y2: y2, page: pageIndex + 1)
                    // Optimistic local insert so it appears immediately
                    let optimistic = Markup(
                        id: Int(Date().timeIntervalSince1970 * 1000),
                        drawingId: drawingId,
                        drawingFileId: drawingFileId,
                        page: pageIndex + 1,
                        markupType: tool,
                        bounds: bounds,
                        content: tool == .TEXT_NOTE ? "" : nil,
                        color: "#FF0000",
                        opacity: 0.5,
                        strokeWidth: 2,
                        title: nil,
                        description: nil,
                        status: "DRAFT",
                        groupId: nil,
                        groupTitle: nil,
                        createdAt: nil,
                        createdBy: nil
                    )
                    // Append optimistically on main thread without making the gesture closure async
                    DispatchQueue.main.async {
                        self.markups.append(optimistic)
                    }
                    // Then persist to server and replace with real one when returned
                    Task {
                        await createMarkup(bounds: bounds, type: tool)
                    }
                }
                draftBounds = nil
                dragStart = nil
                activeTool = nil
            }
    }

    private func createMarkup(bounds: MarkupBounds, type: MarkupType) async {
        // Ensure minimum size similar to backend rules
        let minWidth = max(1.0, abs(bounds.x2 - bounds.x1))
        let minHeight = max(1.0, abs(bounds.y2 - bounds.y1))
        var adjusted = bounds
        if minWidth < 1.0 { adjusted.x2 = adjusted.x1 + 1.0 }
        if minHeight < 1.0 { adjusted.y2 = adjusted.y1 + 1.0 }

        let body = CreateMarkupRequest(
            drawingId: drawingId,
            drawingFileId: drawingFileId,
            page: adjusted.page,
            markupType: type,
            bounds: adjusted,
            content: type == .TEXT_NOTE ? "" : nil,
            color: "#FF0000",
            opacity: 0.5,
            strokeWidth: 2,
            title: nil,
            description: nil
        )
        do {
            let created = try await APIClient.createMarkup(token: token, body: body)
            await MainActor.run {
                if let idx = self.markups.lastIndex(where: { $0.status == "DRAFT" && Int($0.createdAt ?? "0") == nil && $0.bounds.page == created.bounds.page }) {
                    self.markups[idx] = created
                } else {
                    self.markups.append(created)
                }
            }
            saveMarkupsToCache(self.markups)
        } catch {
            // Queue for later sync and keep optimistic
            MarkupSyncManager.shared.enqueue(body: body)
            await MainActor.run { self.error = nil }
        }
    }
}

// MARK: - PDFKit UIViewRepresentable

private struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    @Binding var zoomScale: CGFloat
    var onCreated: ((PDFView) -> Void)? = nil

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        if let page = document.page(at: pageIndex) { pdfView.go(to: page) }
        onCreated?(pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        if let current = pdfView.currentPage, document.index(for: current) != pageIndex {
            if let page = document.page(at: pageIndex) { pdfView.go(to: page) }
        }
    }
}

// MARK: - Canvas Overlay for Markups

private struct MarkupsCanvasView: View {
    let page: PDFPage
    let markups: [Markup]
    let draftBounds: CGRect?
    let zoomScale: CGFloat
    var pdfView: PDFView? = nil
    var onTapMarkup: ((Markup, Data?) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    for m in markups { draw(markup: m, in: context, size: size) }
                    if let draft = draftBounds {
                        var path = Path(roundedRect: draft, cornerRadius: 2)
                        dashedStroke(path: &path, in: context, color: .red.opacity(0.7), lineWidth: 1)
                    }
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(TapGesture().onEnded {
                        // Fallback to view center when we don't get a location from TapGesture
                        let r = geo.frame(in: .local)
                        let fallback = CGPoint(x: r.midX, y: r.midY)
                        if let hit = hitTestMarkup(at: fallback) {
                            onTapMarkup?(hit.markup, hit.snapshot)
                        }
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { value in
                        if let hit = hitTestMarkup(at: value.location) {
                            onTapMarkup?(hit.markup, hit.snapshot)
                        }
                    })
            }
        }
    }

    private func draw(markup: Markup, in context: GraphicsContext, size: CGSize) {
        guard let rect = pdfToViewRect(bounds: markup.bounds) else { return }
        let color = Color(hex: markup.color)
        switch markup.markupType {
        case .HIGHLIGHT:
            context.fill(Path(rect), with: .color(color.opacity(markup.opacity)))
        case .RECTANGLE:
            context.stroke(Path(rect), with: .color(color), lineWidth: markup.strokeWidth)
        case .CIRCLE:
            let circleRect = rect
            context.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: markup.strokeWidth)
        case .TEXT_NOTE:
            context.stroke(Path(rect), with: .color(color), lineWidth: 1)
        case .LINE, .ARROW:
            // Use original direction by converting each endpoint independently
            guard let (start, end) = pdfToViewLinePoints(bounds: markup.bounds) else { return }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: markup.strokeWidth)
            if markup.markupType == .ARROW {
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowSize: CGFloat = 8
                var arrow = Path()
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle - .pi/6), y: end.y - arrowSize * sin(angle - .pi/6)))
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle + .pi/6), y: end.y - arrowSize * sin(angle + .pi/6)))
                context.stroke(arrow, with: .color(color), lineWidth: markup.strokeWidth)
            }
        case .CLOUD:
            // Simple cloud approximation by stroking a rounded rect with dashes
            var path = Path(roundedRect: rect, cornerRadius: 10)
            dashedStroke(path: &path, in: context, color: color, lineWidth: markup.strokeWidth)
        }
    }

    // Simple dashed stroke helper for SwiftUI Canvas (no native dash in this context)
    private func dashedStroke(path: inout Path, in context: GraphicsContext, color: Color, lineWidth: Double) {
        // Render the full stroke as a faint line, then overlay dashes manually
        context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: lineWidth)
        // Note: For simplicity, not computing actual dashes here; keeping a single stroke.
    }

    private func pdfToViewRect(bounds: MarkupBounds) -> CGRect? {
        guard let pdfView = pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        let rect = CGRect(x: min(v1.x, v2.x), y: min(v1.y, v2.y), width: abs(v2.x - v1.x), height: abs(v2.y - v1.y))
        return rect
    }

    private func pdfToViewLinePoints(bounds: MarkupBounds) -> (CGPoint, CGPoint)? {
        guard let pdfView = pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return (v1, v2)
    }

    private func hitTestMarkup(at point: CGPoint) -> (markup: Markup, snapshot: Data?)? {
        // Check CLOUD markups first
        for m in markups.reversed() { // topmost last
            if m.markupType != .CLOUD { continue }
            if let rect = pdfToViewRect(bounds: m.bounds), rect.insetBy(dx: -4, dy: -4).contains(point) {
                // Generate lightweight snapshot of the region
                let snapshotData = snapshotFor(rect: rect)
                return (m, snapshotData)
            }
        }
        return nil
    }

    private func snapshotFor(rect: CGRect) -> Data? {
        guard let pdfView = pdfView else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: rect)
        let image = renderer.image { ctx in
            pdfView.drawHierarchy(in: pdfView.bounds, afterScreenUpdates: false)
        }
        return image.pngData()
    }
}

// References overlay, green translucent boxes similar to web
private struct ReferencesOverlayView: View {
    let page: PDFPage
    let references: [DrawingReference]
    let pdfView: PDFView?

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                for ref in references {
                    guard let b = ref.bounds, let rect = pdfToViewRect(bounds: b) else { continue }
                    let color = Color.green.opacity(0.25)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func pdfToViewRect(bounds: MarkupBounds) -> CGRect? {
        guard let pdfView = pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return CGRect(x: min(v1.x, v2.x), y: min(v1.y, v2.y), width: abs(v2.x - v1.x), height: abs(v2.y - v1.y))
    }
}

// Color(hex:) is provided in Color+Extensions.swift


