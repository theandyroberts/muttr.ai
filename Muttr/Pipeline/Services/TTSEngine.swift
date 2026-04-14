import Foundation
import AVFoundation

/// TTS engine using macOS AVSpeechSynthesizer.
/// Urgency maps to rate and pitch adjustments.
/// Can be replaced with sherpa-onnx/Piper for higher quality local TTS later.
final class TTSEngine: NSObject, TTSProviding, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var speechContinuation: CheckedContinuation<TTSAudioOutput, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func synthesize(_ request: TTSSpeechRequest) async throws -> TTSAudioOutput {
        return try await withCheckedThrowingContinuation { continuation in
            self.speechContinuation = continuation

            let utterance = AVSpeechUtterance(string: request.text)
            utterance.rate = request.rate
            utterance.pitchMultiplier = request.pitch
            utterance.volume = 1.0

            // Use system voice — let AVSpeechSynthesizer handle audio output directly
            if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = voice
            }

            synthesizer.speak(utterance)
        }
    }
}

extension TTSEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Speech completed — return empty audio output since AVSpeechSynthesizer plays directly
        speechContinuation?.resume(returning: .empty)
        speechContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechContinuation?.resume(returning: .empty)
        speechContinuation = nil
    }
}
