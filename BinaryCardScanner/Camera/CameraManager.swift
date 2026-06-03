import AVFoundation
import CoreImage
import Foundation

final class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.binarycard.camera.session")
    private var latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    /// Normalized rect (0–1) defining the scan guide zone within the camera frame.
    var guideNormalizedRect = CGRect(x: 0.25, y: 0.10, width: 0.50, height: 0.80)

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(
                self,
                queue: DispatchQueue(label: "com.binarycard.camera.frames")
            )
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    /// Capture current frame cropped to the guide zone as a grayscale CGImage.
    func captureGuidedFrame() -> CGImage? {
        bufferLock.lock()
        let pb = latestPixelBuffer
        bufferLock.unlock()
        guard let pixelBuffer = pb else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let fullW = Double(CVPixelBufferGetWidth(pixelBuffer))
        let fullH = Double(CVPixelBufferGetHeight(pixelBuffer))
        let cropRect = CGRect(
            x: guideNormalizedRect.minX * fullW,
            y: guideNormalizedRect.minY * fullH,
            width:  guideNormalizedRect.width  * fullW,
            height: guideNormalizedRect.height * fullH
        )
        let cropped = ciImage.cropped(to: cropRect)

        // Convert to grayscale
        guard let grayFilter = CIFilter(name: "CIColorControls") else { return nil }
        grayFilter.setValue(cropped, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = grayFilter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestPixelBuffer = buf
        bufferLock.unlock()
    }
}
