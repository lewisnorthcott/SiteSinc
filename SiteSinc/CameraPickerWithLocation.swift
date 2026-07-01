import SwiftUI
import UIKit
import CoreLocation

struct CameraPickerWithLocation: UIViewControllerRepresentable {
    let onImageCaptured: (PhotoWithLocation) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerWithLocation
        
        init(_ parent: CameraPickerWithLocation) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                
                // Deliver immediately so the "use photo" gate appears without waiting for location.
                // (Matches the reliability fix for multi-photo CustomCameraView.)
                let photoData = PhotoWithLocation(
                    image: data,
                    location: nil,
                    capturedAt: Date()
                )
                parent.onImageCaptured(photoData)
                parent.onDismiss()

                // Best-effort: fetch location in background but do not block attachment.
                // Callers that need accurate location should fetch it themselves at capture time if critical.
                Task.detached {
                    _ = await LocationManager.shared.getCurrentLocation()
                }
            } else {
                parent.onDismiss()
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

// Data structure for photo with location
struct PhotoWithLocation: Equatable {
    let image: Data
    let location: CLLocation?
    let capturedAt: Date
    
    // Convert to dictionary for form submission
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "image": image.base64EncodedString(),
            "capturedAt": ISO8601DateFormatter().string(from: capturedAt)
        ]
        
        if let location = location {
            dict["location"] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
        }
        
        return dict
    }
    
    // Equatable conformance
    static func == (lhs: PhotoWithLocation, rhs: PhotoWithLocation) -> Bool {
        return lhs.image == rhs.image &&
               lhs.capturedAt == rhs.capturedAt &&
               lhs.location?.coordinate.latitude == rhs.location?.coordinate.latitude &&
               lhs.location?.coordinate.longitude == rhs.location?.coordinate.longitude
    }
} 