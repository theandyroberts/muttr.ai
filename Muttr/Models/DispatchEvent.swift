import Foundation

struct DispatchEvent: Codable, Sendable {
    let type: String
    let narration: String
    let urgency: Int
    let timestamp: Date
    let metadata: [String: String]?
}
