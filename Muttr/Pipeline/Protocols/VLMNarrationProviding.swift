import CoreGraphics
import Foundation

protocol VLMNarrationProviding: Sendable {
    func generateNarration(
        currentFrame: CGImage,
        previousFrame: CGImage?,
        timeout: TimeInterval
    ) async throws -> NarrationResult

    func isAvailable() async -> Bool
}
