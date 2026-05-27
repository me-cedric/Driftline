@testable import DriftlineCore
import XCTest

final class FileOperationTests: XCTestCase {
    func testManagedKnownHostsFileWritesTrustedHostLineAndReplacesExistingHost() async throws {
        let url = self.temporaryFileURL("known_hosts")
        let store = ManagedKnownHostsFile(url: url)
        try await store.trust(HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:old", knownHostsLine: "example.com ssh-ed25519 OLD"))
        try await store.trust(HostTrustRecord(host: "example.com", port: 22, algorithm: "ED25519", fingerprint: "SHA256:new", knownHostsLine: "example.com ssh-ed25519 NEW"))

        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(contents.contains("OLD"))
        XCTAssertTrue(contents.contains("example.com ssh-ed25519 NEW"))
    }

    func testSSHCommandBuilderUsesDriftlineKnownHostsFile() throws {
        let knownHostsURL = URL(fileURLWithPath: "/tmp/Application Support/driftline_known_hosts")
        let profile = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        let arguments = try SSHCommandBuilder.baseArguments(for: profile, knownHostsURL: knownHostsURL)

        XCTAssertTrue(arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(arguments.contains("UserKnownHostsFile=/tmp/Application\\ Support/driftline_known_hosts"))
        XCTAssertTrue(arguments.contains("GlobalKnownHostsFile=/dev/null"))
    }

    func testRemoteFileCommandsQuotePaths() {
        XCTAssertEqual(RemoteFileCommandBuilder.createFolderCommand(name: "New Folder", in: "/var/www"), "mkdir -- '/var/www/New Folder'")
        XCTAssertEqual(RemoteFileCommandBuilder.renameCommand(path: "/var/www/old name.txt", newName: "new name.txt"), "mv -- '/var/www/old name.txt' '/var/www/new name.txt'")
        XCTAssertEqual(RemoteFileCommandBuilder.deleteCommand(path: "/var/www/it's.txt"), "rm -rf -- '/var/www/it'\\''s.txt'")
    }

    func testLocalFileOperationsCreateRenameDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = FoundationLocalFileSystemClient()

        try await client.createFolder(named: "Drafts", in: root.path)
        let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
        let draftsExists = await client.itemExists(at: drafts.path)
        XCTAssertTrue(draftsExists)

        try await client.renameItem(at: drafts.path, to: "Final")
        let final = root.appendingPathComponent("Final", isDirectory: true)
        let finalExists = await client.itemExists(at: final.path)
        XCTAssertTrue(finalExists)

        try await client.deleteItem(at: final.path)
        let finalExistsAfterDelete = await client.itemExists(at: final.path)
        XCTAssertFalse(finalExistsAfterDelete)
    }

    private func temporaryFileURL(_ filename: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftlineTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }
}
