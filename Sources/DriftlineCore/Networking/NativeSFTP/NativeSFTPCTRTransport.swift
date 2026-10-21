import CommonCrypto
import Crypto
import Foundation
import NIOCore
import NIOSSH

/// Transport schemes for the native backend: the SwiftNIO SSH AES-GCM schemes first, then AES-CTR with HMAC-SHA-256
/// (RFC 4344, RFC 6668, and the OpenSSH encrypt-then-MAC variant) for servers that offer no AES-GCM.
/// shortcut: no HMAC-SHA-512, because SwiftNIO SSH derives at most one hash block of key material (32 bytes with a
/// SHA-256 key exchange); add it when SwiftNIO SSH implements RFC 4253 key extension.
public enum NativeSFTPTransportSchemes {
    public static let all: [NIOSSHTransportProtection.Type] = Constants.bundledTransportProtectionSchemes + [
        AES256CTRHMACSHA256ETMTransport.self,
        AES256CTRHMACSHA256Transport.self,
        AES128CTRHMACSHA256ETMTransport.self,
        AES128CTRHMACSHA256Transport.self,
    ]
}

enum NativeSFTPTransportError: Error {
    case invalidKeySize
    case cipherFailure
    case invalidPacketLength
    case invalidMAC
    case invalidPadding
}

enum NativeSFTPHMAC {
    static let length = 32

    static func authenticationCode(key: SymmetricKey, sequenceNumber: UInt32, packet: UnsafeRawBufferPointer) -> [UInt8] {
        var hmac = HMAC<SHA256>(key: key)
        hmac.update(data: withUnsafeBytes(of: sequenceNumber.bigEndian) { Array($0) })
        hmac.update(data: packet)
        return Array(hmac.finalize())
    }
}

/// One direction of AES-CTR. The CommonCrypto cryptor keeps the counter between packets, as SSH requires.
final class NativeSFTPAESCTRStream {
    private let cryptor: CCCryptorRef

    init(key: SymmetricKey, iv: [UInt8]) throws {
        guard iv.count == kCCBlockSizeAES128 else { throw NativeSFTPTransportError.invalidKeySize }
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    keyBytes.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }
        guard status == kCCSuccess, let cryptor else { throw NativeSFTPTransportError.cipherFailure }
        self.cryptor = cryptor
    }

    deinit {
        CCCryptorRelease(self.cryptor)
    }

    func apply(_ bytes: UnsafeMutableRawBufferPointer) throws {
        guard !bytes.isEmpty else { return }
        var moved = 0
        let status = CCCryptorUpdate(self.cryptor, bytes.baseAddress, bytes.count, bytes.baseAddress, bytes.count, &moved)
        guard status == kCCSuccess, moved == bytes.count else { throw NativeSFTPTransportError.cipherFailure }
    }
}

class NativeSFTPAESCTRTransport {
    /// OpenSSH refuses packets above 256 KiB. The check also stops a forged length from overflowing the parser.
    static let maximumPacketLength = 256 * 1024

    class var cipherName: String {
        fatalError("Override cipherName")
    }

    class var encryptThenMAC: Bool {
        fatalError("Override encryptThenMAC")
    }

    class var encryptionKeySize: Int {
        fatalError("Override encryptionKeySize")
    }

    class var macName: String? {
        self.encryptThenMAC ? "hmac-sha2-256-etm@openssh.com" : "hmac-sha2-256"
    }

    class var keySizes: ExpectedKeySizes {
        ExpectedKeySizes(ivSize: kCCBlockSizeAES128, encryptionKeySize: self.encryptionKeySize, macKeySize: NativeSFTPHMAC.length)
    }

    private var inboundCipher: NativeSFTPAESCTRStream
    private var outboundCipher: NativeSFTPAESCTRStream
    private var inboundMACKey: SymmetricKey
    private var outboundMACKey: SymmetricKey

    required init(initialKeys: NIOSSHSessionKeys) throws {
        try Self.validate(initialKeys)
        self.inboundCipher = try NativeSFTPAESCTRStream(key: initialKeys.inboundEncryptionKey, iv: initialKeys.initialInboundIV)
        self.outboundCipher = try NativeSFTPAESCTRStream(key: initialKeys.outboundEncryptionKey, iv: initialKeys.initialOutboundIV)
        self.inboundMACKey = initialKeys.inboundMACKey
        self.outboundMACKey = initialKeys.outboundMACKey
    }

    private static func validate(_ keys: NIOSSHSessionKeys) throws {
        let sizes = self.keySizes
        guard keys.inboundEncryptionKey.bitCount == sizes.encryptionKeySize * 8,
              keys.outboundEncryptionKey.bitCount == sizes.encryptionKeySize * 8,
              keys.inboundMACKey.bitCount == sizes.macKeySize * 8,
              keys.outboundMACKey.bitCount == sizes.macKeySize * 8
        else {
            throw NativeSFTPTransportError.invalidKeySize
        }
    }

    private static func constantTimeEquals(_ lhs: [UInt8], _ rhs: ByteBufferView) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

extension NativeSFTPAESCTRTransport: NIOSSHTransportProtection {
    static var cipherBlockSize: Int {
        kCCBlockSizeAES128
    }

    var macBytes: Int {
        NativeSFTPHMAC.length
    }

    var lengthEncrypted: Bool {
        !Self.encryptThenMAC
    }

