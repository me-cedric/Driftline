import Foundation

public enum RemoteFileCommandBuilder {
    public static func createFolderCommand(name: String, in path: String) -> String {
        "mkdir -- \(SSHCommandBuilder.shellSingleQuoted(join(path, name)))"
    }

    public static func renameCommand(path: String, newName: String) -> String {
        let destination = join(URL(fileURLWithPath: path).deletingLastPathComponent().path, newName)
        return "mv -- \(SSHCommandBuilder.shellSingleQuoted(path)) \(SSHCommandBuilder.shellSingleQuoted(destination))"
    }

    public static func deleteCommand(path: String) -> String {
        "rm -rf -- \(SSHCommandBuilder.shellSingleQuoted(path))"
    }

    public static func existsCommand(path: String) -> String {
        "test -e \(SSHCommandBuilder.shellSingleQuoted(path))"
    }

    public static func join(_ base: String, _ name: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? "/\(name)" : "\(trimmed)/\(name)"
    }
}
