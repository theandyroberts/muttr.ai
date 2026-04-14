import Foundation

struct UrgencyClassifier: Sendable {
    private static let urgency4Patterns: [String] = [
        "y/n", "yes/no", "[y/n]", "(y/n)",
        "password", "passphrase", "api key", "api_key",
        "enter your", "type your", "input required",
        "press enter", "press return", "continue?",
        "are you sure", "confirm", "do you want",
        "permission denied", "access denied",
        "fatal error", "panic", "segfault", "segmentation fault",
    ]

    private static let urgency3Patterns: [String] = [
        "error", "failed", "failure", "exception",
        "warning", "warn", "deprecated",
        "build failed", "compilation error", "syntax error",
        "not found", "missing", "undefined", "unresolved",
        "timeout", "timed out", "connection refused",
        "merge conflict", "conflict",
        "exit code", "non-zero", "status code",
    ]

    func classify(_ diff: TextDiff) -> UrgencyLevel {
        let text = diff.summary.lowercased()

        for pattern in Self.urgency4Patterns {
            if text.contains(pattern) {
                return .needsInput
            }
        }

        for pattern in Self.urgency3Patterns {
            if text.contains(pattern) {
                return .noteworthy
            }
        }

        let changeVolume = diff.addedLines.count + diff.removedLines.count
        if changeVolume > 10 {
            return .interesting
        }

        return .routine
    }
}
