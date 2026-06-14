import Foundation

public enum RemoteFindParser {
    public static func parse(_ output: String, preferences: FileListPreferences) -> [FileItem] {
        let items = output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> FileItem? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7 else { return nil }
            let typeCode = String(fields[0])
            let size = Int64(fields[1])
            let modifiedAt = TimeInterval(fields[2]).map { Date(timeIntervalSince1970: $0) }
            let permissions = String(fields[3])
            let owner = String(fields[4])
            let group = String(fields[5])
            let path = fields[6...].joined(separator: "\t")
            let name = URL(fileURLWithPath: path).lastPathComponent
            let isHidden = name.hasPrefix(".")
            guard preferences.showHiddenFiles || !isHidden else { return nil }

            let kind: FileItemKind = switch typeCode {
            case "d": .folder
            case "f": .file
            case "l": .symbolicLink
            default: .unknown
            }

            return FileItem(
                name: name,
                path: path,
                kind: kind,
                size: size,
                modifiedAt: modifiedAt,
                permissions: permissions,
                owner: owner,
                group: group,
                source: .remote,
                isHidden: isHidden
            )
        }
        return FileItemSorter.sort(items, preferences: preferences)
    }
}
