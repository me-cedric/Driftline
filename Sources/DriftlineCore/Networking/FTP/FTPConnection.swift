import CryptoKit
import Foundation
import Security

/// A byte stream for the control or the data connection, plain or TLS.
protocol FTPTransport: AnyObject {
    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int
    func write(_ data: Data) throws
    func close()
}

/// A TLS certificate that macOS does not trust and that does not match the certificate the user trusted.
struct FTPUntrustedCertificate: Error {
    var fingerprint: String
}

final class FTPSocketTransport: FTPTransport {
    let descriptor: Int32
    private var closed = false

    /// Opens TCP to the first address that answers. Both directions time out, so a silent server cannot hang a transfer.
    init(host: String, port: Int, timeout: TimeInterval = 30) throws {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &results)
        guard status == 0, let first = results else {
            throw RemoteClientError.connectionFailed("Could not resolve \(host): \(String(cString: gai_strerror(status))).")
        }
        defer { freeaddrinfo(results) }

        var lastError = ECONNREFUSED
        var candidate: UnsafeMutablePointer<addrinfo>? = first
        while let address = candidate {
            candidate = address.pointee.ai_next
            let descriptor = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
            guard descriptor >= 0 else { continue }
            if Self.connect(descriptor, address.pointee.ai_addr, address.pointee.ai_addrlen, timeout: min(timeout, 15)) {
                var noSigPipe: Int32 = 1
                setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                var interval = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
                self.descriptor = descriptor
                return
            }
            lastError = errno
            Darwin.close(descriptor)
        }
        throw RemoteClientError.connectionFailed("Could not connect to \(host) port \(port): \(String(cString: strerror(lastError))).")
    }

    deinit {
        self.close()
    }

    private static func connect(_ descriptor: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ length: socklen_t, timeout: TimeInterval) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(descriptor, F_SETFL, flags) }
        if Darwin.connect(descriptor, address, length) == 0 {
            return true
        }
        guard errno == EINPROGRESS else { return false }
        var poller = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&poller, 1, Int32(timeout * 1000)) == 1 else {
            errno = ETIMEDOUT
            return false
        }
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size)
        errno = error
        return error == 0
    }

    /// The address the socket connected to, used for passive data connections.
    var peerAddress: String? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(self.descriptor, $0, &length) }
        }
        guard result == 0 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return status == 0 ? String(cString: host) : nil
    }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let count = Darwin.read(self.descriptor, buffer.baseAddress, buffer.count)
        guard count >= 0 else {
            throw RemoteClientError.connectionFailed(errno == EAGAIN ? "The server stopped answering." : String(cString: strerror(errno)))
        }
        return count
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(self.descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                guard written > 0 else { throw RemoteClientError.connectionFailed(String(cString: strerror(errno))) }
                offset += written
            }
        }
    }

    func close() {
        guard !self.closed else { return }
        self.closed = true
        Darwin.close(self.descriptor)
    }
}

/// Opens TLS on a connected socket. FTP servers such as vsftpd, ProFTPD and FileZilla Server refuse a data connection
/// that does not resume the TLS session of the control connection, and Network.framework cannot start TLS on an open
/// connection (AUTH TLS) or share a session between two ports. SecureTransport does both through `SSLSetPeerID`.
protocol FTPTLSFactory {
    static func makeTransport(socket: FTPSocketTransport, host: String, sessionID: String, trustedFingerprint: String?) throws -> FTPTransport
}

enum FTPTLS {
    // shortcut: SecureTransport is deprecated and stops at TLS 1.2; move to Network.framework when it can resume one session across ports.
    private static let factory: FTPTLSFactory.Type = SecureTransportFTPTransport.self

    static func wrap(_ socket: FTPSocketTransport, host: String, sessionID: String, trustedFingerprint: String?) throws -> FTPTransport {
        try self.factory.makeTransport(socket: socket, host: host, sessionID: sessionID, trustedFingerprint: trustedFingerprint)
    }

