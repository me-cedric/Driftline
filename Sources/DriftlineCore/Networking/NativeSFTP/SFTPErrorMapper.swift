import Foundation

public enum SFTPStatusCode: UInt32, Codable, Sendable {
    case ok = 0
    case eof = 1
    case noSuchFile = 2
    case permissionDenied = 3
    case failure = 4
    case badMessage = 5
    case noConnection = 6
    case connectionLost = 7
    case operationUnsupported = 8
}

public struct SFTPStatus: Equatable, Sendable {
    public var code: SFTPStatusCode
    public var message: String
    public var language: String

    public init(code: SFTPStatusCode, message: String = "", language: String = "") {
        self.code = code
        self.message = message
        self.language = language
    }

    public static func parse(payload: Data) throws -> SFTPStatus {
        var reader = SFTPDataReader(data: payload)
        let rawCode = try reader.readUInt32()
        let code = SFTPStatusCode(rawValue: rawCode) ?? .failure
        let message = reader.remainingCount > 0 ? try reader.readString() : ""
        let language = reader.remainingCount > 0 ? try reader.readString() : ""
        return SFTPStatus(code: code, message: message, language: language)
    }

    public func remoteError(fallbackPath: String? = nil) -> RemoteClientError? {
        switch code {
        case .ok, .eof:
            return nil
        case .noSuchFile:
            return .commandFailed(message.isEmpty ? "Remote file not found\(fallbackPath.map { ": \($0)" } ?? "")." : message)
        case .permissionDenied:
            return .commandFailed(message.isEmpty ? "Permission denied." : message)
        case .operationUnsupported:
            return .unsupportedAuthentication(message.isEmpty ? "The SFTP server does not support this operation." : message)
        case .failure, .badMessage, .noConnection, .connectionLost:
            return .commandFailed(message.isEmpty ? "SFTP operation failed." : message)
        }
    }
}

