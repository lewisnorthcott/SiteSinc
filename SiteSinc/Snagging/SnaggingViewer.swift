import SwiftUI
import PDFKit

struct SnaggingViewer: View {
    let projectId: Int
    let token: String
    let drawing: Drawing
    let drawingFileId: Int

    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @EnvironmentObject var sessionManager: SessionManager

    @State private var pdfURL: URL?
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var pageIndex: Int = 0
    @State private var pdfViewRef: PDFView? = nil
    @State private var snags: [APIClient.Snag] = []
    @State private var creatingPin: CGPoint? = nil
    @State private var creatingPage: Int = 1
    @State private var newTitle: String = ""
    @State private var newDescription: String = ""
    @State private var showCreateSheet: Bool = false

    var canCreateSnags: Bool {
        sessionManager.hasPermission("snag_manager") || sessionManager.hasPermission("create_snags")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url = pdfURL {
                GeometryReader { geo in
                    ZStack {
                        PDFRepresentedView(url: url, pageIndex: $pageIndex, onCreated: { view in
                            // Avoid modifying state during view update
                            DispatchQueue.main.async { self.pdfViewRef = view }
                        }, onTap: handleTap)
                        pinOverlay.zIndex(1)
                    }
                    .contentShape(Rectangle())
                }
            } else if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }

            if canCreateSnags {
                Button(action: { creatingPin = nil; showCreateSheet = false }) {
                    Image(systemName: "mappin")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(8)
            }
        }
        .navigationTitle(drawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPDFAndSnags() }
        .sheet(isPresented: $showCreateSheet) { createSnagSheet }
    }

    private var pinOverlay: some View {
        ZStack {
            // Existing snags
            ForEach(snags, id: \.id) { snag in
                SnagPinView(position: snag.position, pdfView: pdfViewRef, color: snagColor(for: snag))
            }
            // New pin preview
            if let creatingPin = creatingPin, let pdfView = pdfViewRef, let page = pdfView.document?.page(at: pageIndex) {
                let pdfPoint = pdfView.convert(creatingPin, to: page)
                let position = APIClient.SnagPosition(x: Double(pdfPoint.x), y: Double(pdfPoint.y), page: pageIndex + 1)
                SnagPinView(position: position, pdfView: pdfViewRef, color: .blue)
            }
        }
        .allowsHitTesting(false)
    }

    private func snagColor(for snag: APIClient.Snag) -> Color {
        switch snag.status.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .yellow
        case "CLOSED": return .green
        default: return .gray
        }
    }

    private func handleTap(location: CGPoint) {
        // Ensure current page exists without binding it (silences unused variable warning)
        guard canCreateSnags, let pdfView = pdfViewRef, pdfView.document?.page(at: pageIndex) != nil else { return }
        creatingPin = location
        creatingPage = pageIndex + 1
        showCreateSheet = true
    }

    private var createSnagSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Snag Details")) {
                    TextField("Title", text: $newTitle)
                    TextField("Description", text: $newDescription, axis: .vertical)
                }
                if let creatingPin = creatingPin, let pdfView = pdfViewRef, let page = pdfView.document?.page(at: pageIndex) {
                    let pdfPoint = pdfView.convert(creatingPin, to: page)
                    Section(header: Text("Location")) {
                        Text("Page: \(creatingPage)")
                        Text(String(format: "x: %.1f, y: %.1f", pdfPoint.x, pdfPoint.y))
                    }
                }
            }
            .navigationTitle("New Snag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateSheet = false; creatingPin = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await createSnag() } }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func loadPDFAndSnags() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            // Try offline path first (project offline cache)
            if let localURL = try findOfflinePDF() {
                await MainActor.run { self.pdfURL = localURL }
            } else {
                let url = try await APIClient.fetchDrawingPDFViaProxy(drawingFileId: drawingFileId, token: token)
                await MainActor.run { self.pdfURL = url }
            }
            // Fetch with file filter and without, then merge unique by id
            async let withFileTask = APIClient.fetchSnagsForDrawing(projectId: projectId, drawingId: drawing.id, drawingFileId: drawingFileId, page: nil, token: token)
            async let withoutFileTask = APIClient.fetchSnagsForDrawing(projectId: projectId, drawingId: drawing.id, drawingFileId: nil, page: nil, token: token)
            var combined: [APIClient.Snag] = []
            do {
                let (withFile, withoutFile) = try await (withFileTask, withoutFileTask)
                var seen: Set<Int> = []
                for s in (withFile + withoutFile) {
                    if !seen.contains(s.id) { combined.append(s); seen.insert(s.id) }
                }
            } catch {
                // If one fails, try the other
                do { combined = try await withFileTask } catch { combined = try await withoutFileTask }
            }
            print("SnaggingViewer: fetched snags merged count=\(combined.count) for drawingId=\(drawing.id), fileId=\(drawingFileId)")
            await MainActor.run { self.snags = combined; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    private func findOfflinePDF() throws -> URL? {
        // Match ProjectSummaryView offline storage
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // try to find by file name in cached drawings folder if present
        if let pdfFile = drawing.revisions
            .flatMap({ $0.drawingFiles })
            .first(where: { $0.id == drawingFileId }) {
            let local = documentsDirectory.appendingPathComponent("Project_\(projectId)/drawings/\(pdfFile.fileName)")
            if FileManager.default.fileExists(atPath: local.path) { return local }
        }
        return nil
    }

    private func createSnag() async {
        guard let pdfView = pdfViewRef, let page = pdfView.document?.page(at: pageIndex), let creatingPin = creatingPin else { return }
        let pdfPoint = pdfView.convert(creatingPin, to: page)
        let position = APIClient.SnagPosition(x: Double(pdfPoint.x), y: Double(pdfPoint.y), page: creatingPage)
        do {
            let created = try await APIClient.createSnag(
                projectId: projectId,
                drawingId: drawing.id,
                drawingFileId: drawingFileId,
                page: creatingPage,
                position: position,
                title: newTitle,
                description: newDescription,
                companyIds: [],
                priority: "medium",
                status: "OPEN",
                responseDate: nil,
                photos: [],
                token: token
            )
            await MainActor.run {
                self.snags.append(created)
                self.newTitle = ""
                self.newDescription = ""
                self.creatingPin = nil
                self.showCreateSheet = false
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}

private struct PDFRepresentedView: UIViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int
    var onCreated: ((PDFView) -> Void)? = nil
    var onTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        if let page = view.document?.page(at: pageIndex) { view.go(to: page) }
        onCreated?(view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let current = uiView.currentPage, uiView.document?.index(for: current) != pageIndex {
            if let page = uiView.document?.page(at: pageIndex) { uiView.go(to: page) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        let parent: PDFRepresentedView
        init(_ parent: PDFRepresentedView) { self.parent = parent }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let point = gesture.location(in: view)
            parent.onTap?(point)
        }
    }
}

private struct SnagPinView: View {
    let position: APIClient.SnagPosition
    let pdfView: PDFView?
    let color: Color

    var body: some View {
        GeometryReader { _ in
            if let pdfView = pdfView, let page = pdfView.document?.page(at: max(0, position.page - 1)) {
                let viewPoint = pdfView.convert(CGPoint(x: position.x, y: position.y), from: page)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
                    .position(x: viewPoint.x, y: viewPoint.y)
            }
        }
        .allowsHitTesting(false)
    }
}


