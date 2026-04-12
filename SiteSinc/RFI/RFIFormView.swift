import SwiftUI
import UIKit
import PhotosUI

struct RFIFormView: View {
    @Binding var title: String
    @Binding var query: String
    @Binding var managerId: Int?
    @Binding var assignedUserIds: [Int]
    @Binding var returnDate: Date?
    @Binding var selectedFiles: [URL]
    @Binding var selectedDrawings: [SelectedDrawing]
    let users: [User]
    let drawings: [Drawing]
    @Binding var isSubmitting: Bool
    @Binding var isLoadingUsers: Bool
    @Binding var isLoadingDrawings: Bool
    @Binding var errorMessage: String?
    @Binding var photosPickerItems: [PhotosPickerItem]
    @Binding var showDrawingPicker: Bool
    @Binding var showCameraPicker: Bool
    let canCreateRFIs: Bool
    let canEditRFIs: Bool
    let canManageRFIs: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let fetchUsers: () -> Void
    let fetchDrawings: () -> Void
    let saveFileToTemporaryDirectory: (Data, String) -> URL?
    let onAppear: () -> Void

    @State private var photoMarkupPresentation: PhotoMarkupPresentationItem?
    @State private var photoMarkupEditorOnDone: ((Data) -> Void)?
    @State private var photoMarkupEditorOnCancel: (() -> Void)?
    @State private var photoMarkupGateImage: UIImage?
    @State private var showPhotoMarkupGate = false
    @State private var photoMarkupGateApplyJPEG: ((Data) -> Void)?
    
    var body: some View {
            contentView
                .navigationTitle("Create RFI")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onSubmit) {
                            Text(errorMessage?.contains("offline mode") ?? false ? "Save as Draft" : (isSubmitting ? "Creating..." : "Create"))
                        }
                        .disabled(isSubmitting || !canCreateRFIs || title.isEmpty || query.isEmpty || managerId == nil || assignedUserIds.isEmpty)
                    }
                }
                .sheet(isPresented: $showDrawingPicker) { drawingPickerSheet }
                .sheet(isPresented: $showCameraPicker) { cameraPickerSheet }
                .onAppear {
                    fetchUsers()
                    fetchDrawings()
                    onAppear()
                }
                .onChange(of: photosPickerItems) { oldItems, newItems in
                    Task {
                        var newFiles: [URL] = []
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                let fileName = "photo_\(UUID().uuidString).jpg"
                                if let url = saveFileToTemporaryDirectory(data, fileName) {
                                    newFiles.append(url)
                                }
                            }
                        }
                        selectedFiles.append(contentsOf: newFiles)
                    }
                }
                .confirmationDialog("Photo", isPresented: $showPhotoMarkupGate, titleVisibility: .visible) {
                    Button("Use photo") {
                        if let img = photoMarkupGateImage, let d = img.jpegData(compressionQuality: 0.8) {
                            photoMarkupGateApplyJPEG?(d)
                        }
                        photoMarkupGateImage = nil
                        photoMarkupGateApplyJPEG = nil
                    }
                    Button("Mark up") {
                        let img = photoMarkupGateImage
                        let apply = photoMarkupGateApplyJPEG
                        photoMarkupGateImage = nil
                        photoMarkupGateApplyJPEG = nil
                        showPhotoMarkupGate = false
                        photoMarkupEditorOnDone = { data in
                            apply?(data)
                            dismissRFIPhotoMarkupEditor()
                        }
                        photoMarkupEditorOnCancel = {
                            if let i = img, let d = i.jpegData(compressionQuality: 0.8) {
                                apply?(d)
                            }
                            dismissRFIPhotoMarkupEditor()
                        }
                        if let ui = img {
                            photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        photoMarkupGateImage = nil
                        photoMarkupGateApplyJPEG = nil
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
        }

    private func dismissRFIPhotoMarkupEditor() {
        photoMarkupPresentation = nil
        photoMarkupEditorOnDone = nil
        photoMarkupEditorOnCancel = nil
    }

    private func openRFIAttachmentMarkup(at index: Int) {
        guard index < selectedFiles.count,
              let ui = UIImage(contentsOfFile: selectedFiles[index].path) else { return }
        photoMarkupEditorOnDone = { data in
            let name = "photo_\(UUID().uuidString).jpg"
            if let url = saveFileToTemporaryDirectory(data, name) {
                selectedFiles[index] = url
            }
            dismissRFIPhotoMarkupEditor()
        }
        photoMarkupEditorOnCancel = {
            dismissRFIPhotoMarkupEditor()
        }
        photoMarkupPresentation = PhotoMarkupPresentationItem(image: ui)
    }
        
        private var contentView: some View {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                if isLoadingUsers || isLoadingDrawings {
                    ProgressView()
                } else if !canCreateRFIs {
                    Text("You don't have permission to create RFIs")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            TitleSection(title: $title)
                            QuerySection(query: $query)
                            ManagerSection(managerId: $managerId, users: users, isLoading: isLoadingUsers)
                            AssignToSection(assignedUserIds: $assignedUserIds, users: users, isLoading: isLoadingUsers)
                            ResponseDateSection(returnDate: $returnDate)
                            if canEditRFIs || canManageRFIs {
                                AttachmentsSection(
                                    selectedFiles: $selectedFiles,
                                    photosPickerItems: $photosPickerItems,
                                    showCameraPicker: $showCameraPicker,
                                    onMarkupPhoto: { openRFIAttachmentMarkup(at: $0) }
                                )
                                DrawingsSection(
                                    selectedDrawings: $selectedDrawings,
                                    showDrawingPicker: $showDrawingPicker,
                                    isLoading: isLoadingDrawings
                                )
                            }
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { dismissKeyboard() }
                    .simultaneousGesture(DragGesture().onChanged { _ in dismissKeyboard() })
                }
            }
        }

        private func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSubmit) {
                    Text(errorMessage?.contains("offline mode") ?? false ? "Save as Draft" : (isSubmitting ? "Creating..." : "Create"))
                }
                .disabled(isSubmitting || !canCreateRFIs || title.isEmpty || query.isEmpty || managerId == nil || assignedUserIds.isEmpty)
            }
        }
    }
    
    private var drawingPickerSheet: some View {
        DrawingPickerView(
            drawings: drawings,
            selectedDrawings: $selectedDrawings,
            onDismiss: { showDrawingPicker = false }
        )
    }
    
    private var cameraPickerSheet: some View {
        ImagePicker(
            onImageCaptured: { data in
                guard let ui = UIImage(data: data) else {
                    showCameraPicker = false
                    return
                }
                photoMarkupGateImage = ui
                photoMarkupGateApplyJPEG = { jpeg in
                    if let url = saveFileToTemporaryDirectory(jpeg, "camera_photo_\(UUID().uuidString).jpg") {
                        selectedFiles.append(url)
                    }
                }
                showPhotoMarkupGate = true
            },
            onDismiss: { showCameraPicker = false }
        )
    }
}
