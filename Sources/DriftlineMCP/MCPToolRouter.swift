import Foundation

// MARK: - MCPToolRouter

/// Sendable struct dispatching tool name → handler.
/// All tool handlers are called from here; they return `CallToolResult`.
public struct MCPToolRouter: Sendable {
    /// Dispatch a tools/call to the appropriate handler.
    /// Unknown tool names return a `not_found`-style error result.
    public static func call(
        name: String,
        arguments: JSONValue,
        context: MCPToolContext
    ) async -> CallToolResult {
        // arguments must be an object; coerce gracefully.
        guard case .object = arguments else {
            return CallToolResult.toolError(
                code: MCPToolErrorCode.invalidArguments,
                message: "Tool arguments must be a JSON object.",
                data: .object([:])
            )
        }

        if let result = await profileTool(name: name, arguments: arguments, context: context) {
            return result
        }
        if let result = await fileSystemTool(name: name, arguments: arguments, context: context) {
            return result
        }
        if let result = await transferTool(name: name, arguments: arguments, context: context) {
            return result
        }
        return CallToolResult.toolError(
            code: MCPToolErrorCode.notFound,
            message: "Unknown tool: \(name)",
            data: .object(["tool": .string(name)])
        )
    }

    // MARK: - Grouped dispatchers

    private static func profileTool(name: String, arguments: JSONValue, context: MCPToolContext) async -> CallToolResult? {
        switch name {
        case "driftline.listProfiles":
            await ProfileTools.listProfiles(arguments: arguments, context: context)
        case "driftline.getProfile":
            await ProfileTools.getProfile(arguments: arguments, context: context)
        case "driftline.connect":
            await ProfileTools.connect(arguments: arguments, context: context)
        case "driftline.disconnect":
            await ProfileTools.disconnect(arguments: arguments, context: context)
        case "driftline.trustHostInfo":
            await ProfileTools.trustHostInfo(arguments: arguments, context: context)
        default:
            nil
        }
    }

    private static func fileSystemTool(name: String, arguments: JSONValue, context: MCPToolContext) async -> CallToolResult? {
        switch name {
        case "driftline.listDirectory":
            await FileSystemTools.listDirectory(arguments: arguments, context: context)
        case "driftline.listLocal":
            await FileSystemTools.listLocal(arguments: arguments, context: context)
        case "driftline.stat":
            await FileSystemTools.stat(arguments: arguments, context: context)
        case "driftline.createFolder":
            await FileSystemTools.createFolder(arguments: arguments, context: context)
        case "driftline.rename":
            await FileSystemTools.rename(arguments: arguments, context: context)
        case "driftline.delete":
            await FileSystemTools.delete(arguments: arguments, context: context)
        default:
            nil
        }
    }

    private static func transferTool(name: String, arguments: JSONValue, context: MCPToolContext) async -> CallToolResult? {
        switch name {
        case "driftline.upload":
            await TransferTools.upload(arguments: arguments, context: context)
        case "driftline.download":
            await TransferTools.download(arguments: arguments, context: context)
        default:
            nil
        }
    }
}
