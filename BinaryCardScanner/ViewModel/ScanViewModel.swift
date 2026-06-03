import Foundation

@MainActor
final class ScanViewModel: ObservableObject {

    @Published var detectedCards: [Int] = []
    @Published var statusMessage: String = "将卡片侧边对准扫描框"

    private let camera: CameraManager
    private let speech = SpeechService()

    init(camera: CameraManager) {
        self.camera = camera
    }

    func scanAndBroadcast() {
        guard let frame = camera.captureGuidedFrame() else {
            statusMessage = "无法获取图像"
            return
        }
        let results = CardDetector.detect(in: frame)
        if results.isEmpty {
            statusMessage = "未检测到卡片"
            detectedCards = []
        } else {
            detectedCards = results
            statusMessage = "检测到 \(results.count) 张卡片"
            speech.speak(results)
        }
    }
}
