import Foundation

/// What a server answered before any login: enough to fill in the connection settings for the user.
public struct ServerDetection: Equatable, Sendable {
    public enum Authentication: Equatable, Sendable {
        case agent
        case password
        case privateKey(path: String)
        case none
    }

    public var host: String
    public var protocolKind: TransferProtocolKind
    public var port: Int
    public var implicitTLS: Bool?
    /// The SSH banner or the FTP greeting.
    public var serverSoftware: String?
    /// SSH only: methods from "Authentications that can continue".
    public var authenticationMethods: [String]
    /// SSH only: false when the server needs algorithms that SwiftNIO SSH lacks (RSA-only host key, DH key exchange).
    public var nativeSSHSupported: Bool?
    public var suggestedAuthentication: Authentication?
    /// From `~/.ssh/config` when the host is an alias.
    public var username: String?

    public init(
        host: String,
        protocolKind: TransferProtocolKind,
        port: Int,
        implicitTLS: Bool? = nil,
        serverSoftware: String? = nil,
        authenticationMethods: [String] = [],
        nativeSSHSupported: Bool? = nil,
        suggestedAuthentication: Authentication? = nil,
        username: String? = nil
    ) {
        self.host = host
        self.protocolKind = protocolKind
        self.port = port
        self.implicitTLS = implicitTLS
        self.serverSoftware = serverSoftware
        self.authenticationMethods = authenticationMethods
        self.nativeSSHSupported = nativeSSHSupported
        self.suggestedAuthentication = suggestedAuthentication
        self.username = username
    }
}

public protocol ServerProbing: Sendable {
    /// `port` nil checks the usual ports (22, 21, 990). Sends no credential: only greetings and the SSH "none" login.
    func detect(host: String, port: Int?, username: String) async -> ServerDetection?
}

/// Identities that the probe can offer as a login suggestion.
public protocol SSHIdentityInventory: Sendable {
    func agentIdentityCount() async -> Int
}

public struct SystemSSHIdentityInventory: SSHIdentityInventory {
    public init() {}

    public func agentIdentityCount() async -> Int {
        guard let agent = SSHAgentClient() else { return 0 }
        return await (try? agent.listIdentities().count) ?? 0
    }
}

public struct SystemServerProbe: ServerProbing {
    private let processExecutor: SystemProcessExecuting
    private let identities: SSHIdentityInventory
    private let timeout: TimeInterval

    public init(processExecutor: SystemProcessExecuting = FoundationProcessExecutor(), identities: SSHIdentityInventory = SystemSSHIdentityInventory(), timeout: TimeInterval = 4) {
        self.processExecutor = processExecutor
        self.identities = identities
        self.timeout = timeout
    }

