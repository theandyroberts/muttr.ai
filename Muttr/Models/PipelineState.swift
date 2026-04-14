import Foundation

enum PipelineState: Sendable {
    case idle
    case running
    case paused
    case error(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

struct PipelineStatus: Sendable {
    var state: PipelineState = .idle
    var lastNarration: NarrationResult?
    var lastError: String?
    var framesProcessed: Int = 0
}
