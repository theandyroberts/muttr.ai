import Foundation

struct NarrationResult: Codable, Sendable {
    let narration: String
    let urgency: Int

    var urgencyLevel: UrgencyLevel {
        UrgencyLevel(rawValue: urgency) ?? .routine
    }
}
