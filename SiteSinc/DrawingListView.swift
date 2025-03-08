//
//  DrawingListView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import SwiftUI
import WebKit

struct DrawingListView: View {
    let projectId: Int
    let token: String
    @State private var drawings: [Drawing] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                VStack {
                    if isLoading {
                        ProgressView("Loading Drawings...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding()
                    } else if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    } else if filteredCompanies.isEmpty {
                        Text("No companies found for Project ID \(projectId)")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        List(filteredCompanies, id: \.self) { companyName in
                            NavigationLink(destination: CompanyDrawingsView(companyName: companyName, drawings: drawings.filter { $0.company?.name == companyName }, token: token)) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text(companyName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(drawings.filter { $0.company?.name == companyName }.count) drawings")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle("Companies for Project \(projectId)")
            }
            .onAppear {
                fetchDrawings()
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }

    private var groupedDrawings: [String: [Drawing]] {
        Dictionary(grouping: drawings, by: { $0.company?.name ?? "Unknown Company" })
    }

    private var filteredCompanies: [String] {
        if searchText.isEmpty {
            return groupedDrawings.keys.sorted()
        } else {
            return groupedDrawings.keys.filter { companyName in
                companyName.lowercased().contains(searchText.lowercased()) ||
                groupedDrawings[companyName]?.contains(where: {
                    $0.title.lowercased().contains(searchText.lowercased()) ||
                    $0.number.lowercased().contains(searchText.lowercased())
                }) ?? false
            }.sorted()
        }
    }

    private func fetchDrawings() {
        isLoading = true
        errorMessage = nil
        APIClient.fetchDrawings(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let d):
                    drawings = d
                    if d.isEmpty {
                        print("No drawings returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(d.count) drawings for projectId: \(projectId)")
                        d.forEach { drawing in
                            print("Drawing \(drawing.id): \(drawing.title), Company: \(drawing.company?.name ?? "N/A"), Revisions: \(drawing.revisions.count)")
                            drawing.revisions.forEach { revision in
                                print("  Revision \(revision.versionNumber), Files: \(revision.drawingFiles.count)")
                                revision.drawingFiles.forEach { file in
                                    print("    File: \(file.fileName), URL: \(file.downloadUrl)")
                                }
                            }
                        }
                    }
                case .failure(let error):
                    errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                    print("Error fetching drawings: \(error)")
                }
            }
        }
    }
}

// View for a specific company's drawings
struct CompanyDrawingsView: View {
    let companyName: String
    let drawings: [Drawing]
    let token: String
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)

            if drawings.isEmpty {
                Text("No drawings found for \(companyName)")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(filteredDrawings, id: \.id) { drawing in
                    NavigationLink(destination: PDFView(drawing: drawing)) {
                        VStack(alignment: .leading) {
                            Text(drawing.title)
                                .font(.headline)
                            Text(drawing.number)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                                Text("Latest Revision: \(latestRevision.versionNumber)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("\(companyName) Drawings")
    }

    private var filteredDrawings: [Drawing] {
        if searchText.isEmpty {
            return drawings
        } else {
            return drawings.filter {
                $0.title.lowercased().contains(searchText.lowercased()) ||
                $0.number.lowercased().contains(searchText.lowercased())
            }
        }
    }
}

// PDF View to display the latest revision with swipe-up revisions
struct PDFView: View {
    let drawing: Drawing
    @State private var selectedRevision: Revision?

    var body: some View {
        VStack {
            // PDF Display
            ZStack {
                if let revision = selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                   let latestFile = revision.drawingFiles.first {
                    WebView(url: URL(string: latestFile.downloadUrl)!)
                        .onAppear {
                            print("Loading PDF for drawing \(drawing.id), Revision \(revision.versionNumber), URL: \(latestFile.downloadUrl)")
                        }
                } else {
                    Text("No PDF available for this drawing")
                        .onAppear {
                            print("No revisions or files for drawing \(drawing.id). Revisions: \(drawing.revisions.count)")
                        }
                }

                // Red banner for non-latest revision
                if let latest = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }),
                   let current = selectedRevision,
                   current.versionNumber != latest.versionNumber {
                    VStack {
                        Text("Not the Latest Revision (Current: \(current.versionNumber), Latest: \(latest.versionNumber))")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
            }

            // Horizontal revision bar
            if !drawing.revisions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(drawing.revisions.sorted(by: { $0.versionNumber > $1.versionNumber }), id: \.id) { revision in
                            Button(action: {
                                withAnimation {
                                    selectedRevision = revision
                                }
                            }) {
                                VStack {
                                    Text("Rev \(revision.versionNumber)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Text(revision.status)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    (selectedRevision?.id == revision.id ||
                                     (selectedRevision == nil && revision.versionNumber == drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })?.versionNumber))
                                    ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.white)
                .shadow(radius: 2)
            }
        }
        .navigationTitle(drawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(drawing.title)
                        .font(.headline)
                    Text(drawing.number)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// WebView to load the PDF with zooming enabled
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Enable zooming
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0
        webView.scrollView.bouncesZoom = true
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.pinchGestureRecognizer?.isEnabled = true // Explicitly enable pinch
        webView.isUserInteractionEnabled = true // Ensure interaction
        webView.configuration.suppressesIncrementalRendering = false // Optimize rendering
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Failed to load PDF: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Failed to start loading PDF: \(error)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Successfully loaded PDF")
        }
    }
}
#Preview {
    DrawingListView(projectId: 2, token: "sample-token")
}