    public func detect(host input: String, port: Int?, username: String) async -> ServerDetection? {
        guard ServerProfileValidator.isUsableHost(input), ServerProfileValidator.isUsableUsername(username) else { return nil }
        let config = await self.sshConfig(for: input)
        let host = config?.hostName ?? input
        let user = config?.user ?? username
        let ports = port.map { [$0] } ?? [config?.port ?? 22, 21, 990]

        let found = await withTaskGroup(of: (Int, PortAnswer?).self) { group in
            for candidate in Array(Set(ports)) {
                group.addTask {
                    // Blocking socket reads: keep them off the cooperative thread pool.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            continuation.resume(returning: (candidate, Self.probePort(host: host, port: candidate, timeout: self.timeout)))
                        }
                    }
                }
            }
            var answers: [Int: PortAnswer] = [:]
            for await (candidate, answer) in group {
                answers[candidate] = answer
            }
            return answers
        }
        // Prefer encryption: SFTP, then FTPS, then plain FTP.
        guard let (foundPort, answer) = found.min(by: { $0.value.rank < $1.value.rank }).map({ ($0.key, $0.value) }) else {
            return nil
        }

        var detection: ServerDetection
        switch answer {
        case let .ssh(banner):
            detection = ServerDetection(host: host, protocolKind: .sftp, port: foundPort, serverSoftware: banner)
            let details = await self.sshDetails(host: host, port: foundPort, username: user)
            detection.authenticationMethods = details.methods
            detection.nativeSSHSupported = details.nativeSupported
            detection.suggestedAuthentication = await self.suggestion(methods: details.methods, identityFiles: config?.identityFiles ?? [])
        case let .ftp(greeting, tls):
            detection = ServerDetection(host: host, protocolKind: tls ? .ftps : .ftp, port: foundPort, implicitTLS: tls ? false : nil, serverSoftware: greeting)
            detection.suggestedAuthentication = .password
        case let .implicitTLSFTP(greeting):
            detection = ServerDetection(host: host, protocolKind: .ftps, port: foundPort, implicitTLS: true, serverSoftware: greeting)
            detection.suggestedAuthentication = .password
        }
        if let configUser = config?.user, configUser != username {
            detection.username = configUser
        }
        return detection
    }

    enum PortAnswer: Equatable {
        case ssh(String)
        case ftp(String, explicitTLS: Bool)
        case implicitTLSFTP(String)

        var rank: Int {
            switch self {
            case .ssh: 0
            case .ftp(_, true): 1
            case .implicitTLSFTP: 2
            case .ftp(_, false): 3
            }
        }
    }

    /// SSH and FTP servers speak first. A server that stays silent may expect TLS at once (implicit FTPS).
    static func probePort(host: String, port: Int, timeout: TimeInterval) -> PortAnswer? {
        guard let socket = try? FTPSocketTransport(host: host, port: port, timeout: timeout) else { return nil }
        defer { socket.close() }
        let reader = ProbeLineReader(socket)
        if let first = reader.line() {
            if first.hasPrefix("SSH-") {
                return .ssh(first)
            }
            guard let greeting = reader.reply(startingWith: first), greeting.code == 220 else { return nil }
            let explicitTLS = (try? socket.write(Data("AUTH TLS\r\n".utf8))) != nil && reader.reply()?.code == 234
            return .ftp(greeting.text, explicitTLS: explicitTLS)
        }
        let tls: FTPTransport
        do {
            // The probe sends no secret, so any certificate will do: trust is asked when the user connects.
            tls = try FTPTLS.wrap(socket, host: host, sessionID: UUID().uuidString, trustedFingerprint: nil, acceptAnyCertificate: true)
        } catch {
            return nil
        }
        defer { tls.close() }
        guard let greeting = ProbeLineReader(tls).reply(), greeting.code == 220 else { return nil }
        return .implicitTLSFTP(greeting.text)
    }

    struct SSHConfig: Equatable {
        var hostName: String?
        var user: String?
        var port: Int?
        var identityFiles: [String]
    }

    /// `ssh -G` resolves `~/.ssh/config` without connecting. Only values that differ from the defaults count.
    func sshConfig(for host: String) async -> SSHConfig? {
        guard let result = try? await self.processExecutor.run(executable: "/usr/bin/ssh", arguments: ["-G", host], timeout: 5), result.exitCode == 0 else {
            return nil
        }
        return Self.parseSSHConfig(result.standardOutput, host: host)
    }

    static func parseSSHConfig(_ output: String, host: String, localUser: String = NSUserName()) -> SSHConfig {
        var config = SSHConfig(identityFiles: [])
        var hasProxy = false
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "hostname" where parts[1].lowercased() != host.lowercased():
                config.hostName = parts[1]
            case "user" where parts[1] != localUser:
                config.user = parts[1]
            case "port" where parts[1] != "22":
                config.port = Int(parts[1])
            case "identityfile":
                let path = NSString(string: parts[1]).expandingTildeInPath
                if FileManager.default.fileExists(atPath: path) {
                    config.identityFiles.append(path)
                }
            case "proxyjump", "proxycommand":
                hasProxy = parts[1].lowercased() != "none"
            default:
                break
            }
        }
        // An alias that goes through a jump host only works with its name; keep it so System SSH applies the config.
        if hasProxy {
            config.hostName = nil
        }
        return config
    }

    struct SSHDetails: Equatable {
        var methods: [String] = []
        var nativeSupported: Bool?
    }

    /// One SSH connection that offers the "none" login: the server lists its login methods and algorithms. No secret is sent.
    func sshDetails(host: String, port: Int, username: String) async -> SSHDetails {
        var arguments = [
            "-vv", "-p", String(port),
            "-o", "BatchMode=yes",
            "-o", "PreferredAuthentications=none",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=8",
        ]
        for option in SSHCommandBuilder.legacyCompatibilityOptions {
            arguments.append(contentsOf: ["-o", option])
        }
        // -N: no remote command, even on a server that accepts the "none" login. The timeout ends that session.
        arguments.append(contentsOf: ["-N", "\(username.isEmpty ? NSUserName() : username)@\(host)"])
        guard let result = try? await self.processExecutor.run(executable: "/usr/bin/ssh", arguments: arguments, timeout: 10) else {
            return SSHDetails()
        }
        return Self.parseSSHDebug(result.standardError)
    }

    static func parseSSHDebug(_ output: String) -> SSHDetails {
        var details = SSHDetails()
        var proposals: [String: [String]] = [:]
        var inServerProposal = false
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let range = line.range(of: "Authentications that can continue: ") {
                details.methods = line[range.upperBound...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            if line.contains("peer server KEXINIT proposal") {
                inServerProposal = true
                continue
            }
            guard inServerProposal, line.hasPrefix("debug2: ") else { continue }
            let body = line.dropFirst("debug2: ".count)
            if body.hasPrefix("first_kex_follows") {
                inServerProposal = false
                continue
            }
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = String(body[..<colon])
            proposals[key] = body[body.index(after: colon)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if !proposals.isEmpty {
            details.nativeSupported = Self.nativeSupports(proposals)
        }
        return details
    }

    /// The algorithms SwiftNIO SSH and Driftline's CTR transports implement.
    static func nativeSupports(_ proposals: [String: [String]]) -> Bool {
        let kex: Set = ["curve25519-sha256", "curve25519-sha256@libssh.org", "ecdh-sha2-nistp256", "ecdh-sha2-nistp384", "ecdh-sha2-nistp521"]
        let hostKeys: Set = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"]
        let aead: Set = ["aes128-gcm@openssh.com", "aes256-gcm@openssh.com"]
        let ctr: Set = ["aes128-ctr", "aes256-ctr"]
        let macs: Set = ["hmac-sha2-256", "hmac-sha2-256-etm@openssh.com"]
        func offers(_ key: String, _ names: Set<String>) -> Bool {
            !names.isDisjoint(with: proposals[key] ?? [])
        }
        let cipher = offers("ciphers stoc", aead) || (offers("ciphers stoc", ctr) && offers("MACs stoc", macs))
        return offers("KEX algorithms", kex) && offers("host key algorithms", hostKeys) && cipher
    }

    /// A key when the server takes keys and the Mac has one; a password when the server takes passwords and no key is loaded.
    func suggestion(methods: [String], identityFiles: [String]) async -> ServerDetection.Authentication? {
        let takesKeys = methods.contains("publickey")
        let takesPassword = methods.contains("password") || methods.contains("keyboard-interactive")
        if takesKeys, await self.identities.agentIdentityCount() > 0 {
            return .agent
        }
        if takesPassword {
            return .password
        }
        if takesKeys, let key = identityFiles.first {
            return .privateKey(path: key)
        }
        return methods.isEmpty ? nil : (takesKeys ? .agent : ServerDetection.Authentication.none)
    }
}

/// Reads text lines from a probe connection. The SSH banner is followed by binary key exchange data in the same
/// packet, so only the bytes up to each line break are decoded.
final class ProbeLineReader {
    private let transport: FTPTransport
    private var buffer = Data()

    init(_ transport: FTPTransport) {
        self.transport = transport
    }

    func line() -> String? {
        while true {
            if let newline = self.buffer.firstIndex(of: 0x0a) {
                let bytes = self.buffer[self.buffer.startIndex ..< newline]
                self.buffer.removeSubrange(self.buffer.startIndex ... newline)
                return FTPText.decode(Data(bytes)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard self.buffer.count < 8192 else { return nil }
            var chunk = [UInt8](repeating: 0, count: 1024)
            guard let count = try? chunk.withUnsafeMutableBytes({ try self.transport.read(into: $0) }), count > 0 else { return nil }
            self.buffer.append(contentsOf: chunk[0 ..< count])
        }
    }

    /// An FTP reply, with the continuation lines of "220-..." replies. Text is the first line.
    func reply(startingWith first: String? = nil) -> (code: Int, text: String)? {
        guard let first = first ?? self.line(), first.count >= 3, let code = Int(first.prefix(3)) else { return nil }
        let text = String(first.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        guard first.dropFirst(3).first == "-" else { return (code, text) }
        while let next = self.line() {
            if next.hasPrefix("\(code) ") {
                return (code, text)
            }
        }
        return nil
    }
}
