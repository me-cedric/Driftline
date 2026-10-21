import Foundation

/// TLS mode of an FTP profile. Without an explicit choice, FTPS on port 990 is implicit TLS and any other port is explicit TLS (AUTH TLS).
public enum FTPSecurityMode: Equatable, Sendable {
    case none
    case explicitTLS
    case implicitTLS

    public init(profile: ServerProfile) {
        switch profile.protocolKind {
        case .ftp, .sftp:
            self = .none
        case .ftps:
            self = (profile.implicitTLS ?? (profile.port == 990)) ? .implicitTLS : .explicitTLS
        }
    }
}

public struct FTPReply: Equatable, Sendable {
    public var code: Int
    public var text: String

    public var isPositive: Bool {
        (100 ..< 400).contains(self.code)
    }
}

public enum FTPCommandBuilder {
    /// Path for an FTP command. A new session starts in the login folder, so `~` maps to a relative path.
    public static func commandPath(_ path: String) throws -> String {
        guard !path.contains(where: \.isNewline) else {
            throw RemoteClientError.commandFailed("File names with line breaks are not supported.")
        }
        if path == "~" || path == "~/" {
            return "."
        }
        return path.hasPrefix("~/") ? String(path.dropFirst(2)) : path
    }

    /// `227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)`. Only the port is used: the host is the control host,
    /// because servers behind NAT often report a private address.
    public static func passivePort(from reply: FTPReply) -> Int? {
        guard reply.code == 227,
              let open = reply.text.firstIndex(of: "("),
              let close = reply.text[open...].firstIndex(of: ")")
        else { return nil }
        let numbers = reply.text[reply.text.index(after: open) ..< close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 6 else { return nil }
        return numbers[4] * 256 + numbers[5]
    }

    /// `229 Entering Extended Passive Mode (|||port|)`.
    public static func extendedPassivePort(from reply: FTPReply) -> Int? {
        guard reply.code == 229, let open = reply.text.firstIndex(of: "("), let close = reply.text.lastIndex(of: ")") else { return nil }
        let fields = reply.text[reply.text.index(after: open) ..< close].split(separator: "|", omittingEmptySubsequences: true)
        return fields.last.flatMap { Int($0) }
    }

    public static func error(for reply: FTPReply) -> RemoteClientError {
        let text = Redactor().redact(reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let lowered = text.lowercased()
        switch reply.code {
        case 530 where lowered.contains("tls") || lowered.contains("ssl") || lowered.contains("encrypt"):
            return .connectionFailed("The server requires an encrypted connection. Choose FTPS. (\(reply.code) \(text))")
        case 530:
            return .authenticationFailed
        case 421:
            return .connectionFailed("\(reply.code) \(text)")
        default:
            return .commandFailed("\(reply.code) \(text)")
        }
    }
}

/// Parses FTP LIST output in the Unix `ls -l` style and the Windows/IIS (DOS) style.
public enum FTPListParser {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dosRegex = try? NSRegularExpression(
        pattern: #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?\s+(<DIR>|\d+)\s+(.+)$"#
    )

    public static func parse(_ output: String, directory: String, preferences: FileListPreferences, now: Date = Date()) -> [FileItem] {
        let items = output.split(whereSeparator: \.isNewline).compactMap { line -> FileItem? in
            let line = String(line)
            return self.unixItem(line, directory: directory, now: now) ?? self.dosItem(line, directory: directory)
        }
        .filter { preferences.showHiddenFiles || !$0.isHidden }
        return FileItemSorter.sort(items, preferences: preferences)
    }

    static func unixItem(_ line: String, directory: String, now: Date) -> FileItem? {
        guard let first = line.first, "-dlcbps".contains(first) else { return nil }
        var tokens: [(text: Substring, end: String.Index)] = []
        var index = line.startIndex
        while index < line.endIndex, tokens.count < 9 {
            guard let start = line[index...].firstIndex(where: { $0 != " " }) else { break }
            let end = line[start...].firstIndex(of: " ") ?? line.endIndex
            tokens.append((line[start ..< end], end))
            index = end
        }
        // The date is the first "month day time-or-year" triple after a numeric size.
        guard let monthIndex = tokens.indices.dropFirst(2).first(where: { position in
            position + 2 < tokens.count
                && self.months.contains(tokens[position].text.lowercased())
                && Int(tokens[position + 1].text) != nil
                && Int64(tokens[position - 1].text) != nil
        }) else { return nil }
        var name = String(line[tokens[monthIndex + 2].end...].dropFirst())
        let kind: FileItemKind = switch first {
        case "d": .folder
        case "-": .file
        case "l": .symbolicLink
        default: .unknown
        }
        if kind == .symbolicLink, let arrow = name.range(of: " -> ") {
            name = String(name[..<arrow.lowerBound])
        }
        guard FileItem.isSafeRemoteName(name) else { return nil }
        let month = (self.months.firstIndex(of: tokens[monthIndex].text.lowercased()) ?? 0) + 1
        return FileItem(
            name: name,
            path: SFTPBatchCommandBuilder.join(directory, name),
            kind: kind,
            size: Int64(tokens[monthIndex - 1].text),
            modifiedAt: SFTPLongListingParser.date(month: month, day: Int(tokens[monthIndex + 1].text) ?? 1, timeOrYear: String(tokens[monthIndex + 2].text), now: now),
            permissions: String(tokens[0].text),
            owner: monthIndex >= 4 ? String(tokens[2].text) : nil,
            group: monthIndex >= 5 ? String(tokens[3].text) : nil,
            source: .remote,
            isHidden: name.hasPrefix(".")
        )
    }

    static func dosItem(_ line: String, directory: String) -> FileItem? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard let match = dosRegex?.firstMatch(in: line, range: range) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: line).map { String(line[$0]) }
        }
        guard let month = group(1).flatMap(Int.init), let day = group(2).flatMap(Int.init), var year = group(3).flatMap(Int.init),
              var hour = group(4).flatMap(Int.init), let minute = group(5).flatMap(Int.init), let sizeField = group(7), let name = group(8)
        else { return nil }
        if year < 100 {
            year += year < 70 ? 2000 : 1900
        }
        switch group(6)?.lowercased() {
        case "pm" where hour < 12: hour += 12
        case "am" where hour == 12: hour = 0
        default: break
        }
        guard FileItem.isSafeRemoteName(name) else { return nil }
        let isFolder = sizeField == "<DIR>"
        return FileItem(
            name: name,
            path: SFTPBatchCommandBuilder.join(directory, name),
            kind: isFolder ? .folder : .file,
            size: isFolder ? nil : Int64(sizeField),
            modifiedAt: Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)),
            source: .remote,
            isHidden: name.hasPrefix(".")
        )
    }
}
