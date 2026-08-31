import SwiftUI
import PDFKit
import QuartzCore

// A SwiftUI PDF viewer with an overlay for drawing and showing markups
struct PDFMarkupViewer: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    let pdfURL: URL
    let drawingId: Int
    let drawingFileId: Int
    let token: String
    let initialPage: Int
    let canCreateMarkups: Bool
    let canDeleteMarkups: Bool
    let canPublishMarkups: Bool
    let canViewMarkups: Bool
    var onMarkupUIActiveChange: ((Bool) -> Void)? = nil
    var onCreateRfiFromMarkup: ((Markup, Data?) -> Void)? = nil
    var searchState: PDFSearchState? = nil
    @ObservedObject var compareController: DrawingCompareController

    @State private var pdfDocument: PDFDocument?
    @State private var pdfViewRef: PDFView? = nil
    @State private var pageIndex: Int
    @State private var zoomScale: CGFloat = 1
    @State private var overlayVersion: Int = 0
    @State private var markups: [Markup] = []
    @State private var references: [DrawingReference] = []
    @State private var showPublishedOnly: Bool = false
    @State private var showDraftsOnly: Bool = false
    @State private var showMyMarkupsOnly: Bool = true  // Default to showing only user's markups
    @State private var showMarkups: Bool = false
    @State private var showToolbar: Bool = false
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var activeTool: MarkupType? = nil
    @State private var draftBounds: CGRect? = nil
    @State private var dragStart: CGPoint? = nil
    @State private var selectedMarkupId: Int? = nil
    @State private var selectedMarkupSnapshot: Data? = nil
    @State private var showMarkupsList: Bool = false
    @State private var showTextInputSheet: Bool = false
    @State private var textInput: String = ""
    @State private var textInputBounds: MarkupBounds? = nil
    @StateObject private var measurementController = PDFMeasurementController()

    init(pdfURL: URL, drawingId: Int, drawingFileId: Int, token: String, page: Int, canCreateMarkups: Bool, canDeleteMarkups: Bool, canPublishMarkups: Bool, canViewMarkups: Bool, onMarkupUIActiveChange: ((Bool) -> Void)? = nil, onCreateRfiFromMarkup: ((Markup, Data?) -> Void)? = nil, searchState: PDFSearchState? = nil, compareController: DrawingCompareController) {
        self.pdfURL = pdfURL
        self.drawingId = drawingId
        self.drawingFileId = drawingFileId
        self.token = token
        self.initialPage = max(1, page)
        self.canCreateMarkups = canCreateMarkups
        self.canDeleteMarkups = canDeleteMarkups
        self.canPublishMarkups = canPublishMarkups
        self.canViewMarkups = canViewMarkups
        self.onMarkupUIActiveChange = onMarkupUIActiveChange
        self.onCreateRfiFromMarkup = onCreateRfiFromMarkup
        self.searchState = searchState
        _compareController = ObservedObject(wrappedValue: compareController)
        _pageIndex = State(initialValue: max(0, page - 1))
    }

    private func handleTap(at location: CGPoint) {
        // Inline hit-test to avoid forward reference issues
        var found: (Markup, Data?)? = nil
        for m in self.markups.reversed() {
            switch m.markupType {
            case .LINE, .ARROW:
                if let (start, end) = self.pdfToViewLinePoints(bounds: m.bounds) {
                    let distance = self.distanceFromPoint(location, toSegmentStart: start, end: end)
                    if distance <= 10 {
                        let rect = CGRect(x: min(start.x, end.x) - 8,
                                          y: min(start.y, end.y) - 8,
                                          width: abs(end.x - start.x) + 16,
                                          height: abs(end.y - start.y) + 16)
                        found = (m, self.snapshotFor(rect: rect))
                        break
                    }
                }
            default:
                if let rect = self.pdfToViewRect(bounds: m.bounds), rect.insetBy(dx: -6, dy: -6).contains(location) {
                    found = (m, self.snapshotFor(rect: rect))
                    break
                }
            }
        }
        if let hit = found {
            selectedMarkupId = hit.0.id
            selectedMarkupSnapshot = hit.1
        } else {
            selectedMarkupId = nil
            selectedMarkupSnapshot = nil
        }
    }

    private var pageCount: Int {
        pdfDocument?.pageCount ?? 0
    }

    private func goToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        let clamped = min(max(0, index), pageCount - 1)
        guard clamped != pageIndex else { return }
        pageIndex = clamped
        selectedMarkupId = nil
        selectedMarkupSnapshot = nil
        draftBounds = nil
        dragStart = nil
        // Local measurements are page-scoped for clarity.
        measurementController.clearAll()
        measurementController.inProgressPoints = []
    }

    private var pageNavigator: some View {
        Group {
            if pageCount > 1 {
                HStack(spacing: 14) {
                    Button {
                        goToPage(pageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(pageIndex <= 0)
                    .accessibilityLabel("Previous page")

                    Text("Page \(pageIndex + 1) of \(pageCount)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("Page \(pageIndex + 1) of \(pageCount)")

                    Button {
                        goToPage(pageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(pageIndex >= pageCount - 1)
                    .accessibilityLabel("Next page")
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 2)
                .padding(.bottom, 12)
            }
        }
    }

    private var pdfContent: some View {
        if let document = pdfDocument, let page = document.page(at: pageIndex) {
            AnyView(
                PDFKitRepresentedView(document: document, pageIndex: $pageIndex, zoomScale: $zoomScale, trackViewChanges: true, onCreated: { view in
                    DispatchQueue.main.async {
                        self.pdfViewRef = view
                        self.searchState?.pdfView = view
                        self.searchState?.performSearch()
                    }
                }, onTap: { location in
                    self.handleTap(at: location)
                }, onViewChanged: {
                    DispatchQueue.main.async {
                        self.overlayVersion += 1
                    }
                })
                .overlay(compareOverlay(for: page))
                .overlay(referenceOverlay(for: page))
                .overlay(markupOverlay(for: page))
                .overlay(drawingOverlay(for: page))
                .overlay(measurementOverlay(for: page))
            )
        } else if isLoading {
            AnyView(ProgressView())
        } else if let error = error {
            AnyView(Text(error).foregroundColor(.red).padding())
        } else {
            AnyView(EmptyView())
        }
    }

    var body: some View {
        sheetWrappedCanvas
    }

    private var sheetWrappedCanvas: some View {
        applySheets(to: compareObservedCanvas)
    }

    private var compareObservedCanvas: some View {
        applyCompareObservers(to: documentObservedCanvas)
    }

    private var documentObservedCanvas: some View {
        applyDocumentObservers(to: canvasWithNavigator)
    }

    private var canvasWithNavigator: some View {
        canvasLayer
            .overlay(alignment: .bottom) { pageNavigator }
    }

    private var canvasLayer: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { _ in
                pdfContent
            }
            if !measurementController.isActive {
                toolbarLayer
                selectionBarLayer
            }
        }
    }

    @ViewBuilder
    private var toolbarLayer: some View {
        if showToolbar && !compareController.isCompareMode {
            toolsBar
                .padding(8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if !compareController.isCompareMode {
            VStack(spacing: 8) {
                if canCreateMarkups {
                    Button(action: { withAnimation(.easeInOut) { showToolbar = true } }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .accessibilityLabel("Show markup tools")
                }

                Button {
                    withAnimation(.easeInOut) {
                        showToolbar = false
                        activeTool = nil
                        selectedMarkupId = nil
                        measurementController.activate(tool: .length)
                    }
                    notifyMarkupUIActiveChange()
                } label: {
                    Image(systemName: "ruler")
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .accessibilityLabel("Measure lengths and areas")
            }
            .padding(8)
        }
    }

    private func notifyMarkupUIActiveChange() {
        onMarkupUIActiveChange?(
            showToolbar
            || activeTool != nil
            || selectedMarkupId != nil
            || measurementController.isActive
        )
    }

    @ViewBuilder
    private var selectionBarLayer: some View {
        if !compareController.isCompareMode, let selectedId = selectedMarkupId, let selected = markups.first(where: { $0.id == selectedId }) {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    selectionActionBar(for: selected)
                        .padding(8)
                        .padding(.bottom, pageCount > 1 ? 44 : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var searchMatchPageIndex: Int? {
        searchState?.currentMatchPageIndex
    }

    private func applyDocumentObservers<V: View>(to view: V) -> some View {
        view
            .onAppear(perform: handleAppear)
            .onChange(of: showToolbar) { _, _ in
                notifyMarkupUIActiveChange()
            }
            .onChange(of: activeTool) { _, _ in
                notifyMarkupUIActiveChange()
            }
            .onChange(of: selectedMarkupId) { _, _ in
                notifyMarkupUIActiveChange()
            }
            .onChange(of: measurementController.isActive) { _, isActive in
                if isActive {
                    showToolbar = false
                    activeTool = nil
                    selectedMarkupId = nil
                }
                notifyMarkupUIActiveChange()
            }
            .onChange(of: networkStatusManager.isNetworkAvailable) { _, isOnline in
                if isOnline { syncPendingMarkupsIfOnline() }
            }
            .onChange(of: pdfURL) { _, _ in handlePDFURLChange() }
            .onChange(of: drawingFileId) { _, _ in handleDrawingFileChange() }
    }

    private func applyCompareObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: pageIndex) { _, _ in
                DispatchQueue.main.async { self.recomputeCompareDiff() }
            }
            .onChange(of: searchMatchPageIndex) { _, newPage in
                if let newPage { goToPage(newPage) }
            }
            .onChange(of: compareController.isCompareMode) { _, isOn in
                handleCompareModeChange(isOn)
            }
            .onChange(of: compareController.comparisonPDFURL) { _, _ in
                DispatchQueue.main.async { self.recomputeCompareDiff() }
            }
            .onChange(of: compareController.baseIsNewer) { _, _ in
                DispatchQueue.main.async { self.recomputeCompareDiff() }
            }
    }

    private func applySheets<V: View>(to view: V) -> some View {
        view
            .sheet(isPresented: $showMarkupsList, content: { markupsListSheet })
            .sheet(isPresented: $showTextInputSheet, content: { textNoteSheet })
    }

    private var markupsListSheet: some View {
        MarkupsListSheet(
            markups: filteredMarkups(),
            canDelete: canDeleteMarkups,
            canPublishFor: { m in canPublishMarkups || m.createdBy?.id == sessionManager.user?.id },
            onPublish: { m in Task { await publishSelectedMarkup(m) } },
            onDelete: { m in Task { await deleteSelectedMarkup(m) } }
        )
    }

    private var textNoteSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add Text Note")
                    .font(.headline)
                TextField("Enter text...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTextInputSheet = false; textInput = ""; textInputBounds = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTextNote)
                        .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func handleAppear() {
        loadDocument()
        Task { await fetchMarkups() }
        Task { await fetchReferences() }
        notifyMarkupUIActiveChange()
        syncPendingMarkupsIfOnline()
    }

    private func handlePDFURLChange() {
        pdfDocument = nil
        pageIndex = 0
        zoomScale = 1
        loadDocument()
        markups = []
        references = []
        measurementController.clearAll()
        measurementController.deactivate()
        Task { await fetchMarkups() }
        Task { await fetchReferences() }
    }

    private func handleDrawingFileChange() {
        markups = []
        references = []
        measurementController.clearAll()
        measurementController.deactivate()
        Task { await fetchMarkups() }
        Task { await fetchReferences() }
    }

    private func handleCompareModeChange(_ isOn: Bool) {
        if isOn {
            showToolbar = false
            activeTool = nil
            selectedMarkupId = nil
            measurementController.deactivate()
        }
        DispatchQueue.main.async {
            if isOn {
                self.recomputeCompareDiff()
            } else {
                self.compareController.clearOverlay()
            }
        }
    }

    private func syncPendingMarkupsIfOnline() {
        guard networkStatusManager.isNetworkAvailable else { return }
        Task {
            await MarkupSyncManager.shared.syncPendingMarkups(
                drawingId: drawingId,
                drawingFileId: drawingFileId,
                token: token,
                onEachSuccess: { created in
                    self.applyCreatedMarkup(created)
                    self.saveMarkupsToCache(self.markups)
                }
            )
        }
    }

    private func saveTextNote() {
        guard let bounds = textInputBounds else {
            showTextInputSheet = false
            return
        }
        let optimistic = Markup(
            id: Int(Date().timeIntervalSince1970 * 1000),
            drawingId: drawingId,
            drawingFileId: drawingFileId,
            page: pageIndex + 1,
            markupType: .TEXT_NOTE,
            bounds: bounds,
            content: textInput,
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
        markups.append(optimistic)
        showTextInputSheet = false
        let content = textInput
        textInput = ""
        textInputBounds = nil
        Task { await createMarkup(bounds: bounds, type: .TEXT_NOTE, content: content, optimisticId: optimistic.id) }
    }

    private func selectionActionBar(for markup: Markup) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Create RFI (only for CLOUD markups that are not published)
                if markup.markupType == .CLOUD && (markup.status ?? "").uppercased() != "PUBLISHED" {
                    Button(action: {
                        onCreateRfiFromMarkup?(markup, selectedMarkupSnapshot)
                    }) {
                        Label("Create RFI", systemImage: "doc.append")
                    }
                    .buttonStyle(.bordered)
                }

                // Publish
                if canPublishMarkups {
                    Button(action: {
                        Task { await publishSelectedMarkup(markup) }
                    }) {
                        Label("Publish", systemImage: "cloud.upload")
                    }
                    .buttonStyle(.bordered)
                    .disabled((markup.status ?? "").uppercased() == "PUBLISHED" || !networkStatusManager.isNetworkAvailable)
                }

                // Delete (only for non-published)
                if canDeleteMarkups && (markup.status ?? "DRAFT").uppercased() != "PUBLISHED" {
                    Button(role: .destructive, action: {
                        Task { await deleteSelectedMarkup(markup) }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // Show published status indicator
            if (markup.status ?? "").uppercased() == "PUBLISHED" {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Published")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
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
            Button(action: { showMarkupsList = true }) {
                Image(systemName: "list.bullet")
                    .foregroundColor(.primary)
            }
            // Filters menu
            Menu {
                Button(action: { 
                    showPublishedOnly = false
                    showDraftsOnly = false
                    showMyMarkupsOnly = true  // Default: user's drafts + all published
                    Task { await fetchMarkups() }
                }) {
                    Label("Default (My Drafts + All Published)", systemImage: "eye")
                }
                Button(action: { 
                    showPublishedOnly = true
                    showDraftsOnly = false
                    showMyMarkupsOnly = false  // Show all published markups
                    Task { await fetchMarkups() }
                }) {
                    Label("Published Only", systemImage: "checkmark.circle")
                }
                Button(action: { 
                    showPublishedOnly = false
                    showDraftsOnly = true
                    showMyMarkupsOnly = true  // Show only user's drafts
                    Task { await fetchMarkups() }
                }) {
                    Label("My Drafts Only", systemImage: "pencil")
                }
                Button(action: { 
                    showPublishedOnly = false
                    showDraftsOnly = false
                    showMyMarkupsOnly = false  // Show all markups (admin view)
                    Task { await fetchMarkups() }
                }) {
                    Label("All Markups", systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 16)
            Button {
                withAnimation(.easeInOut) {
                    showToolbar = false
                    activeTool = nil
                    selectedMarkupId = nil
                    measurementController.activate(tool: .length)
                }
                notifyMarkupUIActiveChange()
            } label: {
                Image(systemName: "ruler")
                    .foregroundColor(.primary)
            }
            .accessibilityLabel("Measure lengths and areas")
            if canCreateMarkups && selectedMarkupId == nil {
                toolButton(.HIGHLIGHT, system: "highlighter")
                toolButton(.RECTANGLE, system: "square")
                toolButton(.CIRCLE, system: "circle")
                toolButton(.ARROW, system: "arrow.right")
                toolButton(.LINE, system: "minus")
                toolButton(.TEXT_NOTE, system: "text.justify")
                toolButton(.CLOUD, system: "cloud")
            }
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
        // Re-run any active search against the freshly loaded document.
        DispatchQueue.main.async {
            if let view = self.pdfViewRef { self.searchState?.pdfView = view }
            self.searchState?.performSearch()
            self.recomputeCompareDiff()
        }
    }

    private func recomputeCompareDiff() {
        guard compareController.isCompareMode,
              let comparisonURL = compareController.comparisonPDFURL else {
            compareController.assignIfNeeded(\.isComputingDiff, false)
            if !compareController.isCompareMode {
                compareController.clearOverlay()
            }
            return
        }

        let token = UUID()
        compareController.computeGeneration = token
        let baseURL = pdfURL
        let currentPageIndex = pageIndex
        let baseIsNewer = compareController.baseIsNewer
        let controller = compareController
        compareController.assignIfNeeded(\.isComputingDiff, true)
        compareController.assignIfNeeded(\.pageNumber, currentPageIndex + 1)

        Task.detached(priority: .userInitiated) {
            let result = PdfCompareDiff.diffPages(
                baseURL: baseURL,
                comparisonURL: comparisonURL,
                pageIndex: currentPageIndex,
                baseIsNewer: baseIsNewer
            )
            await MainActor.run {
                guard controller.computeGeneration == token else { return }
                controller.assignIfNeeded(\.isComputingDiff, false)
                if result == nil {
                    controller.clearOverlay()
                    controller.comparisonError = "This revision has no matching page to compare."
                } else {
                    controller.apply(result: result, pageIndex: currentPageIndex)
                }
            }
        }
    }

    private func fetchMarkups() async {
        do {
            let effectiveShowPublishedOnly: Bool? = {
                if showPublishedOnly { return true }
                if showDraftsOnly { return false }
                // Default: show published to all, drafts only to creator
                return nil
            }()
            
            let effectiveShowMyMarkupsOnly: Bool? = {
                if showMyMarkupsOnly { return true }
                if showPublishedOnly { return false }  // When showing published only, show all users
                // Default: show user's drafts + all published
                return nil
            }()
            
            let fetched = try await APIClient.fetchDrawingMarkups(
                drawingId: drawingId,
                drawingFileId: drawingFileId,
                page: nil,
                token: token,
                showPublishedOnly: effectiveShowPublishedOnly,
                showMyMarkupsOnly: effectiveShowMyMarkupsOnly
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

    private func filteredMarkups() -> [Markup] {
        // Always scope to the current revision's file id to avoid cross-revision bleed
        var items = markups.filter { $0.drawingFileId == drawingFileId }
        if showPublishedOnly {
            items = items.filter { ($0.status ?? "").uppercased() == "PUBLISHED" }
        } else if showDraftsOnly {
            items = items.filter { ($0.status ?? "DRAFT").uppercased() != "PUBLISHED" }
        }
        return items
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
                // Don't allow drawing when a published markup is selected
                if let selectedId = selectedMarkupId,
                   let selectedMarkup = markups.first(where: { $0.id == selectedId }),
                   (selectedMarkup.status ?? "").uppercased() == "PUBLISHED" {
                    return
                }
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
                // Don't allow drawing when a published markup is selected
                if let selectedId = selectedMarkupId,
                   let selectedMarkup = markups.first(where: { $0.id == selectedId }),
                   (selectedMarkup.status ?? "").uppercased() == "PUBLISHED" {
                    draftBounds = nil
                    dragStart = nil
                    activeTool = nil
                    return
                }
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
                    if tool == .TEXT_NOTE {
                        // For text, open input sheet rather than drawing immediately
                        self.textInputBounds = bounds
                        self.textInput = ""
                        self.showTextInputSheet = true
                    } else {
                        // Optimistic local insert so it appears immediately
                        let optimistic = Markup(
                            id: Int(Date().timeIntervalSince1970 * 1000),
                            drawingId: drawingId,
                            drawingFileId: drawingFileId,
                            page: pageIndex + 1,
                            markupType: tool,
                            bounds: bounds,
                            content: nil,
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
                        self.markups.append(optimistic)
                        // Then persist to server and replace with real one when returned
                        Task {
                            await createMarkup(bounds: bounds, type: tool, optimisticId: optimistic.id)
                        }
                    }
                }
                draftBounds = nil
                dragStart = nil
                activeTool = nil
            }
    }

    private static let localMarkupIdThreshold = 1_000_000_000_000

    private func isLocalMarkupId(_ id: Int) -> Bool {
        id >= Self.localMarkupIdThreshold
    }

    private func markupsMatch(_ lhs: Markup, _ rhs: Markup) -> Bool {
        lhs.markupType == rhs.markupType && lhs.bounds.isApproximatelyEqual(to: rhs.bounds)
    }

    private func applyCreatedMarkup(_ created: Markup, replacing optimisticId: Int? = nil) {
        if let optimisticId, let idx = markups.firstIndex(where: { $0.id == optimisticId }) {
            markups[idx] = created
            if selectedMarkupId == optimisticId {
                selectedMarkupId = created.id
            }
            return
        }
        if let idx = markups.firstIndex(where: { isLocalMarkupId($0.id) && markupsMatch($0, created) }) {
            let oldId = markups[idx].id
            markups[idx] = created
            if selectedMarkupId == oldId {
                selectedMarkupId = created.id
            }
            return
        }
        if !markups.contains(where: { $0.id == created.id }) {
            markups.append(created)
        }
    }

    private func removeMarkupAndDuplicates(_ markup: Markup, extraIds: [Int] = []) {
        let extra = Set(extraIds)
        markups.removeAll { m in
            m.id == markup.id
                || extra.contains(m.id)
                || (isLocalMarkupId(m.id) && markupsMatch(m, markup))
        }
        if let selected = selectedMarkupId, !markups.contains(where: { $0.id == selected }) {
            selectedMarkupId = nil
            selectedMarkupSnapshot = nil
        }
    }

    private func createMarkup(bounds: MarkupBounds, type: MarkupType, content: String? = nil, optimisticId: Int? = nil) async {
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
            content: content ?? (type == .TEXT_NOTE ? "" : nil),
            color: "#FF0000",
            opacity: 0.5,
            strokeWidth: 2,
            title: nil,
            description: nil
        )
        do {
            let created = try await APIClient.createMarkup(token: token, body: body)
            await MainActor.run {
                self.applyCreatedMarkup(created, replacing: optimisticId)
                self.saveMarkupsToCache(self.markups)
            }
        } catch APIError.tokenExpired {
            await MainActor.run { self.error = "Session expired. Please log in again." }
        } catch APIError.forbidden {
            await MainActor.run { self.error = "Session expired. Please log in again." }
        } catch {
            // Queue for later sync and keep optimistic
            MarkupSyncManager.shared.enqueue(body: body)
            await MainActor.run { self.error = nil }
        }
    }

    private func deleteSelectedMarkup(_ markup: Markup) async {
        let serverDuplicate = markups.first { !isLocalMarkupId($0.id) && $0.id != markup.id && markupsMatch($0, markup) }
        let serverId: Int? = isLocalMarkupId(markup.id) ? serverDuplicate?.id : markup.id

        guard let serverId else {
            MarkupSyncManager.shared.dequeueMatching(
                drawingId: drawingId,
                drawingFileId: drawingFileId,
                page: markup.bounds.page,
                markupType: markup.markupType,
                bounds: markup.bounds
            )
            await MainActor.run {
                self.removeMarkupAndDuplicates(markup)
                self.saveMarkupsToCache(self.markups)
            }
            return
        }

        do {
            try await APIClient.deleteMarkup(token: token, markupId: serverId)
            await MainActor.run {
                self.removeMarkupAndDuplicates(markup, extraIds: [serverId])
                self.saveMarkupsToCache(self.markups)
            }
            await fetchMarkups()
        } catch APIError.invalidResponse(let code) where code == 400 || code == 404 {
            await MainActor.run {
                self.removeMarkupAndDuplicates(markup, extraIds: [serverId])
                self.saveMarkupsToCache(self.markups)
            }
        } catch APIError.badRequest {
            await MainActor.run {
                self.removeMarkupAndDuplicates(markup, extraIds: [serverId])
                self.saveMarkupsToCache(self.markups)
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to delete markup. Please try again."
            }
        }
    }

    private func publishSelectedMarkup(_ markup: Markup) async {
        do {
            let updated = try await APIClient.publishMarkup(token: token, markupId: markup.id)
            await MainActor.run {
                if let idx = self.markups.firstIndex(where: { $0.id == markup.id }) {
                    if let updated = updated {
                        self.markups[idx] = updated
                    } else {
                        // No payload returned; mark as published locally
                        let original = self.markups[idx]
                        self.markups[idx] = Markup(
                            id: original.id,
                            drawingId: original.drawingId,
                            drawingFileId: original.drawingFileId,
                            page: original.page,
                            markupType: original.markupType,
                            bounds: original.bounds,
                            content: original.content,
                            color: original.color,
                            opacity: original.opacity,
                            strokeWidth: original.strokeWidth,
                            title: original.title,
                            description: original.description,
                            status: "PUBLISHED",
                            groupId: original.groupId,
                            groupTitle: original.groupTitle,
                            createdAt: original.createdAt,
                            createdBy: original.createdBy
                        )
                    }
                    self.selectedMarkupId = self.markups[idx].id
                }
            }
            saveMarkupsToCache(self.markups)
            // Refresh from server to ensure consistency
            await fetchMarkups()
        } catch APIError.forbidden {
            await MainActor.run { self.error = "You don't have permission to publish this markup." }
        } catch APIError.tokenExpired {
            await MainActor.run { self.error = "Session expired. Please log in again." }
        } catch {
            await MainActor.run { self.error = "Failed to publish markup. Please try again." }
        }
    }

    // MARK: - Coordinate and utility helpers for hit-testing and snapshots
    private func pdfToViewRect(bounds: MarkupBounds) -> CGRect? {
        guard let pdfView = self.pdfViewRef, let page = pdfView.currentPage else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return CGRect(x: min(v1.x, v2.x), y: min(v1.y, v2.y), width: abs(v2.x - v1.x), height: abs(v2.y - v1.y))
    }

    private func pdfToViewLinePoints(bounds: MarkupBounds) -> (CGPoint, CGPoint)? {
        guard let pdfView = self.pdfViewRef, let page = pdfView.currentPage else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return (v1, v2)
    }

    private func snapshotFor(rect: CGRect) -> Data? {
        guard let pdfView = self.pdfViewRef else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            pdfView.layer.render(in: ctx.cgContext)
        }
        return image.pngData()
    }

    private func distanceFromPoint(_ p: CGPoint, toSegmentStart a: CGPoint, end b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        if abx == 0 && aby == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let apx = p.x - a.x
        let apy = p.y - a.y
        let t = max(0, min(1, (apx * abx + apy * aby) / (abx * abx + aby * aby)))
        let closest = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - closest.x, p.y - closest.y)
    }
}

// MARK: - Overlay Builders (extracted to help the compiler type-check faster)
private extension PDFMarkupViewer {
    @ViewBuilder
    func compareOverlay(for page: PDFPage) -> some View {
        if compareController.isCompareMode, let image = compareController.overlayImage, let pdfView = pdfViewRef {
            CompareDiffOverlayView(
                image: image,
                pdfView: pdfView,
                page: page,
                overlayVersion: overlayVersion
            )
        }
    }

    @ViewBuilder
    func referenceOverlay(for page: PDFPage) -> some View {
        if compareController.isCompareMode {
            EmptyView()
        } else {
            ZStack {
                ReferencesOverlayView(
                    page: page,
                    references: references.filter { ($0.bounds?.page ?? $0.page ?? 0) == pageIndex + 1 },
                    pdfView: pdfViewRef,
                    overlayVersion: overlayVersion
                )
            }
        }
    }

    @ViewBuilder
    func markupOverlay(for page: PDFPage) -> some View {
        Group {
            if showMarkups && !compareController.isCompareMode {
                MarkupsCanvasView(
                    page: page,
                    markups: filteredMarkups().filter { ($0.bounds.page) == pageIndex + 1 || ($0.page == pageIndex + 1) },
                    draftBounds: draftBounds,
                    zoomScale: zoomScale,
                    overlayVersion: overlayVersion,
                    pdfView: pdfViewRef,
                    selectedMarkupId: selectedMarkupId
                )
            }
        }
    }

    @ViewBuilder
    func drawingOverlay(for page: PDFPage) -> some View {
        Group {
            if activeTool != nil && !compareController.isCompareMode && !measurementController.isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawingGesture(in: page))
            }
        }
    }

    @ViewBuilder
    func measurementOverlay(for page: PDFPage) -> some View {
        if !compareController.isCompareMode {
            PDFMeasurementOverlay(
                controller: measurementController,
                page: page,
                pdfView: pdfViewRef,
                overlayVersion: overlayVersion
            )
        }
    }
}

// MARK: - PDFKit UIViewRepresentable

private struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    @Binding var zoomScale: CGFloat
    var trackViewChanges: Bool = false
    var onCreated: ((PDFView) -> Void)? = nil
    var onTap: ((CGPoint) -> Void)? = nil
    var onViewChanged: (() -> Void)? = nil

    class Coordinator: NSObject {
        var onTap: ((CGPoint) -> Void)?
        var onScale: ((CGFloat) -> Void)?
        var onViewChanged: (() -> Void)?
        var pageIndexBinding: Binding<Int>?
        var displayLink: CADisplayLink?
        weak var pdfView: PDFView?
        var lastContentOffset: CGPoint = .zero
        var lastScale: CGFloat = 1
        var trackViewChanges = false
        var isApplyingSwiftUIUpdate = false
        private var viewChangeScheduled = false
        private var pageIndexWriteScheduled = false
        private var pendingPageIndex: Int?

        func emitViewChanged() {
            guard !isApplyingSwiftUIUpdate else { return }
            scheduleViewChanged()
        }

        func scheduleViewChanged() {
            guard !viewChangeScheduled else { return }
            viewChangeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewChangeScheduled = false
                self.onViewChanged?()
            }
        }

        func schedulePageIndex(_ idx: Int) {
            guard !isApplyingSwiftUIUpdate else { return }
            pendingPageIndex = idx
            guard !pageIndexWriteScheduled else { return }
            pageIndexWriteScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pageIndexWriteScheduled = false
                guard let pending = self.pendingPageIndex else { return }
                self.pendingPageIndex = nil
                if self.pageIndexBinding?.wrappedValue != pending {
                    self.pageIndexBinding?.wrappedValue = pending
                }
            }
        }

        override init() { super.init() }
        init(onTap: ((CGPoint) -> Void)?) {
            self.onTap = onTap
        }
        @objc func didTap(_ sender: UITapGestureRecognizer) {
            let location = sender.location(in: sender.view)
            onTap?(location)
        }
        @objc func scaleChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView else { return }
            onScale?(pdfView.scaleFactor)
            emitViewChanged()
        }
        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView, let doc = pdfView.document, let page = pdfView.currentPage else { return }
            let idx = doc.index(for: page)
            schedulePageIndex(idx)
            emitViewChanged()
        }
        @objc func visiblePagesChanged(_ note: Notification) {
            emitViewChanged()
        }

        func setTracking(_ enabled: Bool, pdfView: PDFView) {
            trackViewChanges = enabled
            self.pdfView = pdfView
            if enabled {
                if displayLink == nil {
                    let link = CADisplayLink(target: self, selector: #selector(checkForChanges))
                    link.add(to: .main, forMode: .common)
                    displayLink = link
                }
            } else {
                displayLink?.invalidate()
                displayLink = nil
            }
        }

        @objc func checkForChanges() {
            guard trackViewChanges, let pdfView else { return }
            guard let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
                    ?? pdfView.documentView?.superview as? UIScrollView else { return }
            let currentOffset = scrollView.contentOffset
            let currentScale = scrollView.zoomScale
            if currentOffset != lastContentOffset || currentScale != lastScale {
                lastContentOffset = currentOffset
                lastScale = currentScale
                emitViewChanged()
            }
        }

        func stopTracking() {
            displayLink?.invalidate()
            displayLink = nil
            pdfView = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        // Keep default auto scaling behaviour for initial fit and allow pinch/pan
        pdfView.autoScales = true
        if let page = document.page(at: pageIndex) { pdfView.go(to: page) }
        // Disable long-press selection/menu so our overlay receives taps
        (pdfView.gestureRecognizers ?? []).forEach { gr in
            if gr is UILongPressGestureRecognizer { gr.isEnabled = false }
        }
        // Add tap recognizer that does not block pan/zoom
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(tap)
        // Observe scale and page changes to refresh overlays in sync with zoom/pan
        context.coordinator.pageIndexBinding = $pageIndex
        context.coordinator.onScale = { newScale in
            DispatchQueue.main.async {
                if self.zoomScale != newScale {
                    self.zoomScale = newScale
                }
            }
        }
        context.coordinator.onViewChanged = onViewChanged
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scaleChanged(_:)), name: Notification.Name.PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: Notification.Name.PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.visiblePagesChanged(_:)), name: Notification.Name.PDFViewVisiblePagesChanged, object: pdfView)
        context.coordinator.setTracking(trackViewChanges, pdfView: pdfView)
        onCreated?(pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.pageIndexBinding = $pageIndex
        context.coordinator.onViewChanged = onViewChanged
        context.coordinator.setTracking(trackViewChanges, pdfView: pdfView)
        context.coordinator.isApplyingSwiftUIUpdate = true
        if pdfView.document !== document { pdfView.document = document }
        if let current = pdfView.currentPage, document.index(for: current) != pageIndex {
            if let page = document.page(at: pageIndex) { pdfView.go(to: page) }
        }
        context.coordinator.isApplyingSwiftUIUpdate = false
        context.coordinator.scheduleViewChanged()
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.stopTracking()
        NotificationCenter.default.removeObserver(coordinator, name: Notification.Name.PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.removeObserver(coordinator, name: Notification.Name.PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.removeObserver(coordinator, name: Notification.Name.PDFViewVisiblePagesChanged, object: pdfView)
    }
}

private struct CompareDiffOverlayView: View {
    let image: UIImage
    let pdfView: PDFView
    let page: PDFPage
    let overlayVersion: Int

    var body: some View {
        let _ = overlayVersion
        GeometryReader { _ in
            let rect = pdfView.convert(page.bounds(for: .mediaBox), from: page)
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: max(0, rect.width), height: max(0, rect.height))
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Canvas Overlay for Markups

private struct MarkupsCanvasView: View {
    let page: PDFPage
    let markups: [Markup]
    let draftBounds: CGRect?
    let zoomScale: CGFloat
    let overlayVersion: Int
    var pdfView: PDFView? = nil
    var selectedMarkupId: Int? = nil

    private var pageScale: CGFloat {
        max(pdfView?.scaleFactor ?? zoomScale, 0.01)
    }

    private func scaledLineWidth(_ pagePoints: Double) -> CGFloat {
        CGFloat(pagePoints) * pageScale
    }

    var body: some View {
        let _ = overlayVersion
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    for m in markups { draw(markup: m, in: context, size: size) }
                    if let draft = draftBounds {
                        var path = Path(roundedRect: draft, cornerRadius: 2)
                        dashedStroke(path: &path, in: context, color: .red.opacity(0.7), lineWidth: scaledLineWidth(1))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(markup: Markup, in context: GraphicsContext, size: CGSize) {
        let color = Color(hex: markup.color)
        let stroke = scaledLineWidth(markup.strokeWidth)
        switch markup.markupType {
        case .HIGHLIGHT, .RECTANGLE, .CIRCLE, .TEXT_NOTE, .CLOUD:
            guard let rect = pdfToViewRect(bounds: markup.bounds) else { return }
            switch markup.markupType {
            case .HIGHLIGHT:
                context.fill(Path(rect), with: .color(color.opacity(markup.opacity)))
            case .RECTANGLE:
                context.stroke(Path(rect), with: .color(color), lineWidth: stroke)
            case .CIRCLE:
                let circleRect = rect
                context.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: stroke)
            case .TEXT_NOTE:
                context.stroke(Path(rect), with: .color(color), lineWidth: scaledLineWidth(1))
                // Render text content
                if let content = markup.content, !content.isEmpty, rect.width > 1, rect.height > 1 {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12 * pageScale),
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: paragraph
                    ]
                    // Use SwiftUI drawing to place text; create an NSAttributedString image and draw
                    let ns = NSAttributedString(string: content, attributes: attrs)
                    let renderer = UIGraphicsImageRenderer(size: rect.size)
                    let image = renderer.image { _ in
                        ns.draw(with: CGRect(origin: .zero, size: rect.size).insetBy(dx: 4 * pageScale, dy: 4 * pageScale), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    }
                    context.draw(Image(uiImage: image), in: rect)
                }
            case .CLOUD:
                // Draw a continuous scalloped cloud outline around the rect
                let targetSpacing: CGFloat = 36 * pageScale
                let bumpsTop = max(4, Int(rect.width / max(targetSpacing, 1)))
                let bumpsSide = max(4, Int(rect.height / max(targetSpacing, 1)))
                let stepX = rect.width / CGFloat(bumpsTop)
                let stepY = rect.height / CGFloat(bumpsSide)
                let r = min(stepX, stepY) * 0.55

                let bezier = cloudPath(around: rect, radius: r, bumpsTop: bumpsTop, bumpsSide: bumpsSide)
                context.stroke(Path(bezier.cgPath), with: .color(color), lineWidth: stroke)
            default: break
            }
            // Selection highlight for area-like shapes
            if let selectedId = selectedMarkupId, selectedId == markup.id {
                var highlight = Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 6)
                dashedStroke(path: &highlight, in: context, color: .orange, lineWidth: max(2, scaledLineWidth(2)))
            }
        case .LINE, .ARROW:
            guard let (start, end) = pdfToViewLinePoints(bounds: markup.bounds) else { return }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: stroke)
            if markup.markupType == .ARROW {
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowSize: CGFloat = 8 * pageScale
                var arrow = Path()
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle - .pi/6), y: end.y - arrowSize * sin(angle - .pi/6)))
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowSize * cos(angle + .pi/6), y: end.y - arrowSize * sin(angle + .pi/6)))
                context.stroke(arrow, with: .color(color), lineWidth: stroke)
            }
            if let selectedId = selectedMarkupId, selectedId == markup.id {
                var highlight = Path()
                highlight.move(to: start)
                highlight.addLine(to: end)
                context.stroke(highlight, with: .color(.orange), lineWidth: max(3, stroke + 2))
            }
        }
    }

    // Simple dashed stroke helper for SwiftUI Canvas (no native dash in this context)
    private func dashedStroke(path: inout Path, in context: GraphicsContext, color: Color, lineWidth: Double) {
        context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: lineWidth)
    }

    // Helpers to convert coordinates and hit-test from outer view
    private func pdfToViewRect(bounds: MarkupBounds) -> CGRect? {
        guard let pdfView = self.pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return CGRect(x: min(v1.x, v2.x), y: min(v1.y, v2.y), width: abs(v2.x - v1.x), height: abs(v2.y - v1.y))
    }

    private func pdfToViewLinePoints(bounds: MarkupBounds) -> (CGPoint, CGPoint)? {
        guard let pdfView = self.pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return (v1, v2)
    }

    private func snapshotFor(rect: CGRect) -> Data? {
        guard let pdfView = self.pdfView else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            pdfView.layer.render(in: ctx.cgContext)
        }
        return image.pngData()
    }

    private func distanceFromPoint(_ p: CGPoint, toSegmentStart a: CGPoint, end b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        if abx == 0 && aby == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let apx = p.x - a.x
        let apy = p.y - a.y
        let t = max(0, min(1, (apx * abx + apy * aby) / (abx * abx + aby * aby)))
        let closest = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - closest.x, p.y - closest.y)
    }

    private func hitTestMarkup(at point: CGPoint) -> (markup: Markup, snapshot: Data?)? {
        // Iterate in reverse for topmost
        for m in self.markups.reversed() {
            switch m.markupType {
            case .LINE, .ARROW:
                if let (start, end) = pdfToViewLinePoints(bounds: m.bounds) {
                    let distance = distanceFromPoint(point, toSegmentStart: start, end: end)
                    if distance <= 10 { // within 10pt tolerance
                        // Build a rect around the line for snapshot
                        let rect = CGRect(x: min(start.x, end.x) - 8,
                                          y: min(start.y, end.y) - 8,
                                          width: abs(end.x - start.x) + 16,
                                          height: abs(end.y - start.y) + 16)
                        return (m, snapshotFor(rect: rect))
                    }
                }
            default:
                if let rect = pdfToViewRect(bounds: m.bounds), rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return (m, snapshotFor(rect: rect))
                }
            }
        }
        return nil
    }
}

