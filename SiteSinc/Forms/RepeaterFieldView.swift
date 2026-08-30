import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation

// MARK: - Repeater media keys & submit helpers
enum RepeaterMediaSupport {
    static let keyPrefix = "repeaterMedia::"

    static func makeKey(repeaterId: String, row: Int, subFieldId: String) -> String {
        "\(keyPrefix)\(repeaterId)::\(row)::\(subFieldId)"
    }

    static func parse(_ key: String) -> (repeaterId: String, row: Int, subFieldId: String)? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        let parts = String(key.dropFirst(keyPrefix.count)).components(separatedBy: "::")
        guard parts.count == 3, let row = Int(parts[1]) else { return nil }
        return (parts[0], row, parts[2])
    }

    static func isRepeaterMedia(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix)
    }

    static func toStorageKey(_ value: String) -> String {
        guard let url = URL(string: value), url.scheme == "http" || url.scheme == "https" else {
            return value
        }
        if url.query?.contains("X-Amz-Algorithm") == true || url.query?.contains("AWSAccessKeyId") == true {
            return String(url.path.dropFirst())
        }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        if path.hasPrefix("tenants/") { return path }
        return value
    }

    static func normalizeStoredMediaItem(_ item: Any) -> Any {
        if let s = item as? String { return toStorageKey(s) }
        if var obj = item as? [String: Any], let image = obj["image"] as? String {
            obj["image"] = toStorageKey(image)
            return obj
        }
        return item
    }

    static func jsonString(from value: Any) -> String {
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: data, encoding: .utf8) else {
            return ""
        }
        return s
    }

    static func parseRepeaterValue(_ jsonString: String, subFields: [FormField]?) -> [[String: Any]] {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return expandNestedJSONStrings(raw, subFields: subFields)
    }

    static func expandNestedJSONStrings(_ rows: [[String: Any]], subFields: [FormField]?) -> [[String: Any]] {
        rows.map { row in
            var out: [String: Any] = [:]
            for (key, value) in row {
                let subType = subFields?.first(where: { $0.id == key })?.type
                if let s = value as? String,
                   (subType == "camera" || subType == "image" || subType == "attachment"),
                   (s.hasPrefix("{") || s.hasPrefix("[")),
                   let nestedData = s.data(using: .utf8),
                   let nested = try? JSONSerialization.jsonObject(with: nestedData) {
                    out[key] = nested
                } else {
                    out[key] = value
                }
            }
            return out
        }
    }

    static func normalizeList(_ value: Any?) -> [Any] {
        guard let value else { return [] }
        if let arr = value as? [Any] { return arr }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "[]" || trimmed == "null" { return [] }
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
               let data = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                if let arr = parsed as? [Any] { return arr }
                return [parsed]
            }
            return [s]
        }
        if value is [String: Any] { return [value] }
        return [value]
    }

    static func storedValueIsEmpty(_ stored: String?) -> Bool {
        guard let stored else { return true }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "[]" || trimmed == "null" || trimmed == "{}"
    }

    static func subFieldHasValue(
        repeaterId: String,
        rowIndex: Int,
        rowData: [String: String],
        subField: FormField,
        stagedCameraData: [String: [PhotoWithLocation]],
        capturedImages: [String: [UIImage]]
    ) -> Bool {
        let key = makeKey(repeaterId: repeaterId, row: rowIndex, subFieldId: subField.id)
        if stagedCameraData[key]?.isEmpty == false { return true }
        if capturedImages[key]?.isEmpty == false { return true }
        if subField.type == "checkbox" {
            return rowData.contains { $0.key.hasPrefix(subField.id + "_") && $0.value == "true" }
        }
        return !storedValueIsEmpty(rowData[subField.id])
    }

    static func displayURLs(from stored: String?) -> [URL] {
        let items = normalizeList(stored)
        return items.compactMap { item -> URL? in
            let raw: String
            if let s = item as? String {
                raw = s
            } else if let obj = item as? [String: Any], let image = obj["image"] as? String {
                raw = image
            } else {
                return nil
            }
            if raw.hasPrefix("data:image/") { return URL(string: raw) }
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
            return nil
        }
    }

    static func cameraDictionary(from photo: PhotoWithLocation, fileKey: String) -> [String: Any] {
        var dict: [String: Any] = [
            "image": fileKey,
            "capturedAt": ISO8601DateFormatter().string(from: photo.capturedAt)
        ]
        if let location = photo.location {
            dict["location"] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
        }
        return dict
    }

    static func injectPendingMedia(
        into processedFormData: inout [String: Any],
        fields: [FormField],
        stagedCameraData: [String: [PhotoWithLocation]],
        capturedImages: [String: [UIImage]],
        upload: (Data, String, String) async throws -> String
    ) async throws {
        for field in fields where field.type == "repeater" {
            var rows: [[String: Any]]
            if let existing = processedFormData[field.id] as? [[String: Any]] {
                rows = expandNestedJSONStrings(existing, subFields: field.subFields)
            } else if let existing = processedFormData[field.id] as? [Any] {
                rows = expandNestedJSONStrings(
                    existing.compactMap { $0 as? [String: Any] },
                    subFields: field.subFields
                )
            } else if let s = processedFormData[field.id] as? String {
                rows = parseRepeaterValue(s, subFields: field.subFields)
            } else {
                rows = []
            }

            let subFields = field.subFields ?? []
            let mediaKeys = Array(stagedCameraData.keys) + Array(capturedImages.keys)
            let maxRowFromMedia = mediaKeys
                .compactMap { parse($0) }
                .filter { $0.repeaterId == field.id }
                .map { $0.row }
                .max() ?? -1
            while rows.count <= maxRowFromMedia {
                rows.append([:])
            }

            for rowIndex in rows.indices {
                for subField in subFields {
                    let key = makeKey(repeaterId: field.id, row: rowIndex, subFieldId: subField.id)
                    if subField.type == "camera" {
                        var items = normalizeList(rows[rowIndex][subField.id])
                        if let photos = stagedCameraData[key] {
                            for (index, photo) in photos.enumerated() {
                                let fileName = "\(key)-staged-\(index).jpg"
                                let fileKey = try await upload(photo.image, fileName, key)
                                items.append(cameraDictionary(from: photo, fileKey: fileKey))
                            }
                        }
                        if let images = capturedImages[key] {
                            for (index, image) in images.enumerated() {
                                guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
                                let fileName = "\(key)-captured-\(index).jpg"
                                let fileKey = try await upload(data, fileName, key)
                                items.append([
                                    "image": fileKey,
                                    "capturedAt": ISO8601DateFormatter().string(from: Date())
                                ])
                            }
                        }
                        items = items.map { normalizeStoredMediaItem($0) }
                        if !items.isEmpty {
                            rows[rowIndex][subField.id] = items
                        }
                    } else if subField.type == "image" {
                        var items = normalizeList(rows[rowIndex][subField.id])
                        if let images = capturedImages[key] {
                            for (index, image) in images.enumerated() {
                                guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
                                let fileName = "\(key)-captured-\(index).jpg"
                                let fileKey = try await upload(data, fileName, key)
                                items.append(fileKey)
                            }
                        }
                        if let photos = stagedCameraData[key] {
                            for (index, photo) in photos.enumerated() {
                                let fileName = "\(key)-staged-\(index).jpg"
                                let fileKey = try await upload(photo.image, fileName, key)
                                items.append(fileKey)
                            }
                        }
                        items = items.map { normalizeStoredMediaItem($0) }
                        if !items.isEmpty {
                            rows[rowIndex][subField.id] = items
                        }
                    }
                }
            }

            processedFormData[field.id] = rows
        }
    }
}

