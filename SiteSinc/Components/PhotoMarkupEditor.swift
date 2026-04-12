import SwiftUI
import PencilKit
import UIKit
import AVFoundation

// MARK: - Aspect fit

func photoMarkupAspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * scale
    let h = imageSize.height * scale
    let x = (container.width - w) / 2
    let y = (container.height - h) / 2
    return CGRect(x: x, y: y, width: w, height: h)
}

// MARK: - Text annotation (normalized 0...1 in image space)

struct PhotoMarkupTextAnnotation: Identifiable, Equatable {
    let id: UUID
    var normalizedPoint: CGPoint
    var text: String

    init(id: UUID = UUID(), normalizedPoint: CGPoint, text: String) {
        self.id = id
        self.normalizedPoint = normalizedPoint
        self.text = text
    }
}

// MARK: - UIKit container

final class PhotoMarkupCanvasContainer: UIView {
    let imageView = UIImageView()
    let canvasView = PKCanvasView()
    private var toolPicker: PKToolPicker?

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.tool = PKInkingTool(.pen, color: .systemRed, width: 4)
        addSubview(imageView)
        addSubview(canvasView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sz = image?.size ?? bounds.size
        let r = AVMakeRect(aspectRatio: sz, insideRect: bounds)
        imageView.frame = r
        canvasView.frame = r
    }

    func setDrawingEnabled(_ enabled: Bool) {
        canvasView.isUserInteractionEnabled = enabled
        if enabled {
            showToolPickerIfNeeded()
            _ = canvasView.becomeFirstResponder()
        } else {
            toolPicker?.setVisible(false, forFirstResponder: canvasView)
            canvasView.resignFirstResponder()
        }
    }

    private func showToolPickerIfNeeded() {
        if toolPicker == nil {
            toolPicker = PKToolPicker()
        }
        guard let picker = toolPicker else { return }
        picker.addObserver(canvasView)
        picker.setVisible(true, forFirstResponder: canvasView)
        _ = canvasView.becomeFirstResponder()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, canvasView.isUserInteractionEnabled {
            showToolPickerIfNeeded()
        }
    }

    func exportCompositeJPEG(annotations: [PhotoMarkupTextAnnotation], compressionQuality: CGFloat = 0.8) -> Data? {
        guard let base = imageView.image ?? image else { return nil }
        let pixelW = base.size.width * base.scale
        let pixelH = base.size.height * base.scale
        guard pixelW > 0, pixelH > 0 else { return nil }

        let bounds = canvasView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return base.jpegData(compressionQuality: compressionQuality)
        }

        let drawingScale = pixelW / bounds.width
        let drawingImage = canvasView.drawing.image(from: bounds, scale: drawingScale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        let outSize = CGSize(width: pixelW, height: pixelH)
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        let composed = renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: outSize))
            drawingImage.draw(in: CGRect(origin: .zero, size: outSize))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            for ann in annotations where !ann.text.isEmpty {
                let x = CGFloat(ann.normalizedPoint.x) * pixelW
                let y = CGFloat(ann.normalizedPoint.y) * pixelH
                let font = UIFont.boldSystemFont(ofSize: max(18, pixelW / 35))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.systemYellow,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3,
                    .paragraphStyle: paragraph
                ]
                let ns = ann.text as NSString
                ns.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }
        return composed.jpegData(compressionQuality: compressionQuality)
    }
}

struct PhotoMarkupCanvasRepresentable: UIViewRepresentable {
    let uiImage: UIImage
    @Binding var annotations: [PhotoMarkupTextAnnotation]
    var drawMode: PhotoMarkupEditorScreen.DrawMode
    var onTapNormalized: (CGPoint) -> Void
    var onContainerAttached: (PhotoMarkupCanvasContainer) -> Void

    func makeUIView(context: Context) -> PhotoMarkupCanvasContainer {
        let v = PhotoMarkupCanvasContainer()
        v.image = uiImage
        DispatchQueue.main.async { onContainerAttached(v) }
        return v
    }

