import Foundation

public struct SystemHostFingerprintProvider: HostFingerprintProviding {
    private let processExecutor: SystemProcessExecuting

    public init(processExecutor: SystemProcessExecuting = FoundationProcessExecutor()) {
        self.processExecutor = processExecutor
    }

    public func fingerprint(host: String, port: Int) async throws -> HostFingerprint {
        let scan = try await processExecutor.run(
            executable: "/usr/bin/ssh-keyscan",
            arguments: ["-p", String(port), "-t", "rsa,ecdsa,ed25519", host],
            timeout: 15
        )
        guard scan.exitCode == 0, !scan.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteClientError.connectionFailed(scan.standardError.isEmpty ? "Could not read host key." : scan.standardError)
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineHostKey-\(UUID().uuidString)")
        try scan.standardOutput.write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let keygen = try await processExecutor.run(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-lf", temporaryURL.path, "-E", "sha256"],
            timeout: 15
        )
        guard keygen.exitCode == 0 else {
            throw RemoteClientError.connectionFailed(keygen.standardError.isEmpty ? "Could not fingerprint host key." : keygen.standardError)
        }

        let keyLines = scan.standardOutput
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .map(String.init)
        guard var parsed = parseKeygenOutput(keygen.standardOutput, host: host, port: port) else {
            throw RemoteClientError.connectionFailed("Could not parse host fingerprint.")
        }
        parsed.knownHostsLine = keyLines.first(where: { line in
            line.localizedCaseInsensitiveContains(parsed.algorithm)
                || line.localizedCaseInsensitiveContains(openSSHKeyType(for: parsed.algorithm))
        }) ?? keyLines.first ?? ""
        return parsed
    }

    public func parseKeygenOutput(_ output: String, host: String, port: Int) -> HostFingerprint? {
        let lines = output.split(separator: "\n")
        let preferredLine = lines.first { $0.localizedCaseInsensitiveContains("(ED25519)") }
            ?? lines.first { $0.localizedCaseInsensitiveContains("(ECDSA)") }
            ?? lines.first { $0.localizedCaseInsensitiveContains("(RSA)") }
            ?? lines.first
        guard let line = preferredLine else { return nil }
        let fields = line.split(separator: " ")
        guard fields.count >= 2 else { return nil }
        let fingerprint = String(fields[1])
        let algorithmField = fields.first { $0.hasPrefix("(") && $0.hasSuffix(")") }
        let algorithm = algorithmField.map { String($0.dropFirst().dropLast()) } ?? "UNKNOWN"
        return HostFingerprint(host: host, port: port, algorithm: algorithm, fingerprint: fingerprint)
    }

    private func openSSHKeyType(for algorithm: String) -> String {
        switch algorithm.lowercased() {
        case "ed25519":
            "ssh-ed25519"
        case "ecdsa":
            "ecdsa-sha2"
        case "rsa":
            "ssh-rsa"
        default:
            algorithm
        }
    }
}
