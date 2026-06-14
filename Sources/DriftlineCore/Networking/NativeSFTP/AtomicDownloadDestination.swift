import Foundation

struct AtomicDownloadDestination {
    let finalURL: URL
    let temporaryURL: URL

    private let fileManager: FileManager

    init(finalURL: URL, id: UUID = UUID(), fileManager: FileManager = .default) {
        self.finalURL = finalURL
        self.fileManager = fileManager

        let name = finalURL.lastPathComponent.isEmpty ? "download" : finalURL.lastPathComponent
        self.temporaryURL = finalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(name).driftline-\(id.uuidString).partial")
    }

    func prepare() throws -> FileHandle {
        try self.fileManager.createDirectory(
            at: self.finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if self.fileManager.fileExists(atPath: self.temporaryURL.path) {
            try self.fileManager.removeItem(at: self.temporaryURL)
        }
        self.fileManager.createFile(atPath: self.temporaryURL.path, contents: nil)
        return try FileHandle(forWritingTo: self.temporaryURL)
    }

    func commit() throws {
        var isDirectory: ObjCBool = false
        if self.fileManager.fileExists(atPath: self.finalURL.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else {
                throw RemoteClientError.commandFailed("Cannot replace folder at \(self.finalURL.path).")
            }
            try self.fileManager.removeItem(at: self.finalURL)
        }
        try self.fileManager.moveItem(at: self.temporaryURL, to: self.finalURL)
    }

    func cleanup() {
        try? self.fileManager.removeItem(at: self.temporaryURL)
    }
}
