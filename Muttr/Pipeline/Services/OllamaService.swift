import Foundation

final class OllamaService: NarrationProviding, Sendable {
    private let baseURL: URL
    private let modelName: String
    private let session: URLSession

    init(baseURL: URL = AppConstants.ollamaBaseURL, modelName: String = AppConstants.defaultLocalModel) {
        self.baseURL = baseURL
        self.modelName = modelName

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0 // generous for cold model loads
        self.session = URLSession(configuration: config)
    }

    /// Pre-load the model into memory so the first real narration is fast
    func warmup() async {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0
        let body: [String: Any] = [
            "model": modelName,
            "prompt": "Hi",
            "stream": false,
            "options": ["num_predict": 1],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }

    func generateNarration(for diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult {
        let prompt = buildPrompt(diff: diff)

        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": [
                "temperature": 0.7,
                "num_predict": 100,
            ],
        ]

        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = max(timeout, 15.0) // at least 15s for slow first calls
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.badResponse
        }

        // Ollama wraps the response in {"response": "..."} — the inner string is our JSON
        let ollamaResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let narration = try JSONDecoder().decode(NarrationResult.self, from: Data(ollamaResponse.response.utf8))

        return narration
    }

    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func buildPrompt(diff: TextDiff) -> String {
        """
        You are the user's eyes. They are NOT looking at the screen. You are the ONLY way they know what is happening. Dig into the smallest detail of what changed and describe it.

        Voice: a dev muttering to themselves. One sentence, max 20 words.

        NEVER be vague. NEVER say "another change", "something updated", "file modified", or anything generic. Instead:
        - Name the exact file, function, variable, command, or error you see.
        - If there's an error, quote the key part of the message.
        - If code is being written, say what it does.
        - If a command is running, say which one and its output.
        - If a build/test is running, say if it passed or failed and why.

        Respond ONLY with: {"narration": "...", "urgency": N}
        urgency: 1=routine, 2=interesting, 3=noteworthy (errors/warnings), 4=needs input (prompts/y/n)

        WHAT JUST APPEARED ON SCREEN:
        \(diff.summary)
        """
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

enum OllamaError: LocalizedError {
    case badResponse
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Bad response from Ollama."
        case .notAvailable: return "Ollama is not running."
        }
    }
}
