import AVFoundation

final class SpeechService {

    private let synthesizer = AVSpeechSynthesizer()

    /// Speak an ordered list of decimal integers in Chinese.
    /// Example: [5, 12, 3] → speaks "五，十二，三"
    func speak(_ numbers: [Int]) {
        synthesizer.stopSpeaking(at: .immediate)
        guard !numbers.isEmpty else { return }
        let text = numbers.map { String($0) }.joined(separator: "，")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
