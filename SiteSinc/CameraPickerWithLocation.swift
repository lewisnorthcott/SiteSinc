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
                
                // Get location data
                Task {
                    let location = await LocationManager.shared.getCurrentLocation()
                    
                    await MainActor.run {
                        let photoData = PhotoWithLocation(
                            image: data,
                            location: location,
                            capturedAt: Date()
                        )
                        parent.onImageCaptured(photoData)
                    }
                }
            }
            parent.onDismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

// Data structure for photo with location
struct PhotoWithLocation {
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
} 