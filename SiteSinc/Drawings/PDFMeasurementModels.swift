import CoreGraphics
import Foundation

// MARK: - Measurement tools (local-only; never persisted to the backend)

enum MeasurementTool: String, CaseIterable, Identifiable {
    case length
    case area
    case calibrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .length: return "Length"
        case .area: return "Area"
        case .calibrate: return "Calibrate"
        }
    }

    var systemImage: String {
        switch self {
        case .length: return "ruler"
        case .area: return "pentagon"
        case .calibrate: return "slider.horizontal.3"
        }
    }

    var instruction: String {
        switch self {
        case .length:
            return "Long-press to place start and end pins. Drag in the loupe to fine-tune."
        case .area:
            return "Long-press to place vertices. Place at least 3, then tap Done to close the shape."
        case .calibrate:
            return "Long-press two points on a known length, then enter its real-world size."
        }
    }
}

enum MeasurementUnit: String, CaseIterable, Identifiable, Codable {
    case meters
    case millimeters
    case feet
    case inches

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .meters: return "m"
        case .millimeters: return "mm"
        case .feet: return "ft"
        case .inches: return "in"
        }
    }

    var displayName: String {
        switch self {
        case .meters: return "Meters"
        case .millimeters: return "Millimeters"
        case .feet: return "Feet"
        case .inches: return "Inches"
        }
    }

    /// Convert a value expressed in this unit into meters.
    func toMeters(_ value: Double) -> Double {
        switch self {
        case .meters: return value
        case .millimeters: return value / 1000.0
        case .feet: return value * 0.3048
        case .inches: return value * 0.0254
        }
    }

    /// Convert a value in meters into this unit.
    func fromMeters(_ meters: Double) -> Double {
        switch self {
        case .meters: return meters
        case .millimeters: return meters * 1000.0
        case .feet: return meters / 0.3048
        case .inches: return meters / 0.0254
        }
    }
}

/// Maps PDF page points to real-world units.
struct DrawingScaleCalibration: Equatable, Codable {
    /// Real-world units represented by one PDF point (in `unit`).
    var unitsPerPoint: Double
    var unit: MeasurementUnit

    var metersPerPoint: Double {
        unit.toMeters(unitsPerPoint)
    }

    static func fromKnownLength(pdfDistancePoints: Double, realLength: Double, unit: MeasurementUnit) -> DrawingScaleCalibration? {
        guard pdfDistancePoints > 0.0001, realLength > 0 else { return nil }
        return DrawingScaleCalibration(unitsPerPoint: realLength / pdfDistancePoints, unit: unit)
    }
}

struct LengthMeasurement: Identifiable, Equatable {
    let id: UUID
    var start: CGPoint
    var end: CGPoint

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint) {
        self.id = id
        self.start = start
        self.end = end
    }

    var pdfDistance: Double {
        MeasurementGeometry.distance(start, end)
    }
}

struct AreaMeasurement: Identifiable, Equatable {
    let id: UUID
    var vertices: [CGPoint]

    init(id: UUID = UUID(), vertices: [CGPoint]) {
        self.id = id
        self.vertices = vertices
    }

    var pdfArea: Double {
        MeasurementGeometry.polygonArea(vertices)
    }

    var perimeterPDF: Double {
        MeasurementGeometry.polygonPerimeter(vertices)
    }
}

enum MeasurementGeometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(b.x - a.x), Double(b.y - a.y))
    }

    /// Shoelace formula; returns absolute area in PDF point².
    static func polygonArea(_ vertices: [CGPoint]) -> Double {
        guard vertices.count >= 3 else { return 0 }
        var sum: Double = 0
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            sum += Double(vertices[i].x) * Double(vertices[j].y)
            sum -= Double(vertices[j].x) * Double(vertices[i].y)
        }
        return abs(sum) * 0.5
    }

    static func polygonPerimeter(_ vertices: [CGPoint]) -> Double {
        guard vertices.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            total += distance(vertices[i], vertices[j])
        }
        return total
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    static func centroid(_ vertices: [CGPoint]) -> CGPoint {
        guard !vertices.isEmpty else { return .zero }
        let sum = vertices.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(vertices.count), y: sum.y / CGFloat(vertices.count))
    }
}

enum MeasurementFormatter {
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func formatNumber(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Formats a PDF-point distance using calibration when available.
    static func formatLength(pdfDistance: Double, calibration: DrawingScaleCalibration?) -> String {
        guard let calibration else {
            return "\(formatNumber(pdfDistance)) pt"
        }
        let value = pdfDistance * calibration.unitsPerPoint
        return "\(formatNumber(value)) \(calibration.unit.shortLabel)"
    }

    /// Formats a PDF-point² area using calibration when available.
    static func formatArea(pdfArea: Double, calibration: DrawingScaleCalibration?) -> String {
        guard let calibration else {
            return "\(formatNumber(pdfArea)) pt²"
        }
        let value = pdfArea * calibration.unitsPerPoint * calibration.unitsPerPoint
        return "\(formatNumber(value)) \(calibration.unit.shortLabel)²"
    }
}
