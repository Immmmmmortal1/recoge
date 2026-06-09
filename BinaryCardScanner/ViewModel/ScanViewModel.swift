import CoreGraphics
import Foundation

@MainActor
final class ScanViewModel: ObservableObject {

    @Published var detectedCards: [Int] = []
    @Published var statusMessage: String = "将卡片蓝色条码区对准黄框"
    /// The exact crop the detector sees. Shown on-screen for debugging capture orientation/crop.
    @Published var debugFrame: CGImage?

    private let camera: CameraManager
    private let speech = SpeechService()

    init(camera: CameraManager) {
        self.camera = camera
    }

    func scanAndBroadcast() {
        let colorFrame = camera.captureGuidedColorFrame()
        let grayFrame = camera.captureGuidedFrame()
        debugFrame = colorFrame
        let outcome = CardDetector.scan(colorFrame: colorFrame, grayFrame: grayFrame)

        detectedCards = outcome.cards
        statusMessage = outcome.userMessage

        let kinds = outcome.kinds
        if !kinds.isEmpty {
            speech.speak(kinds)
        }
    }
}
