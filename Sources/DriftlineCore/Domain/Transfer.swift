import Foundation

public enum TransferDirection: String, Codable, Sendable {
    case upload
    case download

    public var localizedTitle: String {
        switch self {
        case .upload:
            LocalizationManager.shared.localized("browser.upload")
        case .download:
            LocalizationManager.shared.localized("browser.download")
        }
    }
}

public enum TransferStatus: Equatable, Codable, Sendable {
    case queued
    case running(progress: Double, bytesPerSecond: Int64?)
    case succeeded
    case failed(message: String)
    case cancelled
}

public struct TransferJob: Identifiable, Codable, Sendable {
    public var id: TransferJobID
    public var direction: TransferDirection
    public var sourcePath: String
    public var destinationPath: String
    public var byteCount: Int64?
    public var isFolder: Bool
    public var status: TransferStatus
    public var serverName: String?
    public var profileID: ServerProfileID?
    public var protocolKind: TransferProtocolKind?
    public var backendKind: RemoteBackendKind?
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: TransferJobID = TransferJobID(),
        direction: TransferDirection,
        sourcePath: String,
        destinationPath: String,
        byteCount: Int64? = nil,
        isFolder: Bool = false,
        status: TransferStatus = .queued,
        serverName: String? = nil,
        profileID: ServerProfileID? = nil,
        protocolKind: TransferProtocolKind? = nil,
        backendKind: RemoteBackendKind? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.direction = direction
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.byteCount = byteCount
        self.isFolder = isFolder
        self.status = status
        self.serverName = serverName
        self.profileID = profileID
        self.protocolKind = protocolKind
        self.backendKind = backendKind
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, direction, sourcePath, destinationPath, byteCount, isFolder
        case status, serverName, profileID, protocolKind, backendKind, createdAt, startedAt, finishedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(TransferJobID.self, forKey: .id)
        self.direction = try c.decode(TransferDirection.self, forKey: .direction)
        self.sourcePath = try c.decode(String.self, forKey: .sourcePath)
        self.destinationPath = try c.decode(String.self, forKey: .destinationPath)
        self.byteCount = try c.decodeIfPresent(Int64.self, forKey: .byteCount)
        self.isFolder = try c.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false
        self.status = try c.decode(TransferStatus.self, forKey: .status)
        self.serverName = try c.decodeIfPresent(String.self, forKey: .serverName)
        self.profileID = try c.decodeIfPresent(ServerProfileID.self, forKey: .profileID)
        self.protocolKind = try c.decodeIfPresent(TransferProtocolKind.self, forKey: .protocolKind)
        self.backendKind = try c.decodeIfPresent(RemoteBackendKind.self, forKey: .backendKind)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}

public struct TransferStats: Equatable, Codable, Sendable {
    public var uploadCount: Int
    public var downloadCount: Int
    public var bytesUploaded: Int64
    public var bytesDownloaded: Int64
    public var successfulTransfers: Int
    public var failedTransfers: Int
    public var activeTransfers: Int
    public var queuedTransfers: Int

    public init(
        uploadCount: Int = 0,
        downloadCount: Int = 0,
        bytesUploaded: Int64 = 0,
        bytesDownloaded: Int64 = 0,
        successfulTransfers: Int = 0,
        failedTransfers: Int = 0,
        activeTransfers: Int = 0,
        queuedTransfers: Int = 0
    ) {
        self.uploadCount = uploadCount
        self.downloadCount = downloadCount
        self.bytesUploaded = bytesUploaded
        self.bytesDownloaded = bytesDownloaded
        self.successfulTransfers = successfulTransfers
        self.failedTransfers = failedTransfers
        self.activeTransfers = activeTransfers
        self.queuedTransfers = queuedTransfers
    }
}

public enum TransferStatsCalculator {
    public static func calculate(from jobs: [TransferJob]) -> TransferStats {
        var stats = TransferStats()
        for job in jobs {
            switch job.direction {
            case .upload:
                stats.uploadCount += 1
                if case .succeeded = job.status {
                    stats.bytesUploaded += job.byteCount ?? 0
                }
            case .download:
                stats.downloadCount += 1
                if case .succeeded = job.status {
                    stats.bytesDownloaded += job.byteCount ?? 0
                }
            }

            switch job.status {
            case .queued:
                stats.queuedTransfers += 1
            case .running:
                stats.activeTransfers += 1
            case .succeeded:
                stats.successfulTransfers += 1
            case .failed:
                stats.failedTransfers += 1
            case .cancelled:
                break
            }
        }
        return stats
    }
}
