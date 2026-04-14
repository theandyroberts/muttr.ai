import Foundation

final class StubAudioService: AudioOutputProviding, @unchecked Sendable {
    var volume: Float = 0.8

    func play(_ audio: TTSAudioOutput) async throws {
        if audio.pcmData.isEmpty {
            print("[StubAudio] Silent buffer, nothing to play")
            return
        }
        print("[StubAudio] Playing \(audio.pcmData.count) bytes at \(audio.sampleRate)Hz")
    }

    func stop() {
        print("[StubAudio] Stopped")
    }
}
