import Foundation

final class DiffEngine: DiffProviding, Sendable {
    private let minChangeChars = 30
    private let maxSummaryLength = 1500
    // Lines that differ by fewer chars than this are OCR jitter, not real changes
    private let jitterThreshold = 3

    func diff(previous: OCRResult, current: OCRResult) -> TextDiff {
        let prevLines = previous.fullText.components(separatedBy: "\n")
        let currLines = current.fullText.components(separatedBy: "\n")

        let difference = currLines.difference(from: prevLines)

        var rawAdded: [String] = []
        var rawRemoved: [String] = []

        for change in difference {
            switch change {
            case .insert(_, let element, _):
                let trimmed = element.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    rawAdded.append(trimmed)
                }
            case .remove(_, let element, _):
                let trimmed = element.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    rawRemoved.append(trimmed)
                }
            }
        }

        // Filter OCR jitter: if a "removed" line is nearly identical to an "added" line,
        // both are jitter — the same text was re-read slightly differently
        let added = filterJitter(added: rawAdded, removed: &rawRemoved)

        // Check significance — need enough genuinely new content
        let newChars = added.joined().count
        guard newChars >= minChangeChars else {
            return .empty
        }

        let summary = buildSummary(added: added)

        return TextDiff(
            addedLines: added,
            removedLines: rawRemoved,
            summary: summary,
            significantChange: true
        )
    }

    private func filterJitter(added: [String], removed: inout [String]) -> [String] {
        var genuinelyAdded: [String] = []

        for addedLine in added {
            let isJitter = removed.contains { removedLine in
                levenshteinClose(removedLine, addedLine, threshold: jitterThreshold)
            }
            if isJitter {
                // Remove the matched "removed" line too — it's the same content
                removed.removeAll { levenshteinClose($0, addedLine, threshold: jitterThreshold) }
            } else {
                genuinelyAdded.append(addedLine)
            }
        }

        return genuinelyAdded
    }

    /// Quick check: are two strings within `threshold` edits of each other?
    private func levenshteinClose(_ a: String, _ b: String, threshold: Int) -> Bool {
        let lenDiff = abs(a.count - b.count)
        if lenDiff > threshold { return false }
        // For short strings or very similar lengths, do char-by-char compare
        let aChars = Array(a)
        let bChars = Array(b)
        let minLen = min(aChars.count, bChars.count)
        var diffs = lenDiff
        for i in 0..<minLen {
            if aChars[i] != bChars[i] { diffs += 1 }
            if diffs > threshold { return false }
        }
        return true
    }

    private func buildSummary(added: [String]) -> String {
        // Only send what's new — the LLM doesn't need to know what disappeared
        let text = added.prefix(30).joined(separator: "\n")
        if text.count > maxSummaryLength {
            return String(text.prefix(maxSummaryLength))
        }
        return text
    }
}
