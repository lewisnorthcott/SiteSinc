//
//  DrawingViewer.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 21/05/2025.
//
import SwiftUI
import WebKit

struct DrawingViewer: View {
    let drawings: [Drawing]
    @Binding var drawingIndex: Int
    @State private var selectedRevision: Revision?
    @State private var isSidePanelOpen: Bool = false

    private var currentDrawing: Drawing {
        guard drawingIndex >= 0, drawingIndex < drawings.count else {
            fatalError("Drawing index out of bounds: \(drawingIndex)")
        }
        return drawings[drawingIndex]
    }

    var body: some View {
        ZStack {
            DrawingContentView(
                drawing: currentDrawing,
                selectedRevision: $selectedRevision,
                drawingIndex: $drawingIndex,
                drawingsCount: drawings.count
            )

            if isSidePanelOpen {
                SidePanelView(
                    drawing: currentDrawing,
                    selectedRevision: selectedRevision,
                    isSidePanelOpen: $isSidePanelOpen
                )
            }
        }
        .navigationTitle(currentDrawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(currentDrawing.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(currentDrawing.number)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                .accessibilityLabel("Drawing title: \(currentDrawing.title), number: \(currentDrawing.number)")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
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
    }
}

struct DrawingContentView: View {
    let drawing: Drawing
    @Binding var selectedRevision: Revision?
    @Binding var drawingIndex: Int
    let drawingsCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    if let pdfFile = revision.drawingFiles.first(where: { $0.fileName.lowercased().hasSuffix(".pdf") }) {
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let fullPath = documentsDirectory.appendingPathComponent("Project_\(drawing.projectId)/drawings/\(pdfFile.fileName)")
                        WebView(url: FileManager.default.fileExists(atPath: fullPath.path) ? fullPath : URL(string: pdfFile.downloadUrl)!)
                            .accessibilityLabel("Drawing \(drawing.title), Rev \(revision.versionNumber)")
                    } else {
                        VStack(spacing: 8) {
                            Text("Unsupported Format")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.red)
                            Text("No PDF available. Use an external app for DWG files.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(hex: "#6B7280"))
                        }
                    }
                } else {
                    Text("No files available")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#6B7280"))
                }

                if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                   let current = selectedRevision,
                   current.versionNumber != latest.versionNumber {
                    VStack {
                        Text("Not Latest: Rev \(current.versionNumber) (Latest: \(latest.versionNumber))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.red)
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                if !drawing.revisions.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(drawing.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    selectedRevision = revision
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text("Rev \(revision.versionNumber)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: "#1F2A44"))
                                    Text(revision.status)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(Color(hex: "#6B7280"))
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    (selectedRevision?.id == revision.id ||
                                     (selectedRevision == nil && revision.versionNumber == drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber))
                                    ? Color(hex: "#3B82F6").opacity(0.2) : Color(hex: "#FFFFFF").opacity(0.8)
                                )
                                .cornerRadius(6)
                                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                            }
                            .accessibilityLabel("Revision \(revision.versionNumber), status \(revision.status)")
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .background(Color(hex: "#FFFFFF").opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if abs(value.translation.height) > abs(value.translation.width) && !drawing.revisions.isEmpty {
                            let sortedRevisions = drawing.revisions.sorted { $0.versionNumber > $1.versionNumber }
                            let current = selectedRevision ?? sortedRevisions.first!
                            guard let index = sortedRevisions.firstIndex(where: { $0.id == current.id }) else { return }

                            if value.translation.height < -100 {
                                if index > 0 {
                                    withAnimation(.easeInOut) {
                                        selectedRevision = sortedRevisions[index - 1]
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            } else if value.translation.height > 100 {
                                if index < sortedRevisions.count - 1 {
                                    withAnimation(.easeInOut) {
                                        selectedRevision = sortedRevisions[index + 1]
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            }
                        }
                        else if abs(value.translation.width) > abs(value.translation.height) {
                            if value.translation.width < -100 {
                                if drawingIndex < drawingsCount - 1 {
                                    withAnimation(.easeInOut) {
                                        drawingIndex += 1
                                        selectedRevision = nil
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            } else if value.translation.width > 100 {
                                if drawingIndex > 0 {
                                    withAnimation(.easeInOut) {
                                        drawingIndex -= 1
                                        selectedRevision = nil
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            }
                        }
                    }
            )
        }
    }
}

struct SidePanelView: View {
    let drawing: Drawing
    let selectedRevision: Revision?
    @Binding var isSidePanelOpen: Bool

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        formatter.timeZone = TimeZone(identifier: "Europe/London") // BST
        return formatter
    }()

    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                VStack {
                    HStack {
                        Text("Drawing Information")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isSidePanelOpen = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(hex: "#6B7280"))
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                                InfoRow(label: "Revision", value: String(revision.versionNumber))
                                InfoRow(label: "Status", value: revision.status)
                            }

                            // Use the user relation to display the uploader's name
                            InfoRow(
                                label: "Uploaded By",
                                value: {
                                    if let user = drawing.user {
                                        return "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
                                    }
                                    return "Unknown"
                                }()
                            )

                            InfoRow(
                                label: "Uploaded At",
                                value: {
                                    if let createdAt = drawing.createdAt, let date = ISO8601DateFormatter().date(from: createdAt) {
                                        return dateFormatter.string(from: date)
                                    }
                                    return "Unknown"
                                }()
                            )

                            InfoRow(label: "Project ID", value: "\(drawing.projectId)")
                            InfoRow(label: "Drawing Number", value: drawing.number)
                            InfoRow(label: "Offline", value: drawing.isOffline ?? false ? "Yes" : "No")
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .frame(width: min(geometry.size.width * 0.75, 300))
                .background(Color(hex: "#FFFFFF"))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: -2, y: 0)
                .offset(x: isSidePanelOpen ? 0 : min(geometry.size.width * 0.75, 300))
            }
        }
        .background(
            Color.black.opacity(isSidePanelOpen ? 0.3 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut) {
                        isSidePanelOpen = false
                    }
                }
        )
        .ignoresSafeArea()
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#6B7280"))
            Text(value)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
        }
    }
}

//struct WebView: UIViewRepresentable {
//    let url: URL
//
//    func makeUIView(context: Context) -> WKWebView {
//        let configuration = WKWebViewConfiguration()
//        let webView = WKWebView(frame: .zero, configuration: configuration)
//        webView.navigationDelegate = context.coordinator
//        webView.scrollView.minimumZoomScale = 1.0
//        webView.scrollView.maximumZoomScale = 5.0
//        webView.scrollView.bouncesZoom = true
//        webView.scrollView.isScrollEnabled = true
//        webView.scrollView.pinchGestureRecognizer?.isEnabled = true
//        webView.isUserInteractionEnabled = true
//        webView.configuration.suppressesIncrementalRendering = false
//        return webView
//    }
//
//    func updateUIView(_ uiView: WKWebView, context: Context) {
//        let request = URLRequest(url: url)
//        uiView.load(request)
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    class Coordinator: NSObject, WKNavigationDelegate {
//        let parent: WebView
//
//        init(_ parent: WebView) {
//            self.parent = parent
//        }
//
//        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
//            print("Failed to load content: \(error)")
//        }
//
//        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
//            print("Failed to start loading content: \(error)")
//        }
//
//        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//            print("Successfully loaded content")
//        }
//    }
//}
