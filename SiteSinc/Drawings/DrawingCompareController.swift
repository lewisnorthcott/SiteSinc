import Foundation
import SwiftUI

@MainActor
final class DrawingCompareController: ObservableObject {
    @Published var isCompareMode = false
    @Published var comparisonRevision: Revision?
    @Published var comparisonPDFURL: URL?
    @Published var isLoadingComparison = false
    @Published var comparisonError: String?
    @Published var isComputingDiff = false
    @Published var overlayImage: UIImage?
    @Published var overlayJPEG: String?
    @Published var fromPageText = ""
    @Published var toPageText = ""
    @Published var pageNumber = 1
    @Published var baseIsNewer = true
    var computeGeneration = UUID()

    var canExplain: Bool {
        comparisonRevision != nil && overlayImage != nil
    }

    func reset() {
        assignIfNeeded(\.isCompareMode, false)
        if comparisonRevision != nil { comparisonRevision = nil }
        if comparisonPDFURL != nil { comparisonPDFURL = nil }
        if comparisonError != nil { comparisonError = nil }
        clearOverlay()
        assignIfNeeded(\.isComputingDiff, false)
        assignIfNeeded(\.isLoadingComparison, false)
    }

    func clearOverlay() {
        if overlayImage != nil { overlayImage = nil }
        if overlayJPEG != nil { overlayJPEG = nil }
        assignIfNeeded(\.fromPageText, "")
        assignIfNeeded(\.toPageText, "")
    }

    func apply(result: CompareDiffResult?, pageIndex: Int) {
        assignIfNeeded(\.pageNumber, pageIndex + 1)
        guard let result else {
            clearOverlay()
            if comparisonError == nil {
                comparisonError = "Could not compare this page."
            }
            return
        }
        overlayImage = result.image
        overlayJPEG = result.jpegDataURL
        assignIfNeeded(\.fromPageText, result.fromPageText)
        assignIfNeeded(\.toPageText, result.toPageText)
        if comparisonError != nil { comparisonError = nil }
    }

    func assignIfNeeded<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<DrawingCompareController, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