// MARK: - RepeaterFieldView
struct RepeaterFieldView: View {
    let field: FormField
    @Binding var responses: [String: String]
    @Binding var stagedCameraData: [String: [PhotoWithLocation]]
    @Binding var capturedImages: [String: [UIImage]]
    @Binding var photoPreviews: [String: [UIImage]]

    @State private var repeaterData: [[String: String]] = []
    @State private var showingSignaturePad: String? // fieldId_rowIndex format
    @State private var signatureImages: [String: UIImage] = [:] // fieldId_rowIndex -> UIImage

    @State private var mediaActionKey: String?
    @State private var mediaActionType: String = "image"
    @State private var showingMediaDialog = false
    @State private var showingPhotosPicker = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var isCustomCameraPresented = false
    @State private var cameraSessionPhotos: [PhotoWithLocation] = []
    @State private var showingImagePicker = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""

    private var minItems: Int { field.minItems ?? 0 }
    private var maxItems: Int { field.maxItems ?? 10 }
    private var addButtonText: String { field.addButtonText ?? "Add \(field.label)" }
    private var removeButtonText: String { field.removeButtonText ?? "Remove" }

    private var isSheetPresented: Binding<Bool> {
        Binding<Bool>(
            get: { showingSignaturePad != nil },
            set: { if !$0 { showingSignaturePad = nil } }
        )
    }

