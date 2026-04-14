import Foundation

final class StubNarrationService: NarrationProviding, Sendable {
    func generateNarration(for diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult {
        // Simulate some processing delay
        try await Task.sleep(nanoseconds: 200_000_000)

        let narrations = [
            NarrationResult(narration: "Looks like another build kicked off.", urgency: 1),
            NarrationResult(narration: "Something broke, better take a look.", urgency: 3),
            NarrationResult(narration: "Git push went through, nice.", urgency: 1),
            NarrationResult(narration: "Tests are failing, few of them at least.", urgency: 3),
            NarrationResult(narration: "Waiting for input, might want to check.", urgency: 4),
        ]

        let text = diff.summary.lowercased()
        if text.contains("error") || text.contains("failed") {
            print("[StubNarration] Error detected, urgency 3")
            return narrations[1]
        }
        if text.contains("y/n") || text.contains("continue") {
            print("[StubNarration] Input needed, urgency 4")
            return narrations[4]
        }
        print("[StubNarration] Routine narration")
        return narrations[0]
    }

    func isAvailable() async -> Bool {
        true
    }
}
