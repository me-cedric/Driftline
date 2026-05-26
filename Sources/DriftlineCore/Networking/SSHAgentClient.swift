import Foundation
import Darwin

public struct SSHAgentIdentity: Sendable {
    public var keyBlob: Data
    public var comment: String
    public var keyType: String

    public init(keyBlob: Data, comment: String, keyType: String) {
        self.keyBlob = keyBlob
        self.comment = comment
        self.keyType = keyType
    }
}

public actor SSHAgentClient {
    private let socketPath: String
    private let socketFD: Int32

    public init?(socketPath: String = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] ?? "") {
        guard !socketPath.isEmpty else { return nil }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return nil
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { src in
                buffer.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: min(src.count, buffer.count)))
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(fd)
            return nil
        }

        self.socketPath = socketPath
        self.socketFD = fd
    }

    deinit {
        Darwin.close(socketFD)
    }

    public func listIdentities() async throws -> [SSHAgentIdentity] {
        let request = buildFrame(type: 11, payload: Data())
        try writeAll(request)

        let response = try readFrame()
        guard let firstByte = response.first, firstByte == 12 else {
            throw SSHAgentError.unexpectedResponse(response.first.map { Int($0) } ?? -1)
        }

        var cursor = 1
        let count = try readUInt32(from: response, at: &cursor)
        var identities: [SSHAgentIdentity] = []
        identities.reserveCapacity(Int(count))

        for _ in 0..<count {
            let keyBlob = try readBString(from: response, at: &cursor)
            let comment = try readString(from: response, at: &cursor)
            let keyType = parseKeyType(from: keyBlob)
            identities.append(SSHAgentIdentity(keyBlob: keyBlob, comment: comment, keyType: keyType))
        }
        return identities
    }

    public func sign(keyBlob: Data, data: Data, flags: UInt32 = 0) async throws -> Data {
        var payload = Data()
        payload.append(contentsOf: encodeBString(keyBlob))
        payload.append(contentsOf: encodeBString(data))
        payload.append(contentsOf: encodeUInt32(flags))

        let request = buildFrame(type: 13, payload: payload)
        try writeAll(request)

        let response = try readFrame()
        guard let firstByte = response.first else {
            throw SSHAgentError.unexpectedResponse(-1)
        }
        if firstByte == 5 {
            throw SSHAgentError.agentFailure
        }
        guard firstByte == 14 else {
            throw SSHAgentError.unexpectedResponse(Int(firstByte))
        }

        var cursor = 1
        let signature = try readBString(from: response, at: &cursor)
        return signature
    }

    private func buildFrame(type: UInt8, payload: Data) -> Data {
        let length = UInt32(1 + payload.count)
        var frame = Data()
        frame.append(contentsOf: encodeUInt32(length))
        frame.append(type)
        frame.append(payload)
        return frame
    }

    private func writeAll(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { buffer in
                Darwin.send(socketFD, buffer.baseAddress!.advanced(by: offset), data.count - offset, 0)
            }
            if sent <= 0 { throw SSHAgentError.socketWriteFailed }
            offset += sent
        }
    }

    private func readExact(count: Int) throws -> Data {
        var buffer = Data(count: count)
        var received = 0
        while received < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.recv(socketFD, ptr.baseAddress!.advanced(by: received), count - received, 0)
            }
            if n <= 0 { throw SSHAgentError.socketReadFailed }
            received += n
        }
        return buffer
    }

    private func readFrame() throws -> Data {
        let lengthData = try readExact(count: 4)
        var length: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &length) { lengthData.copyBytes(to: $0) }
        length = UInt32(bigEndian: length)
        guard length > 0, length <= 65536 else { throw SSHAgentError.invalidFrameLength(Int(length)) }
        return try readExact(count: Int(length))
    }

    private func readUInt32(from data: Data, at cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw SSHAgentError.malformedResponse }
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: cursor..<(cursor + 4)) }
        cursor += 4
        return UInt32(bigEndian: value)
    }

    private func readBString(from data: Data, at cursor: inout Int) throws -> Data {
        let length = try readUInt32(from: data, at: &cursor)
        guard cursor + Int(length) <= data.count else { throw SSHAgentError.malformedResponse }
        let slice = data[cursor..<(cursor + Int(length))]
        cursor += Int(length)
        return Data(slice)
    }

    private func readString(from data: Data, at cursor: inout Int) throws -> String {
        let raw = try readBString(from: data, at: &cursor)
        return String(decoding: raw, as: UTF8.self)
    }

    private func encodeUInt32(_ value: UInt32) -> [UInt8] {
        let big = value.bigEndian
        return withUnsafeBytes(of: big) { Array($0) }
    }

    private func encodeBString(_ data: Data) -> Data {
        var result = Data()
        result.append(contentsOf: encodeUInt32(UInt32(data.count)))
        result.append(data)
        return result
    }

    private func parseKeyType(from keyBlob: Data) -> String {
        var cursor = 0
        guard let typeData = try? readBString(from: keyBlob, at: &cursor) else { return "unknown" }
        return String(decoding: typeData, as: UTF8.self)
    }
}

public enum SSHAgentError: Error, Equatable, LocalizedError {
    case socketWriteFailed
    case socketReadFailed
    case unexpectedResponse(Int)
    case agentFailure
    case malformedResponse
    case invalidFrameLength(Int)

    public var errorDescription: String? {
        switch self {
        case .socketWriteFailed: "Failed to write to SSH agent socket."
        case .socketReadFailed: "Failed to read from SSH agent socket."
        case .unexpectedResponse(let code): "SSH agent returned unexpected message type \(code)."
        case .agentFailure: "SSH agent refused the operation."
        case .malformedResponse: "SSH agent response was malformed."
        case .invalidFrameLength(let len): "SSH agent sent an invalid frame length: \(len)."
        }
    }
}
