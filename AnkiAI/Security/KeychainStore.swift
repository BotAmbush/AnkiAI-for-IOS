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

/// Where the local collection came from. Gates destructive AnkiWeb upload: a
/// seeded/unknown collection must NEVER be allowed to replace the user's remote
/// AnkiWeb data (P0 data-loss guard).
public enum CollectionProvenance: String {
    case seededSample
    case downloadedFromAnkiWeb
    case importedFromPackage
    case createdLocally
    case restoredFromBackup
    case unknown
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

    /// True ONLY when a real persisted AnkiWeb session key exists. The seeded/demo
    /// collection has none, so it is never presented as an authenticated account.
    public var isAnkiWebLoggedIn: Bool { (ankiWebHKey?.isEmpty == false) }

    /// Log out of AnkiWeb: invalidate/remove the session key + username and the last
    /// background-sync state. Does NOT touch the local collection.
    public func logOutAnkiWeb() {
        ankiWebHKey = nil
        ankiWebUsername = nil
        lastBackgroundSyncResult = nil
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

    /// Default output language for the AI reviewer + creator (Issue 2).
    public var aiLanguage: AILanguage {
        get { AILanguage(rawValue: defaults.string(forKey: "ai_language") ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: "ai_language") }
    }

    /// Provenance of the local collection. Defaults to `.unknown` (the safe value:
    /// upload to AnkiWeb is hard-blocked until provenance is proven).
    public var collectionProvenance: CollectionProvenance {
        get { CollectionProvenance(rawValue: defaults.string(forKey: "collection_provenance") ?? "") ?? .unknown }
        set { defaults.set(newValue.rawValue, forKey: "collection_provenance") }
    }

    /// True when the local collection must NEVER replace remote AnkiWeb data
    /// (seeded sample or unknown provenance). Upload is forbidden in these cases.
    public var isUploadForbidden: Bool {
        switch collectionProvenance {
        case .seededSample, .unknown: return true
        case .downloadedFromAnkiWeb, .importedFromPackage, .createdLocally, .restoredFromBackup: return false
        }
    }

    /// Last background-sync outcome (empty = success), surfaced on next launch so
    /// background failures are never silently discarded.
    public var lastBackgroundSyncResult: String? {
        get { defaults.string(forKey: "bg_sync_last_result") }
        set { defaults.set(newValue, forKey: "bg_sync_last_result") }
    }
    public var lastBackgroundSyncDate: Date? {
        get { let t = defaults.double(forKey: "bg_sync_last_date"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "bg_sync_last_date") }
    }
}
