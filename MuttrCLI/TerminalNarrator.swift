import Foundation

/// Turns stream segments into spoken narration.
///
/// Segments are appended to a FIFO queue and processed by a single consumer
/// so narrations play in full, in order. Narration may lag behind the screen —
/// that's by design: hearing "test passed" before "test failed" is worse than
/// hearing both, in order, slightly late.
///
/// Backpressure: if the queue grows beyond `maxQueued`, the oldest segments
/// collapse into a coalesced one so we don't fall ever-further behind on
/// long-running sessions.
actor TerminalNarrator {
    private let narrator: OllamaService
    private let tts: any TTSProviding
    private let audio: any AudioOutputProviding
    private let voiceID: String
    private let maxQueued: Int

    private var queue: [String] = []
    private var consumer: Task<Void, Never>?
    private var lastNarration = ""

    init(
        narrator: OllamaService,
        tts: any TTSProviding,
        audio: any AudioOutputProviding,
        voiceID: String,
        maxQueued: Int = 8
    ) {
        self.narrator = narrator
        self.tts = tts
        self.audio = audio
        self.voiceID = voiceID
        self.maxQueued = maxQueued
    }

    func warmup() async {
        await narrator.warmup()
    }

    nonisolated func submit(segment: String) {
        Task { await self.enqueue(segment) }
    }

    /// Block until the queue has drained. Called at shutdown so the last
    /// narration actually finishes playing before the process exits.
    func drain(timeout: TimeInterval = 15.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while (!queue.isEmpty || consumer != nil) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func enqueue(_ segment: String) {
        queue.append(segment)
        if queue.count > maxQueued {
            let collapsed = queue.prefix(queue.count - maxQueued + 1).joined(separator: "\n\n")
            queue.removeFirst(queue.count - maxQueued + 1)
            queue.insert(collapsed, at: 0)
            Log.write("queue collapsed oldest segments; depth=\(queue.count)")
        }
        startConsumerIfNeeded()
    }

    private func startConsumerIfNeeded() {
        guard consumer == nil else { return }
        consumer = Task { [weak self] in
            await self?.consume()
        }
    }

    private func consume() async {
        while let next = pop() {
            await narrateAndSpeak(next)
        }
        consumer = nil
    }

    private func pop() -> String? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    private func narrateAndSpeak(_ segment: String) async {
        let preview = segment.replacingOccurrences(of: "\n", with: "⏎ ").prefix(200)
        Log.write("narrator in (\(segment.count) chars): \(preview)")

        let diff = TextDiff(
            addedLines: segment.split(separator: "\n").map(String.init),
            removedLines: [],
            summary: segment,
            significantChange: true
        )

        do {
            let result = try await narrator.generateNarration(for: diff, timeout: 8.0)
            Log.write("narrator out: [\(result.urgencyLevel.label)] \(result.narration)")
            guard result.narration != lastNarration else { return }
            lastNarration = result.narration

            let request = TTSSpeechRequest(
                text: result.narration,
                urgency: result.urgencyLevel,
                voiceID: voiceID
            )
            let output = try await tts.synthesize(request)
            try await audio.play(output)
        } catch is CancellationError {
            return
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled { return }
            Log.write("narration failed: \(error.localizedDescription)")
        }
    }
}
