import Crypto
@testable import DriftlineCore
import NIOCore
import NIOSSH
import XCTest

final class NativeSFTPCTRTransportTests: XCTestCase {
    /// NIST SP 800-38A, F.5.5 CTR-AES256.Encrypt. Two separate updates prove the counter carries over.
    func testAESCTRStreamMatchesNISTVectorAcrossUpdates() throws {
        let stream = try NativeSFTPAESCTRStream(
            key: SymmetricKey(data: Self.bytes("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")),
            iv: Self.bytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        )
        var first = Self.bytes("6bc1bee22e409f96e93d7e117393172a")
        var rest = Self.bytes("ae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52ef")

        try first.withUnsafeMutableBytes { try stream.apply($0) }
        try rest.withUnsafeMutableBytes { try stream.apply($0) }

        XCTAssertEqual(first, Self.bytes("601ec313775789a5b7a7f504bbf3d228"))
        XCTAssertEqual(rest, Self.bytes("f443e3ca4d62b59aca84e990cacaf5c52b0930daa23de94ce87017ba2d84988d"))
    }

    func testEverySchemeRoundTripsPacketsAndRejectsTampering() throws {
        let schemes = NativeSFTPTransportSchemes.all.compactMap { $0 as? NativeSFTPAESCTRTransport.Type }
        XCTAssertEqual(schemes.count, 4)
        for scheme in schemes {
            let (client, server) = try Self.pair(scheme)
            for (sequence, payload) in [(UInt32(3), "hello"), (4, String(repeating: "x", count: 300))] {
                var packet = Self.packet(payload: Array(payload.utf8), encryptThenMAC: !client.lengthEncrypted)
                try client.encryptPacket(&packet, sequenceNumber: sequence)
                var received = packet
                try server.decryptFirstBlock(&received)
                let opened = try server.decryptAndVerifyRemainingPacket(&received, sequenceNumber: sequence)
                XCTAssertEqual(String(buffer: opened), payload, "\(scheme.cipherName) \(scheme.macName ?? "")")
                XCTAssertEqual(received.readableBytes, 0)
            }

            var tampered = Self.packet(payload: Array("tamper".utf8), encryptThenMAC: !client.lengthEncrypted)
            try client.encryptPacket(&tampered, sequenceNumber: 5)
            try tampered.setInteger(XCTUnwrap(tampered.getInteger(at: 20, as: UInt8.self)) ^ 0x01, at: 20)
            try server.decryptFirstBlock(&tampered)
            XCTAssertThrowsError(try server.decryptAndVerifyRemainingPacket(&tampered, sequenceNumber: 5))
        }
    }

    func testOversizedPacketLengthIsRejected() throws {
        let (_, server) = try Self.pair(AES256CTRHMACSHA256ETMTransport.self)
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32.max)
        buffer.writeBytes([UInt8](repeating: 0, count: 60))

        XCTAssertThrowsError(try server.decryptFirstBlock(&buffer))
    }

    private static func pair(_ scheme: NativeSFTPAESCTRTransport.Type) throws -> (NIOSSHTransportProtection, NIOSSHTransportProtection) {
        let sizes = scheme.keySizes
        func key(_ size: Int) -> SymmetricKey {
            SymmetricKey(size: SymmetricKeySize(bitCount: size * 8))
        }
        let ivA = (0 ..< sizes.ivSize).map { UInt8($0) }
        let ivB = (0 ..< sizes.ivSize).map { UInt8(255 - $0) }
        let encryptionA = key(sizes.encryptionKeySize), encryptionB = key(sizes.encryptionKeySize)
        let macA = key(sizes.macKeySize), macB = key(sizes.macKeySize)
        let client = try scheme.init(initialKeys: NIOSSHSessionKeys(
            initialInboundIV: ivB, initialOutboundIV: ivA,
            inboundEncryptionKey: encryptionB, outboundEncryptionKey: encryptionA,
            inboundMACKey: macB, outboundMACKey: macA
        ))
        let server = try scheme.init(initialKeys: NIOSSHSessionKeys(
            initialInboundIV: ivA, initialOutboundIV: ivB,
            inboundEncryptionKey: encryptionA, outboundEncryptionKey: encryptionB,
            inboundMACKey: macA, outboundMACKey: macB
        ))
        return (client, server)
    }

    /// Builds `length || padding_length || payload || padding` padded to the AES block size, as the SwiftNIO SSH serializer does.
    private static func packet(payload: [UInt8], encryptThenMAC: Bool) -> ByteBuffer {
        let covered = (encryptThenMAC ? 0 : 4) + 1 + payload.count
        var padding = 16 - covered % 16
        if padding < 4 { padding += 16 }
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32(1 + payload.count + padding))
        buffer.writeInteger(UInt8(padding))
        buffer.writeBytes(payload)
        buffer.writeBytes([UInt8](repeating: 0xab, count: padding))
        return buffer
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index ..< next], radix: 16)!)
            index = next
        }
        return result
    }
}
