import CodexBarCore
import Foundation
import Security

protocol LLMProxyTokenStoring: Sendable {
    func loadProxyURL() throws -> String?
    func storeProxyURL(_ url: String?) throws
    func loadAPIKey() throws -> String?
    func storeAPIKey(_ key: String?) throws
}

enum LLMProxyTokenStoreError: LocalizedError {
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .keychainStatus(status):
            "Keychain error: \(status)"
        case .invalidData:
            "Keychain returned invalid data."
        }
    }
}

struct KeychainLLMProxyTokenStore: LLMProxyTokenStoring {
    private static let log = CodexBarLog.logger("llmproxy-token-store")

    private let service = "com.steipete.CodexBar"
    private let urlAccount = "llmproxy-url"
    private let apiKeyAccount = "llmproxy-api-key"

    func loadProxyURL() throws -> String? {
        try loadValue(account: urlAccount)
    }

    func storeProxyURL(_ url: String?) throws {
        try storeValue(url, account: urlAccount)
    }

    func loadAPIKey() throws -> String? {
        try loadValue(account: apiKeyAccount)
    }

    func storeAPIKey(_ key: String?) throws {
        try storeValue(key, account: apiKeyAccount)
    }

    // MARK: - Private

    private func loadValue(account: String) throws -> String? {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            Self.log.error("Keychain read failed for \(account): \(status)")
            throw LLMProxyTokenStoreError.keychainStatus(status)
        }

        guard let data = result as? Data else {
            throw LLMProxyTokenStoreError.invalidData
        }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    private func storeValue(_ value: String?, account: String) throws {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == nil || cleaned?.isEmpty == true {
            try self.deleteValueIfPresent(account: account)
            return
        }

        let data = cleaned!.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            Self.log.error("Keychain update failed for \(account): \(updateStatus)")
            throw LLMProxyTokenStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.log.error("Keychain add failed for \(account): \(addStatus)")
            throw LLMProxyTokenStoreError.keychainStatus(addStatus)
        }
    }

    private func deleteValueIfPresent(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        Self.log.error("Keychain delete failed for \(account): \(status)")
        throw LLMProxyTokenStoreError.keychainStatus(status)
    }
}