    /// SHA-256 of the certificate, written like FileZilla and browsers show it.
    static func fingerprint(of certificate: SecCertificate) -> String {
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        return "SHA256:" + digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

final class SecureTransportFTPTransport: FTPTransport {
    private let socket: FTPSocketTransport
    private let context: SSLContext
    private let connection: UnsafeMutablePointer<Int32>

    @available(macOS, deprecated: 10.15)
    private init(socket: FTPSocketTransport, host: String, sessionID: String, trustedFingerprint: String?) throws {
        guard let context = SSLCreateContext(nil, .clientSide, .streamType) else {
            throw RemoteClientError.connectionFailed("Could not start TLS.")
        }
        self.socket = socket
        self.context = context
        self.connection = .allocate(capacity: 1)
        self.connection.pointee = socket.descriptor
        SSLSetIOFuncs(context, Self.readCallback, Self.writeCallback)
        SSLSetConnection(context, self.connection)
        SSLSetProtocolVersionMin(context, .tlsProtocol12)
        SSLSetSessionOption(context, .breakOnServerAuth, true)
        _ = host.withCString { SSLSetPeerDomainName(context, $0, strlen($0)) }
        _ = sessionID.withCString { SSLSetPeerID(context, $0, strlen($0)) }

        var status = SSLHandshake(context)
        if status == errSSLPeerAuthCompleted {
            try Self.verify(context: context, host: host, trustedFingerprint: trustedFingerprint)
            status = SSLHandshake(context)
        }
        guard status == noErr else {
            throw RemoteClientError.connectionFailed("The TLS handshake failed (\(status)).")
        }
    }

    deinit {
        self.connection.deallocate()
    }

    @available(macOS, deprecated: 10.15)
    private static func verify(context: SSLContext, host: String, trustedFingerprint: String?) throws {
        var trust: SecTrust?
        SSLCopyPeerTrust(context, &trust)
        guard let trust else { throw RemoteClientError.connectionFailed("The server sent no certificate.") }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        if SecTrustEvaluateWithError(trust, nil) {
            return
        }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            throw RemoteClientError.connectionFailed("The server sent no certificate.")
        }
        let fingerprint = FTPTLS.fingerprint(of: leaf)
        guard fingerprint == trustedFingerprint else { throw FTPUntrustedCertificate(fingerprint: fingerprint) }
    }

    private static let readCallback: SSLReadFunc = { connection, data, length in
        let descriptor = connection.load(as: Int32.self)
        let requested = length.pointee
        var total = 0
        while total < requested {
            let count = Darwin.read(descriptor, data + total, requested - total)
            if count > 0 {
                total += count
                continue
            }
            length.pointee = total
            if count == 0 { return errSSLClosedGraceful }
            return errno == EAGAIN ? errSSLWouldBlock : errSecIO
        }
        length.pointee = total
        return noErr
    }

    private static let writeCallback: SSLWriteFunc = { connection, data, length in
        let descriptor = connection.load(as: Int32.self)
        let requested = length.pointee
        var total = 0
        while total < requested {
            let count = Darwin.write(descriptor, data + total, requested - total)
            guard count > 0 else {
                length.pointee = total
                return errSecIO
            }
            total += count
        }
        return noErr
    }

    @available(macOS, deprecated: 10.15)
    private func readDeprecated(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        var processed = 0
        let status = SSLRead(self.context, buffer.baseAddress!, buffer.count, &processed)
        if status == noErr || (status == errSSLWouldBlock && processed > 0) {
            return processed
        }
        switch status {
        case errSSLClosedGraceful, errSSLClosedNoNotify:
            return processed
        case errSSLWouldBlock:
            throw RemoteClientError.connectionFailed("The server stopped answering.")
        default:
            throw RemoteClientError.connectionFailed("TLS read failed (\(status)).")
        }
    }

    @available(macOS, deprecated: 10.15)
    private func writeDeprecated(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                var processed = 0
                let status = SSLWrite(self.context, bytes.baseAddress! + offset, bytes.count - offset, &processed)
                guard status == noErr else { throw RemoteClientError.connectionFailed("TLS write failed (\(status)).") }
                offset += processed
            }
        }
    }

    @available(macOS, deprecated: 10.15)
    private func closeDeprecated() {
        SSLClose(self.context)
        self.socket.close()
    }
}

