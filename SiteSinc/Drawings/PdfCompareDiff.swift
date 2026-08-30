import UIKit
import PDFKit

/// Construction-drawing redline: shared ink stays black, unique ink is red or blue.
enum PdfCompareDiff {
    static let red = (r: UInt8(239), g: UInt8(68), b: UInt8(68))   // #ef4444
    static let blue = (r: UInt8(37), g: UInt8(99), b: UInt8(235))  // #2563eb

    static let defaultInkThreshold = 240
    static let maxDiffPixels = 16_000_000
    static let defaultMaxDimension: CGFloat = 1600

    /// Currently viewed revision is treated as newer when dates/versions cannot decide.
    static func isBaseRevisionNewer(current: Revision?, comparison: Revision?) -> Bool {
        guard let current, let comparison else { return true }
        if current.versionNumber != comparison.versionNumber {
            return current.versionNumber > comparison.versionNumber
        }
        let a = parseDate(current.uploadedAt)
        let b = parseDate(comparison.uploadedAt)
        if let a, let b, a != b { return a > b }
        return true
    }

    static func defaultComparisonRevision(current: Revision?, all: [Revision]) -> Revision? {
        guard let current else {
            return all.sorted { $0.versionNumber > $1.versionNumber }.dropFirst().first
        }
        let sorted = all.sorted { $0.versionNumber > $1.versionNumber }
        if let older = sorted.first(where: { $0.versionNumber < current.versionNumber && $0.id != current.id }) {
            return older
        }
        return sorted.first(where: { $0.id != current.id })
    }

    static func pdfFile(in revision: Revision?) -> DrawingFile? {
        revision?.drawingFiles.first { file in
            file.fileName.lowercased().hasSuffix(".pdf") || file.fileType.lowercased().contains("pdf")
        }
    }

    /// Rasterize two PDF pages and classify ink. `baseIsNewer` means the currently
    /// viewed document is the newer revision (blue unique / red unique on comparison).
    static func diffPages(
        baseURL: URL,
        comparisonURL: URL,
        pageIndex: Int,
        baseIsNewer: Bool,
        maxDimension: CGFloat = defaultMaxDimension
    ) -> CompareDiffResult? {
        guard let baseDoc = PDFDocument(url: baseURL),
              let comparisonDoc = PDFDocument(url: comparisonURL) else { return nil }
        guard pageIndex >= 0,
              let basePage = baseDoc.page(at: pageIndex),
              pageIndex < comparisonDoc.pageCount,
              let comparisonPage = comparisonDoc.page(at: pageIndex) else { return nil }

        let olderPage = baseIsNewer ? comparisonPage : basePage
        let newerPage = baseIsNewer ? basePage : comparisonPage

        guard let olderImage = render(olderPage, maxDimension: maxDimension),
              var newerImage = render(newerPage, maxDimension: maxDimension) else { return nil }

        if newerImage.width != olderImage.width || newerImage.height != olderImage.height {
            guard let scaled = scale(newerImage, toWidth: olderImage.width, height: olderImage.height) else { return nil }
            newerImage = scaled
        }

        guard let overlay = diffInk(oldImage: olderImage, newImage: newerImage) else { return nil }
        let fromText = clipPageText(basePage.string)
        let toText = clipPageText(comparisonPage.string)
        return CompareDiffResult(
            image: overlay,
            jpegDataURL: jpegDataURL(from: overlay),
            fromPageText: fromText,
            toPageText: toText
        )
    }

