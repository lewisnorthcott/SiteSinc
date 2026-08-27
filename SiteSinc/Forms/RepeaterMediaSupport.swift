import Foundation
import CoreLocation
import UIKit

/// Local representation of a photo stored on a repeater image/camera sub-field.
struct RepeaterMediaItem: Identifiable, Equatable {
    let id: UUID
    /// Fresh JPEG bytes that still need uploading.
    var jpegData: Data?
    /// Existing remote URL or file key (already uploaded).
    var remoteRef: String?
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var locationTimestamp: Double?

    init(
        id: UUID = UUID(),
        jpegData: Data? = nil,
        remoteRef: String? = nil,
        capturedAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracy: Double? = nil,
        locationTimestamp: Double? = nil
    ) {
        self.id = id
        self.jpegData = jpegData
        self.remoteRef = remoteRef
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.locationTimestamp = locationTimestamp
    }

    var storedImageValue: String {
        if let jpegData, !jpegData.isEmpty {
            return RepeaterMediaSupport.dataURL(fromJPEG: jpegData)
        }
        return remoteRef ?? ""
    }

    var hasImage: Bool {
        (jpegData != nil && !(jpegData?.isEmpty ?? true)) || !(remoteRef?.isEmpty ?? true)
    }
}

enum RepeaterMediaSupport {
    static let maxPhotosPerField = 5
    static let mediaFieldTypes: Set<String> = ["image", "camera", "photo"]

    // MARK: - Data URLs

