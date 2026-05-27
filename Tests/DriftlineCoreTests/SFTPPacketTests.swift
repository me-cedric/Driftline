@testable import DriftlineCore
import XCTest

final class SFTPPacketTests: XCTestCase {
    func testInitializePacketEncoding() throws {
        let packet = SFTPRequestBuilder.initialize()
        let encoded = packet.encoded()

        XCTAssertEqual(Array(encoded), [0, 0, 0, 5, 1, 0, 0, 0, 3])

        let decoded = try SFTPPacket.decodeOne(from: encoded).packet
        XCTAssertEqual(decoded.type, .initialize)
        XCTAssertNil(decoded.requestID)
        XCTAssertEqual(decoded.payload, Data([0, 0, 0, 3]))
    }

    func testRequestPacketEncodingAndDecoding() throws {
        let packet = SFTPRequestBuilder.opendir(id: 42, path: "/config")
        let decoded = try SFTPPacket.decodeOne(from: packet.encoded()).packet

        XCTAssertEqual(decoded.type, .opendir)
        XCTAssertEqual(decoded.requestID, 42)
        var reader = SFTPDataReader(data: decoded.payload)
        XCTAssertEqual(try reader.readString(), "/config")
    }

    func testDecodeOneReturnsRemainingBytes() throws {
        let first = SFTPRequestBuilder.close(id: 1, handle: Data([1, 2]))
        let second = SFTPRequestBuilder.close(id: 2, handle: Data([3, 4]))
        var combined = first.encoded()
        combined.append(second.encoded())

        let result = try SFTPPacket.decodeOne(from: combined)

        XCTAssertEqual(result.packet.requestID, 1)
        XCTAssertFalse(result.remaining.isEmpty)
        XCTAssertEqual(try SFTPPacket.decodeOne(from: result.remaining).packet.requestID, 2)
    }

    func testDecodeRejectsIncompletePacket() {
        XCTAssertThrowsError(try SFTPPacket.decodeOne(from: Data([0, 0, 0, 10, 1]))) { error in
            XCTAssertEqual(error as? SFTPPacketError, .incompletePacket(expected: 10, actual: 1))
        }
    }
}
