import XCTest
@testable import DriftlineCore

final class SFTPAttributesTests: XCTestCase {
    func testAttributesParserReadsSizePermissionsAndModifiedDate() throws {
        var data = Data()
        data.appendUInt32(SFTPAttributeFlag.size | SFTPAttributeFlag.permissions | SFTPAttributeFlag.acmodtime)
        data.appendUInt64(4096)
        data.appendUInt32(0o040755)
        data.appendUInt32(100)
        data.appendUInt32(200)
        var reader = SFTPDataReader(data: data)

        let attrs = try SFTPAttributes.parse(from: &reader)

        XCTAssertEqual(attrs.size, 4096)
        XCTAssertEqual(attrs.permissions, 0o040755)
        XCTAssertEqual(attrs.fileKind, .folder)
        XCTAssertEqual(attrs.modifiedAt, Date(timeIntervalSince1970: 200))
    }

    func testNameParserFiltersDotEntries() throws {
        var payload = Data()
        payload.appendUInt32(3)
        appendName(".", permissions: 0o040755, to: &payload)
        appendName("..", permissions: 0o040755, to: &payload)
        appendName("file.txt", permissions: 0o100644, to: &payload)

        let entries = try SFTPNameParser.parseNamePacketPayload(payload)

        XCTAssertEqual(entries.map(\.filename), ["file.txt"])
        XCTAssertEqual(entries.first?.attributes.fileKind, .file)
    }

    private func appendName(_ name: String, permissions: UInt32, to payload: inout Data) {
        payload.appendString(name)
        payload.appendString(name)
        payload.appendUInt32(SFTPAttributeFlag.permissions)
        payload.appendUInt32(permissions)
    }
}