/// The protocol requirements are not deprecated, so callers compile without warnings; the deprecated calls stay in this type.
extension SecureTransportFTPTransport: FTPTLSFactory {
    @available(macOS, deprecated: 10.15)
    static func makeTransport(socket: FTPSocketTransport, host: String, sessionID: String, trustedFingerprint: String?) throws -> FTPTransport {
        try SecureTransportFTPTransport(socket: socket, host: host, sessionID: sessionID, trustedFingerprint: trustedFingerprint)
    }

    @available(macOS, deprecated: 10.15)
    func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try self.readDeprecated(into: buffer)
    }

    @available(macOS, deprecated: 10.15)
    func write(_ data: Data) throws {
        try self.writeDeprecated(data)
    }

    @available(macOS, deprecated: 10.15)
    func close() {
        self.closeDeprecated()
    }
}

/// One logged-in FTP control connection. Blocking: call it from a background thread.
final class FTPConnection {
    private let profile: ServerProfile
    private let mode: FTPSecurityMode
    private let socket: FTPSocketTransport
    private var control: FTPTransport
    private let trustedFingerprint: String?
    private var buffer = Data()
    private let sessionID = UUID().uuidString

    init(profile: ServerProfile, password: String?, trustedFingerprint: String?) throws {
        self.profile = profile
        self.mode = FTPSecurityMode(profile: profile)
        self.trustedFingerprint = trustedFingerprint
        self.socket = try FTPSocketTransport(host: profile.host, port: profile.port)
        self.control = self.socket
        do {
            try self.open(password: password)
        } catch {
            self.control.close()
            throw error
        }
    }

    deinit {
        self.control.close()
    }

    private func open(password: String?) throws {
        if self.mode == .implicitTLS {
            self.control = try FTPTLS.wrap(self.socket, host: self.profile.host, sessionID: self.sessionID, trustedFingerprint: self.trustedFingerprint)
        }
        try self.expect(self.readReply(), 220)
        if self.mode == .explicitTLS {
            let reply = try self.send("AUTH TLS")
            guard reply.code == 234 else {
                throw RemoteClientError.connectionFailed("The server does not offer FTPS (AUTH TLS). Choose FTP only if you accept an unencrypted connection. (\(reply.code) \(reply.text))")
            }
            self.control = try FTPTLS.wrap(self.socket, host: self.profile.host, sessionID: self.sessionID, trustedFingerprint: self.trustedFingerprint)
        }

        let username = self.profile.username.isEmpty ? "anonymous" : self.profile.username
        var reply = try self.send("USER \(username)")
        if reply.code == 331 {
            reply = try self.send("PASS \(password ?? "anonymous@")")
        }
        guard reply.code == 230 || reply.code == 202 else { throw FTPCommandBuilder.error(for: reply) }

        if self.mode != .none {
            _ = try self.send("PBSZ 0")
            try self.expect(self.send("PROT P"), 200)
        }
        try self.expect(self.send("TYPE I"), 200)
        // IIS and some appliances send names in the local code page until UTF-8 is asked for.
        _ = try? self.send("OPTS UTF8 ON")
    }

    func quit() {
        _ = try? self.send("QUIT")
        self.control.close()
    }

    @discardableResult
    func send(_ command: String) throws -> FTPReply {
        guard !command.contains(where: \.isNewline) else {
            throw RemoteClientError.commandFailed("File names with line breaks are not supported.")
        }
        try self.control.write(Data((command + "\r\n").utf8))
        return try self.readReply()
    }

