import Foundation

// MARK: - Tool Catalog

/// Static catalogue of all v1 MCP tool descriptors.
/// Consumed by `tools/list` — no server-side logic here.
public enum MCPToolCatalog {
    private static func schema(properties: JSONValue, required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": properties,
            "required": .array(required.map { .string($0) }),
            "additionalProperties": .bool(false),
        ])
    }

    // MARK: Tool list

    public static let all: [MCPToolDescriptor] = [
        MCPToolDescriptor(
            name: "driftline.listProfiles",
            title: "List Profiles",
            description: "List saved server profiles (id, host, port, auth method name; no secrets).",
            inputSchema: schema(properties: .object([:]), required: [])
        ),
        MCPToolDescriptor(
            name: "driftline.getProfile",
            title: "Get Profile",
            description: "Read one saved server profile (no secrets).",
            inputSchema: schema(
                properties: .object(["profileId": .object(["type": .string("string")])]),
                required: ["profileId"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.connect",
            title: "Connect",
            description: "Open a session to a profile; surfaces host-trust errors with fingerprint; never auto-trusts.",
            inputSchema: schema(
                properties: .object(["profileId": .object(["type": .string("string")])]),
                required: ["profileId"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.disconnect",
            title: "Disconnect",
            description: "Close a previously opened session.",
            inputSchema: schema(
                properties: .object(["sessionId": .object(["type": .string("string")])]),
                required: ["sessionId"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.listDirectory",
            title: "List Directory",
            description: "List a remote directory (optional showHidden).",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")]),
                    "showHidden": .object(["type": .string("boolean"), "default": .bool(false)]),
                ]),
                required: ["sessionId", "path"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.stat",
            title: "Stat",
            description: "Report existence + metadata for a remote path.",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")]),
                ]),
                required: ["sessionId", "path"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.listLocal",
            title: "List Local",
            description: "List a sandboxed local directory.",
            inputSchema: schema(
                properties: .object([
                    "path": .object(["type": .string("string")]),
                    "showHidden": .object(["type": .string("boolean"), "default": .bool(false)]),
                ]),
                required: ["path"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.createFolder",
            title: "Create Folder",
            description: "Create a remote folder (non-destructive write).",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")]),
                    "name": .object(["type": .string("string")]),
                ]),
                required: ["sessionId", "path", "name"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.rename",
            title: "Rename",
            description: "Rename/move a remote item (non-destructive write).",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")]),
                    "newName": .object(["type": .string("string")]),
                ]),
                required: ["sessionId", "path", "newName"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.upload",
            title: "Upload",
            description: "Upload a sandboxed local file/folder to remote. Overwriting requires allowDestructiveOperations.",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "localPath": .object(["type": .string("string")]),
                    "remotePath": .object(["type": .string("string")]),
                    "overwrite": .object(["type": .string("boolean"), "default": .bool(false)]),
                ]),
                required: ["sessionId", "localPath", "remotePath"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.download",
            title: "Download",
            description: "Download a remote file/folder into a sandboxed local root. Overwriting requires allowDestructiveOperations.",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "remotePath": .object(["type": .string("string")]),
                    "localPath": .object(["type": .string("string")]),
                    "overwrite": .object(["type": .string("boolean"), "default": .bool(false)]),
                ]),
                required: ["sessionId", "remotePath", "localPath"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.delete",
            title: "Delete",
            description: "Delete a remote item. Requires allowDestructiveOperations.",
            inputSchema: schema(
                properties: .object([
                    "sessionId": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")]),
                ]),
                required: ["sessionId", "path"]
            )
        ),
        MCPToolDescriptor(
            name: "driftline.trustHostInfo",
            title: "Trust Host Info",
            description: "Read-only: report a profile host's fingerprint + trust status. Does NOT trust.",
            inputSchema: schema(
                properties: .object(["profileId": .object(["type": .string("string")])]),
                required: ["profileId"]
            )
        ),
    ]
}
