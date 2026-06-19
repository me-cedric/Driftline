import Foundation

public struct SyncDifference: Identifiable, Sendable, Equatable {
    public var id: String {
        self.name
    }

    public var name: String
    public var local: FileItem
    public var remote: FileItem

    public init(name: String, local: FileItem, remote: FileItem) {
        self.name = name
        self.local = local
        self.remote = remote
    }

    public var reason: String {
        if self.local.kind != self.remote.kind {
            return "Type differs"
        }
        if self.local.size != self.remote.size {
            if let localSize = self.local.size, let remoteSize = self.remote.size {
                let delta = localSize - remoteSize
                let sign = delta >= 0 ? "+" : "-"
                return "Size differs: local \(Self.formatBytes(localSize)), remote \(Self.formatBytes(remoteSize)), delta \(sign)\(Self.formatBytes(abs(delta)))"
            }
            return "Size differs: one side has unknown size"
        }
        return "Metadata differs"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct SyncPreview: Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var localPath: String
    public var remotePath: String
    public var localOnly: [FileItem]
    public var remoteOnly: [FileItem]
    public var changed: [SyncDifference]
    public var matchingCount: Int

    public init(localPath: String, remotePath: String, localItems: [FileItem], remoteItems: [FileItem]) {
        self.localPath = localPath
        self.remotePath = remotePath
        let localByName = Dictionary(uniqueKeysWithValues: localItems.map { ($0.name, $0) })
        let remoteByName = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.name, $0) })
        let names = Set(localByName.keys).union(remoteByName.keys)

        var localOnly: [FileItem] = []
        var remoteOnly: [FileItem] = []
        var changed: [SyncDifference] = []
        var matchingCount = 0

        for name in names.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            switch (localByName[name], remoteByName[name]) {
            case let (.some(local), .some(remote)):
                if Self.matches(local, remote) {
                    matchingCount += 1
                } else {
                    changed.append(SyncDifference(name: name, local: local, remote: remote))
                }
            case let (.some(local), .none):
                localOnly.append(local)
            case let (.none, .some(remote)):
                remoteOnly.append(remote)
            case (.none, .none):
                break
            }
        }

        self.localOnly = localOnly
        self.remoteOnly = remoteOnly
        self.changed = changed
        self.matchingCount = matchingCount
    }

    private static func matches(_ local: FileItem, _ remote: FileItem) -> Bool {
        guard local.kind == remote.kind else { return false }
        guard local.kind == .file else { return true }
        return local.size == remote.size
    }
}
