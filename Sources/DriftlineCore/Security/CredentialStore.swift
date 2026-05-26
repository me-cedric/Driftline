import Foundation

public protocol CredentialStore: Sendable {
    func save(secret: Data, reference: CredentialReference) async throws
    func read(reference: CredentialReference) async throws -> Data?
    func delete(reference: CredentialReference) async throws
}

public extension CredentialStore {
    func saveString(_ secret: String, reference: CredentialReference) async throws {
        try await save(secret: Data(secret.utf8), reference: reference)
    }

    func readString(reference: CredentialReference) async throws -> String? {
        guard let data = try await read(reference: reference) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public actor InMemoryCredentialStore: CredentialStore {
    private var secrets: [CredentialReference: Data] = [:]

    public init() {}

    public func save(secret: Data, reference: CredentialReference) async throws {
        secrets[reference] = secret
    }

    public func read(reference: CredentialReference) async throws -> Data? {
        secrets[reference]
    }

    public func delete(reference: CredentialReference) async throws {
        secrets.removeValue(forKey: reference)
    }
}

#if canImport(Security)
import Security

public actor KeychainCredentialStore: CredentialStore {
    public init() {}

    public func save(secret: Data, reference: CredentialReference) async throws {
        var query = baseQuery(reference)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = secret
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func read(reference: CredentialReference) async throws -> Data? {
        var query = baseQuery(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        return result as? Data
    }

    public func delete(reference: CredentialReference) async throws {
        let status = SecItemDelete(baseQuery(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(_ reference: CredentialReference) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]
    }
}

public enum KeychainError: Error, Equatable {
    case unhandledStatus(OSStatus)
}
#endif