// MARK: - Cloud Path Helper
private func cloudPath(around rect: CGRect, radius r: CGFloat, bumpsTop: Int, bumpsSide: Int) -> UIBezierPath {
    let path = UIBezierPath()

    // Top edge (left -> right)
    let stepX = rect.width / CGFloat(bumpsTop)
    var x = rect.minX
    for i in 0..<bumpsTop {
        let cx = x + stepX * 0.5
        let cy = rect.minY
        let end = CGPoint(x: x + stepX, y: cy)
        let c1 = CGPoint(x: cx - r * 0.6, y: cy - r)
        let c2 = CGPoint(x: cx + r * 0.6, y: cy - r)
        if i == 0 {
            let start = CGPoint(x: x, y: cy)
            path.move(to: start)
        }
        path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
        x += stepX
    }

    // Right edge (top -> bottom)
    let stepY = rect.height / CGFloat(bumpsSide)
    var y = rect.minY
    for _ in 0..<bumpsSide {
        let cx = rect.maxX
        let cy = y + stepY * 0.5
        let end = CGPoint(x: cx, y: y + stepY)
        let c1 = CGPoint(x: cx + r, y: cy - r * 0.6)
        let c2 = CGPoint(x: cx + r, y: cy + r * 0.6)
        path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
        y += stepY
    }

    // Bottom edge (right -> left)
    x = rect.maxX
    for _ in 0..<bumpsTop {
        let cx = x - stepX * 0.5
        let cy = rect.maxY
        let end = CGPoint(x: x - stepX, y: cy)
        let c1 = CGPoint(x: cx + r * 0.6, y: cy + r)
        let c2 = CGPoint(x: cx - r * 0.6, y: cy + r)
        path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
        x -= stepX
    }

    // Left edge (bottom -> top)
    y = rect.maxY
    for _ in 0..<bumpsSide {
        let cx = rect.minX
        let cy = y - stepY * 0.5
        let end = CGPoint(x: cx, y: y - stepY)
        let c1 = CGPoint(x: cx - r, y: cy + r * 0.6)
        let c2 = CGPoint(x: cx - r, y: cy - r * 0.6)
        path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
        y -= stepY
    }

    path.close()
    return path
}

