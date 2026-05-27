import Crypto
import Foundation

#if canImport(CommonCrypto)
    import CommonCrypto
#endif

enum OpenSSHKeyDecryptor {
    static func decrypt(
        encryptedPrivateBlob: Data,
        cipher: String,
        kdfName: String,
        kdfOptions: Data,
        passphrase: String
    ) throws -> Data {
        guard kdfName == "bcrypt" else {
            throw RemoteClientError.unsupportedAuthentication("Unsupported KDF '\(kdfName)' for encrypted OpenSSH private key.")
        }

        let (salt, rounds) = try parseBcryptOptions(kdfOptions)
        let passphraseData = Data(passphrase.utf8)

        switch cipher {
        case "aes256-ctr":
            return try self.decryptAES256CTR(blob: encryptedPrivateBlob, passphrase: passphraseData, salt: salt, rounds: rounds)
        case "aes256-gcm@openssh.com":
            return try self.decryptAES256GCM(blob: encryptedPrivateBlob, passphrase: passphraseData, salt: salt, rounds: rounds)
        case "chacha20-poly1305@openssh.com":
            return try self.decryptChaCha20Poly1305(blob: encryptedPrivateBlob, passphrase: passphraseData, salt: salt, rounds: rounds)
        default:
            throw RemoteClientError.unsupportedAuthentication("Unsupported cipher '\(cipher)' for encrypted OpenSSH private key.")
        }
    }

    private static func parseBcryptOptions(_ options: Data) throws -> (salt: Data, rounds: UInt32) {
        var reader = SFTPDataReader(data: options)
        let salt = try reader.readBinaryString()
        let rounds = try reader.readUInt32()
        return (salt, rounds)
    }

    private static func decryptAES256CTR(blob: Data, passphrase: Data, salt: Data, rounds: UInt32) throws -> Data {
        let keyIV = try BcryptPBKDF.derive(password: passphrase, salt: salt, outputLength: 48, rounds: rounds)
        let key = keyIV.prefix(32)
        let iv = keyIV.dropFirst(32).prefix(16)

        #if canImport(CommonCrypto)
            return try commonCryptoAES256CTR(blob: blob, key: Data(key), iv: Data(iv))
        #else
            throw RemoteClientError.unsupportedAuthentication("AES-256-CTR decryption is not available on this platform.")
        #endif
    }

    private static func decryptAES256GCM(blob: Data, passphrase: Data, salt: Data, rounds: UInt32) throws -> Data {
        guard blob.count >= 16 else {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }
        let keyIV = try BcryptPBKDF.derive(password: passphrase, salt: salt, outputLength: 44, rounds: rounds)
        let key = keyIV.prefix(32)
        let iv = keyIV.dropFirst(32).prefix(12)

        let ciphertext = blob.dropLast(16)
        let tag = blob.suffix(16)

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: iv),
                ciphertext: ciphertext,
                tag: tag
            )
            let symKey = SymmetricKey(data: key)
            return try AES.GCM.open(sealedBox, using: symKey)
        } catch {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }
    }

    private static func decryptChaCha20Poly1305(blob: Data, passphrase: Data, salt: Data, rounds: UInt32) throws -> Data {
        guard blob.count >= 16 else {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }
        let keyIV = try BcryptPBKDF.derive(password: passphrase, salt: salt, outputLength: 44, rounds: rounds)
        let key = keyIV.prefix(32)
        let iv = keyIV.dropFirst(32).prefix(12)

        let ciphertext = blob.dropLast(16)
        let tag = blob.suffix(16)

        do {
            let sealedBox = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: iv),
                ciphertext: ciphertext,
                tag: tag
            )
            let symKey = SymmetricKey(data: key)
            return try ChaChaPoly.open(sealedBox, using: symKey)
        } catch {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }
    }
}

#if canImport(CommonCrypto)
    private func commonCryptoAES256CTR(blob: Data, key: Data, iv: Data) throws -> Data {
        var cryptorRef: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    32,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptorRef
                )
            }
        }

        guard status == kCCSuccess, let cryptor = cryptorRef else {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: blob.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var moved = 0

        let updateStatus: CCCryptorStatus = blob.withUnsafeBytes { blobBytes in
            output.withUnsafeMutableBytes { outBytes in
                CCCryptorUpdate(
                    cryptor,
                    blobBytes.baseAddress,
                    blob.count,
                    outBytes.baseAddress,
                    outputCapacity,
                    &moved
                )
            }
        }
        guard updateStatus == kCCSuccess else {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }

        var finalMoved = 0
        let remaining = outputCapacity - moved
        let finalStatus: CCCryptorStatus = output.withUnsafeMutableBytes { outBytes in
            guard let base = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return CCCryptorFinal(
                cryptor,
                base.advanced(by: moved),
                remaining,
                &finalMoved
            )
        }
        guard finalStatus == kCCSuccess else {
            throw RemoteClientError.unsupportedAuthentication("Passphrase is incorrect or key is corrupt")
        }

        return output.prefix(moved + finalMoved)
    }
#endif
