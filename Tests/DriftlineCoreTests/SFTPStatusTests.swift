import XCTest
@testable import DriftlineCore

final class SFTPStatusTests: XCTestCase {
    func testStatusParserMapsPermissionDenied() throws {
        var payload = Data()
        payload.appendUInt32(SFTPStatusCode.permissionDenied.rawValue)
        payload.appendString("denied")
        payload.appendString("en")

        let status = try SFTPStatus.parse(payload: payload)
        let error = status.remoteError()

        XCTAssertEqual(status.code, .permissionDenied)
        XCTAssertEqual(error?.errorDescription, "denied")
    }

    func testOKStatusHasNoRemoteError() {
        XCTAssertNil(SFTPStatus(code: .ok).remoteError())
    }
}

