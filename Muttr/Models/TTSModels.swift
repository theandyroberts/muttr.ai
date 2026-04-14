import Foundation

struct TTSSpeechRequest: Sendable {
    let text: String
    let urgency: UrgencyLevel
    let voiceID: String

    var rate: Float {
        switch urgency {
        case .routine: return 0.45
        case .interesting: return 0.50
        case .noteworthy: return 0.55
        case .needsInput: return 0.60
        }
    }

    var pitch: Float {
        switch urgency {
        case .routine: return 0.8
        case .interesting: return 0.9
        case .noteworthy: return 1.0
        case .needsInput: return 1.1
        }
    }
}

struct TTSAudioOutput: Sendable {
    let pcmData: Data
    let sampleRate: Double
    let channelCount: Int

    static let empty = TTSAudioOutput(pcmData: Data(), sampleRate: 22050, channelCount: 1)
}
