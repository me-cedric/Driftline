import Foundation

public struct ViewPreferences: Codable, Equatable, Sendable {
    public var fileList: FileListPreferences
    public var showInspector: Bool
    public var showTransferQueue: Bool
    public var showSidebar: Bool
    public var transferConcurrency: Int
    public var confirmBeforeDelete: Bool
    public var confirmBeforeOverwrite: Bool
    public var remoteBackendKind: RemoteBackendKind

    enum CodingKeys: String, CodingKey {
        case fileList
        case showInspector
        case showTransferQueue
        case showSidebar
        case transferConcurrency
        case confirmBeforeDelete
        case confirmBeforeOverwrite
        case remoteBackendKind
    }

    public init(
        fileList: FileListPreferences = FileListPreferences(),
        showInspector: Bool = true,
        showTransferQueue: Bool = true,
        showSidebar: Bool = true,
        transferConcurrency: Int = 3,
        confirmBeforeDelete: Bool = true,
        confirmBeforeOverwrite: Bool = true,
        remoteBackendKind: RemoteBackendKind = .systemSSH
    ) {
        self.fileList = fileList
        self.showInspector = showInspector
        self.showTransferQueue = showTransferQueue
        self.showSidebar = showSidebar
        self.transferConcurrency = transferConcurrency
        self.confirmBeforeDelete = confirmBeforeDelete
        self.confirmBeforeOverwrite = confirmBeforeOverwrite
        self.remoteBackendKind = remoteBackendKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileList = try container.decodeIfPresent(FileListPreferences.self, forKey: .fileList) ?? FileListPreferences()
        self.showInspector = try container.decodeIfPresent(Bool.self, forKey: .showInspector) ?? true
        self.showTransferQueue = try container.decodeIfPresent(Bool.self, forKey: .showTransferQueue) ?? true
        self.showSidebar = try container.decodeIfPresent(Bool.self, forKey: .showSidebar) ?? true
        self.transferConcurrency = try container.decodeIfPresent(Int.self, forKey: .transferConcurrency) ?? 3
        self.confirmBeforeDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeDelete) ?? true
        self.confirmBeforeOverwrite = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeOverwrite) ?? true
        self.remoteBackendKind = try container.decodeIfPresent(RemoteBackendKind.self, forKey: .remoteBackendKind) ?? .systemSSH
    }
}
