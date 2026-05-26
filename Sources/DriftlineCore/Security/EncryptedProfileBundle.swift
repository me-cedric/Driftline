import Foundation

public struct EncryptedProfileBundle: Codable, Sendable {
    public var version: Int
    public var salt: Data
    public var nonce: Data
    public var ciphertext: Data
    public var profileCount: Int
    public var exportedAt: Date

    public init(version: Int, salt: Data, nonce: Data, ciphertext: Data, profileCount: Int, exportedAt: Date) {
        self.version = version
        self.salt = salt
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.profileCount = profileCount
        self.exportedAt = exportedAt
    }
}

public struct ProfileBundlePayload: Codable, Sendable {
    public var profiles: [ServerProfile]

    public init(profiles: [ServerProfile]) {
        self.profiles = profiles
    }
}
