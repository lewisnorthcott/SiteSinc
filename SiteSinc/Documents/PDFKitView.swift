//
//  PDFKitView.swift
//  SiteSinc
//
//  Created by Lewis Northcott.
//
//  A PDFKit-based viewer used by the Documents viewer.
//  Supports native text search with highlighting and match cycling.
//

import SwiftUI
import PDFKit

// MARK: - Search state

final class PDFSearchState: ObservableObject {
    @Published var query: String = ""
    @Published var currentIndex: Int = 0
    @Published var totalMatches: Int = 0
    @Published private(set) var currentMatchPageIndex: Int?

    weak var pdfView: PDFView?
    private var matches: [PDFSelection] = []

    func performSearch() {
        guard let pdfView = pdfView, let document = pdfView.document else {
            clearResults()
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        let selections = document.findString(trimmed, withOptions: .caseInsensitive)
        for sel in selections { sel.color = .systemYellow }

        matches = selections
        totalMatches = selections.count
        currentIndex = selections.isEmpty ? 0 : 0
        pdfView.highlightedSelections = selections.isEmpty ? nil : selections

        if let first = selections.first {
            reveal(first, in: pdfView)
        } else {
            pdfView.setCurrentSelection(nil, animate: false)
        }
    }

    func next() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        goToCurrent()
    }

    func previous() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        goToCurrent()
    }

    func clearResults() {
        matches = []
        totalMatches = 0
        currentIndex = 0
        currentMatchPageIndex = nil
        pdfView?.highlightedSelections = nil
        pdfView?.setCurrentSelection(nil, animate: false)
    }

    private func goToCurrent() {
        guard matches.indices.contains(currentIndex), let pdfView else { return }
        reveal(matches[currentIndex], in: pdfView)
    }

    private func reveal(_ selection: PDFSelection, in pdfView: PDFView) {
        let destinationPage = selection.pages.first
        if let destinationPage, let document = pdfView.document {
            let pageIndex = document.index(for: destinationPage)
            if pageIndex != NSNotFound {
                currentMatchPageIndex = pageIndex
            }
            pdfView.go(to: destinationPage)
        }

        pdfView.highlightedSelections = matches
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)

        // Single-page viewers may finish laying out the new page after this call.
        // Re-apply so the match stays selected and in view.
        DispatchQueue.main.async {
            guard self.matches.indices.contains(self.currentIndex) else { return }
            let current = self.matches[self.currentIndex]
            pdfView.highlightedSelections = self.matches
            pdfView.setCurrentSelection(current, animate: true)
            pdfView.go(to: current)
        }
    }
}

// MARK: - PDFView wrapper

struct PDFKitView: UIViewRepresentable {
    let url: URL
    @ObservedObject var searchState: PDFSearchState
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)
        pdfView.backgroundColor = .systemGray6
        pdfView.pageShadowsEnabled = true

        searchState.pdfView = pdfView
        context.coordinator.parent = self
        context.coordinator.loadedURL = nil
        loadDocument(into: pdfView, context: context)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        searchState.pdfView = uiView
        context.coordinator.parent = self

        if context.coordinator.loadedURL != url {
            loadDocument(into: uiView, context: context)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func loadDocument(into pdfView: PDFView, context: Context) {
        context.coordinator.loadedURL = url

        DispatchQueue.main.async {
            self.isLoading = true
            self.loadError = nil
        }

        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                let doc = PDFDocument(url: url)
                DispatchQueue.main.async {
                    guard context.coordinator.loadedURL == url else { return }
                    if let doc = doc {
                        pdfView.document = doc
                        self.isLoading = false
                        self.searchState.performSearch()
                    } else {
                        self.loadError = "Failed to open PDF."
                        self.isLoading = false
                    }
                }
            }
        } else {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            context.coordinator.dataTask?.cancel()
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                DispatchQueue.main.async {
                    guard context.coordinator.loadedURL == url else { return }
                    if let data = data, let doc = PDFDocument(data: data) {
                        pdfView.document = doc
                        self.isLoading = false
                        self.searchState.performSearch()
                    } else {
                        self.loadError = error?.localizedDescription ?? "Failed to load PDF."
                        self.isLoading = false
                    }
                }
            }
            context.coordinator.dataTask = task
            task.resume()
        }
    }

    final class Coordinator {
        var parent: PDFKitView
        var loadedURL: URL?
        var dataTask: URLSessionDataTask?

        init(parent: PDFKitView) {
            self.parent = parent
        }
    }
}
