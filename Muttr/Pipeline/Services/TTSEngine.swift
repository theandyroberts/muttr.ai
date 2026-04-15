import Foundation
import AVFoundation

/// TTS engine using macOS AVSpeechSynthesizer. One `SpeechSession` per call
/// so concurrent/cancelled synths can't leak continuations.
/// Urgency maps to rate and pitch adjustments. Can be replaced with
/// sherpa-onnx/Piper for higher quality local TTS later.
final class TTSEngine: TTSProviding, Sendable {
    func synthesize(_ request: TTSSpeechRequest) async throws -> TTSAudioOutput {
        let session = SpeechSession(request: request)
        return try await withTaskCancellationHandler {
            try await session.speak()
        } onCancel: {
            session.cancel()
        }
    }
}

private final class SpeechSession: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let request: TTSSpeechRequest
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TTSAudioOutput, Error>?
    private var resolved = false

    init(request: TTSSpeechRequest) {
        self.request = request
        super.init()
        synthesizer.delegate = self
    }

    func speak() async throws -> TTSAudioOutput {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()

            let utterance = AVSpeechUtterance(string: request.text)
            utterance.rate = request.rate
            utterance.pitchMultiplier = request.pitch
            utterance.volume = 1.0
            utterance.voice = Self.resolveVoice(request.voiceID)
            synthesizer.speak(utterance)
        }
    }

    static func resolveVoice(_ id: String) -> AVSpeechSynthesisVoice? {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return AVSpeechSynthesisVoice(language: "en-US") }
        // Exact identifier (e.g. com.apple.voice.compact.en-US.Samantha)
        if let v = AVSpeechSynthesisVoice(identifier: trimmed) { return v }

        let voices = AVSpeechSynthesisVoice.speechVoices()

        // "Name:Lang" disambiguation — e.g. "Eddy:en-GB"
        if let colon = trimmed.firstIndex(of: ":") {
            let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let lang = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
            if let v = voices.first(where: { $0.name.lowercased() == name && $0.language.lowercased() == lang }) {
                return v
            }
            if let v = voices.first(where: { $0.name.lowercased() == name && $0.language.lowercased().hasPrefix(lang) }) {
                return v
            }
        }

        // Case-insensitive name match, then substring fallback
        let lowered = trimmed.lowercased()
        if let v = voices.first(where: { $0.name.lowercased() == lowered }) { return v }
        if let v = voices.first(where: { $0.name.lowercased().contains(lowered) }) { return v }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    func cancel() {
        synthesizer.stopSpeaking(at: .immediate)
        // If didCancel doesn't fire (e.g. not yet speaking), resolve directly.
        resolve()
    }

    private func resolve() {
        lock.lock()
        guard !resolved, let cont = continuation else {
            lock.unlock()
            return
        }
        resolved = true
        continuation = nil
        lock.unlock()
        cont.resume(returning: .empty)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resolve()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resolve()
    }
}
