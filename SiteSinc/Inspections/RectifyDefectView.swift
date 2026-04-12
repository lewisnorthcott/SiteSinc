import SwiftUI
import PhotosUI
import AVFoundation

struct RectifyDefectView: View {
    let defect: InspectionDefect
    let inspection: Inspection
    let projectId: Int
    let token: String
    let onSuccess: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var rectificationNotes: String = ""
    @State private var photos: [InspectionDefect.InspectionDefectPhoto] = []
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showPhotoActionSheet = false
    @State private var showPhotosPicker = false
    @State private var isSubmitting = false
    @State private var isUploadingPhoto = false
    @State private var errorMessage: String?
    @State private var pendingPhotos: [Data] = []
    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?
    @State private var photoMarkupGateImage: UIImage?
    @State private var photoMarkupGateCapturedData: Data?
    @State private var showPhotoMarkupGate = false
    
    private var currentToken: String {
        return sessionManager.token ?? token
    }

    private var initialPhotos: [InspectionDefect.InspectionDefectStagePhoto] {
        defect.stageResult?.photos ?? []
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section("Issue") {
                        Text("Inspection item \"\(defect.stageResult?.stage.name ?? "Unknown")\" failed")
                            .font(.body)
                            .foregroundColor(.primary)
                    }

                    if !initialPhotos.isEmpty {
                        Section("Initial Photos (defect)") {
                            photoStrip(urls: initialPhotos.map { $0.fileUrl }, thumbnailSize: 80)
                        }
                    }
                    
                    Section("Rectification Notes") {
                        TextEditor(text: $rectificationNotes)
                            .frame(minHeight: 100)
                    }
                    
                    Section("Rectification Photos") {
                        Button(action: {
                            showPhotoActionSheet = true
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Add Photos")
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if !photos.isEmpty || !pendingPhotos.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                photoStrip(urls: photos.map { $0.fileUrl }, thumbnailSize: 80)
                                
                                if !pendingPhotos.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(Array(pendingPhotos.enumerated()), id: \.offset) { index, data in
                                                if let uiImage = UIImage(data: data) {
                                                    ZStack(alignment: .topTrailing) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 80, height: 80)
                                                            .cornerRadius(8)
                                                        
                                                        VStack {
                                                            Spacer()
                                                            HStack {
                                                                Button {
                                                                    openRectifyPendingMarkup(at: index)
                                                                } label: {
                                                                    Image(systemName: "pencil.tip.crop.circle")
                                                                        .font(.system(size: 16))
                                                                        .foregroundStyle(.white)
                                                                        .padding(5)
                                                                        .background(.ultraThinMaterial, in: Circle())
                                                                }
                                                                .accessibilityLabel("Mark up photo")
                                                                Spacer()
                                                            }
                                                        }
                                                        .padding(4)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if isSubmitting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Submitting rectification...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                }
            }
            .navigationTitle("Rectify Defect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        submitRectification()
                    }
                    .disabled(isSubmitting || rectificationNotes.isEmpty)
                }
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItems, maxSelectionCount: 10, matching: .images)
            .onChange(of: photosPickerItems) { oldItems, newItems in
                if !newItems.isEmpty {
                    Task {
                        await processSelectedPhotos(newItems)
                    }
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraPickerWithLocation(
                    onImageCaptured: { photoWithLocation in
                        guard let ui = UIImage(data: photoWithLocation.image) else { return }
                        photoMarkupGateCapturedData = photoWithLocation.image
                        photoMarkupGateImage = ui
                        showPhotoMarkupGate = true
                    },
                    onDismiss: {
                        showCameraPicker = false
                    }
                )
            }
            .confirmationDialog("Photo", isPresented: $showPhotoMarkupGate, titleVisibility: .visible) {
                Button("Use photo") {
                    if let d = photoMarkupGateCapturedData {
                        pendingPhotos.append(d)
                    }
                    photoMarkupGateCapturedData = nil
                    photoMarkupGateImage = nil
                }
                Button("Mark up") {
                    let orig = photoMarkupGateCapturedData
                    let ui = photoMarkupGateImage
                    photoMarkupGateCapturedData = nil
                    photoMarkupGateImage = nil
                    showPhotoMarkupGate = false
                    photoMarkupEditorOnDone = { data in
                        pendingPhotos.append(data)
                        dismissRectifyPhotoMarkupEditor()
                    }
                    photoMarkupEditorOnCancel = {
                        if let o = orig {
                            pendingPhotos.append(o)
                        }
                        dismissRectifyPhotoMarkupEditor()
                    }
                    if let img = ui {
                        photoMarkupPresentation = PhotoMarkupPresentationItem(image: img)
                    }
                }
                Button("Cancel", role: .cancel) {
                    photoMarkupGateCapturedData = nil
                    photoMarkupGateImage = nil
                }
            } message: {
                Text("Use this photo as captured, or mark it up before adding.")
            }
            .fullScreenCover(item: $photoMarkupPresentation) { item in
                PhotoMarkupEditorScreen(
                    image: item.image,
                    onDone: { data in
                        photoMarkupEditorOnDone?(data)
                    },
                    onCancel: {
                        photoMarkupEditorOnCancel?()
                    }
                )
            }
            .confirmationDialog("Add Photo", isPresented: $showPhotoActionSheet, titleVisibility: .visible) {
                Button("Take Photo") {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .authorized {
                        showCameraPicker = true
                    } else if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    showCameraPicker = true
                                }
                            }
                        }
                    }
                }
                Button("Choose From Library") {
                    showPhotosPicker = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
        .onAppear {
            loadDefectPhotos()
        }
    }
    
    private func dismissRectifyPhotoMarkupEditor() {
        photoMarkupPresentation = nil
        photoMarkupEditorOnDone = nil
        photoMarkupEditorOnCancel = nil
    }
    
    private func openRectifyPendingMarkup(at index: Int) {
        guard index < pendingPhotos.count, let ui = UIImage(data: pendingPhotos[index]) else { return }
        let idx = index
        photoMarkupEditorOnDone = { data in
            guard idx < pendingPhotos.count else {
                dismissRectifyPhotoMarkupEditor()
                return
            }
            pendingPhotos[idx] = data
            dismissRectifyPhotoMarkupEditor()
        }
        photoMarkupEditorOnCancel = {
            dismissRectifyPhotoMarkupEditor()
        }
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
    }
    
    private func loadDefectPhotos() {
        // Photos are loaded with the defect, so we can use them directly
        if let defectPhotos = defect.photos {
            photos = defectPhotos.filter { $0.type?.uppercased() != "INITIAL" }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    pendingPhotos.append(data)
                    photosPickerItems = []
                }
            }
        }
    }
    
    private func submitRectification() {
        guard !isSubmitting else { return }
        guard !rectificationNotes.isEmpty else {
            errorMessage = "Rectification notes are required"
            return
        }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                // First, submit the rectification
                _ = try await APIClient.rectifyDefect(
                    projectId: projectId,
                    inspectionId: inspection.id,
                    defectId: defect.id,
                    notes: rectificationNotes,
                    token: currentToken
                )
                
                // Then upload photos if any
                if !pendingPhotos.isEmpty {
                    isUploadingPhoto = true
                    do {
                        for (index, photoData) in pendingPhotos.enumerated() {
                            let fileName = "rectification_\(UUID().uuidString)_\(index).jpg"
                            _ = try await APIClient.uploadDefectPhoto(
                                projectId: projectId,
                                inspectionId: inspection.id,
                                defectId: defect.id,
                                imageData: photoData,
                                fileName: fileName,
                                latitude: nil,
                                longitude: nil,
                                accuracy: nil,
                                locationTimestamp: nil,
                                token: currentToken
                            )
                        }
                        isUploadingPhoto = false
                    } catch {
                        // Log photo upload error but don't fail the whole submission
                        print("Warning: Failed to upload some photos: \(error)")
                        isUploadingPhoto = false
                    }
                }
                
                await MainActor.run {
                    isSubmitting = false
                    onSuccess()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    isUploadingPhoto = false
                    errorMessage = "Failed to submit rectification: \(error.localizedDescription)"
                }
            }
        }
    }

    private func photoStrip(urls: [String], thumbnailSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: thumbnailSize, height: thumbnailSize)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

