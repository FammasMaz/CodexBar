import Foundation

// MARK: - API Response Models

/// Response from /v1/quota-stats endpoint
public struct LLMProxyQuotaResponse: Decodable, Sendable {
    public let providers: [String: LLMProxyProviderStats]
    public let summary: LLMProxySummary?
    public let global_summary: LLMProxySummary?
    public let data_source: String?
    public let timestamp: Double?
}

/// Stats for a single provider
public struct LLMProxyProviderStats: Decodable, Sendable {
    public let credential_count: Int?
    public let active_count: Int?
    public let on_cooldown_count: Int?
    public let exhausted_count: Int?
    public let total_requests: Int?
    public let tokens: LLMProxyTokens?
    public let approx_cost: Double?
    public let quota_groups: [String: LLMProxyQuotaGroup]?
    public let credentials: [LLMProxyCredential]?
}

/// Quota group (e.g., "claude", "gemini-2.5-flash-low")
public struct LLMProxyQuotaGroup: Decodable, Sendable {
    public let models: [String]?
    public let credentials_total: Int?
    public let credentials_exhausted: Int?
    public let avg_remaining_pct: Int?
    public let total_remaining_pct: Int?
    public let total_requests_used: Int?
    public let total_requests_max: Int?
    public let tiers: [String: LLMProxyTier]?
}

/// Tier info within a quota group
public struct LLMProxyTier: Decodable, Sendable {
    public let total: Int?
    public let active: Int?
    public let priority: Int?
}

/// Token usage stats
public struct LLMProxyTokens: Decodable, Sendable {
    public let input_cached: Int?
    public let input_uncached: Int?
    public let input_cache_pct: Double?
    public let output: Int?
}

/// Individual credential info
public struct LLMProxyCredential: Decodable, Sendable {
    public let credential: String?
    public let status: String?
    public let tier: String?
    public let request_count: Int?
    public let tokens: LLMProxyTokens?
    public let approx_cost: Double?
}

/// Summary stats across all providers
public struct LLMProxySummary: Decodable, Sendable {
    public let total_providers: Int?
    public let total_credentials: Int?
    public let active_credentials: Int?
    public let exhausted_credentials: Int?
    public let total_requests: Int?
    public let tokens: LLMProxyTokens?
    public let approx_total_cost: Double?
}

// MARK: - Usage Snapshot

/// Processed snapshot for CodexBar display
public struct LLMProxyUsageSnapshot: Sendable {
    public let providerStats: LLMProxyProviderStats
    public let providerName: String
    public let quotaGroups: [(name: String, group: LLMProxyQuotaGroup)]
    public let updatedAt: Date

    public init(providerStats: LLMProxyProviderStats, providerName: String, updatedAt: Date) {
        self.providerStats = providerStats
        self.providerName = providerName
        self.updatedAt = updatedAt

        // Sort quota groups: claude first, then others alphabetically
        let groups = providerStats.quota_groups ?? [:]
        self.quotaGroups = groups.sorted { lhs, rhs in
            // Prioritize "claude" first
            if lhs.key.lowercased().contains("claude") && !rhs.key.lowercased().contains("claude") {
                return true
            }
            if !lhs.key.lowercased().contains("claude") && rhs.key.lowercased().contains("claude") {
                return false
            }
            // Then by remaining percentage (lowest remaining first = most used)
            let lhsRemaining = lhs.value.total_remaining_pct ?? lhs.value.avg_remaining_pct ?? 100
            let rhsRemaining = rhs.value.total_remaining_pct ?? rhs.value.avg_remaining_pct ?? 100
            return lhsRemaining < rhsRemaining
        }.map { ($0.key, $0.value) }
    }
}

extension LLMProxyUsageSnapshot {
    /// Convert to UsageSnapshot for CodexBar display
    public func toUsageSnapshot() -> UsageSnapshot {
        let primary: RateWindow
        var secondary: RateWindow?
        var tertiary: RateWindow?

        // Map quota groups to RateWindows
        let groups = self.quotaGroups.prefix(3)
        if groups.count > 0 {
            let (groupName, group) = groups[groups.startIndex]
            primary = Self.rateWindow(for: group, groupName: groupName)
        } else {
            // Fallback if no quota groups
            primary = Self.fallbackRateWindow(from: self.providerStats)
        }

        if groups.count > 1 {
            let idx = groups.index(groups.startIndex, offsetBy: 1)
            let (groupName, group) = groups[idx]
            secondary = Self.rateWindow(for: group, groupName: groupName)
        }

        if groups.count > 2 {
            let idx = groups.index(groups.startIndex, offsetBy: 2)
            let (groupName, group) = groups[idx]
            tertiary = Self.rateWindow(for: group, groupName: groupName)
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .llmProxy,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "\(self.providerName) via proxy")

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private static func rateWindow(for group: LLMProxyQuotaGroup, groupName: String) -> RateWindow {
        let remainingPct = group.total_remaining_pct ?? group.avg_remaining_pct ?? 100
        let usedPercent = max(0, min(100, Double(100 - remainingPct)))

        let resetDescription = Self.formatResetDescription(for: group, groupName: groupName)
        let displayName = Self.formatGroupName(groupName)

        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: resetDescription,
            label: displayName)
    }

    private static func fallbackRateWindow(from stats: LLMProxyProviderStats) -> RateWindow {
        let total = stats.credential_count ?? 1
        let exhausted = stats.exhausted_count ?? 0
        let usedPercent = total > 0 ? Double(exhausted) / Double(total) * 100 : 0

        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "\(stats.active_count ?? 0)/\(total) active")
    }

    private static func formatResetDescription(for group: LLMProxyQuotaGroup, groupName: String) -> String {
        var parts: [String] = []

        // Add request counts if available
        if let used = group.total_requests_used, let max = group.total_requests_max, max > 0 {
            parts.append("\(used)/\(max) requests")
        }

        // Add credential status
        if let total = group.credentials_total, let exhausted = group.credentials_exhausted {
            let active = total - exhausted
            if active < total {
                parts.append("\(active)/\(total) keys")
            }
        }

        return parts.joined(separator: ", ")
    }

    private static func formatGroupName(_ name: String) -> String {
        // Convert "gemini-2.5-flash-low" to "Gemini Flash"
        // Convert "claude" to "Claude"
        let lower = name.lowercased()

        if lower == "claude" || lower.hasPrefix("claude-") {
            return "Claude"
        }
        if lower.contains("gemini") {
            if lower.contains("flash") {
                return "Gemini Flash"
            }
            if lower.contains("pro") {
                return "Gemini Pro"
            }
            return "Gemini"
        }
        if lower.contains("gpt") {
            return "GPT"
        }

        // Default: capitalize first letter
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - Errors

public enum LLMProxyError: LocalizedError, Sendable {
    case missingURL
    case connectionFailed(String)
    case invalidResponse(String)
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            "LLM Proxy URL not configured. Set LLM_PROXY_URL or configure in Preferences."
        case let .connectionFailed(message):
            "Failed to connect to LLM Proxy: \(message)"
        case let .invalidResponse(message):
            "Invalid response from LLM Proxy: \(message)"
        case .authenticationFailed:
            "Authentication failed. Check your API key."
        }
    }
}
