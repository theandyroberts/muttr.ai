import Foundation

struct AppSettings: Codable {
    var captureFPS: Double = AppConstants.defaultCaptureFPS
    var selectedModelName: String = AppConstants.defaultLocalModel
    var narrationMode: NarrationMode = .localOnly
    var selectedVoiceID: String = VoiceProfile.defaultVoice.id
    var volume: Float = 0.8
    var launchAtLogin: Bool = false
    var cloudProvider: CloudProvider = .openAI

    enum CloudProvider: String, Codable, CaseIterable {
        case openAI
        case anthropic
    }
}
