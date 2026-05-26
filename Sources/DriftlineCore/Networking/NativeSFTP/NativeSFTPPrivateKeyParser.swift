import Crypto
import Foundation
import NIOSSH

public enum NativeSFTPPrivateKeyParser {
    public static func parse(contents: String) throws -> NIOSSHPrivateKey {
        if contents.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHEd25519(contents: contents)
        }
        if contents.contains("BEGIN PRIVATE KEY") || contents.contains("BEGIN EC PRIVATE KEY") {
            return try parsePEM(contents: contents)
        }
        throw RemoteClientError.unsupportedAuthentication("Unsupported private key format. Use an unencrypted OpenSSH Ed25519 key or an ECDSA PEM key.")
    }

    private static func parsePEM(contents: String) throws -> NIOSSHPrivateKey {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: contents) {
            return NIOSSHPrivateKey(p256Key: key)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: contents) {
            return NIOSSHPrivateKey(p384Key: key)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: contents) {
            return NIOSSHPrivateKey(p521Key: key)
        }
        throw RemoteClientError.unsupportedAuthentication("Unsupported PEM private key. Driftline currently supports ECDSA P-256/P-384/P-521 PEM keys.")
    }

    private static func parseOpenSSHEd25519(contents: String) throws -> NIOSSHPrivateKey {
        let base64 = contents
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: base64) else {
            throw RemoteClientError.unsupportedAuthentication("Could not decode OpenSSH private key.")
        }

        var reader = SFTPDataReader(data: data)
        let magic = try reader.readData(count: 15)
        guard String(data: magic, encoding: .utf8) == "openssh-key-v1\0" else {
            throw RemoteClientError.unsupportedAuthentication("Unsupported OpenSSH private key container.")
        }

        let cipherName = try reader.readString()
        let kdfName = try reader.readString()
        _ = try reader.readBinaryString()
        guard cipherName == "none", kdfName == "none" else {
            throw RemoteClientError.unsupportedAuthentication("Encrypted OpenSSH private keys are not supported by the native backend yet. Use System SSH for passphrase-protected keys.")
        }

        let keyCount = try reader.readUInt32()
        guard keyCount == 1 else {
            throw RemoteClientError.unsupportedAuthentication("OpenSSH keys with multiple identities are not supported.")
        }
        _ = try reader.readBinaryString()

        var privateReader = SFTPDataReader(data: try reader.readBinaryString())
        let check1 = try privateReader.readUInt32()
        let check2 = try privateReader.readUInt32()
        guard check1 == check2 else {
            throw RemoteClientError.unsupportedAuthentication("OpenSSH private key integrity check failed.")
        }

        let keyType = try privateReader.readString()
        guard keyType == "ssh-ed25519" else {
            throw RemoteClientError.unsupportedAuthentication("Only OpenSSH Ed25519 private keys are supported by the native backend right now.")
        }

        let publicKey = try privateReader.readBinaryString()
        let privateKey = try privateReader.readBinaryString()
        guard publicKey.count == 32, privateKey.count >= 32 else {
            throw RemoteClientError.unsupportedAuthentication("Invalid Ed25519 private key payload.")
        }

        return try NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey(rawRepresentation: privateKey.prefix(32)))
    }
}
