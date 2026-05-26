import XCTest
@testable import DriftlineCore

final class SSHAgentClientTests: XCTestCase {
    func testSSHAgentClientReturnsNilWhenSocketPathEmpty() {
        let client = SSHAgentClient(socketPath: "")
        XCTAssertNil(client)
    }

    func testSSHAgentClientReturnsNilWhenSocketPathInvalid() {
        let client = SSHAgentClient(socketPath: "/tmp/driftline-nonexistent-agent-socket-\(UUID().uuidString)")
        XCTAssertNil(client)
    }

    func testJumpHostProxyValueFormatsCorrectly() {
        let jumps = [JumpHost(host: "bastion.example.com", port: 22, username: "admin")]
        XCTAssertEqual(SSHCommandBuilder.jumpProxyValue(for: jumps), "admin@bastion.example.com:22")
    }

    func testJumpHostProxyValueMultipleHosts() {
        let jumps = [
            JumpHost(host: "first.example.com", port: 22, username: "alice"),
            JumpHost(host: "second.example.com", port: 2222, username: "bob")
        ]
        XCTAssertEqual(
            SSHCommandBuilder.jumpProxyValue(for: jumps),
            "alice@first.example.com:22,bob@second.example.com:2222"
        )
    }

    func testJumpHostProxyValueNoUsername() {
        let jumps = [JumpHost(host: "bastion.example.com", port: 2222)]
        XCTAssertEqual(SSHCommandBuilder.jumpProxyValue(for: jumps), "bastion.example.com:2222")
    }
}
