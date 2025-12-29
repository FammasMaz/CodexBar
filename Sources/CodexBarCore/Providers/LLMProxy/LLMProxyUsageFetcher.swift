import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches usage stats from the LLM Proxy server
public struct LLMProxyUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger("llmproxy-usage")

    private let baseURL: String
    private let apiKey: String?
    private let targetProvider: String

    public init(baseURL: String, apiKey: String?, targetProvider: String = "antigravity") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.targetProvider = targetProvider
    }

    /// Fetches usage stats from the LLM Proxy
    public func fetchUsage() async throws -> LLMProxyUsageSnapshot {
        let urlString = "\(baseURL)/v1/quota-stats?provider=\(targetProvider)"

        guard let url = URL(string: urlString) else {
            throw LLMProxyError.connectionFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        // Add authorization if API key is configured
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        Self.log.debug("Fetching from \(urlString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProxyError.connectionFailed("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw LLMProxyError.authenticationFailed
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.log.error("LLM Proxy returned \(httpResponse.statusCode): \(errorMessage)")
            throw LLMProxyError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Log raw response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            Self.log.debug("LLM Proxy response: \(jsonString.prefix(500))...")
        }

        let decoder = JSONDecoder()
        do {
            let apiResponse = try decoder.decode(LLMProxyQuotaResponse.self, from: data)

            guard let providerStats = apiResponse.providers[targetProvider] else {
                let available = apiResponse.providers.keys.joined(separator: ", ")
                throw LLMProxyError.invalidResponse(
                    "Provider '\(targetProvider)' not found. Available: \(available)"
                )
            }

            return LLMProxyUsageSnapshot(
                providerStats: providerStats,
                providerName: targetProvider,
                updatedAt: Date()
            )
        } catch let error as DecodingError {
            Self.log.error("JSON decoding error: \(error.localizedDescription)")
            throw LLMProxyError.invalidResponse(error.localizedDescription)
        } catch let error as LLMProxyError {
            throw error
        } catch {
            Self.log.error("Parsing error: \(error.localizedDescription)")
            throw LLMProxyError.invalidResponse(error.localizedDescription)
        }
    }

    /// Test connection to the proxy
    public func testConnection() async throws -> Bool {
        let urlString = "\(baseURL)/v1/providers"

        guard let url = URL(string: urlString) else {
            throw LLMProxyError.connectionFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw LLMProxyError.authenticationFailed
        }

        return httpResponse.statusCode == 200
    }
}
