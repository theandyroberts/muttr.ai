import Foundation

enum NarrationMode: String, Codable, CaseIterable {
    case localOnly
    case cloudOnly
    case hybrid
    case vlmCloud
}
