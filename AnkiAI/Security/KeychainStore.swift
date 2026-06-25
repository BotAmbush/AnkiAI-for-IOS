import Foundation
import Security

/// Abstraction over secret storage so view models / settings can be tested
/// without a Keychain entitlement (the host-less unit-test bundle cannot use the
/// Keychain reliably). Production uses `KeychainStore`; tests use `InMemorySecretStore`.
public protocol SecretStore {
    func set(_ value: String, for key: String)
    func get(_ key: String) -> String?
    func remove(_ key: String)
}

/// In-memory secret store for tests.
public final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]
    public init() {}
    public func set(_ value: String, for key: String) { storage[key] = value }
    public func get(_ key: String) -> String? { storage[key] }
    public func remove(_ key: String) { storage[key] = nil }
}

/// Keychain-backed secret storage. Per the iOS migration requirements, the Claude
/// API key lives in the Keychain (the Android fork used SharedPreferences; iOS
/// upgrades this to the platform secure store).
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = "com.evyatar.ankiai.secrets") { self.service = service }

    public func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    public func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Centralized access to AI credentials and budget settings.
/// Mirrors the `AnkiDroidAI` SharedPreferences keys from `AiChatViewModel`.
public final class AISettingsStore {
    public static let keyClaudeAPIKey = "claude_api_key"
    public static let keyAnkiWebHKey = "ankiweb_hkey"

    private let keychain: SecretStore
    private let defaults: UserDefaults

    public init(keychain: SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }

    public var apiKey: String? {
        get { keychain.get(Self.keyClaudeAPIKey) }
        set {
            if let v = newValue, !v.trimmingCharacters(in: .whitespaces).isEmpty {
                keychain.set(v.trimmingCharacters(in: .whitespaces), for: Self.keyClaudeAPIKey)
            } else {
                keychain.remove(Self.keyClaudeAPIKey)
            }
        }
    }

    public var hasAPIKey: Bool { apiKey != nil }

    /// AnkiWeb session host key (Keychain) + username (UserDefaults).
    public var ankiWebHKey: String? {
        get { keychain.get(Self.keyAnkiWebHKey) }
        set {
            if let v = newValue, !v.isEmpty { keychain.set(v, for: Self.keyAnkiWebHKey) }
            else { keychain.remove(Self.keyAnkiWebHKey) }
        }
    }
    public var ankiWebUsername: String? {
        get { defaults.string(forKey: "ankiweb_username") }
        set { defaults.set(newValue, forKey: "ankiweb_username") }
    }

    public var budgetLimitUSD: Double {
        get {
            let v = defaults.double(forKey: "ai_budget_limit_usd")
            return v == 0 ? AIPricing.defaultBudgetUSD : v
        }
        set { defaults.set(newValue, forKey: "ai_budget_limit_usd") }
    }

    public var totalSpentUSD: Double {
        get { defaults.double(forKey: "ai_total_spent_usd") }
        set { defaults.set(newValue, forKey: "ai_total_spent_usd") }
    }
}