// References overlay, green translucent boxes similar to web
private struct ReferencesOverlayView: View {
    let page: PDFPage
    let references: [DrawingReference]
    let pdfView: PDFView?
    let overlayVersion: Int

    var body: some View {
        let _ = overlayVersion
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
        guard let pdfView = self.pdfView else { return nil }
        let p1 = CGPoint(x: bounds.x1, y: bounds.y1)
        let p2 = CGPoint(x: bounds.x2, y: bounds.y2)
        let v1 = pdfView.convert(p1, from: page)
        let v2 = pdfView.convert(p2, from: page)
        return CGRect(x: min(v1.x, v2.x), y: min(v1.y, v2.y), width: abs(v2.x - v1.x), height: abs(v2.y - v1.y))
    }
}

// Color(hex:) is provided in Color+Extensions.swift


// MARK: - Markups List Sheet
private struct MarkupsListSheet: View {
    let markups: [Markup]
    let canDelete: Bool
    var canPublishFor: ((Markup) -> Bool) = { _ in false }
    var onPublish: ((Markup) -> Void)? = nil
    var onDelete: ((Markup) -> Void)? = nil

    var body: some View {
        NavigationView {
            List(markups) { m in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: m.markupType))
                        .foregroundColor(Color(hex: m.color))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: m))
                            .font(.headline)
                        Text((m.status ?? "DRAFT").capitalized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if canPublishFor(m) {
                        Button(action: { onPublish?(m) }) {
                            Image(systemName: "cloud.upload")
                        }
                        .disabled((m.status ?? "").uppercased() == "PUBLISHED")
                    }
                    if canDelete && (m.status ?? "DRAFT").uppercased() != "PUBLISHED" {
                        Button(role: .destructive, action: { onDelete?(m) }) {
                            Image(systemName: "trash")
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .navigationTitle("Markups")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func icon(for type: MarkupType) -> String {
        switch type {
        case .HIGHLIGHT: return "highlighter"
        case .RECTANGLE: return "square"
        case .CIRCLE: return "circle"
        case .ARROW: return "arrow.right"
        case .LINE: return "minus"
        case .TEXT_NOTE: return "text.justify"
        case .CLOUD: return "cloud"
        }
    }

    private func title(for m: Markup) -> String {
        if let t = m.title, !t.isEmpty { return t }
        return m.markupType.rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

