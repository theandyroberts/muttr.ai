import Foundation

struct VoiceProfile: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let language: String
    let isPro: Bool

    static let defaultVoice = VoiceProfile(
        id: "en_US-amy-medium",
        name: "Amy",
        language: "en_US",
        isPro: false
    )
}
