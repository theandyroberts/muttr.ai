import Foundation

final class StubTTSEngine: TTSProviding, Sendable {
    func synthesize(_ request: TTSSpeechRequest) async throws -> TTSAudioOutput {
        print("[StubTTS] Synthesizing: \"\(request.text)\" (urgency \(request.urgency.rawValue), rate \(request.rate))")
        // Return silent buffer
        return .empty
    }
}
