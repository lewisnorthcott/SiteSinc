import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - RepeaterFieldView
struct RepeaterFieldView: View {
    let field: FormField
    @Binding var responses: [String: String]
    
    @State private var repeaterData: [[String: String]] = []
    @State private var showingSignaturePad: String? // fieldId_rowIndex format
    @State private var signatureImages: [String: UIImage] = [:] // fieldId_rowIndex -> UIImage
    @State private var mediaItems: [String: [RepeaterMediaItem]] = [:]
    @State private var photoPreviews: [String: [UIImage]] = [:]
    
    @State private var activeMediaKey: String?
    @State private var showingPhotosPicker = false
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var showingCameraActionSheetForKey: String?
    @State private var isCustomCameraPresented = false
    @State private var cameraSessionPhotos: [PhotoWithLocation] = []
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupTarget: (key: String, index: Int)?
    
    private var minItems: Int { field.minItems ?? 0 }
    private var maxItems: Int { field.maxItems ?? 10 }
    private var addButtonText: String { field.addButtonText ?? "Add \(field.label)" }
    private var removeButtonText: String { field.removeButtonText ?? "Remove" }
    
    // Computed properties to break down complex expressions
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
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $pickerSelection,
            maxSelectionCount: remainingPhotoSlots(for: activeMediaKey),
            matching: .images
        )
        .onChange(of: pickerSelection) { _, newItems in
            handlePickerSelection(newItems)
        }
        .confirmationDialog(
            "Add Image",
            isPresented: Binding(
                get: { showingCameraActionSheetForKey != nil },
                set: { if !$0 { showingCameraActionSheetForKey = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Take Photo") {
                requestCameraAndPresent()
            }
            Button("Choose From Library") {
                activeMediaKey = showingCameraActionSheetForKey ?? activeMediaKey
                showingPhotosPicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Take new photos or pick from your library.")
        }
        .fullScreenCover(isPresented: $isCustomCameraPresented, onDismiss: {
            cameraSessionPhotos = []
        }) {
            CustomCameraView(capturedImages: $cameraSessionPhotos)
        }
        .onChange(of: cameraSessionPhotos) { oldValue, newValue in
            let added = Array(newValue.dropFirst(oldValue.count))
            guard !added.isEmpty, let key = activeMediaKey else { return }
            appendPhotos(added, to: key)
        }
        .fullScreenCover(item: $photoMarkupPresentation) { item in
            PhotoMarkupEditorScreen(
                image: item.image,
                onDone: { data in
                    applyMarkup(data)
                },
                onCancel: {
                    photoMarkupPresentation = nil
                    photoMarkupTarget = nil
                }
            )
        }
        .alert("Camera Permission", isPresented: $showingPermissionAlert) {
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
        ForEach(Array(repeaterData.enumerated()), id: \.offset) { index, _ in
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
                
                // Render sub-fields
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
            // Convert image to base64 and save to repeater data
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
            let decodedRows = RepeaterMediaSupport.rowsAsStringDicts(from: existingJson)
            if !decodedRows.isEmpty {
                repeaterData = decodedRows
                
                for (rowIndex, rowData) in decodedRows.enumerated() {
                    if let subFields = field.subFields {
                        for subField in subFields {
                            if subField.type == "signature" {
                                if let base64String = rowData[subField.id], !base64String.isEmpty,
                                   let image = base64ToUIImage(base64String) {
                                    let signatureKey = RepeaterMediaSupport.mediaKey(fieldId: subField.id, rowIndex: rowIndex)
                                    signatureImages[signatureKey] = image
                                }
                            } else if RepeaterMediaSupport.mediaFieldTypes.contains(subField.type) {
                                loadMedia(for: subField, rowIndex: rowIndex, stored: rowData[subField.id] ?? "")
                            }
                        }
                    }
                }
            }
        }
        
        // Ensure minimum items
        while repeaterData.count < minItems {
            addItem()
        }
    }
    
    private func loadMedia(for subField: FormField, rowIndex: Int, stored: String) {
        let key = RepeaterMediaSupport.mediaKey(fieldId: subField.id, rowIndex: rowIndex)
        let isCamera = RepeaterMediaSupport.isCameraType(subField.type)
        let items = RepeaterMediaSupport.mediaItems(fromStoredValue: stored, isCamera: isCamera)
        mediaItems[key] = items
        var previews: [UIImage] = []
        for item in items {
            if let data = item.jpegData, let image = UIImage(data: data) {
                previews.append(image.thumbnail(maxPixelSize: 400))
            } else {
                previews.append(UIImage())
            }
        }
        photoPreviews[key] = previews
        Task {
            var updated = previews
            for (index, item) in items.enumerated() {
                if item.jpegData != nil { continue }
                guard let ref = item.remoteRef, let url = URL(string: ref), url.scheme?.hasPrefix("http") == true else { continue }
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    updated[index] = image.thumbnail(maxPixelSize: 400)
                }
            }
            await MainActor.run {
                photoPreviews[key] = updated
            }
        }
    }
    
    private func base64ToUIImage(_ base64String: String) -> UIImage? {
        RepeaterMediaSupport.uiImage(fromStoredImage: base64String)
    }
    
    private func saveRepeaterData() {
        if let jsonString = RepeaterMediaSupport.encodeRows(repeaterData, subFields: field.subFields ?? []) {
            responses[field.id] = jsonString
        }
    }
    
    private func addItem() {
        guard repeaterData.count < maxItems else { return }
        
        var newItem: [String: String] = [:]
        // Initialize with empty values for all sub-fields
        field.subFields?.forEach { subField in
            newItem[subField.id] = ""
        }
        repeaterData.append(newItem)
    }
    
    private func removeItem(at index: Int) {
        guard index < repeaterData.count, repeaterData.count > minItems else { return }
        repeaterData.remove(at: index)
        reindexKeyedState(removedIndex: index)
    }
    
    private func reindexKeyedState(removedIndex: Int) {
        signatureImages = reindexDictionary(signatureImages, removedIndex: removedIndex)
        mediaItems = reindexDictionary(mediaItems, removedIndex: removedIndex)
        photoPreviews = reindexDictionary(photoPreviews, removedIndex: removedIndex)
        if let pad = showingSignaturePad, let parsed = RepeaterMediaSupport.parseMediaKey(pad), parsed.rowIndex == removedIndex {
            showingSignaturePad = nil
        }
        if let key = activeMediaKey, let parsed = RepeaterMediaSupport.parseMediaKey(key), parsed.rowIndex == removedIndex {
            activeMediaKey = nil
        }
    }
    
    private func reindexDictionary<Value>(_ dict: [String: Value], removedIndex: Int) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in dict {
            guard let parsed = RepeaterMediaSupport.parseMediaKey(key) else { continue }
            if parsed.rowIndex == removedIndex { continue }
            let newIndex = parsed.rowIndex > removedIndex ? parsed.rowIndex - 1 : parsed.rowIndex
            result[RepeaterMediaSupport.mediaKey(fieldId: parsed.fieldId, rowIndex: newIndex)] = value
        }
        return result
    }
    
    private func updateSignatureInRepeaterData(fieldKey: String, signature: String) {
        guard let parsed = RepeaterMediaSupport.parseMediaKey(fieldKey),
              parsed.rowIndex < repeaterData.count else {
            return
        }
        repeaterData[parsed.rowIndex][parsed.fieldId] = signature
    }
    
    // MARK: - Media helpers
    
    private func remainingPhotoSlots(for key: String?) -> Int {
        let current = key.flatMap { mediaItems[$0]?.count } ?? 0
        return max(1, RepeaterMediaSupport.maxPhotosPerField - current)
    }
    
    private func persistMedia(for key: String) {
        guard let parsed = RepeaterMediaSupport.parseMediaKey(key),
              parsed.rowIndex < repeaterData.count else { return }
        let items = mediaItems[key] ?? []
        let subType = field.subFields?.first(where: { $0.id == parsed.fieldId })?.type ?? "image"
        if RepeaterMediaSupport.isCameraType(subType) {
            repeaterData[parsed.rowIndex][parsed.fieldId] = RepeaterMediaSupport.encodeCameraItems(items)
        } else {
            repeaterData[parsed.rowIndex][parsed.fieldId] = RepeaterMediaSupport.encodeImageItems(items)
        }
    }
    
    private func appendItems(_ newItems: [RepeaterMediaItem], to key: String) {
        var existing = mediaItems[key] ?? []
        let room = RepeaterMediaSupport.maxPhotosPerField - existing.count
        guard room > 0 else { return }
        let toAdd = Array(newItems.prefix(room))
        existing.append(contentsOf: toAdd)
        mediaItems[key] = existing
        var previews = photoPreviews[key] ?? []
        for item in toAdd {
            if let data = item.jpegData, let image = UIImage(data: data) {
                previews.append(image.thumbnail(maxPixelSize: 400))
            }
        }
        photoPreviews[key] = previews
        persistMedia(for: key)
    }
    
    private func appendPhotos(_ photos: [PhotoWithLocation], to key: String) {
        appendItems(photos.map { RepeaterMediaSupport.item(from: $0) }, to: key)
    }
    
    private func removeMedia(at index: Int, key: String) {
        guard var items = mediaItems[key], index < items.count else { return }
        items.remove(at: index)
        mediaItems[key] = items
        if var previews = photoPreviews[key], index < previews.count {
            previews.remove(at: index)
            photoPreviews[key] = previews
        }
        persistMedia(for: key)
    }
    
    private func handlePickerSelection(_ newItems: [PhotosPickerItem]) {
        guard let key = activeMediaKey, !newItems.isEmpty else {
            if newItems.isEmpty { activeMediaKey = nil }
            return
        }
        Task {
            var loaded: [RepeaterMediaItem] = []
            for item in newItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
                    loaded.append(RepeaterMediaSupport.item(fromJPEG: jpeg))
                }
            }
            await MainActor.run {
                appendItems(loaded, to: key)
                pickerSelection = []
                activeMediaKey = nil
            }
        }
    }
    
    private func requestCameraAndPresent() {
        let key = showingCameraActionSheetForKey ?? activeMediaKey
        activeMediaKey = key
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            isCustomCameraPresented = true
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.isCustomCameraPresented = true
                    }
                }
            }
        } else {
            permissionAlertMessage = "Camera access is required. Enable it in Settings."
            showingPermissionAlert = true
        }
    }
    
    private func openMarkupEditor(key: String, index: Int) {
        guard let items = mediaItems[key], index < items.count,
              let data = items[index].jpegData, let image = UIImage(data: data) else { return }
        photoMarkupTarget = (key, index)
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: image)
    }
    
    private func applyMarkup(_ data: Data) {
        guard let target = photoMarkupTarget else { return }
        guard var items = mediaItems[target.key], target.index < items.count else {
            photoMarkupPresentation = nil
            photoMarkupTarget = nil
            return
        }
        items[target.index].jpegData = data
        items[target.index].remoteRef = nil
        mediaItems[target.key] = items
        if var previews = photoPreviews[target.key], target.index < previews.count, let image = UIImage(data: data) {
            previews[target.index] = image.thumbnail(maxPixelSize: 400)
            photoPreviews[target.key] = previews
        }
        persistMedia(for: target.key)
        photoMarkupPresentation = nil
        photoMarkupTarget = nil
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
                
                // Show validation status for required fields
                if subField.required {
                    let currentValue = repeaterData[safe: rowIndex]?[subField.id] ?? ""
                    let isEmpty = RepeaterMediaSupport.isEmptyValue(currentValue)
                    
                    if isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
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
                let signatureKey = RepeaterMediaSupport.mediaKey(fieldId: subField.id, rowIndex: rowIndex)
                VStack(alignment: .leading, spacing: 8) {
                    // Show existing signature if available
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
                        // Show add signature button
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
                
            case "image", "camera", "photo":
                repeaterMediaEditor(subField: subField, rowIndex: rowIndex)
                
            case "attachment":
                VStack(alignment: .leading, spacing: 8) {
                    // Note: Attachment functionality for repeater fields is not yet implemented
                    Button(action: {
                        // TODO: Implement file attachment for repeater fields
                    }) {
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
    private func repeaterMediaEditor(subField: FormField, rowIndex: Int) -> some View {
        let key = RepeaterMediaSupport.mediaKey(fieldId: subField.id, rowIndex: rowIndex)
        let isCamera = RepeaterMediaSupport.isCameraType(subField.type)
        let items = mediaItems[key] ?? []
        let previews = photoPreviews[key] ?? []
        let canAddMore = items.count < RepeaterMediaSupport.maxPhotosPerField
        
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ZStack(alignment: .topTrailing) {
                                if index < previews.count, previews[index].size.width > 1 {
                                    Image(uiImage: previews[index])
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
                                        .cornerRadius(8)
                                } else {
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                        .background(Color.gray.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                
                                if isCamera, item.jpegData != nil {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Button {
                                                openMarkupEditor(key: key, index: index)
                                            } label: {
                                                Image(systemName: "pencil.tip.crop.circle")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(.ultraThinMaterial, in: Circle())
                                            }
                                            .accessibilityLabel("Mark up photo")
                                            Spacer()
                                        }
                                    }
                                    .padding(4)
                                }
                                
                                Button(action: {
                                    removeMedia(at: index, key: key)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(4)
                            }
                            .frame(height: 100)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            if canAddMore {
                if isCamera {
                    Button(action: {
                        activeMediaKey = key
                        showingCameraActionSheetForKey = key
                    }) {
                        Label("Add Image(s)", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        activeMediaKey = key
                        showingPhotosPicker = true
                    }) {
                        Label("Select Images", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
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
