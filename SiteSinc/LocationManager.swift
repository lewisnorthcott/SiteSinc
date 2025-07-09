import Foundation
import CoreLocation
import UIKit

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var isAuthorized = false
    @Published var currentLocation: CLLocation?
    @Published var locationError: String?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        checkAuthorizationStatus()
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func checkAuthorizationStatus() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            locationError = nil
        case .denied, .restricted:
            isAuthorized = false
            locationError = "Location access denied"
        case .notDetermined:
            isAuthorized = false
            locationError = nil
        @unknown default:
            isAuthorized = false
            locationError = "Unknown authorization status"
        }
    }
    
    func getCurrentLocation() async -> CLLocation? {
        guard isAuthorized else {
            locationError = "Location access not authorized"
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            locationManager.requestLocation()
            
            // Set up a timer to handle timeout
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if self.currentLocation == nil {
                    Task { @MainActor in
                        self.locationError = "Location request timed out"
                        self.locationContinuation?.resume(returning: nil)
                        self.locationContinuation = nil
                    }
                }
            }
            
            // Store continuation to be called when location is received
            self.locationContinuation = continuation
        }
    }
    
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationError = nil
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.checkAuthorizationStatus()
        }
    }
} 