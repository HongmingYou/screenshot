import Foundation

/// Persists user-configurable settings via UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var openRouterAPIKey: String {
        didSet { defaults.set(openRouterAPIKey, forKey: Keys.apiKey) }
    }

    @Published var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: Keys.model) }
    }

    static let availableModels: [(id: String, label: String)] = [
        ("anthropic/claude-3-haiku",              "Claude 3 Haiku"),
        ("anthropic/claude-3.5-sonnet",           "Claude 3.5 Sonnet"),
        ("openai/gpt-4o-mini",                    "GPT-4o Mini"),
        ("openai/gpt-4o",                         "GPT-4o"),
        ("google/gemini-flash-1.5",               "Gemini Flash 1.5"),
        ("meta-llama/llama-3.1-8b-instruct",      "Llama 3.1 8B"),
        ("mistralai/mistral-7b-instruct",         "Mistral 7B"),
    ]

    private enum Keys {
        static let apiKey = "openRouterAPIKey"
        static let model  = "openRouterModel"
    }

    private init() {
        openRouterAPIKey = defaults.string(forKey: Keys.apiKey) ?? ""
        openRouterModel  = defaults.string(forKey: Keys.model) ?? "anthropic/claude-3-haiku"
    }
}
