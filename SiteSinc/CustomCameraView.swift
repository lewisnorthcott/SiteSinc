// NOTE: For best results, present CustomCameraView using .fullScreenCover in SwiftUI, not .sheet, to ensure the camera covers the whole screen.
import SwiftUI
import AVFoundation
import CoreLocation

struct CustomCameraView: UIViewControllerRepresentable {
    @Binding var capturedImages: [PhotoWithLocation]
    @Environment(\.dismiss) var dismiss
    // Removed: @State private var isCameraReady = false

    func makeUIViewController(context: Context) -> CustomCameraViewController {
        let controller = CustomCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: CustomCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CustomCameraViewControllerDelegate {
        var parent: CustomCameraView

        init(_ parent: CustomCameraView) {
            self.parent = parent
        }

        func didCapture(photo: PhotoWithLocation) {
            DispatchQueue.main.async {
                self.parent.capturedImages.append(photo)
            }
        }
        
        func didFinish() {
            parent.dismiss()
        }
    }
}

protocol CustomCameraViewControllerDelegate: AnyObject {
    func didCapture(photo: PhotoWithLocation)
    func didFinish()
}

class CustomCameraViewController: UIViewController {
    weak var delegate: CustomCameraViewControllerDelegate?
    
    private let sessionQueue = DispatchQueue(label: "session.queue")
    private var isSessionConfigured = false
    
    private var captureSession: AVCaptureSession!
    private var backCamera: AVCaptureDevice!
    private var backInput: AVCaptureInput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput?
    
    private let shutterButton = UIButton()
    private let doneButton = UIButton()
    private let thumbnailImageView = UIImageView()
    private let photoCounterLabel = UILabel()
    
    private var capturedPhotos: [UIImage] = [] {
        didSet {
            updateThumbnail()
            updatePhotoCounter()
        }
    }

    // Removed completion closure from init
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkPermissions()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupCameraIfNeeded()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async {
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
            }
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                }
            }
        case .denied, .restricted:
            // Handle denied access
            break
        @unknown default:
            // Handle future cases
            break
        }
    }

    private func setupCameraIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        setupCamera()
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession = AVCaptureSession()
            self.captureSession.beginConfiguration()

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                self.backCamera = device
            } else {
                return
            }
            
            guard let bInput = try? AVCaptureDeviceInput(device: self.backCamera) else {
                return
            }
            self.backInput = bInput
            
            if self.captureSession.canAddInput(self.backInput) {
                self.captureSession.addInput(self.backInput)
            } else {
                return
            }
            
            let photoOutput = AVCapturePhotoOutput()
            if self.captureSession.canAddOutput(photoOutput) {
                self.captureSession.addOutput(photoOutput)
                self.photoOutput = photoOutput
            } else {
                print("Failed to add photo output")
                return
            }
            
            DispatchQueue.main.async {
                if self.previewLayer == nil {
                    self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                    self.previewLayer.videoGravity = .resizeAspectFill
                    self.view.layer.insertSublayer(self.previewLayer, at: 0)
                } else {
                    self.previewLayer.session = self.captureSession
                }
                self.previewLayer.frame = self.view.bounds
                // Start session on main thread after preview layer is added
                if !(self.captureSession.isRunning) {
                    self.captureSession.startRunning()
                }
            }

            self.captureSession.commitConfiguration()
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.layer.cornerRadius = 40
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.layer.borderWidth = 4
        shutterButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)
        
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneButton)
        
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.backgroundColor = .gray
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 8
        thumbnailImageView.layer.borderColor = UIColor.white.cgColor
        thumbnailImageView.layer.borderWidth = 1
        view.addSubview(thumbnailImageView)
        
        photoCounterLabel.translatesAutoresizingMaskIntoConstraints = false
        photoCounterLabel.textColor = .white
        photoCounterLabel.backgroundColor = .systemBlue
        photoCounterLabel.font = .systemFont(ofSize: 12, weight: .bold)
        photoCounterLabel.textAlignment = .center
        photoCounterLabel.layer.cornerRadius = 11
        photoCounterLabel.clipsToBounds = true
        photoCounterLabel.layer.borderColor = UIColor.white.cgColor
        photoCounterLabel.layer.borderWidth = 1
        photoCounterLabel.isHidden = true
        thumbnailImageView.addSubview(photoCounterLabel)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 80),
            shutterButton.heightAnchor.constraint(equalToConstant: 80),
            
            doneButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            
            thumbnailImageView.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 60),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 60),
            
            photoCounterLabel.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 6),
            photoCounterLabel.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: 6),
            photoCounterLabel.widthAnchor.constraint(equalToConstant: 22),
            photoCounterLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Always update preview layer to fill the view
        previewLayer?.frame = view.bounds
    }

    @objc private func takePhoto() {
        sessionQueue.async {
            guard let photoOutput = self.photoOutput else {
                print("Error: Photo output not initialized")
                return
            }
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    @objc private func doneTapped() {
        delegate?.didFinish()
    }
    
    private func updateThumbnail() {
        thumbnailImageView.image = capturedPhotos.last
    }
    
    private func updatePhotoCounter() {
        if capturedPhotos.isEmpty {
            photoCounterLabel.isHidden = true
        } else {
            photoCounterLabel.isHidden = false
            photoCounterLabel.text = "\(capturedPhotos.count)"
        }
    }
}

extension CustomCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        
        capturedPhotos.append(UIImage(data: data) ?? UIImage())
        
        Task {
            let location = await LocationManager.shared.getCurrentLocation()
            await MainActor.run {
                let photoWithLocation = PhotoWithLocation(image: data, location: location, capturedAt: Date())
                self.delegate?.didCapture(photo: photoWithLocation)
            }
        }
    }
} 