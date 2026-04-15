import Foundation

final class OllamaService: NarrationProviding, Sendable {
    private let baseURL: URL
    private let modelName: String
    private let pov: NarrationPOV
    private let session: URLSession

    init(
        baseURL: URL = AppConstants.ollamaBaseURL,
        modelName: String = AppConstants.defaultLocalModel,
        pov: NarrationPOV = .documentary
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.pov = pov

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
        \(pov.systemPrompt)

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
