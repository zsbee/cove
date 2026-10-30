import Foundation

struct LocalQuerySettings: Sendable, Equatable {
    static let endpointKey = "queryAI.ollama.endpoint"
    static let modelKey = "queryAI.ollama.model"
    static let timeoutKey = "queryAI.ollama.timeout"
    static let autoStartKey = "queryAI.ollama.autoStart"
    static let defaultEndpoint = "http://127.0.0.1:11434"
    static let defaultModel = "qwen2.5-coder:14b"

    var endpoint = defaultEndpoint
    var model = defaultModel
    var timeout: TimeInterval = 180
    var autoStart = true

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let timeout = defaults.double(forKey: timeoutKey)
        return Self(
            endpoint: defaults.string(forKey: endpointKey) ?? defaultEndpoint,
            model: defaults.string(forKey: modelKey) ?? defaultModel,
            timeout: timeout > 0 ? timeout : 180,
            autoStart: defaults.object(forKey: autoStartKey) == nil || defaults.bool(forKey: autoStartKey)
        )
    }

    func baseURL() throws -> URL {
        guard let components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "http",
              let host = components.host,
              ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased()),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let url = components.url else {
            throw QueryAgentError.launchUnavailable("Use a local Ollama HTTP address, such as http://127.0.0.1:11434. Remote endpoints are not allowed.")
        }
        return url
    }
}
