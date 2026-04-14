import Foundation

final class StubDiffEngine: DiffProviding, Sendable {
    func diff(previous: OCRResult, current: OCRResult) -> TextDiff {
        if previous.fullText.isEmpty {
            print("[StubDiff] First frame, no diff")
            return .empty
        }
        if previous.fullText == current.fullText {
            print("[StubDiff] No change")
            return .empty
        }
        let summary = "Screen changed: \(current.fullText.prefix(80))"
        print("[StubDiff] Change detected")
        return TextDiff(
            addedLines: current.fullText.components(separatedBy: "\n"),
            removedLines: previous.fullText.components(separatedBy: "\n"),
            summary: summary,
            significantChange: true
        )
    }
}
