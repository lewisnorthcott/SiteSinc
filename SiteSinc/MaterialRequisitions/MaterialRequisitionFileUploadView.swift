import SwiftUI
import PhotosUI

struct MaterialRequisitionFileUploadView: View {
    let requisitionId: Int
    let token: String
    let onSuccess: ([MaterialRequisitionAttachment]) -> Void
    var onFileDataSelected: (([Data], [String], [String]) -> Void)? = nil // Callback for file data when requisitionId is 0
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var errorMessage: String?
    @State private var uploadedFiles: [MaterialRequisitionAttachment] = []
    
    var body: some View {
        NavigationView {
            VStack {
                if uploading {
                    ProgressView("Uploading files...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            PhotosPicker(
                                selection: $selectedItems,
                                maxSelectionCount: 10,
                                matching: .any(of: [.images, .videos])
                            ) {
                                Label("Select Files", systemImage: "photo.on.rectangle")
                            }
                            
                            if !selectedItems.isEmpty {
                                Text("\(selectedItems.count) file(s) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let errorMessage = errorMessage {
                            Section {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upload Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        uploadFiles()
                    }
                    .disabled(selectedItems.isEmpty || uploading)
                }
            }
            .onChange(of: selectedItems) { oldItems, newItems in
                if !newItems.isEmpty && !uploading {
                    // Files selected, ready to upload
                }
            }
        }
    }
    
    private func uploadFiles() {
        guard !selectedItems.isEmpty else { return }
        guard requisitionId > 0 else {
            // If requisitionId is 0, we need to store file data for later upload
            // This is used during creation before the requisition exists
            uploading = true
            errorMessage = nil
            
            Task {
                var fileDataArray: [Data] = []
                var fileNamesArray: [String] = []
                var mimeTypesArray: [String] = []
                
                print("📸 [FileUploadView] Processing \(selectedItems.count) files for requisition creation...")
                
                for (index, item) in selectedItems.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        var fileName = "file_\(index)_\(UUID().uuidString)"
                        var mimeType = "image/jpeg"
                        
                        // Determine file type from supported content types
                        if let typeIdentifier = item.supportedContentTypes.first {
                            if typeIdentifier.conforms(to: .image) {
                                if typeIdentifier.conforms(to: .png) {
                                    fileName += ".png"
                                    mimeType = "image/png"
                                } else {
                                    fileName += ".jpg"
                                    mimeType = "image/jpeg"
                                }
                            } else if typeIdentifier.conforms(to: .movie) {
                                fileName += ".mov"
                                mimeType = "video/quicktime"
                            }
                        }
                        
                        fileDataArray.append(data)
                        fileNamesArray.append(fileName)
                        mimeTypesArray.append(mimeType)
                        
                        print("📸 [FileUploadView] File \(index + 1): \(fileName), size: \(data.count) bytes, type: \(mimeType)")
                    } else {
                        print("❌ [FileUploadView] Failed to load data for file \(index + 1)")
                    }
                }
                
                if fileDataArray.isEmpty {
                    await MainActor.run {
                        errorMessage = "Failed to load file data"
                        uploading = false
                    }
                    return
                }
                
                // Create placeholder attachments for display
                let mockAttachments = fileNamesArray.enumerated().map { index, fileName -> MaterialRequisitionAttachment in
                    MaterialRequisitionAttachment(
                        name: fileName,
                        type: mimeTypesArray[index],
                        size: fileDataArray[index].count,
                        fileKey: nil,
                        url: nil
                    )
                }
                
                await MainActor.run {
                    uploadedFiles = mockAttachments
                    uploading = false
                    // Call the file data callback if provided
                    onFileDataSelected?(fileDataArray, fileNamesArray, mimeTypesArray)
                    // Also call onSuccess for backward compatibility
                    onSuccess(mockAttachments)
                    dismiss()
                }
            }
            return
        }
        
        uploading = true
        errorMessage = nil
        
        Task {
            do {
                var fileDataArray: [Data] = []
                var fileNamesArray: [String] = []
                
                for (index, item) in selectedItems.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        fileDataArray.append(data)
                        // Generate a unique filename
                        let fileName = "file_\(index)_\(UUID().uuidString).jpg"
                        fileNamesArray.append(fileName)
                    }
                }
                
                if fileDataArray.isEmpty {
                    await MainActor.run {
                        errorMessage = "Failed to load file data"
                        uploading = false
                    }
                    return
                }
                
                let uploaded = try await APIClient.uploadMaterialRequisitionFiles(
                    id: requisitionId,
                    files: fileDataArray,
                    fileNames: fileNamesArray,
                    token: token
                )
                
                await MainActor.run {
                    uploadedFiles = uploaded
                    uploading = false
                    onSuccess(uploaded)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to upload files: \(error.localizedDescription)"
                    uploading = false
                }
            }
        }
    }
}