    func updateUIView(_ uiView: PhotoMarkupCanvasContainer, context: Context) {
        uiView.image = uiImage
        uiView.setDrawingEnabled(drawMode == .draw)
        onContainerAttached(uiView)

        context.coordinator.container = uiView
        context.coordinator.onTapNormalized = onTapNormalized
        context.coordinator.drawMode = drawMode

        if drawMode == .text {
            if context.coordinator.tapGesture == nil {
                let g = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
                uiView.addGestureRecognizer(g)
                context.coordinator.tapGesture = g
            }
            context.coordinator.tapGesture?.isEnabled = true
        } else {
            context.coordinator.tapGesture?.isEnabled = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var container: PhotoMarkupCanvasContainer?
        var tapGesture: UITapGestureRecognizer?
        var onTapNormalized: (CGPoint) -> Void = { _ in }
        var drawMode: PhotoMarkupEditorScreen.DrawMode = .draw

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard drawMode == .text, let view = container else { return }
            let p = gr.location(in: view)
            let imgRect = AVMakeRect(aspectRatio: view.image?.size ?? .zero, insideRect: view.bounds)
            guard imgRect.contains(p) else { return }
            let nx = (p.x - imgRect.minX) / imgRect.width
            let ny = (p.y - imgRect.minY) / imgRect.height
            onTapNormalized(CGPoint(x: nx, y: ny))
        }
    }
}

// MARK: - Presentation item (use with `fullScreenCover(item:)`)

/// Avoids a blank first frame: `fullScreenCover(isPresented:)` + `if let image` can present before `image` is committed; item-based cover always has the image.
struct PhotoMarkupPresentationItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Full-screen editor

struct PhotoMarkupEditorScreen: View {
    enum DrawMode: String, CaseIterable, Identifiable {
        case draw = "Draw"
        case text = "Text"
        var id: String { rawValue }
    }

    let image: UIImage
    var onDone: (Data) -> Void
    var onCancel: () -> Void

    @State private var annotations: [PhotoMarkupTextAnnotation] = []
    @State private var drawMode: DrawMode = .draw
    @State private var textDraft = ""
    @State private var pendingTextPoint: CGPoint?
    @State private var showTextAlert = false
    @State private var markupContainer: PhotoMarkupCanvasContainer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                PhotoMarkupCanvasRepresentable(
                    uiImage: image,
                    annotations: $annotations,
                    drawMode: drawMode,
                    onTapNormalized: { norm in
                        pendingTextPoint = norm
                        textDraft = ""
                        showTextAlert = true
                    },
                    onContainerAttached: { container in
                        markupContainer = container
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                ForEach(annotations) { ann in
                    GeometryReader { geo in
                        let rect = photoMarkupAspectFitRect(imageSize: image.size, in: geo.size)
                        let x = rect.minX + ann.normalizedPoint.x * rect.width
                        let y = rect.minY + ann.normalizedPoint.y * rect.height
                        Text(ann.text)
                            .font(.headline.bold())
                            .foregroundStyle(.yellow)
                            .shadow(color: .black, radius: 1)
                            .position(x: x + 40, y: y + 10)
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Mark up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $drawMode) {
                        ForEach(DrawMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            .alert("Add label", isPresented: $showTextAlert) {
                TextField("Text", text: $textDraft)
                Button("Add") {
                    if let pt = pendingTextPoint, !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        annotations.append(PhotoMarkupTextAnnotation(normalizedPoint: pt, text: textDraft))
                    }
                    pendingTextPoint = nil
                }
                Button("Cancel", role: .cancel) { pendingTextPoint = nil }
            } message: {
                Text("Enter text to place at the tap location.")
            }
        }
    }

    private func finish() {
        if let data = markupContainer?.exportCompositeJPEG(annotations: annotations, compressionQuality: 0.8) {
            onDone(data)
            return
        }
        if let data = image.jpegData(compressionQuality: 0.8) {
            onDone(data)
        }
    }
}
