import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum LLMProxyDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .llmProxy,
            metadata: ProviderMetadata(
                id: .llmProxy,
                displayName: "LLM Proxy",
                sessionLabel: "Quota",
                weeklyLabel: "Requests",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show LLM Proxy usage",
                cliName: "llmproxy",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .llmProxy,
                iconResourceName: "ProviderIcon-llmproxy",
                // Cornflower blue color
                color: ProviderColor(red: 100 / 255, green: 149 / 255, blue: 237 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "LLM Proxy cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [LLMProxyAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "llmproxy",
                aliases: ["proxy", "llm-proxy"],
                versionDetector: nil))
    }
}

struct LLMProxyAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "llmproxy.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        // Available if we have a proxy URL configured (environment or keychain)
        Self.resolveURL(context: context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let proxyURL = Self.resolveURL(context: context) else {
            throw LLMProxyError.missingURL
        }

        let apiKey = Self.resolveAPIKey(context: context)
        let targetProvider = LLMProxySettingsReader.targetProvider(environment: context.env)

        let fetcher = LLMProxyUsageFetcher(
            baseURL: proxyURL,
            apiKey: apiKey,
            targetProvider: targetProvider
        )

        let snapshot = try await fetcher.fetchUsage()
        return makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "api"
        )
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        // No fallback for this provider
        false
    }

    private static func resolveURL(context: ProviderFetchContext) -> String? {
        // Check keychain first (via settings), then environment
        if let keychainURL = context.settings?.llmProxy?.proxyURL,
           !keychainURL.isEmpty
        {
            return keychainURL
        }
        return LLMProxySettingsReader.proxyURL(environment: context.env)
    }

    private static func resolveAPIKey(context: ProviderFetchContext) -> String? {
        // Check keychain first (via settings), then environment
        if let keychainKey = context.settings?.llmProxy?.apiKey,
           !keychainKey.isEmpty
        {
            return keychainKey
        }
        return LLMProxySettingsReader.apiKey(environment: context.env)
    }
}
