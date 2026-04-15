import Foundation

final class CloudAPIService: NarrationProviding, Sendable {
    private let provider: CloudProvider
    private let apiKey: String
    private let pov: NarrationPOV
    private let session: URLSession

    enum CloudProvider: Sendable {
        case openAI
        case anthropic
    }

    init(provider: CloudProvider, apiKey: String, pov: NarrationPOV = .documentary) {
        self.provider = provider
        self.apiKey = apiKey
        self.pov = pov

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConstants.cloudTimeoutSeconds
        self.session = URLSession(configuration: config)
    }

    func generateNarration(for diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult {
        switch provider {
        case .openAI:
            return try await generateOpenAI(diff: diff, timeout: timeout)
        case .anthropic:
            return try await generateAnthropic(diff: diff, timeout: timeout)
        }
    }

    func isAvailable() async -> Bool {
        !apiKey.isEmpty
    }

    // MARK: - OpenAI

    private func generateOpenAI(diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult {
        let systemPrompt = pov.systemPrompt
        let userPrompt = "What changed on screen:\n\(diff.summary)"

        let body: [String: Any] = [
            "model": AppConstants.CloudAPI.openAIModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.7,
            "max_tokens": 100,
            "response_format": ["type": "json_object"],
        ]

        var request = URLRequest(url: AppConstants.CloudAPI.openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudAPIError.badResponse
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw CloudAPIError.noContent
        }

        return try JSONDecoder().decode(NarrationResult.self, from: Data(content.utf8))
    }

    // MARK: - Anthropic

    private func generateAnthropic(diff: TextDiff, timeout: TimeInterval) async throws -> NarrationResult {
        let systemPrompt = pov.systemPrompt
        let userPrompt = "What changed on screen:\n\(diff.summary)\n\nRespond with only the JSON object."

        let body: [String: Any] = [
            "model": AppConstants.CloudAPI.anthropicModel,
            "max_tokens": 100,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt],
            ],
        ]

        var request = URLRequest(url: AppConstants.CloudAPI.anthropicEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudAPIError.badResponse
        }

        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let textBlock = anthropicResponse.content.first(where: { $0.type == "text" }) else {
            throw CloudAPIError.noContent
        }

        return try JSONDecoder().decode(NarrationResult.self, from: Data(textBlock.text.utf8))
    }

    // MARK: - Shared

    static func validateKey(provider: CloudProvider, apiKey: String) async -> Bool {
        let service = CloudAPIService(provider: provider, apiKey: apiKey)
        let testDiff = TextDiff(
            addedLines: ["Hello world"],
            removedLines: [],
            summary: "Added: Hello world",
            significantChange: true
        )
        do {
            _ = try await service.generateNarration(for: testDiff, timeout: 10)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Response Models

private struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}

enum CloudAPIError: LocalizedError {
    case badResponse
    case noContent
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Bad response from cloud API."
        case .noContent: return "No content in cloud API response."
        case .invalidKey: return "API key is invalid."
        }
    }
}
