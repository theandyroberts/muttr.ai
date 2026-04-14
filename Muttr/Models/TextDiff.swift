import Foundation

struct TextDiff: Sendable {
    let addedLines: [String]
    let removedLines: [String]
    let summary: String
    let significantChange: Bool

    static let empty = TextDiff(addedLines: [], removedLines: [], summary: "", significantChange: false)
}
