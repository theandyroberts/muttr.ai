import Foundation

protocol TTSProviding: Sendable {
    func synthesize(_ request: TTSSpeechRequest) async throws -> TTSAudioOutput
}
