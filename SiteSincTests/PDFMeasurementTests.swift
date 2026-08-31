import XCTest
@testable import SiteSinc
import CoreGraphics

final class PDFMeasurementTests: XCTestCase {

    func testDistance_axisAligned() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 30, y: 40)
        XCTAssertEqual(MeasurementGeometry.distance(a, b), 50, accuracy: 0.0001)
    }

    func testPolygonArea_unitSquare() {
        let square: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        XCTAssertEqual(MeasurementGeometry.polygonArea(square), 100, accuracy: 0.0001)
    }

    func testPolygonArea_triangle() {
        let triangle: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 0, y: 3)
        ]
        XCTAssertEqual(MeasurementGeometry.polygonArea(triangle), 6, accuracy: 0.0001)
    }

    func testPolygonArea_requiresThreePoints() {
        XCTAssertEqual(MeasurementGeometry.polygonArea([.zero, CGPoint(x: 1, y: 1)]), 0)
    }

    func testPolygonPerimeter_square() {
        let square: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        XCTAssertEqual(MeasurementGeometry.polygonPerimeter(square), 40, accuracy: 0.0001)
    }

    func testCalibration_fromKnownLength() {
        let cal = DrawingScaleCalibration.fromKnownLength(
            pdfDistancePoints: 100,
            realLength: 5,
            unit: .meters
        )
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal!.unitsPerPoint, 0.05, accuracy: 0.000001)
        XCTAssertEqual(cal!.unit, .meters)
        XCTAssertEqual(cal!.metersPerPoint, 0.05, accuracy: 0.000001)
    }

    func testCalibration_rejectsInvalidInput() {
        XCTAssertNil(DrawingScaleCalibration.fromKnownLength(pdfDistancePoints: 0, realLength: 5, unit: .meters))
        XCTAssertNil(DrawingScaleCalibration.fromKnownLength(pdfDistancePoints: 10, realLength: 0, unit: .meters))
        XCTAssertNil(DrawingScaleCalibration.fromKnownLength(pdfDistancePoints: -1, realLength: 5, unit: .feet))
    }

    func testUnitConversion_metersRoundTrip() {
        XCTAssertEqual(MeasurementUnit.millimeters.fromMeters(1), 1000, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.feet.toMeters(1), 0.3048, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.inches.toMeters(12), 0.3048, accuracy: 0.0001)
    }

    func testFormatLength_uncalibratedUsesPoints() {
        let text = MeasurementFormatter.formatLength(pdfDistance: 12.5, calibration: nil)
        XCTAssertTrue(text.contains("pt"), text)
    }

    func testFormatLength_calibrated() {
        let cal = DrawingScaleCalibration(unitsPerPoint: 0.01, unit: .meters)
        let text = MeasurementFormatter.formatLength(pdfDistance: 250, calibration: cal)
        XCTAssertTrue(text.contains("m"), text)
        XCTAssertTrue(text.contains("2.5") || text.contains("2,5"), text)
    }

    func testFormatArea_calibrated() {
        let cal = DrawingScaleCalibration(unitsPerPoint: 0.1, unit: .meters)
        // 100 pt² * 0.01 m²/pt² = 1 m²
        let text = MeasurementFormatter.formatArea(pdfArea: 100, calibration: cal)
        XCTAssertTrue(text.contains("m²") || text.contains("m2") || text.contains("m"), text)
        XCTAssertTrue(text.contains("1"), text)
    }

    func testLengthMeasurement_pdfDistance() {
        let length = LengthMeasurement(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 3, y: 4))
        XCTAssertEqual(length.pdfDistance, 5, accuracy: 0.0001)
    }

    func testAreaMeasurement_pdfArea() {
        let area = AreaMeasurement(vertices: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 0, y: 2)
        ])
        XCTAssertEqual(area.pdfArea, 4, accuracy: 0.0001)
    }

    @MainActor
    func testController_placesLengthAfterTwoPoints() {
        let controller = PDFMeasurementController()
        controller.activate(tool: .length)
        controller.placePoint(CGPoint(x: 0, y: 0))
        XCTAssertEqual(controller.inProgressPoints.count, 1)
        controller.placePoint(CGPoint(x: 10, y: 0))
        XCTAssertEqual(controller.inProgressPoints.count, 0)
        XCTAssertEqual(controller.lengths.count, 1)
        XCTAssertEqual(controller.lengths[0].pdfDistance, 10, accuracy: 0.0001)
    }

    @MainActor
    func testController_areaRequiresDone() {
        let controller = PDFMeasurementController()
        controller.activate(tool: .area)
        controller.placePoint(CGPoint(x: 0, y: 0))
        controller.placePoint(CGPoint(x: 4, y: 0))
        controller.placePoint(CGPoint(x: 0, y: 3))
        XCTAssertEqual(controller.areas.count, 0)
        controller.finishAreaIfPossible()
        XCTAssertEqual(controller.areas.count, 1)
        XCTAssertEqual(controller.areas[0].pdfArea, 6, accuracy: 0.0001)
    }

    @MainActor
    func testController_calibrationSheet() {
        let controller = PDFMeasurementController()
        controller.activate(tool: .calibrate)
        controller.placePoint(CGPoint(x: 0, y: 0))
        controller.placePoint(CGPoint(x: 100, y: 0))
        XCTAssertTrue(controller.showCalibrationSheet)
        XCTAssertEqual(controller.pendingCalibrationDistance, 100, accuracy: 0.0001)
        controller.calibrationInput = "5"
        controller.calibrationUnit = .meters
        controller.applyCalibration()
        XCTAssertFalse(controller.showCalibrationSheet)
        XCTAssertNotNil(controller.calibration)
        XCTAssertEqual(controller.calibration!.unitsPerPoint, 0.05, accuracy: 0.000001)
        XCTAssertEqual(controller.tool, .length)
    }

    @MainActor
    func testController_undoInProgressThenCompleted() {
        let controller = PDFMeasurementController()
        controller.activate(tool: .length)
        controller.placePoint(CGPoint(x: 1, y: 1))
        controller.undoLast()
        XCTAssertTrue(controller.inProgressPoints.isEmpty)
        controller.placePoint(CGPoint(x: 0, y: 0))
        controller.placePoint(CGPoint(x: 5, y: 0))
        XCTAssertEqual(controller.lengths.count, 1)
        controller.undoLast()
        XCTAssertTrue(controller.lengths.isEmpty)
    }
}