    static func dataURL(fromJPEG data: Data) -> String {
        "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    static func jpegData(fromStoredImage string: String) -> Data? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:image/") else { return nil }
        guard let range = trimmed.range(of: ";base64,") else { return nil }
        return Data(base64Encoded: String(trimmed[range.upperBound...]))
    }

    static func uiImage(fromStoredImage string: String) -> UIImage? {
        if let data = jpegData(fromStoredImage: string) {
            return UIImage(data: data)
        }
        return nil
    }

    static func isLocalImagePayload(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("data:image/")
    }

    // MARK: - Repeater JSON

    static func parseRows(from jsonString: String) -> [[String: Any]] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return parseRows(fromJSONObject: obj)
    }

    static func parseRows(fromJSONObject obj: Any) -> [[String: Any]] {
        if let rows = obj as? [[String: Any]] {
            return rows
        }
        if let arr = obj as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static func stringifyValue(_ value: Any) -> String {
        if value is NSNull {
            return ""
        }
        if let s = value as? String {
            return s
        }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }

    static func isEmptyValue(_ value: Any?) -> Bool {
        guard let value else { return true }
        if value is NSNull { return true }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "[]" || trimmed == "{}" || trimmed == "null"
        }
        if let arr = value as? [Any] {
            return arr.isEmpty
        }
        if let dict = value as? [String: Any] {
            if let image = dict["image"] as? String {
                return image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return dict.isEmpty
        }
        return false
    }

    static func scalarString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    /// Turns internally stored string cells (including JSON blobs) into typed JSON for the API.
    static func expandRowsForStorage(_ rows: [[String: String]], subFields: [FormField]) -> [[String: Any]] {
        let mediaIds = Set(subFields.filter { mediaFieldTypes.contains($0.type) }.map(\.id))
        return rows.map { row in
            var out: [String: Any] = [:]
            for (key, value) in row {
                if mediaIds.contains(key), let parsed = jsonObject(from: value) {
                    out[key] = parsed
                } else {
                    out[key] = value
                }
            }
            return out
        }
    }

    static func encodeRows(_ rows: [[String: String]], subFields: [FormField]) -> String? {
        let expanded = expandRowsForStorage(rows, subFields: subFields)
        guard JSONSerialization.isValidJSONObject(expanded),
              let data = try? JSONSerialization.data(withJSONObject: expanded, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func rowsAsStringDicts(from jsonString: String) -> [[String: String]] {
        parseRows(from: jsonString).map { row in
            Dictionary(uniqueKeysWithValues: row.map { ($0.key, stringifyValue($0.value)) })
        }
    }

    static func jsonObject(from string: String) -> Any? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Image / camera cell parsing

    static func parseImageRefs(_ value: Any) -> [String] {
        if let s = value as? String {
            if isEmptyValue(s) { return [] }
            if let obj = jsonObject(from: s) {
                return parseImageRefs(obj)
            }
            return [s]
        }
        if let arr = value as? [String] {
            return arr.filter { !isEmptyValue($0) }
        }
        if let arr = value as? [Any] {
            return arr.compactMap { item -> String? in
                if let s = item as? String, !isEmptyValue(s) { return s }
                if let d = item as? [String: Any], let image = d["image"] as? String, !isEmptyValue(image) {
                    return image
                }
                return nil
            }
        }
        if let d = value as? [String: Any], let image = d["image"] as? String, !isEmptyValue(image) {
            return [image]
        }
        return []
    }

    static func parseCameraDicts(_ value: Any) -> [[String: Any]] {
        if let s = value as? String {
            if isEmptyValue(s) { return [] }
            if let obj = jsonObject(from: s) {
                return parseCameraDicts(obj)
            }
            if isLocalImagePayload(s) || looksLikeImageRef(s) {
                return [["image": s]]
            }
            return []
        }
        if let dict = value as? [String: Any], dict["image"] != nil {
            return [dict]
        }
        if let arr = value as? [Any] {
            return arr.compactMap { item -> [String: Any]? in
                if let d = item as? [String: Any], d["image"] != nil {
                    return d
                }
                if let s = item as? String, !isEmptyValue(s) {
                    return ["image": s]
                }
                return nil
            }
        }
        return []
    }

    static func mediaItems(fromStoredValue value: Any, isCamera: Bool) -> [RepeaterMediaItem] {
        if isCamera {
            return parseCameraDicts(value).compactMap { dict in
                guard let image = dict["image"] as? String, !isEmptyValue(image) else { return nil }
                var item = RepeaterMediaItem()
                applyImageRef(image, to: &item)
                item.capturedAt = parseDate(dict["capturedAt"])
                if let loc = dict["location"] as? [String: Any] {
                    item.latitude = (loc["latitude"] as? NSNumber)?.doubleValue ?? loc["latitude"] as? Double
                    item.longitude = (loc["longitude"] as? NSNumber)?.doubleValue ?? loc["longitude"] as? Double
                    item.accuracy = (loc["accuracy"] as? NSNumber)?.doubleValue ?? loc["accuracy"] as? Double
                    item.locationTimestamp = (loc["timestamp"] as? NSNumber)?.doubleValue ?? loc["timestamp"] as? Double
                }
                return item
            }
        }
        return parseImageRefs(value).compactMap { ref in
            guard !isEmptyValue(ref) else { return nil }
            var item = RepeaterMediaItem()
            applyImageRef(ref, to: &item)
            return item
        }
    }

    static func encodeImageItems(_ items: [RepeaterMediaItem]) -> String {
        let refs = items.map(\.storedImageValue).filter { !$0.isEmpty }
        if refs.isEmpty { return "" }
        if refs.count == 1 { return refs[0] }
        guard JSONSerialization.isValidJSONObject(refs),
              let data = try? JSONSerialization.data(withJSONObject: refs, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return refs[0]
        }
        return json
    }

    static func encodeCameraItems(_ items: [RepeaterMediaItem]) -> String {
        let dicts: [[String: Any]] = items.compactMap { item in
            let image = item.storedImageValue
            guard !image.isEmpty else { return nil }
            var dict: [String: Any] = ["image": image]
            if let capturedAt = item.capturedAt {
                dict["capturedAt"] = ISO8601DateFormatter().string(from: capturedAt)
            }
            if let lat = item.latitude, let lon = item.longitude {
                var loc: [String: Any] = [
                    "latitude": lat,
                    "longitude": lon
                ]
                if let accuracy = item.accuracy { loc["accuracy"] = accuracy }
                if let ts = item.locationTimestamp { loc["timestamp"] = ts }
                dict["location"] = loc
            }
            return dict
        }
        if dicts.isEmpty { return "" }
        guard JSONSerialization.isValidJSONObject(dicts),
              let data = try? JSONSerialization.data(withJSONObject: dicts, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    static func item(from photo: PhotoWithLocation) -> RepeaterMediaItem {
        RepeaterMediaItem(
            jpegData: photo.image,
            capturedAt: photo.capturedAt,
            latitude: photo.location?.coordinate.latitude,
            longitude: photo.location?.coordinate.longitude,
            accuracy: photo.location?.horizontalAccuracy,
            locationTimestamp: photo.location?.timestamp.timeIntervalSince1970
        )
    }

    static func item(fromJPEG data: Data, capturedAt: Date = Date()) -> RepeaterMediaItem {
        RepeaterMediaItem(jpegData: data, capturedAt: capturedAt)
    }

    // MARK: - Upload rewrite

    static func rewriteRowsForSubmission(
        _ rows: [[String: Any]],
        subFields: [FormField],
        parentFieldId: String,
        uploadJPEG: (Data, String) async throws -> String,
        fileKeyFromRef: (String) -> String
    ) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        for (rowIndex, row) in rows.enumerated() {
            var newRow = row
            for subField in subFields {
                guard let raw = row[subField.id] else { continue }
                switch subField.type {
                case "image":
                    var keys: [String] = []
                    for (i, ref) in parseImageRefs(raw).enumerated() {
                        if let data = jpegData(fromStoredImage: ref) {
                            let name = "\(parentFieldId)-\(subField.id)-r\(rowIndex)-\(i).jpg"
                            keys.append(try await uploadJPEG(data, name))
                        } else if !ref.isEmpty {
                            keys.append(fileKeyFromRef(ref))
                        }
                    }
                    if keys.isEmpty {
                        newRow[subField.id] = ""
                    } else if keys.count == 1 {
                        newRow[subField.id] = keys[0]
                    } else {
                        newRow[subField.id] = keys
                    }
                case "camera", "photo":
                    var items = parseCameraDicts(raw)
                    for i in items.indices {
                        guard let image = items[i]["image"] as? String, !image.isEmpty else { continue }
                        if let data = jpegData(fromStoredImage: image) {
                            let name = "\(parentFieldId)-\(subField.id)-r\(rowIndex)-\(i).jpg"
                            items[i]["image"] = try await uploadJPEG(data, name)
                        } else {
                            items[i]["image"] = fileKeyFromRef(image)
                        }
                    }
                    newRow[subField.id] = items
                default:
                    break
                }
            }
            result.append(newRow)
        }
        return result
    }

    static func fileKey(from ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isLocalImagePayload(trimmed) { return trimmed }
        if trimmed.hasPrefix("tenants/") { return trimmed }

        var working = trimmed
        if let decoded = working.removingPercentEncoding {
            working = decoded
        }
        if let url = URL(string: working) {
            let path = url.path
            if let range = path.range(of: "tenants/") {
                var key = String(path[range.lowerBound...])
                if key.hasPrefix("/") { key.removeFirst() }
                return key
            }
            if url.query?.contains("AWSAccessKeyId") == true || url.query?.contains("X-Amz-Algorithm") == true {
                var key = url.path
                if key.hasPrefix("/") { key.removeFirst() }
                return key
            }
        }
        return trimmed
    }

    static func looksLikeImageRef(_ string: String) -> Bool {
        let s = string.lowercased()
        return s.hasPrefix("http")
            || s.hasPrefix("tenants/")
            || s.contains("amazonaws")
            || s.contains("sitesinc")
            || s.contains("/forms/")
    }

    static func parseMediaKey(_ key: String) -> (fieldId: String, rowIndex: Int)? {
        let components = key.split(separator: "_")
        guard components.count >= 2, let rowIndex = Int(components.last!) else { return nil }
        let fieldId = components.dropLast().joined(separator: "_")
        return (fieldId, rowIndex)
    }

    static func mediaKey(fieldId: String, rowIndex: Int) -> String {
        "\(fieldId)_\(rowIndex)"
    }

    static func isCameraType(_ type: String) -> Bool {
        type == "camera" || type == "photo"
    }

    // MARK: - Validation

    enum RepeaterValidationIssue {
        case missingRequired(row: Int, subField: FormField)
        case submissionRequirement(row: Int, subField: FormField, message: String)
    }

    static func firstValidationIssue(in jsonString: String?, subFields: [FormField]) -> RepeaterValidationIssue? {
        guard let jsonString, !jsonString.isEmpty else { return nil }
        let rows = parseRows(from: jsonString)
        for (index, row) in rows.enumerated() {
            for subField in subFields {
                if subField.required && isEmptyValue(row[subField.id]) {
                    return .missingRequired(row: index, subField: subField)
                }
                if let req = subField.submissionRequirement, req.requiredForSubmission {
                    let value = scalarString(row[subField.id])
                    if value.lowercased() != req.requiredValue.lowercased() {
                        return .submissionRequirement(row: index, subField: subField, message: req.validationMessage)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Private

    private static func applyImageRef(_ ref: String, to item: inout RepeaterMediaItem) {
        if let data = jpegData(fromStoredImage: ref) {
            item.jpegData = data
        } else {
            item.remoteRef = ref
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let s = value as? String {
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)
        }
        if let n = value as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        return nil
    }
}
