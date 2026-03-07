//
//  AssetPhotoPicker.swift
//  SiteSinc
//
//  Picker for a photo when checking out or checking in an asset.
//  Supports camera or photo library (e.g. for testing).
//

import SwiftUI
import UIKit

struct AssetPhotoPicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .camera
    let onImageCaptured: (Data) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = sourceType == .camera ? .fullScreen : .pageSheet
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: AssetPhotoPicker

        init(_ parent: AssetPhotoPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            let data = image.flatMap { $0.jpegData(compressionQuality: 0.85) }
            if let data = data {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.onImageCaptured(data)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.onDismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}
