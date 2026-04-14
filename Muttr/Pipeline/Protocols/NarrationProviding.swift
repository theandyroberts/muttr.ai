import Foundation

protocol NarrationProviding: Sendable {
    func generateNarration(for diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult
    func isAvailable() async -> Bool
}
