import Foundation

public enum FileSource: String, Codable, Sendable {
    case local
    case remote
}

public enum FileItemKind: String, Codable, Sendable {
    case file
    case folder
    case symbolicLink
    case unknown
}

public struct FileItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        "\(self.source.rawValue):\(self.path)"
    }

    public var name: String
    public var path: String
    public var kind: FileItemKind
    public var size: Int64?
    public var modifiedAt: Date?
    public var permissions: String?
    public var owner: String?
    public var group: String?
    public var source: FileSource
    public var isHidden: Bool

    public init(
        name: String,
        path: String,
        kind: FileItemKind,
        size: Int64? = nil,
        modifiedAt: Date? = nil,
        permissions: String? = nil,
        owner: String? = nil,
        group: String? = nil,
        source: FileSource,
        isHidden: Bool = false
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.source = source
        self.isHidden = isHidden
    }
}

public enum FileSortKey: String, CaseIterable, Codable, Sendable {
    case name
    case size
    case type
    case modifiedAt
}

public struct FileListPreferences: Codable, Equatable, Sendable {
    public var showHiddenFiles: Bool
    public var showFileExtensions: Bool
    public var sortKey: FileSortKey
    public var sortAscending: Bool
    public var foldersFirst: Bool

    public init(
        showHiddenFiles: Bool = false,
        showFileExtensions: Bool = true,
        sortKey: FileSortKey = .name,
        sortAscending: Bool = true,
        foldersFirst: Bool = true
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.showFileExtensions = showFileExtensions
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        self.foldersFirst = foldersFirst
    }
}
