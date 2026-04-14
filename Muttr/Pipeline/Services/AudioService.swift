import Foundation
import AVFoundation

/// Audio output service using AVAudioEngine for PCM playback.
/// When TTSEngine uses AVSpeechSynthesizer (which plays directly), this is a passthrough.
/// When TTSEngine produces raw PCM (sherpa-onnx), this handles playback.
final class AudioService: AudioOutputProviding, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    var volume: Float = 0.8 {
        didSet {
            playerNode.volume = volume
        }
    }

    init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        playerNode.volume = volume
    }

    func play(_ audio: TTSAudioOutput) async throws {
        // If empty (AVSpeechSynthesizer handled playback), just return
        guard !audio.pcmData.isEmpty else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audio.sampleRate,
            channels: AVAudioChannelCount(audio.channelCount),
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(audio.pcmData.count / MemoryLayout<Float>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioError.bufferCreationFailed
        }
        buffer.frameLength = frameCount

        audio.pcmData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            if let dst = buffer.floatChannelData?[0] {
                memcpy(dst, src, audio.pcmData.count)
            }
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        return try await withCheckedThrowingContinuation { continuation in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}

enum AudioError: LocalizedError {
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed: return "Failed to create audio buffer."
        }
    }
}
