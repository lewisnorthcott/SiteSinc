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
                                            ForEach(Array(pendingPhotos.enumerated()), id: \.offset) { _, data in
                                                if let uiImage = UIImage(data: data) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 80, height: 80)
                                                        .cornerRadius(8)
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
                        pendingPhotos.append(photoWithLocation.image)
                        showCameraPicker = false
                    },
                    onDismiss: {
                        showCameraPicker = false
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

