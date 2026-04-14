import CoreGraphics

protocol OCRProviding: Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult
}
