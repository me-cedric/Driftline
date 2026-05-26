import Foundation

public struct FoundationLocalFileSystemClient: LocalFileSystemClient {
    public init() {}

    public func listDirectory(at path: String, preferences: FileListPreferences) async throws -> [FileItem] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .typeIdentifierKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])
        let mapped = try urls.compactMap { itemURL -> FileItem? in
            let values = try itemURL.resourceValues(forKeys: keys)
            let isHidden = values.isHidden ?? itemURL.lastPathComponent.hasPrefix(".")
            if isHidden && !preferences.showHiddenFiles { return nil }
            let kind: FileItemKind
            if values.isDirectory == true {
                kind = .folder
            } else if values.isSymbolicLink == true {
                kind = .symbolicLink
            } else {
                kind = .file
            }
            return FileItem(
                name: itemURL.lastPathComponent,
                path: itemURL.path,
                kind: kind,
                size: values.fileSize.map(Int64.init),
                modifiedAt: values.contentModificationDate,
                source: .local,
                isHidden: isHidden
            )
        }
        return FileItemSorter.sort(mapped, preferences: preferences)
    }

    public func createFolder(named name: String, in path: String) async throws {
        let url = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    public func renameItem(at path: String, to newName: String) async throws {
        let source = URL(fileURLWithPath: path)
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func deleteItem(at path: String) async throws {
        try FileManager.default.removeItem(atPath: path)
    }

    public func itemExists(at path: String) async -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public enum FileItemSorter {
    public static func sort(_ items: [FileItem], preferences: FileListPreferences) -> [FileItem] {
        items.sorted { lhs, rhs in
            if preferences.foldersFirst, lhs.kind != rhs.kind {
                if lhs.kind == .folder { return true }
                if rhs.kind == .folder { return false }
            }
            let ascendingResult: Bool
            switch preferences.sortKey {
            case .name:
                ascendingResult = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                ascendingResult = (lhs.size ?? -1) < (rhs.size ?? -1)
            case .type:
                ascendingResult = lhs.kind.rawValue < rhs.kind.rawValue
            case .modifiedAt:
                ascendingResult = (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
            }
            return preferences.sortAscending ? ascendingResult : !ascendingResult
        }
    }
}
