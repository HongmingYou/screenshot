import Foundation

/// Calls the OpenRouter chat completions API.
struct OpenRouterClient {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Chronicle macOS", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ],
            "max_tokens": 1024,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OpenRouterError.apiError(http.statusCode, msg)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OpenRouterError.unexpectedShape
        }

        return content
    }

    enum OpenRouterError: Error, LocalizedError {
        case invalidResponse
        case apiError(Int, String)
        case unexpectedShape

        var errorDescription: String? {
            switch self {
            case .invalidResponse:       return "Invalid server response"
            case .apiError(let c, let m): return "API error \(c): \(m)"
            case .unexpectedShape:       return "Unexpected API response format"
            }
        }
    }
}
