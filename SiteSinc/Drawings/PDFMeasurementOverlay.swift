import SwiftUI
import PDFKit
import UIKit

// MARK: - Measurement session state

@MainActor
final class PDFMeasurementController: ObservableObject {
    @Published var isActive: Bool = false
    @Published var tool: MeasurementTool = .length
    @Published var calibration: DrawingScaleCalibration?
    @Published var lengths: [LengthMeasurement] = []
    @Published var areas: [AreaMeasurement] = []
    @Published var inProgressPoints: [CGPoint] = []
    @Published var loupeVisible: Bool = false
    @Published var loupeViewPoint: CGPoint = .zero
    @Published var loupePDFPoint: CGPoint = .zero
    @Published var showCalibrationSheet: Bool = false
    @Published var pendingCalibrationDistance: Double = 0
    @Published var calibrationInput: String = ""
    @Published var calibrationUnit: MeasurementUnit = .meters

    var hasCalibration: Bool { calibration != nil }

    var statusText: String {
        if loupeVisible {
            return "Drag to move pin · release to place"
        }
        switch tool {
        case .length:
            switch inProgressPoints.count {
            case 0: return "Long-press to place start pin"
            case 1: return "Long-press to place end pin"
            default: return MeasurementTool.length.instruction
            }
        case .area:
            let n = inProgressPoints.count
            if n == 0 { return "Long-press to place first vertex" }
            if n < 3 { return "Place \(3 - n) more vertex\(3 - n == 1 ? "" : "es")" }
            return "Add more vertices or tap Done"
        case .calibrate:
            switch inProgressPoints.count {
            case 0: return "Long-press first calibration point"
            case 1: return "Long-press second calibration point"
            default: return MeasurementTool.calibrate.instruction
            }
        }
    }

    func activate(tool: MeasurementTool = .length) {
        isActive = true
        self.tool = tool
        inProgressPoints = []
        loupeVisible = false
    }

    func deactivate() {
        isActive = false
        inProgressPoints = []
        loupeVisible = false
        showCalibrationSheet = false
    }

    func clearAll() {
        lengths.removeAll()
        areas.removeAll()
        inProgressPoints.removeAll()
        loupeVisible = false
    }

    func undoLast() {
        if !inProgressPoints.isEmpty {
            inProgressPoints.removeLast()
            return
        }
        switch tool {
        case .length:
            if !lengths.isEmpty { lengths.removeLast() }
        case .area:
            if !areas.isEmpty { areas.removeLast() }
        case .calibrate:
            break
        }
    }

