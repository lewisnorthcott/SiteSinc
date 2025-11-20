import SwiftUI
import PhotosUI

struct MaterialRequisitionFileUploadView: View {
    let requisitionId: Int
    let token: String
    let onSuccess: ([MaterialRequisitionAttachment]) -> Void
    
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
            // If requisitionId is 0, we need to upload files first and return them
            // This is used during creation before the requisition exists
            Task {
                var fileDataArray: [Data] = []
                var fileNamesArray: [String] = []
                
                for (index, item) in selectedItems.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        fileDataArray.append(data)
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
                
                // For creation, we'll need to upload to a temporary endpoint or handle differently
                // For now, create mock attachments that will be uploaded after requisition creation
                let mockAttachments = fileNamesArray.enumerated().map { index, fileName -> MaterialRequisitionAttachment in
                    MaterialRequisitionAttachment(
                        name: fileName,
                        type: "image/jpeg",
                        size: fileDataArray[index].count,
                        fileKey: nil,
                        url: nil
                    )
                }
                
                await MainActor.run {
                    uploadedFiles = mockAttachments
                    uploading = false
                    // Store file data temporarily - in a real implementation, you'd upload to a temp endpoint
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

