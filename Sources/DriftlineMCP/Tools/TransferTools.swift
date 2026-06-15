import DriftlineCore
import Foundation

// MARK: - TransferTools

/// Handlers for upload and download tools.
public enum TransferTools {
    // MARK: driftline.upload

    public static func upload(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let localPath = arguments["localPath"]?.stringValue, !localPath.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "localPath is required.", data: .object(["field": .string("localPath")]))
        }
        guard let remotePath = arguments["remotePath"]?.stringValue, !remotePath.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "remotePath is required.", data: .object(["field": .string("remotePath")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        switch self.sandboxResult(path: localPath, sandbox: context.sandbox, isNew: false) {
        case let .failure(error): return error
        case let .success(validatedLocal):
            return await self.performUpload(
                localPath: validatedLocal,
                remotePath: remotePath,
                overwrite: arguments["overwrite"]?.boolValue ?? false,
                entry: entry,
                context: context
            )
        }
    }

    // MARK: driftline.download

    public static func download(arguments: JSONValue, context: MCPToolContext) async -> CallToolResult {
        guard let sessionId = arguments["sessionId"]?.stringValue else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "sessionId is required.", data: .object(["field": .string("sessionId")]))
        }
        guard let remotePath = arguments["remotePath"]?.stringValue, !remotePath.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "remotePath is required.", data: .object(["field": .string("remotePath")]))
        }
        guard let localPath = arguments["localPath"]?.stringValue, !localPath.isEmpty else {
            return .toolError(code: MCPToolErrorCode.invalidArguments, message: "localPath is required.", data: .object(["field": .string("localPath")]))
        }
        guard let entry = await context.sessionRegistry.entry(for: sessionId) else {
            return .toolError(code: MCPToolErrorCode.notFound, message: "No session found with id: \(sessionId)", data: .object(["kind": .string("session"), "id": .string(sessionId)]))
        }

        switch self.sandboxResult(path: localPath, sandbox: context.sandbox, isNew: true) {
        case let .failure(error): return error
        case let .success(validatedLocal):
            return await self.performDownload(
                remotePath: remotePath,
                localPath: validatedLocal,
                overwrite: arguments["overwrite"]?.boolValue ?? false,
                entry: entry,
                context: context
            )
        }
    }

    // MARK: - Helpers

    private enum ValidationResult {
        case success(String)
        case failure(CallToolResult)
    }

    private static func sandboxResult(path: String, sandbox: LocalPathSandbox, isNew: Bool) -> ValidationResult {
        do {
            let validated = try isNew ? sandbox.validatedNewPath(path) : sandbox.validatedPath(path)
            return .success(validated)
        } catch let e as SandboxError {
            if case let .notAllowed(p, roots) = e {
                return .failure(.toolError(
                    code: MCPToolErrorCode.pathNotAllowed,
                    message: "Local path is outside allowed roots.",
                    data: .object(["path": .string(p), "allowedRoots": .array(roots.map { .string($0) })])
                ))
            }
            return .failure(.toolError(code: MCPToolErrorCode.pathNotAllowed, message: "Path not allowed."))
        } catch {
            return .failure(.toolError(code: MCPToolErrorCode.pathNotAllowed, message: "Path validation failed."))
        }
    }

    private static func performUpload(
        localPath: String,
        remotePath: String,
        overwrite: Bool,
        entry: MCPSessionEntry,
        context: MCPToolContext
    ) async -> CallToolResult {
        do {
            let exists = try await context.remoteFileSystem.itemExists(at: remotePath, profile: entry.profile, session: entry.session)
            if exists {
                if !context.configuration.allowDestructiveOperations {
                    return .toolError(
                        code: MCPToolErrorCode.capabilityDenied,
                        message: "Overwriting an existing remote file requires allowDestructiveOperations to be enabled.",
                        data: .object(["operation": .string("upload-overwrite"), "requiredFlag": .string("allowDestructiveOperations")])
                    )
                }
                if !overwrite {
                    return .toolError(
                        code: MCPToolErrorCode.itemAlreadyExists,
                        message: "An item already exists at \(remotePath). Pass overwrite:true and ensure allowDestructiveOperations is enabled.",
                        data: .object(["path": .string(remotePath)])
                    )
                }
            }
        } catch let e as RemoteClientError {
            return remoteClientToolError(e)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }

        return await self.enqueueTransfer(direction: .upload, source: localPath, destination: remotePath, entry: entry, context: context)
    }

    private static func performDownload(
        remotePath: String,
        localPath: String,
        overwrite: Bool,
        entry: MCPSessionEntry,
        context: MCPToolContext
    ) async -> CallToolResult {
        if FileManager.default.fileExists(atPath: localPath) {
            if !context.configuration.allowDestructiveOperations {
                return .toolError(
                    code: MCPToolErrorCode.capabilityDenied,
                    message: "Overwriting an existing local file requires allowDestructiveOperations to be enabled.",
                    data: .object(["operation": .string("download-overwrite"), "requiredFlag": .string("allowDestructiveOperations")])
                )
            }
            if !overwrite {
                return .toolError(
                    code: MCPToolErrorCode.itemAlreadyExists,
                    message: "A file already exists at \(localPath). Pass overwrite:true and ensure allowDestructiveOperations is enabled.",
                    data: .object(["path": .string(localPath)])
                )
            }
        }

        return await self.enqueueTransfer(direction: .download, source: remotePath, destination: localPath, entry: entry, context: context)
    }

    private static func enqueueTransfer(
        direction: TransferDirection,
        source: String,
        destination: String,
        entry: MCPSessionEntry,
        context: MCPToolContext
    ) async -> CallToolResult {
        do {
            let job = TransferJob(
                direction: direction,
                sourcePath: source,
                destinationPath: destination,
                profileID: entry.profile.id
            )
            try await context.transferClient.enqueue(job, profile: entry.profile)
            return .success(.object([
                "ok": .bool(true),
                "direction": .string(direction.rawValue),
                "sourcePath": .string(source),
                "destinationPath": .string(destination),
                "bytes": .null,
            ]))
        } catch let e as RemoteClientError {
            return remoteClientToolError(e)
        } catch {
            return .toolError(code: MCPToolErrorCode.commandFailed, message: Redactor().redact(error.localizedDescription))
        }
    }
}
