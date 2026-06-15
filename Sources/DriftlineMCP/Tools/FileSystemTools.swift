import DriftlineCore
import Foundation

// MARK: - FileSystemTools

/// Handlers for remote filesystem tools.
public enum FileSystemTools {
    // MARK: driftline.listDirectory

    public static func listDirectory(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }
        let showHidden = arguments["showHidden"]?.boolValue ?? false
        let prefs = FileListPreferences(showHiddenFiles: showHidden)

        do {
            let items = try await context.remoteFileSystem.listDirectory(
                at: path,
                profile: entry.profile,
                session: entry.session,
                preferences: prefs
            )
            let itemsJSON: [JSONValue] = items.map { self.fileItemJSON($0) }
            return .success(.object(["path": .string(path), "items": .array(itemsJSON)]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: driftline.listLocal

    public static func listLocal(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }

        let validatedPath: String
        do {
            validatedPath = try context.sandbox.validatedPath(path)
        } catch let e as SandboxError {
            if case let .notAllowed(path, roots) = e {
                return .toolError(
                    code: MCPToolErrorCode.pathNotAllowed,
                    message: "Local path is outside allowed roots.",
                    data: .object(["path": .string(path), "allowedRoots": .array(roots.map { .string($0) })])
                )
            }
            return .toolError(code: MCPToolErrorCode.pathNotAllowed, message: "Path not allowed.")
        } catch {
            return .toolError(code: MCPToolErrorCode.pathNotAllowed, message: "Path validation failed.")
        }

        let showHidden = arguments["showHidden"]?.boolValue ?? false
        do {
            let items = try await context.localFileSystem.listDirectory(
                at: validatedPath,
                preferences: FileListPreferences(showHiddenFiles: showHidden)
            )
            let itemsJSON: [JSONValue] = items.map { self.fileItemJSON($0) }
            return .success(.object(["path": .string(validatedPath), "items": .array(itemsJSON)]))
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: driftline.stat

    public static func stat(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        do {
            let exists = try await context.remoteFileSystem.itemExists(at: path, profile: entry.profile, session: entry.session)
            if !exists {
                return .success(.object(["exists": .bool(false), "item": .null]))
            }
            // Try to get metadata by listing the parent directory and matching the name.
            let url = URL(fileURLWithPath: path)
            let parentPath = url.deletingLastPathComponent().path
            let name = url.lastPathComponent
            let items = await (try? context.remoteFileSystem.listDirectory(
                at: parentPath,
                profile: entry.profile,
                session: entry.session,
                preferences: FileListPreferences(showHiddenFiles: true)
            )) ?? []
            if let match = items.first(where: { $0.name == name }) {
                return .success(.object(["exists": .bool(true), "item": self.fileItemJSON(match)]))
            }
            return .success(.object(["exists": .bool(true), "item": .null]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: driftline.createFolder

    public static func createFolder(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "name is required.", data: .object(["field": .string("name")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        do {
            try await context.remoteFileSystem.createFolder(named: name, in: path, profile: entry.profile, session: entry.session)
            let fullPath = (path as NSString).appendingPathComponent(name)
            return .success(.object(["ok": .bool(true), "path": .string(fullPath)]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: driftline.rename

    public static func rename(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }
        guard let newName = arguments["newName"]?.stringValue, !newName.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "newName is required.", data: .object(["field": .string("newName")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        do {
            try await context.remoteFileSystem.renameItem(at: path, to: newName, profile: entry.profile, session: entry.session)
            let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let newPath = (parentPath as NSString).appendingPathComponent(newName)
            return .success(.object(["ok": .bool(true), "path": .string(newPath)]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: driftline.delete

    public static func delete(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        // Capability gate.
        guard context.configuration.allowDestructiveOperations else {
            return .toolError(
                code: MCPToolErrorCode.capabilityDenied,
                message: "delete requires allowDestructiveOperations to be enabled.",
                data: .object(["operation": .string("delete"), "requiredFlag": .string("allowDestructiveOperations")])
            )
        }
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let path = arguments["path"]?.stringValue, !path.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "path is required.", data: .object(["field": .string("path")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        do {
            try await context.remoteFileSystem.deleteItem(at: path, profile: entry.profile, session: entry.session)
            return .success(.object(["ok": .bool(true), "path": .string(path)]))
        } catch let clientError as RemoteClientError {
            return remoteClientToolError(clientError)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }

    // MARK: Helpers

    private static func fileItemJSON(_ item: FileItem) -> JSONValue {
        var obj: [String: JSONValue] = [
            "name": .string(item.name),
            "path": .string(item.path),
            "kind": .string(item.kind.rawValue),
            "isHidden": .bool(item.isHidden),
        ]
        if let size = item.size {
            obj["size"] = .int(Int(size))
        } else {
            obj["size"] = .null
        }
        if let modifiedAt = item.modifiedAt {
            obj["modifiedAt"] = .string(ISO8601DateFormatter().string(from: modifiedAt))
        } else {
            obj["modifiedAt"] = .null
        }
        if let permissions = item.permissions {
            obj["permissions"] = .string(permissions)
        } else {
            obj["permissions"] = .null
        }
        return .object(obj)
    }
}
