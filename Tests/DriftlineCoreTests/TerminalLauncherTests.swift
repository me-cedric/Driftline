import XCTest
@testable import DriftlineCore

final class TerminalLauncherTests: XCTestCase {
    func testAppleScriptEscapesTerminalCommand() {
        let command = TerminalCommand(executable: "ssh", arguments: ["deploy@example.com", "echo", "hello world"])
        let script = TerminalAppleScriptBuilder().script(for: command)

        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("ssh deploy@example.com echo 'hello world'"))
    }
}