    private func signatureImageBinding(for key: String) -> Binding<UIImage?> {
        Binding<UIImage?>(
            get: { signatureImages[key] },
            set: { newImage in
                handleSignatureImageChange(key: key, image: newImage)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            itemsCountHeader
            itemsList
            addButton
            maxItemsReachedText
        }
        .onAppear {
            loadExistingData()
        }
        .onChange(of: repeaterData) { _, _ in
            saveRepeaterData()
        }
        .sheet(isPresented: isSheetPresented) {
            signaturePadSheet
        }
        .sheet(isPresented: $showingImagePicker) {
            CameraPickerWithLocation(
                onImageCaptured: { photo in
                    applyCapturedPhotos([photo])
                },
                onDismiss: {
                    showingImagePicker = false
                    mediaActionKey = nil
                }
            )
        }
        .fullScreenCover(isPresented: $isCustomCameraPresented, onDismiss: {
            let key = mediaActionKey
            cameraSessionPhotos = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if mediaActionKey == key {
                    mediaActionKey = nil
                }
            }
        }) {
            CustomCameraView(capturedImages: $cameraSessionPhotos)
        }
        .onChange(of: cameraSessionPhotos) { oldValue, newValue in
            let newItems = Array(newValue.dropFirst(oldValue.count))
            guard !newItems.isEmpty else { return }
            applyCapturedPhotos(newItems)
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $pickerSelection, maxSelectionCount: 5, matching: .images)
        .onChange(of: pickerSelection) { _, newItems in
            handleLibrarySelection(newItems)
        }
        .confirmationDialog(
            "Add Image",
            isPresented: $showingMediaDialog,
            titleVisibility: .visible
        ) {
            Button("Take Photo") {
                requestCameraAccessAndCapture()
            }
            Button("Choose From Library") {
                showingPhotosPicker = true
            }
            Button("Cancel", role: .cancel) {
                mediaActionKey = nil
            }
        } message: {
            Text("Take a new photo or pick from your library.")
        }
        .alert("Camera Access", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(permissionAlertMessage)
        }
    }

