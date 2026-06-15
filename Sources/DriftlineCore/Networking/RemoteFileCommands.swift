import Foundation

public enum RemoteFileCommandBuilder {
    public static func createFolderCommand(name: String, in path: String) -> String {
        "mkdir -- \(SSHCommandBuilder.remoteShellPathExpression(self.join(path, name)))"
    }

    public static func renameCommand(path: String, newName: String) -> String {
        let destination = self.join(self.parentPath(of: path), newName)
        return "mv -- \(SSHCommandBuilder.remoteShellPathExpression(path)) \(SSHCommandBuilder.remoteShellPathExpression(destination))"
    }

    public static func deleteCommand(path: String) -> String {
        "rm -rf -- \(SSHCommandBuilder.remoteShellPathExpression(path))"
    }

    public static func existsCommand(path: String) -> String {
        "test -e \(SSHCommandBuilder.remoteShellPathExpression(path))"
    }

    public static func join(_ base: String, _ name: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? "/\(name)" : "\(trimmed)/\(name)"
    }

    private static func parentPath(of path: String) -> String {
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
}
