import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published var availableModels: [OllamaModel] = []
    @Published var isPulling: Bool = false
    @Published var pullProgress: Double = 0

    private let baseURL: URL
    private let session = URLSession.shared

    init(baseURL: URL = AppConstants.ollamaBaseURL) {
        self.baseURL = baseURL
    }

    func listModels() async throws {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        self.availableModels = response.models
    }

    func pullModel(name: String) async throws {
        isPulling = true
        pullProgress = 0
        defer { isPulling = false }

        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])

        let (bytes, _) = try await session.bytes(for: request)

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let progress = try? JSONDecoder().decode(OllamaPullProgress.self, from: data) else {
                continue
            }
            if progress.total > 0 {
                self.pullProgress = Double(progress.completed) / Double(progress.total)
            }
        }

        // Refresh model list
        try await listModels()
    }

    func deleteModel(name: String) async throws {
        let url = baseURL.appendingPathComponent("api/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.badResponse
        }

        try await listModels()
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaPullProgress: Decodable {
    let status: String
    let completed: Int64
    let total: Int64

    enum CodingKeys: String, CodingKey {
        case status, completed, total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        completed = try container.decodeIfPresent(Int64.self, forKey: .completed) ?? 0
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? 0
    }
}