    @discardableResult
    func expect(_ reply: FTPReply, _ codes: Int...) throws -> FTPReply {
        guard codes.contains(reply.code) else { throw FTPCommandBuilder.error(for: reply) }
        return reply
    }

    /// Reads a reply, including the "123-" continuation lines of a multi-line reply.
    func readReply() throws -> FTPReply {
        var lines: [String] = []
        while true {
            let line = try self.readLine()
            lines.append(line)
            let characters = Array(line)
            if lines.count == 1, characters.count >= 3, Int(String(characters[0 ..< 3])) != nil, characters.count == 3 || characters[3] == " " {
                return FTPReply(code: Int(String(characters[0 ..< 3]))!, text: String(line.dropFirst(min(4, line.count))))
            }
            if lines.count > 1, let first = lines.first, line.hasPrefix(String(first.prefix(3)) + " ") {
                return FTPReply(code: Int(first.prefix(3)) ?? 0, text: lines.map { String($0.dropFirst(4)) }.joined(separator: "\n"))
            }
        }
    }

    private func readLine() throws -> String {
        while true {
            if let newline = self.buffer.firstIndex(of: 0x0a) {
                let line = self.buffer[self.buffer.startIndex ..< newline]
                self.buffer.removeSubrange(self.buffer.startIndex ... newline)
                return FTPText.decode(Data(line)).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = try chunk.withUnsafeMutableBytes { try self.control.read(into: $0) }
            guard count > 0 else { throw RemoteClientError.connectionFailed("The server closed the connection.") }
            self.buffer.append(contentsOf: chunk[0 ..< count])
        }
    }

    func changeDirectory(_ path: String) throws {
        let target = try FTPCommandBuilder.commandPath(path)
        guard target != "." else { return }
        try self.expect(self.send("CWD \(target)"), 250, 200)
    }

    /// Opens a passive data connection: EPSV first (IPv6 and NAT friendly), then PASV.
    private func openDataConnection() throws -> FTPSocketTransport {
        let host = self.socket.peerAddress ?? self.profile.host
        var port = try FTPCommandBuilder.extendedPassivePort(from: self.send("EPSV"))
        if port == nil {
            port = try FTPCommandBuilder.passivePort(from: self.send("PASV"))
        }
        guard let port else { throw RemoteClientError.connectionFailed("The server did not open a passive data port.") }
        return try FTPSocketTransport(host: host, port: port, timeout: 60)
    }

    /// Runs a data command (LIST, RETR, STOR). `body` reads or writes the data stream.
    func transfer(_ command: String, body: (FTPTransport) throws -> Void) throws {
        let socket = try self.openDataConnection()
        let preliminary = try self.send(command)
        guard preliminary.code == 150 || preliminary.code == 125 else {
            socket.close()
            throw FTPCommandBuilder.error(for: preliminary)
        }
        let data: FTPTransport = self.mode == .none
            ? socket
            : try FTPTLS.wrap(socket, host: self.profile.host, sessionID: self.sessionID, trustedFingerprint: self.trustedFingerprint)
        do {
            try body(data)
            data.close()
        } catch {
            data.close()
            throw error
        }
        try self.expect(self.readReply(), 226, 250)
    }

    func list(_ path: String, showHidden: Bool) throws -> String {
        try self.changeDirectory(path)
        var output = Data()
        let read: (FTPTransport) throws -> Void = { data in
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = try chunk.withUnsafeMutableBytes { try data.read(into: $0) }
                guard count > 0 else { return }
                output.append(contentsOf: chunk[0 ..< count])
            }
        }
        if showHidden {
            // Most servers list dot files with "LIST -a"; IIS rejects the flag, so fall back to LIST.
            do {
                try self.transfer("LIST -a", body: read)
                return FTPText.decode(output)
            } catch RemoteClientError.commandFailed {
                output.removeAll()
            }
        }
        try self.transfer("LIST", body: read)
        return FTPText.decode(output)
    }
}

enum FTPText {
    /// UTF-8 when the server sends it; older servers send Latin-1 names.
    static func decode(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }
}
