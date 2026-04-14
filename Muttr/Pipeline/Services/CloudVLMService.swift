import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class CloudVLMService: VLMNarrationProviding, Sendable {
    private let provider: CloudProvider
    private let apiKey: String
    private let session: URLSession

    enum CloudProvider: Sendable {
        case openAI
        case anthropic
    }

    init(provider: CloudProvider, apiKey: String) {
        self.provider = provider
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConstants.vlmTimeoutSeconds
        self.session = URLSession(configuration: config)
    }

    func generateNarration(
        currentFrame: CGImage,
        previousFrame: CGImage?,
        timeout: TimeInterval
    ) async throws -> NarrationResult {
        switch provider {
        case .openAI:
            return try await generateOpenAI(current: currentFrame, previous: previousFrame, timeout: timeout)
        case .anthropic:
            return try await generateAnthropic(current: currentFrame, previous: previousFrame, timeout: timeout)
        }
    }

    func isAvailable() async -> Bool {
        !apiKey.isEmpty
    }

    // MARK: - Image Encoding

    private static func encodeFrame(_ image: CGImage) -> String? {
        let maxDimension: CGFloat = 1024
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let scale = min(1.0, maxDimension / max(width, height))
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resized = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.6]
        CGImageDestinationAddImage(destination, resized, options as CFDictionary)
        CGImageDestinationFinalize(destination)

        return (data as Data).base64EncodedString()
    }

    // MARK: - OpenAI (GPT-4o Vision)

    private func generateOpenAI(current: CGImage, previous: CGImage?, timeout: TimeInterval) async throws -> NarrationResult {
        guard let currentB64 = Self.encodeFrame(current) else {
            throw VLMError.imageEncodingFailed
        }

        var imageContent: [[String: Any]] = []

        if let previous, let prevB64 = Self.encodeFrame(previous) {
            imageContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(prevB64)", "detail": "low"],
            ])
        }

        imageContent.append([
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(currentB64)", "detail": "low"],
        ])

        let userContent: [[String: Any]] = [
            ["type": "text", "text": Self.userPrompt(hasPrevious: previous != nil)],
        ] + imageContent

        let body: [String: Any] = [
            "model": AppConstants.CloudAPI.openAIVisionModel,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent],
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
            throw VLMError.badResponse
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIVLMResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw VLMError.noContent
        }

        return try JSONDecoder().decode(NarrationResult.self, from: Data(content.utf8))
    }

    // MARK: - Anthropic (Claude Vision)

    private func generateAnthropic(current: CGImage, previous: CGImage?, timeout: TimeInterval) async throws -> NarrationResult {
        guard let currentB64 = Self.encodeFrame(current) else {
            throw VLMError.imageEncodingFailed
        }

        var userContent: [[String: Any]] = []

        if let previous, let prevB64 = Self.encodeFrame(previous) {
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": prevB64,
                ],
            ])
        }

        userContent.append([
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": "image/jpeg",
                "data": currentB64,
            ],
        ])

        userContent.append([
            "type": "text",
            "text": Self.userPrompt(hasPrevious: previous != nil) + "\n\nRespond with only the JSON object.",
        ])

        let body: [String: Any] = [
            "model": AppConstants.CloudAPI.anthropicModel,
            "max_tokens": 100,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": userContent],
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
            throw VLMError.badResponse
        }

        let anthropicResponse = try JSONDecoder().decode(AnthropicVLMResponse.self, from: data)
        guard let textBlock = anthropicResponse.content.first(where: { $0.type == "text" }) else {
            throw VLMError.noContent
        }

        return try JSONDecoder().decode(NarrationResult.self, from: Data(textBlock.text.utf8))
    }

    // MARK: - Prompts

    private static let systemPrompt = """
        You are Muttr, a developer's screen narrator. You watch a developer's screen and mutter \
        observations about what's happening.

        Respond with JSON: {"narration": "...", "urgency": N}
        - narration: One sentence, max 20 words. Voice of a slightly bored developer muttering to themselves.
        - urgency: 1=routine, 2=interesting, 3=noteworthy, 4=needs user input

        Focus on what CHANGED between frames. Ignore static UI chrome (menu bars, dock, window decorations). \
        Pay attention to: code being written/modified, terminal output, build results, errors, prompts \
        waiting for input, test results, git operations, file changes.

        If nothing meaningful changed, respond with: {"narration": "Nothing new.", "urgency": 1}
        """

    private static func userPrompt(hasPrevious: Bool) -> String {
        if hasPrevious {
            return "Here are two screenshots of a developer's screen. The first is the previous state, the second is the current state. What changed?"
        } else {
            return "Here is a screenshot of a developer's screen. What's happening?"
        }
    }
}

// MARK: - Response Models

private struct OpenAIVLMResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct AnthropicVLMResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}

enum VLMError: LocalizedError {
    case imageEncodingFailed
    case badResponse
    case noContent

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Failed to encode screen frame."
        case .badResponse: return "Bad response from vision API."
        case .noContent: return "No content in vision API response."
        }
    }
}
