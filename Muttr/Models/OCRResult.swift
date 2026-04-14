import Foundation
import CoreGraphics

struct OCRTextBlock: Sendable {
    let text: String
    let confidence: Float
    let bounds: CGRect
}

struct OCRResult: Sendable {
    let fullText: String
    let blocks: [OCRTextBlock]
    let timestamp: Date

    static let empty = OCRResult(fullText: "", blocks: [], timestamp: Date())
}
