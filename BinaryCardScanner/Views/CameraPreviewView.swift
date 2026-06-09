import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraManager
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PreviewView {
        let view = _PreviewView()
        view.session = session
        camera.previewView = view
        camera.updatePreviewOrientation()
        return view
    }

    func updateUIView(_ uiView: _PreviewView, context: Context) {
        uiView.session = session
        camera.previewView = uiView
        camera.updatePreviewOrientation()
    }
}

final class _PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        didSet { previewLayer.session = session }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
