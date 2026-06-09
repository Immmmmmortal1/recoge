import AVFoundation
import CoreImage
import Foundation

final class CameraManager: NSObject, ObservableObject {

    let session = AVCaptureSession()
    /// Session hardware is configured (inputs/outputs attached).
    @Published private(set) var isSessionReady = false
    /// At least one preview frame arrived — camera is actually live.
    @Published private(set) var isPreviewActive = false
    @Published private(set) var setupError: String?

    weak var previewView: _PreviewView?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.binarycard.camera.session")
    private var latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()
    private var didConfigure = false
    private var shouldRun = false
    private var announcedPreview = false
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init() {
        super.init()
    }

    func setupIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self, !self.didConfigure else { return }
            self.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        defer {
            session.commitConfiguration()
            didConfigure = true
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            DispatchQueue.main.async {
                self.setupError = "无法打开后置相机"
                self.isSessionReady = false
                self.isPreviewActive = false
            }
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(
            self,
            queue: DispatchQueue(label: "com.binarycard.camera.frames")
        )
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        applyPortraitRotation()

        DispatchQueue.main.async {
            self.isSessionReady = true
            self.setupError = nil
        }

        startRunningIfNeeded()
    }

    private func applyPortraitRotation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func applyPortraitRotation() {
        applyPortraitRotation(to: videoOutput.connection(with: .video))
    }

    func updatePreviewOrientation() {
        applyPortraitRotation(to: previewView?.previewLayer.connection)
    }

    func start() {
        shouldRun = true
        announcedPreview = false
        DispatchQueue.main.async {
            self.isPreviewActive = false
        }
        setupIfNeeded()
        sessionQueue.async { [weak self] in
            self?.startRunningIfNeeded()
        }
    }

    private func startRunningIfNeeded() {
        guard shouldRun, didConfigure, !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        shouldRun = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isPreviewActive = false
            }
        }
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { completion(true) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    func captureGuidedColorFrame() -> CGImage? {
        updatePreviewOrientation()
        return renderGuideCrop()
    }

    func captureGuidedFrame() -> CGImage? {
        updatePreviewOrientation()
        return renderGuideCrop()?.grayscaleImage()
    }

    private func renderGuideCrop() -> CGImage? {
        bufferLock.lock()
        let pixelBuffer = latestPixelBuffer
        bufferLock.unlock()
        guard let pixelBuffer else { return nil }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rawW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let rawH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard rawW > 1, rawH > 1 else { return nil }

        // Sensor delivers landscape pixels (1280×720) while UI/preview is portrait.
        // Crop in portrait space so the tall yellow guide maps to a tall crop, not a center horizontal band.
        if rawW > rawH {
            ciImage = ciImage.oriented(.right)
        }
        let fullW = ciImage.extent.width
        let fullH = ciImage.extent.height

        let cropRect = guideCropRect(bufferWidth: fullW, bufferHeight: fullH)
        guard cropRect.width > 1, cropRect.height > 1 else { return nil }
        let cropped = ciImage.cropped(to: cropRect)
        return ciContext.createCGImage(cropped, from: cropped.extent)
    }

    /// Maps the on-screen yellow guide into pixel coordinates of the portrait-oriented image.
    private func guideCropRect(bufferWidth: CGFloat, bufferHeight: CGFloat) -> CGRect {
        aspectFillGuideCrop(
            guide: GuideZone.normalizedRect,
            previewSize: previewView?.bounds.size ?? .zero,
            bufferSize: CGSize(width: bufferWidth, height: bufferHeight)
        )
    }

    /// Normalized rect in video-output coordinates (origin top-left) → CIImage pixels (origin bottom-left).
    private func pixelCropRect(normalized: CGRect,
                               bufferWidth: CGFloat,
                               bufferHeight: CGFloat) -> CGRect {
        CGRect(
            x: normalized.minX * bufferWidth,
            y: (1 - normalized.minY - normalized.height) * bufferHeight,
            width: normalized.width * bufferWidth,
            height: normalized.height * bufferHeight
        ).integral
    }

    /// Same mapping as `.resizeAspectFill` preview: map screen-normalized guide into visible buffer band.
    private func aspectFillGuideCrop(guide: CGRect,
                                     previewSize: CGSize,
                                     bufferSize: CGSize) -> CGRect {
        var bx = guide.minX, by = guide.minY, bw = guide.width, bh = guide.height

        if previewSize.width > 1, previewSize.height > 1 {
            let previewAspect = previewSize.width / previewSize.height
            let bufferAspect = bufferSize.width / bufferSize.height
            if bufferAspect > previewAspect {
                let visible = previewAspect / bufferAspect
                bx = (1 - visible) / 2 + guide.minX * visible
                bw = guide.width * visible
            } else if bufferAspect < previewAspect {
                let visible = bufferAspect / previewAspect
                by = (1 - visible) / 2 + guide.minY * visible
                bh = guide.height * visible
            }
        }

        return pixelCropRect(
            normalized: CGRect(x: bx, y: by, width: bw, height: bh),
            bufferWidth: bufferSize.width,
            bufferHeight: bufferSize.height
        )
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

        guard !announcedPreview else { return }
        announcedPreview = true
        DispatchQueue.main.async { [weak self] in
            self?.isPreviewActive = true
        }
    }
}

private extension CGImage {
    func grayscaleImage() -> CGImage? {
        let ci = CIImage(cgImage: self)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let out = filter.outputImage else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }
}
