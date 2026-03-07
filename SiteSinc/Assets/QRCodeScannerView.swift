//
//  QRCodeScannerView.swift
//  SiteSinc
//
//  Camera view that scans QR codes and reports the scanned string.
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: (() -> Void)?

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let vc = QRCodeScannerViewController()
        vc.onScan = onScan
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

final class QRCodeScannerViewController: UIViewController {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let sessionQueue = DispatchQueue(label: "qr.scan.queue")
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCancelButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPermissionAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.isSessionRunning = false
        }
    }

    private func setupCancelButton() {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureAndStart()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.configureAndStart()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.onCancel?()
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
        }
    }

    private func configureAndStart() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return
        }
        session.addOutput(output)
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        captureSession = session
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.frame = self.view.bounds
            layer.videoGravity = .resizeAspectFill
            self.view.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        }
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            self?.isSessionRunning = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

extension QRCodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isSessionRunning,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return }
        captureSession?.stopRunning()
        isSessionRunning = false
        DispatchQueue.main.async { [weak self] in
            self?.onScan?(str)
        }
    }
}
