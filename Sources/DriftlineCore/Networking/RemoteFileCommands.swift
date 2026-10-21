import Foundation

/// Commands for `sftp -b -`. They use the SFTP subsystem only, so they also work on servers without a shell (chroot, internal-sftp, managed transfer servers).
public enum SFTPBatchCommandBuilder {
    public static func listCommands(path: String) throws -> String {
        try self.changeDirectory(path) + "pwd\nls -lan\n"
    }

    public static func createFolderCommand(name: String, in path: String) throws -> String {
        try "mkdir \(self.quoted(self.join(path, name)))\n"
    }

    public static func renameCommand(path: String, newName: String) throws -> String {
        let destination = self.join(self.parentPath(of: path), newName)
        return try "rename \(self.quoted(path)) \(self.quoted(destination))\n"
    }

    public static func removeFileCommand(path: String) throws -> String {
        try "rm \(self.quoted(path))\n"
    }

    public static func removeFolderCommand(path: String) throws -> String {
        try "rmdir \(self.quoted(path))\n"
    }

    public static func existsCommand(path: String) throws -> String {
        try "ls -lan \(self.quoted(path))\n"
    }

    public static func transferCommand(direction: TransferDirection, sourcePath: String, destinationPath: String, isFolder: Bool) throws -> String {
        guard isFolder else {
            switch direction {
            case .upload:
                return try "put \(self.localQuoted(sourcePath)) \(self.quoted(destinationPath))\n"
            case .download:
                return try "get \(self.quoted(sourcePath)) \(self.localQuoted(destinationPath))\n"
            }
        }
        // sftp copies a folder into the target when the target folder exists. With the same name, the parent is the
        // target, so the result is the same whether the folder exists or not.
        let sameName = (sourcePath as NSString).lastPathComponent == (destinationPath as NSString).lastPathComponent
        switch direction {
        case .upload:
            let target = sameName ? self.parentPath(of: destinationPath) : destinationPath
            return try "put -r \(self.localQuoted(sourcePath)) \(self.quoted(target))\n"
        case .download:
            let target = sameName ? (destinationPath as NSString).deletingLastPathComponent : destinationPath
            return try "get -r \(self.quoted(sourcePath)) \(self.localQuoted(target))\n"
        }
    }

    /// Quotes a remote path for the sftp batch parser. sftp starts in the login directory, so `~` maps to a relative path.
    public static func quoted(_ path: String) throws -> String {
        try self.quote(self.sftpPath(path))
    }

    public static func join(_ base: String, _ name: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? "/\(name)" : "\(trimmed)/\(name)"
    }

    public static func parentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        if trimmed == "~" {
            return "~"
        }
        if trimmed.hasPrefix("~/") {
            guard let slash = trimmed.lastIndex(of: "/") else { return "~" }
            return slash == trimmed.index(trimmed.startIndex, offsetBy: 1) ? "~" : String(trimmed[..<slash])
        }
        guard let slash = trimmed.lastIndex(of: "/") else { return "/" }
        if slash == trimmed.startIndex { return "/" }
        return String(trimmed[..<slash])
    }

    static func sftpPath(_ path: String) -> String {
        if path == "~" || path == "~/" {
            return "."
        }
        if path.hasPrefix("~/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private static func changeDirectory(_ path: String) throws -> String {
        self.sftpPath(path) == "." ? "" : try "cd \(self.quoted(path))\n"
    }

    private static func localQuoted(_ path: String) throws -> String {
        try self.quote(NSString(string: path).expandingTildeInPath)
    }

    private static func quote(_ value: String) throws -> String {
        // A line break would end the batch command and start a new one.
        guard !value.contains(where: \.isNewline) else {
            throw RemoteClientError.commandFailed("File names with line breaks are not supported.")
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Parses the output of `pwd` and `ls -lan` from `sftp -b`. With `-n`, sftp formats each line itself, so the layout does not depend on the server.
public enum SFTPLongListingParser {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func workingDirectory(in output: String) -> String? {
        let prefix = "Remote working directory: "
        return output.split(separator: "\n").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    public static func parse(_ output: String, directory: String, preferences: FileListPreferences, now: Date = Date()) -> [FileItem] {
        let items = output.split(separator: "\n").compactMap { self.item(from: String($0), directory: directory, now: now) }
            .filter { preferences.showHiddenFiles || !$0.isHidden }
        return FileItemSorter.sort(items, preferences: preferences)
    }

    static func item(from line: String, directory: String, now: Date) -> FileItem? {
        guard let first = line.first, "-dlcbps".contains(first), !line.hasPrefix("sftp> ") else { return nil }
        var tokens: [Substring] = []
        var rest = Substring(line)
        /// mode, links, owner, group, size, then month, day and time or year.
        func nextToken() -> Substring? {
            rest = rest.drop { $0 == " " }
            guard let end = rest.firstIndex(of: " ") else { return nil }
            defer { rest = rest[end...] }
            return rest[..<end]
        }
        for _ in 0 ..< 5 {
            guard let token = nextToken() else { return nil }
            tokens.append(token)
        }
        guard let size = Int64(tokens[4]) else { return nil }
        let afterSize = rest
        var modifiedAt: Date?
        let monthToken = nextToken(), dayToken = nextToken(), timeToken = nextToken()
        if let monthToken, let month = months.firstIndex(of: String(monthToken)), let dayToken, let day = Int(dayToken), let timeToken {
            modifiedAt = self.date(month: month + 1, day: day, timeOrYear: String(timeToken), now: now)
        } else {
            // A zero modification time prints no date: "size  name".
            rest = afterSize.dropFirst()
        }
        let name = String(rest.dropFirst())
        guard FileItem.isSafeRemoteName(name) else { return nil }

        let mode = String(tokens[0])
        let kind: FileItemKind = switch first {
        case "d": .folder
        case "-": .file
        case "l": .symbolicLink
        default: .unknown
        }
        return FileItem(
            name: name,
            path: SFTPBatchCommandBuilder.join(directory, name),
            kind: kind,
            size: size,
            modifiedAt: modifiedAt,
            permissions: mode,
            owner: String(tokens[2]),
            group: String(tokens[3]),
            source: .remote,
            isHidden: name.hasPrefix(".")
        )
    }

    /// ls style dates: `HH:MM` for the last six months (year is implied), else a year.
    static func date(month: Int, day: Int, timeOrYear: String, now: Date) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents(month: month, day: day)
        let parts = timeOrYear.split(separator: ":")
        if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
            components.hour = hour
            components.minute = minute
            components.year = calendar.component(.year, from: now)
            if let date = calendar.date(from: components), date > now.addingTimeInterval(86400) {
                components.year = (components.year ?? 0) - 1
            }
        } else if let year = Int(timeOrYear) {
            components.year = year
        } else {
            return nil
        }
        return calendar.date(from: components)
    }
}