    static func jpegDataURL(from image: UIImage, maxWidth: CGFloat = 2200, quality: CGFloat = 0.88) -> String? {
        var output = image
        if image.size.width > maxWidth, image.size.width > 0 {
            let scale = maxWidth / image.size.width
            let size = CGSize(width: maxWidth, height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = output.jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    // MARK: - Rasterize

    static func render(_ page: PDFPage, maxDimension: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        var scale = min(maxDimension / bounds.width, maxDimension / bounds.height)
        var pixelW = bounds.width * scale
        var pixelH = bounds.height * scale
        if pixelW * pixelH > CGFloat(maxDiffPixels) {
            scale *= sqrt(CGFloat(maxDiffPixels) / (pixelW * pixelH))
            pixelW = bounds.width * scale
            pixelH = bounds.height * scale
        }
        let size = CGSize(width: max(1, floor(pixelW)), height: max(1, floor(pixelH)))
        let drawScale = size.width / bounds.width

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let uiImage = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: drawScale, y: -drawScale)
            ctx.cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
        return uiImage.cgImage
    }

    // MARK: - Pixel buffers

    private static func rgbaBytes(from image: CGImage) -> (UnsafeMutablePointer<UInt8>, Int, Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let count = width * height * 4
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        ptr.initialize(repeating: 255, count: count)
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: ptr,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: bitmapInfo
        ) else {
            ptr.deallocate()
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (ptr, width, height)
    }

    private static func scale(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func diffInk(oldImage: CGImage, newImage: CGImage) -> UIImage? {
        guard let oldBuf = rgbaBytes(from: oldImage),
              let newBuf = rgbaBytes(from: newImage) else { return nil }
        defer {
            oldBuf.0.deallocate()
            newBuf.0.deallocate()
        }
        let width = oldBuf.1
        let height = oldBuf.2
        guard newBuf.1 == width, newBuf.2 == height else { return nil }

        let count = width * height * 4
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        out.initialize(repeating: 255, count: count)
        defer { out.deallocate() }

        diffInkBuffers(
            oldBuf: oldBuf.0,
            newBuf: newBuf.0,
            outBuf: out,
            width: width,
            height: height
        )

        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: out,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: bitmapInfo
        ), let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    static func diffInkBuffers(
        oldBuf: UnsafePointer<UInt8>,
        newBuf: UnsafePointer<UInt8>,
        outBuf: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        inkThreshold: Int = defaultInkThreshold,
        neighbourMatch: Bool = true
    ) {
        let pixelCount = width * height
        for p in 0..<pixelCount {
            let i = p * 4
            let x = p % width
            let y = p / width
            let oldInk = luminance(oldBuf[i], oldBuf[i + 1], oldBuf[i + 2]) < inkThreshold
            let newInk = luminance(newBuf[i], newBuf[i + 1], newBuf[i + 2]) < inkThreshold

            if oldInk && newInk {
                writePixel(outBuf, i, 0, 0, 0)
                continue
            }
            if oldInk && !newInk {
                if neighbourMatch && hasNeighbourInk(newBuf, width: width, height: height, x: x, y: y, threshold: inkThreshold) {
                    writePixel(outBuf, i, 0, 0, 0)
                } else {
                    writePixel(outBuf, i, red.r, red.g, red.b)
                }
                continue
            }
            if !oldInk && newInk {
                if neighbourMatch && hasNeighbourInk(oldBuf, width: width, height: height, x: x, y: y, threshold: inkThreshold) {
                    writePixel(outBuf, i, 0, 0, 0)
                } else {
                    writePixel(outBuf, i, blue.r, blue.g, blue.b)
                }
                continue
            }
            writePixel(outBuf, i, 255, 255, 255)
        }
    }

    @inline(__always)
    private static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        (299 * Int(r) + 587 * Int(g) + 114 * Int(b)) / 1000
    }

    @inline(__always)
    private static func writePixel(_ out: UnsafeMutablePointer<UInt8>, _ i: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        out[i] = r
        out[i + 1] = g
        out[i + 2] = b
        out[i + 3] = 255
    }

    private static func isInkAt(
        _ data: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        threshold: Int
    ) -> Bool {
        if x < 0 || y < 0 || x >= width || y >= height { return false }
        let i = (y * width + x) * 4
        return luminance(data[i], data[i + 1], data[i + 2]) < threshold
    }

    private static func hasNeighbourInk(
        _ data: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        threshold: Int
    ) -> Bool {
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                if isInkAt(data, width: width, height: height, x: x + dx, y: y + dy, threshold: threshold) {
                    return true
                }
            }
        }
        return false
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        if let d = frac.date(from: value) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return plain.date(from: value)
    }

    private static func clipPageText(_ value: String?, maxChars: Int = 14000) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars - 1)) + "…"
    }
}

struct CompareDiffResult {
    let image: UIImage
    let jpegDataURL: String?
    let fromPageText: String
    let toPageText: String
}
