import Foundation

enum AppConstants {
    static let bundleID = "ai.mattr.muttr"
    static let ollamaBaseURL = URL(string: "http://localhost:11434")!
    static let defaultCaptureFPS: Double = 1.0
    static let maxCaptureFPS: Double = 2.0
    static let cloudTimeoutSeconds: TimeInterval = 3.0
    static let vlmTimeoutSeconds: TimeInterval = 5.0
    static let maxNarrationWords = 20
    static let defaultLocalModel = "llama3.2:3b"
    static let defaultHotkey = "⌘⇧M"

    enum Keychain {
        static let openAIKeyAccount = "muttr-openai-api-key"
        static let anthropicKeyAccount = "muttr-anthropic-api-key"
        static let serviceName = "ai.mattr.muttr"
    }

    enum CloudAPI {
        static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        static let openAIModel = "gpt-4o-mini"
        static let openAIVisionModel = "gpt-4o"
        static let anthropicModel = "claude-sonnet-4-20250514"
    }

    enum Performance {
        static let captureTarget: TimeInterval = 0.050
        static let ocrTarget: TimeInterval = 0.200
        static let diffTarget: TimeInterval = 0.050
        static let narrationTarget: TimeInterval = 2.0
        static let ttsTarget: TimeInterval = 0.500
        static let totalIdeal: TimeInterval = 3.0
        static let totalAcceptable: TimeInterval = 5.0
    }
}
