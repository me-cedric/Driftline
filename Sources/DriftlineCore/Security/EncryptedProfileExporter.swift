import Crypto
import Foundation

// HKDF-SHA256 is used for key derivation from the password + salt.
// HKDF is not a password-stretching KDF (no iteration rounds), so it provides
// no brute-force resistance beyond what the password entropy itself offers.
// This is intentional and acceptable for profile export: users control password
// strength, and the alternative (PBKDF2/Argon2) is not available in swift-crypto.
// Callers should document this limitation in the UI.

public enum EncryptedProfileError: Error, Equatable {
    case wrongPassword
    case unsupportedVersion(Int)
    case malformedBundle
}

public enum EncryptedProfileExporter {
    private static let currentVersion = 1
    private static let hkdfInfo = Data("driftline-profile-export-v1".utf8)
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func export(profiles: [ServerProfile], password: String) throws -> Data {
        let salt = self.randomBytes(count: 32)
        let derivedKey = self.deriveKey(password: password, salt: salt)
        let nonce = AES.GCM.Nonce()
        let payload = ProfileBundlePayload(profiles: profiles)
        let plaintext = try encoder.encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: derivedKey, nonce: nonce)
        let nonceData = Data(nonce)
        let ciphertext = sealed.ciphertext + sealed.tag
        let bundle = EncryptedProfileBundle(
            version: currentVersion,
            salt: salt,
            nonce: nonceData,
            ciphertext: ciphertext,
            profileCount: profiles.count,
            exportedAt: Date()
        )
        return try self.encoder.encode(bundle)
    }

    public static func `import`(data: Data, password: String) throws -> [ServerProfile] {
        let bundle: EncryptedProfileBundle
        do {
            bundle = try self.decoder.decode(EncryptedProfileBundle.self, from: data)
        } catch {
            throw EncryptedProfileError.malformedBundle
        }

        guard bundle.version == self.currentVersion else {
            throw EncryptedProfileError.unsupportedVersion(bundle.version)
        }

        let derivedKey = self.deriveKey(password: password, salt: bundle.salt)

        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: bundle.nonce)
        } catch {
            throw EncryptedProfileError.malformedBundle
        }

        guard bundle.ciphertext.count > 16 else {
            throw EncryptedProfileError.malformedBundle
        }

        let tagOffset = bundle.ciphertext.count - 16
        let ciphertextBody = bundle.ciphertext[bundle.ciphertext.startIndex ..< bundle.ciphertext.index(bundle.ciphertext.startIndex, offsetBy: tagOffset)]
        let tag = bundle.ciphertext[bundle.ciphertext.index(bundle.ciphertext.startIndex, offsetBy: tagOffset)...]

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextBody, tag: tag)
        } catch {
            throw EncryptedProfileError.malformedBundle
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: derivedKey)
        } catch {
            throw EncryptedProfileError.wrongPassword
        }

        do {
            let payload = try decoder.decode(ProfileBundlePayload.self, from: plaintext)
            return payload.profiles
        } catch {
            throw EncryptedProfileError.malformedBundle
        }
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: self.hkdfInfo,
            outputByteCount: 32
        )
    }

    private static func randomBytes(count: Int) -> Data {
        #if canImport(Security)
            return randomBytesViaSecurity(count: count)
        #else
            return SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.prefix(count)
        #endif
    }
}

#if canImport(Security)
    import Security

    private func randomBytesViaSecurity(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return bytes
    }
#endif
