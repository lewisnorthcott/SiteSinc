import SwiftUI
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
                .onChange(of: photosPickerItems) { newItems in
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
                                    showCameraPicker: $showCameraPicker
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
                }
            }
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
        CameraPickerView(
            onImageCaptured: { data in
                if let url = saveFileToTemporaryDirectory(data, "camera_photo_\(UUID().uuidString).jpg") {
                    selectedFiles.append(url)
                }
            },
            onDismiss: { showCameraPicker = false }
        )
    }
}
