import SwiftUI
import PDFKit

struct FormLocationPicker: View {
    let projectId: Int
    let token: String
    @Binding var locationId: Int?
    @Binding var drawingPin: FormDrawingPin?
    var disabled: Bool = false

    @State private var mode: Mode
    @State private var showPinPicker = false
    @State private var hasSystemLocations: Bool?

    enum Mode { case location, drawing }

    init(
        projectId: Int,
        token: String,
        locationId: Binding<Int?>,
        drawingPin: Binding<FormDrawingPin?>,
        disabled: Bool = false
    ) {
        self.projectId = projectId
        self.token = token
        self._locationId = locationId
        self._drawingPin = drawingPin
        self.disabled = disabled
        _mode = State(initialValue: drawingPin.wrappedValue != nil ? .drawing : .location)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Location type", selection: $mode) {
                Text("Location").tag(Mode.location)
                Text("Drawing pin").tag(Mode.drawing)
            }
            .pickerStyle(.segmented)
            .disabled(disabled)
            .onChange(of: mode) { _, newMode in
                if newMode == .location {
                    drawingPin = nil
                } else {
                    locationId = nil
                }
            }

            if mode == .location {
                if hasSystemLocations == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This project has no locations yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Pin on a drawing instead") {
                            mode = .drawing
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                } else if hasSystemLocations == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    LocationSelector(
                        projectId: projectId,
                        token: token,
                        selectedLocationId: $locationId,
                        showLabel: false
                    )
                    .disabled(disabled)
                }
            } else if let pin = drawingPin {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pin.label)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(3)
                        Button("Change pin") { showPinPicker = true }
                            .font(.subheadline.weight(.semibold))
                            .disabled(disabled)
                    }
                    Spacer(minLength: 0)
                    if !disabled {
                        Button {
                            drawingPin = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    showPinPicker = true
                } label: {
                    Label("Choose a drawing and drop a pin", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
            }
        }
        .task { await loadLocationAvailability() }
        .onChange(of: drawingPin) { _, pin in
            if pin != nil { mode = .drawing }
        }
        .onChange(of: locationId) { _, id in
            if id != nil { mode = .location }
        }
        .fullScreenCover(isPresented: $showPinPicker) {
            DrawingPinPickerView(
                projectId: projectId,
                token: token,
                initialPin: drawingPin,
                readOnly: false
            ) { pin in
                drawingPin = pin
                locationId = nil
                showPinPicker = false
            } onCancel: {
                showPinPicker = false
            }
        }
    }

    private func loadLocationAvailability() async {
        do {
            let locations = try await APIClient.fetchProjectLocations(projectId: projectId, token: token)
            await MainActor.run {
                hasSystemLocations = !locations.isEmpty
                if locations.isEmpty && drawingPin == nil && locationId == nil {
                    mode = .drawing
                }
            }
        } catch {
            await MainActor.run {
                hasSystemLocations = false
                if drawingPin == nil && locationId == nil {
                    mode = .drawing
                }
            }
        }
    }
}

struct FormDrawingPinSummary: View {
    let pin: FormDrawingPin
    let projectId: Int
    let token: String

    @State private var showViewer = false

    var body: some View {
        Button { showViewer = true } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(pin.label)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("View on drawing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showViewer) {
            DrawingPinPickerView(
                projectId: projectId,
                token: token,
                initialPin: pin,
                readOnly: true,
                onConfirm: { _ in },
                onCancel: { showViewer = false }
            )
        }
    }
}

struct DrawingPinPickerView: View {
    let projectId: Int
    let token: String
    let initialPin: FormDrawingPin?
    var readOnly: Bool = false
    let onConfirm: (FormDrawingPin) -> Void
    let onCancel: () -> Void

    @State private var drawings: [Drawing] = []
    @State private var search = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDrawing: Drawing?
    @State private var selectedFile: DrawingFile?
    @State private var selectedRevision: Revision?
    @State private var pdfURL: URL?
    @State private var pdfLoading = false
    @State private var tempPin: (x: Double, y: Double, page: Int)?

    private var pdfDrawings: [Drawing] {
        let withPdf = drawings.filter { $0.latestPdf != nil }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return withPdf }
        return withPdf.filter {
            $0.number.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if let pdfURL, selectedDrawing != nil {
                    pinDropView(url: pdfURL)
                } else {
                    drawingList
                }
            }
            .navigationTitle(readOnly ? "Pinned location" : (selectedDrawing == nil ? "Select drawing" : "Drop a pin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(readOnly ? "Done" : "Cancel", action: onCancel)
                }
                if !readOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        if selectedDrawing != nil {
                            Button("Use pin") { confirmPin() }
                                .disabled(tempPin == nil)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await loadDrawings() }
    }

