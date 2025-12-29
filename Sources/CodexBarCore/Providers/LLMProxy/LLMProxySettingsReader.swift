import Foundation

public struct LLMProxySettingsReader: Sendable {
    private static let log = CodexBarLog.logger("llmproxy-settings")

    public static let proxyURLKey = "LLM_PROXY_URL"
    public static let proxyAPIKeyKey = "LLM_PROXY_API_KEY"
    public static let proxyProviderKey = "LLM_PROXY_PROVIDER"

    public static let defaultProxyURL = "http://localhost:8000"
    public static let defaultProvider = "antigravity"

    /// Resolve proxy URL from environment
    public static func proxyURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        cleaned(environment[proxyURLKey])
    }

    /// Resolve API key from environment
    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        cleaned(environment[proxyAPIKeyKey])
    }

    /// Resolve target provider to query
    public static func targetProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String
    {
        cleaned(environment[proxyProviderKey]) ?? defaultProvider
    }

    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
