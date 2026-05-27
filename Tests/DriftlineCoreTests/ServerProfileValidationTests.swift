@testable import DriftlineCore
import XCTest

final class ServerProfileValidationTests: XCTestCase {
    func testValidProfilePassesValidation() throws {
        let profile = ServerProfile(displayName: "Staging", host: "staging.example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        XCTAssertNoThrow(try ServerProfileValidator.validate(profile))
    }

    func testMissingRequiredFieldsFailValidation() {
        let missingName = ServerProfile(displayName: " ", host: "example.com", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let missingHost = ServerProfile(displayName: "Server", host: " ", protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)
        let missingUsername = ServerProfile(displayName: "Server", host: "example.com", protocolKind: .sftp, username: " ", authenticationMethod: .agent)

        XCTAssertThrowsError(try ServerProfileValidator.validate(missingName)) { error in
            XCTAssertEqual(error as? ServerProfileValidationError, .missingDisplayName)
        }
        XCTAssertThrowsError(try ServerProfileValidator.validate(missingHost)) { error in
            XCTAssertEqual(error as? ServerProfileValidationError, .missingHost)
        }
        XCTAssertThrowsError(try ServerProfileValidator.validate(missingUsername)) { error in
            XCTAssertEqual(error as? ServerProfileValidationError, .missingUsername)
        }
    }

    func testInvalidPortFailsValidation() {
        let profile = ServerProfile(displayName: "Server", host: "example.com", port: 70000, protocolKind: .sftp, username: "deploy", authenticationMethod: .agent)

        XCTAssertThrowsError(try ServerProfileValidator.validate(profile)) { error in
            XCTAssertEqual(error as? ServerProfileValidationError, .invalidPort)
        }
    }
}