    private var drawingList: some View {
        VStack(spacing: 0) {
            TextField("Search drawings", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let errorMessage {
                Spacer()
                Text(errorMessage).foregroundStyle(.red).padding()
                Spacer()
            } else if pdfDrawings.isEmpty {
                Spacer()
                Text("No drawings with a PDF in this project.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(pdfDrawings) { drawing in
                    Button {
                        selectDrawing(drawing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drawing.number)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(drawing.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func pinDropView(url: URL) -> some View {
        VStack(spacing: 0) {
            Text(readOnly ? "Pin placed on this drawing." : "Tap the drawing to place the pin. Tap again to move it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if !readOnly {
                Button("Choose a different drawing") {
                    selectedDrawing = nil
                    selectedFile = nil
                    pdfURL = nil
                    tempPin = nil
                }
                .font(.caption)
                .padding(.bottom, 8)
            }
            FormPinPDFView(
                url: url,
                existingPin: tempPin,
                allowsDrop: !readOnly,
                onDrop: { x, y, page in
                    tempPin = (x, y, page)
                }
            )
        }
    }

    private func selectDrawing(_ drawing: Drawing) {
        guard let pdf = drawing.latestPdf else { return }
        selectedDrawing = drawing
        selectedRevision = pdf.revision
        selectedFile = pdf.file
        tempPin = nil
        Task { await loadPDF(fileId: pdf.file.id) }
    }

    private func loadDrawings() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await APIClient.fetchDrawings(projectId: projectId, token: token)
            await MainActor.run {
                drawings = fetched
                isLoading = false
                if let pin = initialPin, let drawing = fetched.first(where: { $0.id == pin.drawingId }) {
                    selectedDrawing = drawing
                    selectedRevision = drawing.revisions.first(where: { $0.id == pin.revisionId }) ?? drawing.latestPdf?.revision
                    selectedFile = drawing.revisions
                        .flatMap(\.drawingFiles)
                        .first(where: { $0.id == pin.drawingFileId }) ?? drawing.latestPdf?.file
                    tempPin = (pin.x, pin.y, pin.page)
                }
            }
            if let fileId = await MainActor.run(body: { selectedFile?.id }) {
                await loadPDF(fileId: fileId)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadPDF(fileId: Int) async {
        await MainActor.run { pdfLoading = true }
        do {
            let url = try await APIClient.fetchDrawingPDFViaProxy(drawingFileId: fileId, token: token)
            await MainActor.run {
                pdfURL = url
                pdfLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                pdfLoading = false
            }
        }
    }

    private func confirmPin() {
        guard let drawing = selectedDrawing, let file = selectedFile, let pin = tempPin else { return }
        onConfirm(FormDrawingPin(
            drawingId: drawing.id,
            drawingFileId: file.id,
            drawingNumber: drawing.number,
            drawingTitle: drawing.title,
            revisionId: selectedRevision?.id,
            revisionNumber: selectedRevision?.revisionNumber,
            x: pin.x,
            y: pin.y,
            page: pin.page
        ))
    }
}

private extension Drawing {
    var latestPdf: (revision: Revision, file: DrawingFile)? {
        for revision in revisions {
            if let file = revision.drawingFiles.first(where: {
                $0.fileType.lowercased() == "pdf" || $0.fileName.lowercased().hasSuffix(".pdf")
            }) {
                return (revision, file)
            }
        }
        return nil
    }
}

private struct FormPinPDFView: UIViewRepresentable {
    let url: URL
    let existingPin: (x: Double, y: Double, page: Int)?
    var allowsDrop: Bool = true
    let onDrop: (Double, Double, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrop: onDrop, allowsDrop: allowsDrop)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        context.coordinator.pdfView = view
        context.coordinator.pinLayer = makePinLayer()
        if let overlay = context.coordinator.pinLayer {
            view.addSubview(overlay)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.existingPin = existingPin
        context.coordinator.allowsDrop = allowsDrop
        DispatchQueue.main.async {
            context.coordinator.renderExistingPin()
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        context.coordinator.existingPin = existingPin
        context.coordinator.allowsDrop = allowsDrop
        context.coordinator.renderExistingPin()
    }

    private func makePinLayer() -> UIView {
        let pin = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        pin.backgroundColor = UIColor.systemRed
        pin.layer.cornerRadius = 11
        pin.layer.borderColor = UIColor.white.cgColor
        pin.layer.borderWidth = 2
        pin.isUserInteractionEnabled = false
        pin.isHidden = true
        return pin
    }

    final class Coordinator: NSObject {
        let onDrop: (Double, Double, Int) -> Void
        var allowsDrop: Bool
        weak var pdfView: PDFView?
        var pinLayer: UIView?
        var existingPin: (x: Double, y: Double, page: Int)?

        init(onDrop: @escaping (Double, Double, Int) -> Void, allowsDrop: Bool) {
            self.onDrop = onDrop
            self.allowsDrop = allowsDrop
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard allowsDrop, let pdfView, let page = pdfView.currentPage else { return }
            let viewPoint = gesture.location(in: pdfView)
            let pdfPoint = pdfView.convert(viewPoint, to: page)
            let pageIndex = (pdfView.document?.index(for: page) ?? 0) + 1
            existingPin = (Double(pdfPoint.x), Double(pdfPoint.y), pageIndex)
            onDrop(Double(pdfPoint.x), Double(pdfPoint.y), pageIndex)
            renderExistingPin()
        }

        func renderExistingPin() {
            guard let pdfView, let pinLayer, let existingPin, let page = pdfView.currentPage else {
                pinLayer?.isHidden = true
                return
            }
            let pageIndex = (pdfView.document?.index(for: page) ?? 0) + 1
            guard existingPin.page == pageIndex else {
                pinLayer.isHidden = true
                return
            }
            let viewPoint = pdfView.convert(CGPoint(x: existingPin.x, y: existingPin.y), from: page)
            pinLayer.center = viewPoint
            pinLayer.isHidden = false
        }
    }
}
