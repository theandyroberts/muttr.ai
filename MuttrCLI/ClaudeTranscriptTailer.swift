import Foundation

/// Tails Claude Code's structured JSONL transcripts and emits clean narration
/// segments to a callback. Much higher fidelity than scraping the PTY because
/// every event is already typed (user, assistant, tool_use, tool_result) and
/// free of TUI chrome, spinners, ANSI escape sequences, or keystroke echoes.
///
/// Transcript layout:
///   ~/.claude/projects/<project-slug>/<session-uuid>.jsonl
/// Each line is one JSON event.
actor ClaudeTranscriptTailer {
    private let projectsRoot: URL
    private let pollInterval: TimeInterval
    private let onSegment: @Sendable (String) -> Void

    private var currentFile: URL?
    private var position: UInt64 = 0
    private var lineBuffer = Data()
    private var pollTask: Task<Void, Never>?

    init(
        projectsRoot: URL = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")),
        pollInterval: TimeInterval = 0.2,
        onSegment: @escaping @Sendable (String) -> Void
    ) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
        self.onSegment = onSegment
    }

    func start() {
        guard pollTask == nil else { return }
        Log.write("claude-tail: watching \(projectsRoot.path)")
        pollTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func tick() async {
        guard let newest = findNewestSession() else { return }
        if newest != currentFile {
            currentFile = newest
            // Start reading from the current end so we don't replay session history.
            let size = (try? FileManager.default.attributesOfItem(atPath: newest.path)[.size] as? UInt64) ?? 0
            position = size
            lineBuffer.removeAll(keepingCapacity: true)
            Log.write("claude-tail: attached to \(newest.lastPathComponent) from byte \(size)")
        }
        await readNewBytes(from: newest)
    }

    private func findNewestSession() -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else { continue }
            if best == nil || date > best!.date {
                best = (url, date)
            }
        }
        return best?.url
    }

    private func readNewBytes(from url: URL) async {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: position)
        } catch {
            return
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        position += UInt64(data.count)
        lineBuffer.append(data)

        // Split on newlines; keep partial tail for the next poll.
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: 0..<nl)
            lineBuffer.removeSubrange(0...nl)
            if lineData.isEmpty { continue }
            if let text = render(line: lineData) {
                onSegment(text)
            }
        }
    }

    private func render(line: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        let type = obj["type"] as? String
        switch type {
        case "assistant":
            return renderAssistant(obj)
        case "tool_use":
            return renderToolUse(obj)
        case "summary":
            if let summary = obj["summary"] as? String { return "[summary] \(summary)" }
            return nil
        default:
            // user, tool_result, system, etc. — skip. User events we already
            // know, and raw tool results are too noisy for narration.
            return nil
        }
    }

    private func renderAssistant(_ event: [String: Any]) -> String? {
        guard let message = event["message"] as? [String: Any] else { return nil }
        guard let content = message["content"] as? [[String: Any]] else {
            if let text = message["content"] as? String { return text }
            return nil
        }
        var parts: [String] = []
        for block in content {
            let blockType = block["type"] as? String
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    parts.append(text)
                }
            case "tool_use":
                if let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    parts.append("[tool] \(describeTool(name: name, input: input))")
                }
            default:
                break
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    private func renderToolUse(_ event: [String: Any]) -> String? {
        guard let name = event["name"] as? String else { return nil }
        let input = event["input"] as? [String: Any] ?? [:]
        return "[tool] \(describeTool(name: name, input: input))"
    }

    private func describeTool(name: String, input: [String: Any]) -> String {
        func s(_ key: String) -> String {
            (input[key] as? String) ?? ""
        }
        switch name {
        case "Read":       return "Reading \(s("file_path"))"
        case "Write":      return "Writing \(s("file_path"))"
        case "Edit":       return "Editing \(s("file_path"))"
        case "Bash":
            let cmd = s("command")
            return "Running bash: \(cmd.prefix(100))"
        case "Grep":       return "Grepping \(s("pattern"))"
        case "Glob":       return "Globbing \(s("pattern"))"
        case "WebFetch":   return "Fetching \(s("url"))"
        case "WebSearch":  return "Searching web for \(s("query"))"
        case "TodoWrite":  return "Updating the task list"
        default:           return "Calling \(name)"
        }
    }
}
