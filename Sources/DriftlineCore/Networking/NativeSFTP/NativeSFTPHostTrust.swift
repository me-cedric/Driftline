import CryptoKit
import Foundation
import NIOCore
@preconcurrency import NIOSSH

public enum NativeSFTPHostKeyFingerprint {
    public static func fingerprint(for hostKey: NIOSSHPublicKey) throws -> HostFingerprint {
        let openSSH = String(openSSHPublicKey: hostKey)
        let fields = openSSH.split(separator: " ", maxSplits: 1).map(String.init)
        guard fields.count == 2, let keyData = Data(base64Encoded: fields[1]) else {
            throw RemoteClientError.connectionFailed("Could not read SSH host key.")
        }

        let digest = SHA256.hash(data: keyData)
        let fingerprint = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return HostFingerprint(
            host: "",
            port: 0,
            algorithm: self.displayAlgorithm(forOpenSSHKeyType: fields[0]),
            fingerprint: "SHA256:\(fingerprint)"
        )
    }

    public static func knownHostsLine(host: String, port: Int, hostKey: NIOSSHPublicKey) -> String {
        let hostPrefix = port == 22 ? host : "[\(host)]:\(port)"
        return "\(hostPrefix) \(String(openSSHPublicKey: hostKey))"
    }

    private static func displayAlgorithm(forOpenSSHKeyType keyType: String) -> String {
        if keyType == "ssh-ed25519" {
            return "ED25519"
        }
        if keyType.hasPrefix("ecdsa-sha2-") {
            return "ECDSA"
        }
        if keyType.hasPrefix("rsa-") || keyType == "ssh-rsa" {
            return "RSA"
        }
        return keyType.uppercased()
    }
}

final class NativeSFTPHostTrustDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let hostTrustStore: HostTrustStore

    init(host: String, port: Int, hostTrustStore: HostTrustStore) {
        self.host = host
        self.port = port
        self.hostTrustStore = hostTrustStore
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let host = host
        let port = port
        let store = self.hostTrustStore
        Task {
            do {
                var fingerprint = try NativeSFTPHostKeyFingerprint.fingerprint(for: hostKey)
                fingerprint.host = host
                fingerprint.port = port
                fingerprint.knownHostsLine = NativeSFTPHostKeyFingerprint.knownHostsLine(host: host, port: port, hostKey: hostKey)

                switch try await store.verificationResult(
                    host: host,
                    port: port,
                    algorithm: fingerprint.algorithm,
                    fingerprint: fingerprint.fingerprint
                ) {
                case .trusted:
                    validationCompletePromise.succeed(())
                case .unknown:
                    validationCompletePromise.fail(
                        RemoteClientError.hostNotTrusted(
                            host: host,
                            port: port,
                            algorithm: fingerprint.algorithm,
                            fingerprint: fingerprint.fingerprint,
                            knownHostsLine: fingerprint.knownHostsLine
                        )
                    )
                case .changed:
                    validationCompletePromise.fail(RemoteClientError.hostFingerprintChanged)
                }
            } catch {
                validationCompletePromise.fail(error)
            }
        }
    }
}

extension NativeSFTPHostTrustDelegate: @unchecked Sendable {}
