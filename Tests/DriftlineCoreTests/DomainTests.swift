@testable import DriftlineCore
import XCTest

final class DomainTests: XCTestCase {
    func testServerProfileDuplicateCreatesNewIdentityAndCopyName() {
        let original = ServerProfile(
            displayName: "Production",
            host: "example.com",
            protocolKind: .sftp,
            username: "cedric",
            authenticationMethod: .agent
        )

        let copy = original.duplicated(now: Date(timeIntervalSince1970: 100))

        XCTAssertNotEqual(original.id, copy.id)
        XCTAssertEqual(copy.displayName, "Production Copy")
        XCTAssertEqual(copy.host, original.host)
        XCTAssertEqual(copy.protocolKind, .sftp)
    }

    func testDefaultPortsMatchProtocolExpectations() {
        XCTAssertEqual(TransferProtocolKind.sftp.defaultPort, 22)
        XCTAssertEqual(TransferProtocolKind.ftp.defaultPort, 21)
        XCTAssertEqual(TransferProtocolKind.ftps.defaultPort, 990)
    }
}
