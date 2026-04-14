import Foundation

struct OllamaModel: Identifiable, Codable, Sendable {
    let name: String
    let size: Int64
    let modifiedAt: String

    var id: String { name }

    var displaySize: String {
        let gb = Double(size) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}