    func updateKeys(_ newKeys: NIOSSHSessionKeys) throws {
        try Self.validate(newKeys)
        self.inboundCipher = try NativeSFTPAESCTRStream(key: newKeys.inboundEncryptionKey, iv: newKeys.initialInboundIV)
        self.outboundCipher = try NativeSFTPAESCTRStream(key: newKeys.outboundEncryptionKey, iv: newKeys.initialOutboundIV)
        self.inboundMACKey = newKeys.inboundMACKey
        self.outboundMACKey = newKeys.outboundMACKey
    }

    func decryptFirstBlock(_ source: inout ByteBuffer) throws {
        let blockSize = Self.cipherBlockSize
        if !Self.encryptThenMAC {
            try source.withUnsafeMutableReadableBytes { bytes in
                try self.inboundCipher.apply(UnsafeMutableRawBufferPointer(rebasing: bytes[0 ..< blockSize]))
            }
        }
        guard let length = source.getInteger(at: source.readerIndex, as: UInt32.self),
              length <= Self.maximumPacketLength
        else {
            throw NativeSFTPTransportError.invalidPacketLength
        }
    }

    func decryptAndVerifyRemainingPacket(_ source: inout ByteBuffer, sequenceNumber: UInt32) throws -> ByteBuffer {
        let blockSize = Self.cipherBlockSize
        let packetBytes = source.readableBytes - self.macBytes
        // Encrypted bytes: the whole packet, or the packet without its length field (encrypt-then-MAC).
        let encryptedBytes = Self.encryptThenMAC ? packetBytes - 4 : packetBytes
        guard encryptedBytes >= blockSize, encryptedBytes % blockSize == 0,
              let receivedMAC = source.viewBytes(at: source.readerIndex + packetBytes, length: self.macBytes)
        else {
            throw NativeSFTPTransportError.invalidPacketLength
        }

        func verifyMAC() throws {
            let expected = source.withUnsafeReadableBytes { bytes in
                NativeSFTPHMAC.authenticationCode(key: self.inboundMACKey, sequenceNumber: sequenceNumber, packet: UnsafeRawBufferPointer(rebasing: bytes[0 ..< packetBytes]))
            }
            guard Self.constantTimeEquals(expected, receivedMAC) else { throw NativeSFTPTransportError.invalidMAC }
        }

        if Self.encryptThenMAC {
            try verifyMAC()
            try source.withUnsafeMutableReadableBytes { bytes in
                try self.inboundCipher.apply(UnsafeMutableRawBufferPointer(rebasing: bytes[4 ..< packetBytes]))
            }
        } else {
            // The first block was decrypted by decryptFirstBlock.
            try source.withUnsafeMutableReadableBytes { bytes in
                try self.inboundCipher.apply(UnsafeMutableRawBufferPointer(rebasing: bytes[blockSize ..< packetBytes]))
            }
            try verifyMAC()
        }

        guard let paddingLength = source.getInteger(at: source.readerIndex + 4, as: UInt8.self), paddingLength >= 4 else {
            throw NativeSFTPTransportError.invalidPadding
        }
        let payloadLength = packetBytes - 5 - Int(paddingLength)
        guard payloadLength >= 0, let payload = source.getSlice(at: source.readerIndex + 5, length: payloadLength) else {
            throw NativeSFTPTransportError.invalidPadding
        }
        source.moveReaderIndex(forwardBy: source.readableBytes)
        return payload
    }

    func encryptPacket(_ destination: inout ByteBuffer, sequenceNumber: UInt32) throws {
        let tag: [UInt8]
        if Self.encryptThenMAC {
            try destination.withUnsafeMutableReadableBytes { bytes in
                try self.outboundCipher.apply(UnsafeMutableRawBufferPointer(rebasing: bytes[4...]))
            }
            tag = destination.withUnsafeReadableBytes { NativeSFTPHMAC.authenticationCode(key: self.outboundMACKey, sequenceNumber: sequenceNumber, packet: $0) }
        } else {
            tag = destination.withUnsafeReadableBytes { NativeSFTPHMAC.authenticationCode(key: self.outboundMACKey, sequenceNumber: sequenceNumber, packet: $0) }
            try destination.withUnsafeMutableReadableBytes { bytes in
                try self.outboundCipher.apply(bytes)
            }
        }
        destination.writeBytes(tag)
    }
}

final class AES256CTRHMACSHA256ETMTransport: NativeSFTPAESCTRTransport {
    override static var cipherName: String {
        "aes256-ctr"
    }

    override static var encryptThenMAC: Bool {
        true
    }

    override static var encryptionKeySize: Int {
        32
    }
}

final class AES256CTRHMACSHA256Transport: NativeSFTPAESCTRTransport {
    override static var cipherName: String {
        "aes256-ctr"
    }

    override static var encryptThenMAC: Bool {
        false
    }

    override static var encryptionKeySize: Int {
        32
    }
}

final class AES128CTRHMACSHA256ETMTransport: NativeSFTPAESCTRTransport {
    override static var cipherName: String {
        "aes128-ctr"
    }

    override static var encryptThenMAC: Bool {
        true
    }

    override static var encryptionKeySize: Int {
        16
    }
}

final class AES128CTRHMACSHA256Transport: NativeSFTPAESCTRTransport {
    override static var cipherName: String {
        "aes128-ctr"
    }

    override static var encryptThenMAC: Bool {
        false
    }

    override static var encryptionKeySize: Int {
        16
    }
}
