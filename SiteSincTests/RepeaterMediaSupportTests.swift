import XCTest
@testable import SiteSinc

final class RepeaterMediaSupportTests: XCTestCase {

    func testDataURLRoundTrip() {
        let original = Data("jpeg-bytes".utf8)
        let url = RepeaterMediaSupport.dataURL(fromJPEG: original)
        XCTAssertTrue(RepeaterMediaSupport.isLocalImagePayload(url))
        XCTAssertEqual(RepeaterMediaSupport.jpegData(fromStoredImage: url), original)
    }

    func testParseRowsHandlesNestedCameraObjects() {
        let json = """
        [{"name":"Row 1","photo":[{"image":"tenants/1/forms/a.jpg","capturedAt":"2026-01-01T00:00:00Z"}]}]
        """
        let rows = RepeaterMediaSupport.parseRows(from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(RepeaterMediaSupport.scalarString(rows[0]["name"]), "Row 1")
        XCTAssertFalse(RepeaterMediaSupport.isEmptyValue(rows[0]["photo"]))
        let items = RepeaterMediaSupport.mediaItems(fromStoredValue: rows[0]["photo"]!, isCamera: true)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].remoteRef, "tenants/1/forms/a.jpg")
    }

    func testStringDictsSurviveNestedObjects() {
        let json = """
        [{"note":"ok","image":["data:image/jpeg;base64,QQ=="]}]
        """
        let rows = RepeaterMediaSupport.rowsAsStringDicts(from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["note"], "ok")
        let refs = RepeaterMediaSupport.parseImageRefs(rows[0]["image"]!)
        XCTAssertEqual(refs.count, 1)
        XCTAssertTrue(RepeaterMediaSupport.isLocalImagePayload(refs[0]))
    }

    func testEncodeImageItemsSingleAndMultiple() {
        let one = RepeaterMediaItem(jpegData: Data("a".utf8))
        XCTAssertTrue(RepeaterMediaSupport.encodeImageItems([one]).hasPrefix("data:image/jpeg;base64,"))

        let two = [
            RepeaterMediaItem(jpegData: Data("a".utf8)),
            RepeaterMediaItem(remoteRef: "tenants/1/forms/b.jpg")
        ]
        let encoded = RepeaterMediaSupport.encodeImageItems(two)
        let refs = RepeaterMediaSupport.parseImageRefs(encoded)
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[1], "tenants/1/forms/b.jpg")
    }

    func testEncodeCameraItemsIncludesLocation() {
        let item = RepeaterMediaItem(
            jpegData: Data("cam".utf8),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            latitude: 51.5,
            longitude: -0.1,
            accuracy: 8,
            locationTimestamp: 1_700_000_000
        )
        let encoded = RepeaterMediaSupport.encodeCameraItems([item])
        let dicts = RepeaterMediaSupport.parseCameraDicts(encoded)
        XCTAssertEqual(dicts.count, 1)
        XCTAssertNotNil(dicts[0]["capturedAt"] as? String)
        let loc = dicts[0]["location"] as? [String: Any]
        XCTAssertEqual(loc?["latitude"] as? Double, 51.5)
        XCTAssertEqual(loc?["longitude"] as? Double, -0.1)
    }

    func testEmptyMediaIsEmptyValue() {
        XCTAssertTrue(RepeaterMediaSupport.isEmptyValue(""))
        XCTAssertTrue(RepeaterMediaSupport.isEmptyValue("[]"))
        XCTAssertTrue(RepeaterMediaSupport.isEmptyValue([Any]()))
        XCTAssertFalse(RepeaterMediaSupport.isEmptyValue("data:image/jpeg;base64,QQ=="))
        XCTAssertFalse(RepeaterMediaSupport.isEmptyValue(["tenants/1/forms/a.jpg"]))
    }

    func testExpandRowsPromotesCameraJSON() throws {
        let cameraJSON = RepeaterMediaSupport.encodeCameraItems([
            RepeaterMediaItem(remoteRef: "tenants/1/forms/a.jpg", capturedAt: Date())
        ])
        let rows = [["title": "A", "cam": cameraJSON]]
        let field = makeField(id: "cam", type: "camera")
        let expanded = RepeaterMediaSupport.expandRowsForStorage(rows, subFields: [field])
        XCTAssertTrue(expanded[0]["cam"] is [Any])
        XCTAssertEqual(expanded[0]["title"] as? String, "A")
    }

    func testRewriteUploadsDataURLsAndKeepsFileKeys() async throws {
        let jpeg = Data("new-photo".utf8)
        let dataURL = RepeaterMediaSupport.dataURL(fromJPEG: jpeg)
        let imageField = makeField(id: "img", type: "image")
        let cameraField = makeField(id: "cam", type: "camera")
        let rows: [[String: Any]] = [[
            "img": dataURL,
            "cam": [["image": dataURL, "capturedAt": "2026-01-01T00:00:00Z"]],
            "note": "keep"
        ]]

        var uploadedNames: [String] = []
        let rewritten = try await RepeaterMediaSupport.rewriteRowsForSubmission(
            rows,
            subFields: [imageField, cameraField],
            parentFieldId: "repeater1",
            uploadJPEG: { data, name in
                uploadedNames.append(name)
                XCTAssertEqual(data, jpeg)
                return "tenants/1/forms/\(name)"
            },
            fileKeyFromRef: { RepeaterMediaSupport.fileKey(from: $0) }
        )

        XCTAssertEqual(uploadedNames.count, 2)
        XCTAssertEqual(rewritten[0]["img"] as? String, "tenants/1/forms/\(uploadedNames[0])")
        let cam = rewritten[0]["cam"] as? [[String: Any]]
        XCTAssertEqual(cam?.first?["image"] as? String, "tenants/1/forms/\(uploadedNames[1])")
        XCTAssertEqual(rewritten[0]["note"] as? String, "keep")
    }

    func testRewriteLeavesExistingFileKeys() async throws {
        let imageField = makeField(id: "img", type: "image")
        let rows: [[String: Any]] = [[
            "img": "https://cdn.example.com/tenants/9/forms/kept.jpg?X-Amz-Algorithm=AWS4"
        ]]
        var uploadCount = 0
        let rewritten = try await RepeaterMediaSupport.rewriteRowsForSubmission(
            rows,
            subFields: [imageField],
            parentFieldId: "rep",
            uploadJPEG: { _, _ in
                uploadCount += 1
                return "should-not-upload"
            },
            fileKeyFromRef: { RepeaterMediaSupport.fileKey(from: $0) }
        )
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(rewritten[0]["img"] as? String, "tenants/9/forms/kept.jpg")
    }

    func testFileKeyExtractsTenantsPath() {
        XCTAssertEqual(
            RepeaterMediaSupport.fileKey(from: "tenants/1/forms/a.jpg"),
            "tenants/1/forms/a.jpg"
        )
        XCTAssertEqual(
            RepeaterMediaSupport.fileKey(from: "https://cdn.example.com/tenants/1/forms/a.jpg?X-Amz-Algorithm=AWS4"),
            "tenants/1/forms/a.jpg"
        )
    }

    func testValidationFindsMissingRequiredImage() {
        let imageField = makeField(id: "img", type: "image", required: true)
        let json = #"[{"img":""}]"#
        let issue = RepeaterMediaSupport.firstValidationIssue(in: json, subFields: [imageField])
        guard case .missingRequired(let row, let field)? = issue else {
            return XCTFail("Expected missing required image")
        }
        XCTAssertEqual(row, 0)
        XCTAssertEqual(field.id, "img")
    }

    func testValidationPassesFilledImageArray() {
        let imageField = makeField(id: "img", type: "image", required: true)
        let json = #"[{"img":["tenants/1/forms/a.jpg"]}]"#
        XCTAssertNil(RepeaterMediaSupport.firstValidationIssue(in: json, subFields: [imageField]))
    }

    func testMediaKeyParseAllowsUnderscoresInFieldId() {
        let key = RepeaterMediaSupport.mediaKey(fieldId: "site_photo", rowIndex: 2)
        let parsed = RepeaterMediaSupport.parseMediaKey(key)
        XCTAssertEqual(parsed?.fieldId, "site_photo")
        XCTAssertEqual(parsed?.rowIndex, 2)
    }

    private func makeField(id: String, type: String, required: Bool = false) -> FormField {
        FormField(
            id: id,
            label: id,
            type: type,
            required: required,
            options: nil,
            subFields: nil,
            minItems: nil,
            maxItems: nil,
            addButtonText: nil,
            removeButtonText: nil,
            description: nil,
            placeholder: nil,
            submissionRequirement: nil,
            closeoutSettings: nil,
            tableColumns: nil,
            minRows: nil,
            maxRows: nil,
            enableRowNames: nil,
            rowNameLabel: nil,
            tableMode: nil,
            staticRows: nil
        )
    }
}
