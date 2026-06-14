import Foundation

public enum SFTPPacketType: UInt8, Codable, Sendable {
    case initialize = 1
    case version = 2
    case open = 3
    case close = 4
    case read = 5
    case write = 6
    case lstat = 7
    case fstat = 8
    case setstat = 9
    case fsetstat = 10
    case opendir = 11
    case readdir = 12
    case remove = 13
    case mkdir = 14
    case rmdir = 15
    case realpath = 16
    case stat = 17
    case rename = 18
    case readlink = 19
    case symlink = 20
    case status = 101
    case handle = 102
    case data = 103
    case name = 104
    case attrs = 105
    case extended = 200
    case extendedReply = 201
}

public struct SFTPPacket: Equatable, Sendable {
    public var type: SFTPPacketType
    public var requestID: UInt32?
    public var payload: Data

    public init(type: SFTPPacketType, requestID: UInt32? = nil, payload: Data = Data()) {
        self.type = type
        self.requestID = requestID
        self.payload = payload
    }

    public func encoded() -> Data {
        var body = Data([type.rawValue])
        if let requestID {
            body.appendUInt32(requestID)
        }
        body.append(self.payload)

        var data = Data()
        data.appendUInt32(UInt32(body.count))
        data.append(body)
        return data
    }

    public static func decodeOne(from data: Data) throws -> (packet: SFTPPacket, remaining: Data) {
        var reader = SFTPDataReader(data: data)
        let length = try reader.readUInt32()
        guard length > 0 else {
            throw SFTPPacketError.invalidLength(length)
        }
        guard reader.remainingCount >= Int(length) else {
            throw SFTPPacketError.incompletePacket(expected: Int(length), actual: reader.remainingCount)
        }

        let packetBytes = try reader.readData(count: Int(length))
        let remaining = try reader.readData(count: reader.remainingCount)
        var packetReader = SFTPDataReader(data: packetBytes)
        let rawType = try packetReader.readUInt8()
        guard let type = SFTPPacketType(rawValue: rawType) else {
            throw SFTPPacketError.unknownPacketType(rawType)
        }

        let requestID: UInt32? = switch type {
        case .initialize, .version:
            nil
        default:
            try packetReader.readUInt32()
        }
        let payload = try packetReader.readData(count: packetReader.remainingCount)
        return (SFTPPacket(type: type, requestID: requestID, payload: payload), remaining)
    }
}

public enum SFTPPacketError: Error, Equatable, LocalizedError {
    case invalidLength(UInt32)
    case incompletePacket(expected: Int, actual: Int)
    case unknownPacketType(UInt8)
    case truncatedField
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .invalidLength:
            "The SFTP packet length is invalid."
        case .incompletePacket:
            "The SFTP packet is incomplete."
        case let .unknownPacketType(type):
            "Unknown SFTP packet type \(type)."
        case .truncatedField:
            "The SFTP packet ended unexpectedly."
        case .invalidUTF8:
            "The SFTP packet contains invalid UTF-8."
        }
    }
}

public struct SFTPDataReader {
    private var data: Data
    private var offset = 0

    public init(data: Data) {
        self.data = data
    }

    public var remainingCount: Int {
        self.data.count - self.offset
    }

    public mutating func readUInt8() throws -> UInt8 {
        guard self.remainingCount >= 1 else { throw SFTPPacketError.truncatedField }
        defer { offset += 1 }
        return self.data[self.offset]
    }

    public mutating func readUInt32() throws -> UInt32 {
        guard self.remainingCount >= 4 else { throw SFTPPacketError.truncatedField }
        let value = self.data[self.offset ..< self.offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        self.offset += 4
        return value
    }

    public mutating func readUInt64() throws -> UInt64 {
        guard self.remainingCount >= 8 else { throw SFTPPacketError.truncatedField }
        let value = self.data[self.offset ..< self.offset + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        self.offset += 8
        return value
    }

    public mutating func readData(count: Int) throws -> Data {
        guard count >= 0, self.remainingCount >= count else { throw SFTPPacketError.truncatedField }
        let slice = self.data[self.offset ..< self.offset + count]
        self.offset += count
        return Data(slice)
    }

    public mutating func readString() throws -> String {
        let length = try readUInt32()
        let data = try readData(count: Int(length))
        guard let string = String(data: data, encoding: .utf8) else {
            throw SFTPPacketError.invalidUTF8
        }
        return string
    }

    public mutating func readBinaryString() throws -> Data {
        let length = try readUInt32()
        return try self.readData(count: Int(length))
    }
}

public extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt64(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendString(_ value: String) {
        let bytes = Data(value.utf8)
        self.appendUInt32(UInt32(bytes.count))
        append(bytes)
    }

    mutating func appendBinaryString(_ value: Data) {
        self.appendUInt32(UInt32(value.count))
        append(value)
    }
}
