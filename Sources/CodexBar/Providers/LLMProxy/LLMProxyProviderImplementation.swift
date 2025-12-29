import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct LLMProxyProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .llmProxy

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "llmproxy-url",
                title: "Proxy URL",
                subtitle: "Base URL of your LLM Proxy server (e.g., http://192.168.1.100:8000)",
                kind: .plain,
                placeholder: "http://localhost:8000",
                binding: context.stringBinding(\.llmProxyURL),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "llmproxy-test",
                        title: "Test Connection",
                        style: .bordered,
                        isVisible: { !context.settings.llmProxyURL.isEmpty },
                        perform: {
                            await testConnection(context: context)
                        }),
                ],
                isVisible: nil),
            ProviderSettingsFieldDescriptor(
                id: "llmproxy-api-key",
                title: "API Key",
                subtitle: "Optional. Required if the proxy has PROXY_API_KEY set.",
                kind: .secure,
                placeholder: "Paste API key (optional)…",
                binding: context.stringBinding(\.llmProxyAPIKey),
                actions: [],
                isVisible: nil),
        ]
    }

    @MainActor
    private func testConnection(context: ProviderSettingsContext) async {
        let proxyURL = context.settings.llmProxyURL
        let apiKey = context.settings.llmProxyAPIKey
        guard !proxyURL.isEmpty else { return }

        context.setStatusText("llmproxy-test", "Testing connection…")

        let fetcher = LLMProxyUsageFetcher(
            baseURL: proxyURL,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )

        do {
            _ = try await fetcher.testConnection()
            context.setStatusText("llmproxy-test", "✓ Connection successful")

            // Clear status after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    context.setStatusText("llmproxy-test", nil)
                }
            }
        } catch let error as LLMProxyError {
            context.setStatusText("llmproxy-test", "✗ \(error.localizedDescription)")
        } catch {
            context.setStatusText("llmproxy-test", "✗ Connection failed")
        }
    }
}
