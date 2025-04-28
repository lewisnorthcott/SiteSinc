import SwiftUI
import PhotosUI

struct AttachmentsSection: View {
    @Binding var selectedFiles: [URL]
    @Binding var photosPickerItems: [PhotosPickerItem]
    @Binding var showCameraPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.subheadline)
                .foregroundColor(.gray)
            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $photosPickerItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Select Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                Button {
                    showCameraPicker = true
                } label: {
                    HStack {
                        Image(systemName: "camera")
                        Text("Take Photo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
                }
            }
            if !selectedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Files (\(selectedFiles.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                    ScrollView(.vertical) {
                        VStack(spacing: 8) {
                            ForEach(selectedFiles.indices, id: \.self) { index in
                                HStack {
                                    Text(selectedFiles[index].lastPathComponent)
                                        .font(.caption)
                                    Spacer()
                                    Button {
                                        selectedFiles.remove(at: index)
                                        photosPickerItems.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
        }
    }
}
