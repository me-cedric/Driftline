import Foundation

public enum SFTPOpenPFlags {
    public static let read: UInt32 = 0x0000_0001
    public static let write: UInt32 = 0x0000_0002
    public static let append: UInt32 = 0x0000_0004
    public static let create: UInt32 = 0x0000_0008
    public static let truncate: UInt32 = 0x0000_0010
    public static let exclusive: UInt32 = 0x0000_0020
}

public enum SFTPRequestBuilder {
    public static func initialize(version: UInt32 = 3) -> SFTPPacket {
        var payload = Data()
        payload.appendUInt32(version)
        return SFTPPacket(type: .initialize, payload: payload)
    }

    public static func opendir(id: UInt32, path: String) -> SFTPPacket {
        var payload = Data()
        payload.appendString(path)
        return SFTPPacket(type: .opendir, requestID: id, payload: payload)
    }

    public static func realpath(id: UInt32, path: String) -> SFTPPacket {
        var payload = Data()
        payload.appendString(path)
        return SFTPPacket(type: .realpath, requestID: id, payload: payload)
    }

    public static func readdir(id: UInt32, handle: Data) -> SFTPPacket {
        var payload = Data()
        payload.appendBinaryString(handle)
        return SFTPPacket(type: .readdir, requestID: id, payload: payload)
    }

    public static func close(id: UInt32, handle: Data) -> SFTPPacket {
        var payload = Data()
        payload.appendBinaryString(handle)
        return SFTPPacket(type: .close, requestID: id, payload: payload)
    }

    public static func mkdir(id: UInt32, path: String) -> SFTPPacket {
        var payload = Data()
        payload.appendString(path)
        payload.appendUInt32(0)
        return SFTPPacket(type: .mkdir, requestID: id, payload: payload)
    }

    public static func rename(id: UInt32, oldPath: String, newPath: String) -> SFTPPacket {
        var payload = Data()
        payload.appendString(oldPath)
        payload.appendString(newPath)
        return SFTPPacket(type: .rename, requestID: id, payload: payload)
    }

    public static func remove(id: UInt32, path: String) -> SFTPPacket {
        self.pathOnlyPacket(type: .remove, id: id, path: path)
    }

    public static func rmdir(id: UInt32, path: String) -> SFTPPacket {
        self.pathOnlyPacket(type: .rmdir, id: id, path: path)
    }

    public static func stat(id: UInt32, path: String) -> SFTPPacket {
        self.pathOnlyPacket(type: .stat, id: id, path: path)
    }

    public static func lstat(id: UInt32, path: String) -> SFTPPacket {
        self.pathOnlyPacket(type: .lstat, id: id, path: path)
    }

    public static func open(id: UInt32, path: String, pflags: UInt32) -> SFTPPacket {
        var payload = Data()
        payload.appendString(path)
        payload.appendUInt32(pflags)
        payload.appendUInt32(0)
        return SFTPPacket(type: .open, requestID: id, payload: payload)
    }

    public static func read(id: UInt32, handle: Data, offset: UInt64, length: UInt32) -> SFTPPacket {
        var payload = Data()
        payload.appendBinaryString(handle)
        payload.appendUInt64(offset)
        payload.appendUInt32(length)
        return SFTPPacket(type: .read, requestID: id, payload: payload)
    }

    public static func write(id: UInt32, handle: Data, offset: UInt64, data: Data) -> SFTPPacket {
        var payload = Data()
        payload.appendBinaryString(handle)
        payload.appendUInt64(offset)
        payload.appendBinaryString(data)
        return SFTPPacket(type: .write, requestID: id, payload: payload)
    }

    private static func pathOnlyPacket(type: SFTPPacketType, id: UInt32, path: String) -> SFTPPacket {
        var payload = Data()
        payload.appendString(path)
        return SFTPPacket(type: type, requestID: id, payload: payload)
    }
}
