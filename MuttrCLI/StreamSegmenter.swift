import Foundation

/// Consumes bytes from a child PTY, strips ANSI escape sequences,
/// and emits "segments" — logical chunks delimited by a quiet pause
/// or by a big block of text (avoid letting the buffer grow unbounded).
actor StreamSegmenter {
    private var buffer = ""
    private var lastAppendAt = Date.distantPast
    private var lastTypingAt = Date.distantPast
    private let quietPause: TimeInterval
    private let typingEchoWindow: TimeInterval
    private let maxChars: Int
    private let minChars: Int
    private var flushTask: Task<Void, Never>?
    private let onSegment: @Sendable (String) -> Void

    init(
        quietPause: TimeInterval = 0.8,
        typingEchoWindow: TimeInterval = 0.5,
        minChars: Int = 40,
        maxChars: Int = 2000,
        onSegment: @escaping @Sendable (String) -> Void
    ) {
        self.quietPause = quietPause
        self.typingEchoWindow = typingEchoWindow
        self.minChars = minChars
        self.maxChars = maxChars
        self.onSegment = onSegment
    }

    func ingest(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        let cleaned = AnsiStripper.strip(chunk)
        guard !cleaned.isEmpty else { return }
        buffer.append(cleaned)
        lastAppendAt = Date()

        if buffer.count >= maxChars {
            flushNow()
            return
        }
        scheduleFlush()
    }

    /// Called when the user types. Suppresses narration of output that arrives
    /// within `typingEchoWindow` of a keystroke — that output is almost always
    /// just the terminal echoing the keypress back, not fresh app content.
    func noteTyping() {
        lastTypingAt = Date()
    }

    func finish() {
        flushTask?.cancel()
        flushTask = nil
        flushNow()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [quietPause] in
            try? await Task.sleep(nanoseconds: UInt64(quietPause * 1_000_000_000))
            if Task.isCancelled { return }
            await self.tickFlush()
        }
    }

    private func tickFlush() {
        let quietFor = Date().timeIntervalSince(lastAppendAt)
        guard quietFor >= quietPause else {
            scheduleFlush()
            return
        }
        flushNow()
    }

    private func flushNow() {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard text.count >= minChars else { return }
        // Skip segments that arrived while the user was actively typing —
        // those are overwhelmingly keypress echoes, not app output.
        if Date().timeIntervalSince(lastTypingAt) < typingEchoWindow {
            Log.write("segmenter: dropping \(text.count) chars (typing echo)")
            return
        }
        onSegment(text)
    }
}

enum AnsiStripper {
    // CSI sequences: ESC [ ... final byte in @-~
    // OSC sequences: ESC ] ... BEL or ESC \
    // Plus stray carriage returns, bells, etc.
    private static let csi = try! NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]")
    private static let osc = try! NSRegularExpression(pattern: "\u{001B}\\].*?(\u{0007}|\u{001B}\\\\)")
    private static let other = try! NSRegularExpression(pattern: "\u{001B}[@-Z\\\\-_]")

    static func strip(_ s: String) -> String {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        var out = osc.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        let r2 = NSRange(out.startIndex..<out.endIndex, in: out)
        out = csi.stringByReplacingMatches(in: out, range: r2, withTemplate: "")
        let r3 = NSRange(out.startIndex..<out.endIndex, in: out)
        out = other.stringByReplacingMatches(in: out, range: r3, withTemplate: "")
        // Normalize line endings and drop lone CRs used for line redraw
        out = out.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r", with: "\n")
        return out
    }
}
