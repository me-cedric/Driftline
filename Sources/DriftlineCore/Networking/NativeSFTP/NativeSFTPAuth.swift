import Foundation
import NIOCore
import NIOSSH

public enum NativeSFTPAuthFactory {
    public static func passwordDelegate(username: String, password: String) -> NIOSSHClientUserAuthenticationDelegate {
        SimplePasswordDelegate(username: username, password: password)
    }

    public static func offerSequence(username: String, methods: [NativeSFTPAuthMethod]) -> NIOSSHClientUserAuthenticationDelegate {
        NativeSFTPAuthDelegate(username: username, methods: methods)
    }
}

public enum NativeSFTPAuthMethod: Sendable {
    case password(String)
    case privateKey(NIOSSHPrivateKey)
    case none
}

final class NativeSFTPAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var methods: [NativeSFTPAuthMethod]

    init(username: String, methods: [NativeSFTPAuthMethod]) {
        self.username = username
        self.methods = methods
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        while !self.methods.isEmpty {
            let method = self.methods.removeFirst()
            switch method {
            case let .password(password) where availableMethods.contains(.password):
                nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: self.username, serviceName: "", offer: .password(.init(password: password))))
                return
            case let .privateKey(key) where availableMethods.contains(.publicKey):
                nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: self.username, serviceName: "", offer: .privateKey(.init(privateKey: key))))
                return
            case .none:
                nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: self.username, serviceName: "", offer: .none))
                return
            case .password, .privateKey:
                continue
            }
        }
        nextChallengePromise.succeed(nil)
    }
}

@available(*, unavailable)
extension NativeSFTPAuthDelegate: Sendable {}