    @ViewBuilder
    private var itemsCountHeader: some View {
        HStack {
            Text("Items: \(repeaterData.count)/\(maxItems)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var itemsList: some View {
        ForEach(Array(repeaterData.enumerated()), id: \.offset) { index, item in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(field.label) #\(index + 1)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    if repeaterData.count > minItems {
                        Button(action: {
                            removeItem(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }

                if let subFields = field.subFields {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(subFields, id: \.id) { subField in
                            renderSubField(subField: subField, rowIndex: index)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if repeaterData.count < maxItems {
            Button(action: addItem) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(addButtonText)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private var maxItemsReachedText: some View {
        if repeaterData.count >= maxItems {
            Text("Maximum of \(maxItems) items reached")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var signaturePadSheet: some View {
        if let currentSignatureKey = showingSignaturePad {
            SignaturePadView(
                signatureImage: signatureImageBinding(for: currentSignatureKey),
                onDismiss: {
                    showingSignaturePad = nil
                }
            )
        }
    }

    private func handleSignatureImageChange(key: String, image: UIImage?) {
        if let image = image {
            signatureImages[key] = image
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let base64String = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                updateSignatureInRepeaterData(fieldKey: key, signature: base64String)
            }
        } else {
            signatureImages.removeValue(forKey: key)
            updateSignatureInRepeaterData(fieldKey: key, signature: "")
        }
    }

    private func loadExistingData() {
        if let existingJson = responses[field.id], !existingJson.isEmpty {
            if let data = existingJson.data(using: .utf8),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                repeaterData = raw.map { row in
                    var converted: [String: String] = [:]
                    for (k, v) in row {
                        if let s = v as? String {
                            converted[k] = s
                        } else {
                            converted[k] = RepeaterMediaSupport.jsonString(from: v)
                        }
                    }
                    return converted
                }

                for (rowIndex, rowData) in repeaterData.enumerated() {
                    if let subFields = field.subFields {
                        for subField in subFields where subField.type == "signature" {
                            if let base64String = rowData[subField.id], !base64String.isEmpty {
                                if let image = base64ToUIImage(base64String) {
                                    let signatureKey = "\(subField.id)_\(rowIndex)"
                                    signatureImages[signatureKey] = image
                                }
                            }
                        }
                    }
                }
            }
        }

        while repeaterData.count < minItems {
            addItem()
        }
    }

    private func base64ToUIImage(_ base64String: String) -> UIImage? {
        let base64Data: String
        if base64String.hasPrefix("data:image/") {
            guard let range = base64String.range(of: ";base64,") else { return nil }
            base64Data = String(base64String[range.upperBound...])
        } else {
            base64Data = base64String
        }

        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return UIImage(data: data)
    }

    private func saveRepeaterData() {
        do {
            let jsonData = try JSONEncoder().encode(repeaterData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                responses[field.id] = jsonString
            }
        } catch {
            print("Failed to encode repeater data: \(error)")
        }
    }

    private func addItem() {
        guard repeaterData.count < maxItems else { return }

        var newItem: [String: String] = [:]
        field.subFields?.forEach { subField in
            newItem[subField.id] = ""
        }
        repeaterData.append(newItem)
    }

    private func removeItem(at index: Int) {
        guard index < repeaterData.count, repeaterData.count > minItems else { return }
        reindexMedia(removedRow: index)
        repeaterData.remove(at: index)
    }

    private func reindexMedia(removedRow: Int) {
        func reindex<T>(_ dict: inout [String: T]) {
            var updated: [String: T] = [:]
            for (key, value) in dict {
                guard let parsed = RepeaterMediaSupport.parse(key), parsed.repeaterId == field.id else {
                    updated[key] = value
                    continue
                }
                if parsed.row == removedRow { continue }
                let newRow = parsed.row > removedRow ? parsed.row - 1 : parsed.row
                updated[RepeaterMediaSupport.makeKey(repeaterId: parsed.repeaterId, row: newRow, subFieldId: parsed.subFieldId)] = value
            }
            dict = updated
        }
        reindex(&stagedCameraData)
        reindex(&capturedImages)
        reindex(&photoPreviews)
    }

    private func updateSignatureInRepeaterData(fieldKey: String, signature: String) {
        let components = fieldKey.split(separator: "_")

        guard components.count >= 2,
              let rowIndex = Int(components.last!) else {
            return
        }

        let fieldIdComponents = components.dropLast()
        let fieldId = fieldIdComponents.joined(separator: "_")

        if rowIndex < repeaterData.count {
            repeaterData[rowIndex][fieldId] = signature
        }
    }

    private func mediaKey(subFieldId: String, rowIndex: Int) -> String {
        RepeaterMediaSupport.makeKey(repeaterId: field.id, row: rowIndex, subFieldId: subFieldId)
    }

    private func applyCapturedPhotos(_ photos: [PhotoWithLocation]) {
        guard let key = mediaActionKey, !photos.isEmpty else { return }
        if mediaActionType == "camera" {
            stagedCameraData[key, default: []].append(contentsOf: photos)
        } else {
            for photo in photos {
                if let image = UIImage(data: photo.image) {
                    capturedImages[key, default: []].append(image)
                }
            }
        }
        for photo in photos {
            if let image = UIImage(data: photo.image) {
                photoPreviews[key, default: []].append(image.thumbnail(maxPixelSize: 400))
            }
        }
    }

    private func handleLibrarySelection(_ newItems: [PhotosPickerItem]) {
        guard let key = mediaActionKey, !newItems.isEmpty else {
            if newItems.isEmpty { mediaActionKey = nil }
            return
        }
        let fieldType = mediaActionType
        Task {
            var photos: [PhotoWithLocation] = []
            var images: [UIImage] = []
            for item in newItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photos.append(PhotoWithLocation(image: data, location: nil, capturedAt: Date()))
                    if let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
            }
            await MainActor.run {
                if fieldType == "camera" {
                    stagedCameraData[key, default: []].append(contentsOf: photos)
                } else {
                    capturedImages[key, default: []].append(contentsOf: images)
                }
                photoPreviews[key, default: []].append(contentsOf: images.map { $0.thumbnail(maxPixelSize: 400) })
                pickerSelection = []
                mediaActionKey = nil
            }
        }
    }

    private func requestCameraAccessAndCapture() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            isCustomCameraPresented = true
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isCustomCameraPresented = true
                    } else {
                        permissionAlertMessage = "Camera access is required. Enable it in Settings."
                        showingPermissionAlert = true
                    }
                }
            }
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingImagePicker = true
        } else {
            permissionAlertMessage = "Camera access is required. Enable it in Settings."
            showingPermissionAlert = true
        }
    }

    private func removeLocalMedia(key: String, index: Int) {
        if var staged = stagedCameraData[key], index < staged.count {
            staged.remove(at: index)
            stagedCameraData[key] = staged.isEmpty ? nil : staged
        }
        if var captured = capturedImages[key], index < captured.count {
            captured.remove(at: index)
            capturedImages[key] = captured.isEmpty ? nil : captured
        }
        if var previews = photoPreviews[key], index < previews.count {
            previews.remove(at: index)
            photoPreviews[key] = previews.isEmpty ? nil : previews
        }
    }

    private func removeExistingStoredMedia(rowIndex: Int, subFieldId: String, index: Int) {
        guard rowIndex < repeaterData.count else { return }
        var items = RepeaterMediaSupport.normalizeList(repeaterData[rowIndex][subFieldId])
        guard index < items.count else { return }
        items.remove(at: index)
        repeaterData[rowIndex][subFieldId] = items.isEmpty ? "" : RepeaterMediaSupport.jsonString(from: items)
    }

    @ViewBuilder
    private func renderSubField(subField: FormField, rowIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(subField.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if subField.required {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()

                if subField.required {
                    let isFilled = RepeaterMediaSupport.subFieldHasValue(
                        repeaterId: field.id,
                        rowIndex: rowIndex,
                        rowData: repeaterData[safe: rowIndex] ?? [:],
                        subField: subField,
                        stagedCameraData: stagedCameraData,
                        capturedImages: capturedImages
                    )

                    if isFilled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
            }

            switch subField.type {
            case "text", "input":
                TextField("Enter \(subField.label.lowercased())", text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())

            case "textarea":
                TextEditor(text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))

            case "yesNoNA":
                Picker("", selection: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                )) {
                    Text("Select").tag("")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                    Text("N/A").tag("na")
                }
                .pickerStyle(SegmentedPickerStyle())

            case "dropdown":
                Picker(subField.label, selection: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                )) {
                    Text("Select").tag("")
                    ForEach(subField.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())

            case "radio":
                if let options = subField.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                if rowIndex < repeaterData.count {
                                    repeaterData[rowIndex][subField.id] = option
                                }
                            }) {
                                HStack {
                                    Image(systemName: (repeaterData[safe: rowIndex]?[subField.id] == option) ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(.blue)
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

            case "checkbox":
                if let options = subField.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(options, id: \.self) { option in
                            let isSelected = (repeaterData[safe: rowIndex]?[subField.id + "_" + option] == "true")
                            Toggle(isOn: Binding(
                                get: { isSelected },
                                set: { newValue in
                                    if rowIndex < repeaterData.count {
                                        repeaterData[rowIndex][subField.id + "_" + option] = newValue ? "true" : "false"
                                    }
                                }
                            )) {
                                Text(option)
                            }
                        }
                    }
                }

            case "signature":
                let signatureKey = "\(subField.id)_\(rowIndex)"
                VStack(alignment: .leading, spacing: 8) {
                    if let signatureImage = signatureImages[signatureKey] {
                        VStack(spacing: 8) {
                            Image(uiImage: signatureImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 80)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3))
                                )

                            HStack(spacing: 12) {
                                Button(action: {
                                    showingSignaturePad = signatureKey
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }

                                Button(action: {
                                    signatureImages.removeValue(forKey: signatureKey)
                                    updateSignatureInRepeaterData(fieldKey: signatureKey, signature: "")
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(6)
                                }

                                Spacer()
                            }
                        }
                    } else {
                        Button(action: {
                            showingSignaturePad = signatureKey
                        }) {
                            HStack {
                                Image(systemName: "signature")
                                Text("Add Signature")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                    }
                }

            case "image", "camera":
                repeaterMediaField(subField: subField, rowIndex: rowIndex)

            case "attachment":
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "paperclip")
                            Text("Select File")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                    }
                    .disabled(true)

                    Text("File attachments in repeaters coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            default:
                TextField("Enter \(subField.label.lowercased())", text: Binding(
                    get: { repeaterData[safe: rowIndex]?[subField.id] ?? "" },
                    set: { newValue in
                        if rowIndex < repeaterData.count {
                            repeaterData[rowIndex][subField.id] = newValue
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }

    @ViewBuilder
    private func repeaterMediaField(subField: FormField, rowIndex: Int) -> some View {
        let key = mediaKey(subFieldId: subField.id, rowIndex: rowIndex)
        let existingURLs = RepeaterMediaSupport.displayURLs(from: repeaterData[safe: rowIndex]?[subField.id])
        let localPreviews = photoPreviews[key] ?? []

        VStack(alignment: .leading, spacing: 8) {
            if !existingURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(existingURLs.enumerated()), id: \.offset) { index, url in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                        .frame(width: 80, height: 80)
                                }
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)

                                Button {
                                    removeExistingStoredMedia(rowIndex: rowIndex, subFieldId: subField.id, index: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }

            if !localPreviews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(localPreviews.enumerated()), id: \.offset) { index, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue.opacity(0.5))
                                    )

                                Button {
                                    removeLocalMedia(key: key, index: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }

            Button(action: {
                mediaActionKey = key
                mediaActionType = subField.type
                showingMediaDialog = true
            }) {
                HStack {
                    Image(systemName: subField.type == "camera" ? "camera" : "photo.on.rectangle.angled")
                    Text(subField.type == "camera" ? "Add Photo(s)" : "Add Image(s)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
        }
    }
}

// Safe array access extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}

// Helper struct for identifiable string (needed for sheet presentation)
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

// Note: SignaturePadView and IdentifiablePath are defined in FormSubmissionCreateView.swift