    func beginLoupe(at viewPoint: CGPoint, pdfPoint: CGPoint) {
        loupeVisible = true
        loupeViewPoint = viewPoint
        loupePDFPoint = pdfPoint
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func moveLoupe(to viewPoint: CGPoint, pdfPoint: CGPoint) {
        loupeViewPoint = viewPoint
        loupePDFPoint = pdfPoint
    }

    func endLoupe(place: Bool) {
        let point = loupePDFPoint
        loupeVisible = false
        guard place else { return }
        placePoint(point)
    }

    func placePoint(_ pdfPoint: CGPoint) {
        inProgressPoints.append(pdfPoint)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        finalizeIfReady()
    }

    func finishAreaIfPossible() {
        guard tool == .area, inProgressPoints.count >= 3 else { return }
        areas.append(AreaMeasurement(vertices: inProgressPoints))
        inProgressPoints = []
    }

    func applyCalibration() {
        guard let value = Double(calibrationInput.replacingOccurrences(of: ",", with: ".")),
              value > 0,
              let cal = DrawingScaleCalibration.fromKnownLength(
                pdfDistancePoints: pendingCalibrationDistance,
                realLength: value,
                unit: calibrationUnit
              ) else { return }
        calibration = cal
        showCalibrationSheet = false
        calibrationInput = ""
        inProgressPoints = []
        pendingCalibrationDistance = 0
        tool = .length
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func finalizeIfReady() {
        switch tool {
        case .length:
            guard inProgressPoints.count >= 2 else { return }
            let start = inProgressPoints[0]
            let end = inProgressPoints[1]
            lengths.append(LengthMeasurement(start: start, end: end))
            inProgressPoints = []
        case .area:
            break
        case .calibrate:
            guard inProgressPoints.count >= 2 else { return }
            let d = MeasurementGeometry.distance(inProgressPoints[0], inProgressPoints[1])
            pendingCalibrationDistance = d
            if let existing = calibration {
                calibrationUnit = existing.unit
            }
            calibrationInput = ""
            showCalibrationSheet = true
        }
    }
}

// MARK: - Overlay chrome + interaction

struct PDFMeasurementOverlay: View {
    @ObservedObject var controller: PDFMeasurementController
    let page: PDFPage
    let pdfView: PDFView?
    let overlayVersion: Int

    var body: some View {
        ZStack {
            if controller.isActive {
                MeasurementGestureLayer(
                    page: page,
                    pdfView: pdfView,
                    onTap: { point in
                        controller.placePoint(point)
                    },
                    onLoupeBegan: { viewPt, pdfPt in
                        controller.beginLoupe(at: viewPt, pdfPoint: pdfPt)
                    },
                    onLoupeMoved: { viewPt, pdfPt in
                        controller.moveLoupe(to: viewPt, pdfPoint: pdfPt)
                    },
                    onLoupeEnded: { place in
                        controller.endLoupe(place: place)
                    }
                )
            }

            MeasurementCanvasView(
                lengths: controller.lengths,
                areas: controller.areas,
                inProgressPoints: controller.inProgressPoints,
                calibration: controller.calibration,
                loupePDFPoint: controller.loupeVisible ? controller.loupePDFPoint : nil,
                page: page,
                pdfView: pdfView,
                overlayVersion: overlayVersion
            )
            .allowsHitTesting(false)

            if controller.isActive, controller.loupeVisible, let pdfView {
                MeasurementLoupeView(
                    pdfView: pdfView,
                    page: page,
                    pdfPoint: controller.loupePDFPoint,
                    anchorViewPoint: controller.loupeViewPoint
                )
                .allowsHitTesting(false)
            }

            if controller.isActive {
                VStack {
                    measurementHeader
                    Spacer()
                    measurementFooter
                }
                .padding(10)
            }
        }
        .allowsHitTesting(controller.isActive)
        .sheet(isPresented: $controller.showCalibrationSheet) {
            calibrationSheet
        }
    }

    private var measurementHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MeasurementTool.allCases) { tool in
                    Button {
                        controller.tool = tool
                        controller.inProgressPoints = []
                    } label: {
                        Label(tool.title, systemImage: tool.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(controller.tool == tool ? Color.accentColor : Color.clear)
                            .foregroundColor(controller.tool == tool ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button {
                    controller.deactivate()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close measure tools")
            }

            Text(controller.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: controller.hasCalibration ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(controller.hasCalibration ? .green : .orange)
                    .font(.system(size: 12))
                Text(controller.hasCalibration
                     ? "Scale set · \(MeasurementFormatter.formatLength(pdfDistance: 1, calibration: controller.calibration)) per pt"
                     : "Not calibrated · values shown in PDF points")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var measurementFooter: some View {
        HStack(spacing: 10) {
            Button {
                controller.undoLast()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(controller.inProgressPoints.isEmpty
                      && controller.lengths.isEmpty
                      && controller.areas.isEmpty)

            if controller.tool == .area && controller.inProgressPoints.count >= 3 {
                Button {
                    controller.finishAreaIfPossible()
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Button(role: .destructive) {
                controller.clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(controller.lengths.isEmpty
                      && controller.areas.isEmpty
                      && controller.inProgressPoints.isEmpty)
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(.bordered)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var calibrationSheet: some View {
        NavigationView {
            Form {
                Section {
                    Text("Measured \(MeasurementFormatter.formatNumber(controller.pendingCalibrationDistance)) PDF points between pins.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Real-world length", text: $controller.calibrationInput)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $controller.calibrationUnit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                } header: {
                    Text("Calibrate scale")
                } footer: {
                    Text("Measurements stay on this device only and are not saved to the project.")
                }
            }
            .navigationTitle("Set Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.showCalibrationSheet = false
                        controller.inProgressPoints = []
                        controller.pendingCalibrationDistance = 0
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        controller.applyCalibration()
                    }
                    .disabled(Double(controller.calibrationInput.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}

// MARK: - Drawn measurements

private struct MeasurementCanvasView: View {
    let lengths: [LengthMeasurement]
    let areas: [AreaMeasurement]
    let inProgressPoints: [CGPoint]
    let calibration: DrawingScaleCalibration?
    let loupePDFPoint: CGPoint?
    let page: PDFPage
    let pdfView: PDFView?
    let overlayVersion: Int

    var body: some View {
        Canvas { context, _ in
            let _ = overlayVersion
            for length in lengths {
                drawLength(length, in: &context)
            }
            for area in areas {
                drawArea(area, in: &context)
            }
            drawInProgress(in: &context)
            if let loupePDFPoint, let viewPoint = viewPoint(for: loupePDFPoint) {
                drawPin(at: viewPoint, in: &context, emphasized: true)
            }
        }
    }

    private func viewPoint(for pdfPoint: CGPoint) -> CGPoint? {
        guard let pdfView else { return nil }
        return pdfView.convert(pdfPoint, from: page)
    }

    private func drawLength(_ length: LengthMeasurement, in context: inout GraphicsContext) {
        guard let a = viewPoint(for: length.start), let b = viewPoint(for: length.end) else { return }
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(Color(hex: "#0EA5E9")), lineWidth: 2)
        drawPin(at: a, in: &context, emphasized: false)
        drawPin(at: b, in: &context, emphasized: false)

        let label = MeasurementFormatter.formatLength(pdfDistance: length.pdfDistance, calibration: calibration)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 14)
        drawLabel(label, at: mid, in: &context)
    }

    private func drawArea(_ area: AreaMeasurement, in context: inout GraphicsContext) {
        let points = area.vertices.compactMap { viewPoint(for: $0) }
        guard points.count >= 3 else { return }
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        context.fill(path, with: .color(Color(hex: "#0EA5E9").opacity(0.18)))
        context.stroke(path, with: .color(Color(hex: "#0284C7")), lineWidth: 2)
        for p in points { drawPin(at: p, in: &context, emphasized: false) }

        let label = MeasurementFormatter.formatArea(pdfArea: area.pdfArea, calibration: calibration)
        let center = MeasurementGeometry.centroid(points)
        drawLabel(label, at: center, in: &context)
    }

    private func drawInProgress(in context: inout GraphicsContext) {
        let points = inProgressPoints.compactMap { viewPoint(for: $0) }
        guard !points.isEmpty else { return }
        if points.count >= 2 {
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(Color(hex: "#38BDF8")),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
        }
        for p in points { drawPin(at: p, in: &context, emphasized: false) }
    }

    private func drawPin(at point: CGPoint, in context: inout GraphicsContext, emphasized: Bool) {
        let radius: CGFloat = emphasized ? 7 : 5
        let outer = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(outer, with: .color(.white))
        context.stroke(outer, with: .color(Color(hex: "#0369A1")), lineWidth: emphasized ? 2.5 : 2)
        let innerR: CGFloat = emphasized ? 2.5 : 2
        let inner = Path(ellipseIn: CGRect(x: point.x - innerR, y: point.y - innerR, width: innerR * 2, height: innerR * 2))
        context.fill(inner, with: .color(Color(hex: "#0EA5E9")))
    }

    private func drawLabel(_ text: String, at point: CGPoint, in context: inout GraphicsContext) {
        let ns = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
        )
        let size = ns.size()
        let padding = CGSize(width: 8, height: 4)
        let rect = CGRect(
            x: point.x - size.width / 2 - padding.width,
            y: point.y - size.height / 2 - padding.height,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        let bubble = Path(roundedRect: rect, cornerRadius: 8)
        context.fill(bubble, with: .color(Color(.systemBackground).opacity(0.92)))
        context.stroke(bubble, with: .color(Color(hex: "#0284C7").opacity(0.35)), lineWidth: 1)
        context.draw(Text(text).font(.system(size: 12, weight: .semibold)), at: point)
    }
}

// MARK: - Magnifier loupe

private struct MeasurementLoupeView: View {
    let pdfView: PDFView
    let page: PDFPage
    let pdfPoint: CGPoint
    let anchorViewPoint: CGPoint

    private let loupeSize: CGFloat = 140
    private let magnification: CGFloat = 2.4

    var body: some View {
        GeometryReader { geo in
            let preferredY = anchorViewPoint.y - loupeSize * 0.75 - 20
            let loupeCenter = CGPoint(
                x: min(max(anchorViewPoint.x, loupeSize / 2 + 8), geo.size.width - loupeSize / 2 - 8),
                y: min(max(preferredY, loupeSize / 2 + 8), geo.size.height - loupeSize / 2 - 8)
            )

            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: loupeSize, height: loupeSize)
                    .overlay(
                        LoupePDFSnapshot(
                            pdfView: pdfView,
                            page: page,
                            pdfPoint: pdfPoint,
                            size: loupeSize,
                            magnification: magnification
                        )
                        .clipShape(Circle())
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "#0EA5E9"), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

                Path { path in
                    path.move(to: CGPoint(x: loupeSize / 2 - 16, y: loupeSize / 2))
                    path.addLine(to: CGPoint(x: loupeSize / 2 + 16, y: loupeSize / 2))
                    path.move(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 - 16))
                    path.addLine(to: CGPoint(x: loupeSize / 2, y: loupeSize / 2 + 16))
                }
                .stroke(Color(hex: "#0369A1").opacity(0.9), lineWidth: 1.2)

                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: 10, height: 10)
            }
            .frame(width: loupeSize, height: loupeSize)
            .position(loupeCenter)
            .accessibilityLabel("Magnified pin placement")
        }
    }
}

private struct LoupePDFSnapshot: UIViewRepresentable {
    let pdfView: PDFView
    let page: PDFPage
    let pdfPoint: CGPoint
    let size: CGFloat
    let magnification: CGFloat

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.image = render()
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = render()
    }

    private func render() -> UIImage? {
        let viewPoint = pdfView.convert(pdfPoint, from: page)
        let sourceSize = size / magnification
        let sourceRect = CGRect(
            x: viewPoint.x - sourceSize / 2,
            y: viewPoint.y - sourceSize / 2,
            width: sourceSize,
            height: sourceSize
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: -sourceRect.origin.x * magnification, y: -sourceRect.origin.y * magnification)
            ctx.cgContext.scaleBy(x: magnification, y: magnification)
            pdfView.layer.render(in: ctx.cgContext)
        }
    }
}

// MARK: - Gesture layer (long-press loupe + tap)

private struct MeasurementGestureLayer: UIViewRepresentable {
    let page: PDFPage
    let pdfView: PDFView?
    var onTap: (CGPoint) -> Void
    var onLoupeBegan: (CGPoint, CGPoint) -> Void
    var onLoupeMoved: (CGPoint, CGPoint) -> Void
    var onLoupeEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 10_000
        longPress.cancelsTouchesInView = true
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)

        context.coordinator.longPress = longPress
        context.coordinator.tap = tap
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: MeasurementGestureLayer
        weak var longPress: UILongPressGestureRecognizer?
        weak var tap: UITapGestureRecognizer?

        init(_ parent: MeasurementGestureLayer) {
            self.parent = parent
        }

        private func pdfPoint(from viewPoint: CGPoint, in view: UIView) -> CGPoint? {
            guard let pdfView = parent.pdfView else { return nil }
            // Convert from overlay view coordinates into the PDFView's coordinate space.
            let pointInPDFView = view.convert(viewPoint, to: pdfView)
            return pdfView.convert(pointInPDFView, to: parent.page)
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, let view = gr.view else { return }
            let location = gr.location(in: view)
            guard let pdfPoint = pdfPoint(from: location, in: view) else { return }
            parent.onTap(pdfPoint)
        }

        @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard let view = gr.view else { return }
            let location = gr.location(in: view)
            guard let pdfPoint = pdfPoint(from: location, in: view) else {
                if gr.state == .ended || gr.state == .cancelled || gr.state == .failed {
                    parent.onLoupeEnded(false)
                }
                return
            }
            switch gr.state {
            case .began:
                parent.onLoupeBegan(location, pdfPoint)
            case .changed:
                parent.onLoupeMoved(location, pdfPoint)
            case .ended:
                parent.onLoupeEnded(true)
            case .cancelled, .failed:
                parent.onLoupeEnded(false)
            default:
                break
            }
        }
    }
}
