import Foundation

protocol DiffProviding: Sendable {
    func diff(previous: OCRResult, current: OCRResult) -> TextDiff
}
