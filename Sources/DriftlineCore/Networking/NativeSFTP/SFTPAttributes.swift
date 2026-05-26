import Foundation

public struct SFTPAttributes: Equatable, Sendable {
    public var size: UInt64?
    public var uid: UInt32?
    public var gid: UInt32?
    public var permissions: UInt32?
    public var accessedAt: Date?
    public var modifiedAt: Date?

    public init(size: UInt64? = nil, uid: UInt32? = nil, gid: UInt32? = nil, permissions: UInt32? = nil, accessedAt: Date? = nil, modifiedAt: Date? = nil) {
        self.size = size
        self.uid = uid
        self.gid = gid
        self.permissions = permissions
        self.accessedAt = accessedAt
        self.modifiedAt = modifiedAt
    }

    public var fileKind: FileItemKind {
        guard let permissions else { return .file }
        let typeBits = permissions & 0o170000
        switch typeBits {
        case 0o040000:
            return .folder
        case 0o120000:
            return .symbolicLink
        case 0o100000:
            return .file
        default:
            return .unknown
        }
    }

    public static func parse(from reader: inout SFTPDataReader) throws -> SFTPAttributes {
        let flags = try reader.readUInt32()
        var attributes = SFTPAttributes()

        if flags & SFTPAttributeFlag.size != 0 {
            attributes.size = try reader.readUInt64()
        }
        if flags & SFTPAttributeFlag.uidgid != 0 {
            attributes.uid = try reader.readUInt32()
            attributes.gid = try reader.readUInt32()
        }
        if flags & SFTPAttributeFlag.permissions != 0 {
            attributes.permissions = try reader.readUInt32()
        }
        if flags & SFTPAttributeFlag.acmodtime != 0 {
            let accessed = try reader.readUInt32()
            let modified = try reader.readUInt32()
            attributes.accessedAt = Date(timeIntervalSince1970: TimeInterval(accessed))
            attributes.modifiedAt = Date(timeIntervalSince1970: TimeInterval(modified))
        }
        if flags & SFTPAttributeFlag.extended != 0 {
            let count = try reader.readUInt32()
            for _ in 0..<count {
                _ = try reader.readString()
                _ = try reader.readString()
            }
        }

        return attributes
    }
}

public enum SFTPAttributeFlag {
    public static let size: UInt32 = 0x00000001
    public static let uidgid: UInt32 = 0x00000002
    public static let permissions: UInt32 = 0x00000004
    public static let acmodtime: UInt32 = 0x00000008
    public static let extended: UInt32 = 0x80000000
}

public struct SFTPNameEntry: Equatable, Sendable {
    public var filename: String
    public var longname: String
    public var attributes: SFTPAttributes

    public init(filename: String, longname: String, attributes: SFTPAttributes) {
        self.filename = filename
        self.longname = longname
        self.attributes = attributes
    }
}

public enum SFTPNameParser {
    public static func parseNamePacketPayload(_ payload: Data) throws -> [SFTPNameEntry] {
        var reader = SFTPDataReader(data: payload)
        let count = try reader.readUInt32()
        var entries: [SFTPNameEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0..<count {
            let filename = try reader.readString()
            let longname = try reader.readString()
            let attrs = try SFTPAttributes.parse(from: &reader)
            if filename != "." && filename != ".." {
                entries.append(SFTPNameEntry(filename: filename, longname: longname, attributes: attrs))
            }
        }
        return entries
    }
}
