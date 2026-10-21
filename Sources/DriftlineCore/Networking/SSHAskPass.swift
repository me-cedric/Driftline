import Foundation

/// Gives one secret to OpenSSH through `SSH_ASKPASS`, without a command argument, an environment value or a file that holds it.
/// The helper script reads a FIFO in a private 0700 directory, and this session writes the secret into the FIFO when ssh asks.
public final class SSHAskPassSession: @unchecked Sendable {
    public let environment: [String: String]
    private let directory: URL
    private let fifoPath: String
    private let lock = NSLock()
    private var closed = false

    /// `maximumPrompts`: how many prompts get the secret. Later prompts get an empty answer, so a wrong password
    /// is not tried again by keyboard-interactive (lockout tools count each try) and ssh exits instead of waiting.
    public init(secret: String, maximumPrompts: Int = 1) throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("driftline-askpass-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let scriptURL = directory.appendingPathComponent("askpass")
        let fifoURL = directory.appendingPathComponent("secret")
        do {
            // An empty answer exits 1: ssh then cancels the prompt instead of trying an empty password.
            let script = "#!/bin/sh\nsecret=$(/bin/cat \"$DRIFTLINE_ASKPASS_FIFO\") || exit 1\n[ -n \"$secret\" ] || exit 1\nprintf '%s\\n' \"$secret\"\n"
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            guard mkfifo(fifoURL.path, 0o600) == 0 else {
                throw RemoteClientError.connectionFailed("Could not prepare the SSH password prompt.")
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }

        self.directory = directory
        self.fifoPath = fifoURL.path
        self.environment = [
            "SSH_ASKPASS": scriptURL.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "driftline:0",
            "DRIFTLINE_ASKPASS_FIFO": fifoURL.path,
        ]

        let payload = Data((secret + "\n").utf8)
        Thread { [self] in self.serve(payload, maximumPrompts: maximumPrompts) }.start()
    }

    deinit {
        self.close()
    }

    /// Makes a session when the profile needs a stored password or key passphrase.
    public static func make(for profile: ServerProfile, credentialStore: CredentialStore?) async throws -> SSHAskPassSession? {
        switch profile.authenticationMethod {
        case let .password(reference):
            guard let secret = try await credentialStore?.readString(reference: reference), !secret.isEmpty else {
                throw RemoteClientError.unsupportedAuthentication("No password is saved for this server. Edit the server and enter the password.")
            }
            return try SSHAskPassSession(secret: secret)
        case let .privateKey(_, passphrase?):
            guard let secret = try await credentialStore?.readString(reference: passphrase), !secret.isEmpty else {
                throw RemoteClientError.unsupportedAuthentication("No passphrase is saved for this private key. Edit the server and enter the passphrase.")
            }
            return try SSHAskPassSession(secret: secret)
        case .privateKey, .agent, .none:
            return nil
        }
    }

    public func close() {
        self.lock.lock()
        let wasClosed = self.closed
        self.closed = true
        self.lock.unlock()
        guard !wasClosed else { return }
        // A reader that still waits gets end of file, so ssh fails fast instead of hanging.
        let descriptor = open(self.fifoPath, O_WRONLY | O_NONBLOCK)
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        try? FileManager.default.removeItem(at: self.directory)
    }

    private var isClosed: Bool {
        self.lock.lock()
        defer { lock.unlock() }
        return self.closed
    }

    private func serve(_ secret: Data, maximumPrompts: Int) {
        var served = 0
        while !self.isClosed {
            let payload = served < maximumPrompts ? secret : Data()
            let descriptor = open(self.fifoPath, O_WRONLY | O_NONBLOCK)
            guard descriptor >= 0 else {
                // ENXIO: no reader yet. Any other error: the FIFO is gone.
                guard errno == ENXIO else { return }
                usleep(50000)
                continue
            }
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
            payload.withUnsafeBytes { buffer in
                _ = write(descriptor, buffer.baseAddress, buffer.count)
            }
            Darwin.close(descriptor)
            served += 1
            // Let the reader reach end of file before the FIFO opens again.
            usleep(200_000)
        }
    }
}
