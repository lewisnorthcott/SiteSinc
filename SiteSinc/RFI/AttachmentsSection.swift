import SwiftUI
import PhotosUI

struct AttachmentsSection: View {
    @Binding var selectedFiles: [URL]
    @Binding var photosPickerItems: [PhotosPickerItem]
    @Binding var showCameraPicker: Bool
    /// When set, shows a mark-up control for raster image attachments at the given index.
    var onMarkupPhoto: ((Int) -> Void)? = nil

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
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.primary)
                }
                Button {
                    showCameraPicker = true
                } label: {
                    HStack {
                        Image(systemName: "camera")
                        Text("Take Photo")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
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
                                HStack(spacing: 8) {
                                    if let image = UIImage(contentsOfFile: selectedFiles[index].path),
                                       let ext = selectedFiles[index].pathExtension.lowercased() as String?,
                                       ["jpg", "jpeg", "png", "gif"].contains(ext) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "doc")
                                            .resizable()
                                            .frame(width: 32, height: 40)
                                            .foregroundColor(.gray)
                                    }
                                    Text(selectedFiles[index].lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    if let onMarkup = onMarkupPhoto,
                                       UIImage(contentsOfFile: selectedFiles[index].path) != nil,
                                       let ext = selectedFiles[index].pathExtension.lowercased() as String?,
                                       ["jpg", "jpeg", "png", "gif"].contains(ext) {
                                        Button {
                                            onMarkup(index)
                                        } label: {
                                            Image(systemName: "pencil.tip.crop.circle")
                                                .foregroundColor(.accentColor)
                                        }
                                        .accessibilityLabel("Mark up photo")
                                    }
                                    Button {
                                        selectedFiles.remove(at: index)
                                        if index < photosPickerItems.count {
                                            photosPickerItems.remove(at: index)
                                        }
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
