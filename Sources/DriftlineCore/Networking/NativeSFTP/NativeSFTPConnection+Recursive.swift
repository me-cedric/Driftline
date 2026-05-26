import Foundation

extension NativeSFTPConnection {
    public func uploadFolder(
        localPath: String,
        remotePath: String,
        jobID: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        let localURL = URL(fileURLWithPath: localPath).resolvingSymlinksInPath()
        let entries = try localEntries(under: localURL)
        let totalBytes = entries.reduce(into: Int64(0)) { acc, entry in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard !isDir else { return }
            acc += (try? FileManager.default.attributesOfItem(atPath: entry.path)[.size] as? NSNumber)?.int64Value ?? 0
        }

        try await expectStatusOK(SFTPRequestBuilder.mkdir(id: nextID(), path: remotePath))

        var bytesCompleted: Int64 = 0
        let started = Date()

        for entry in entries {
            if await cancellation() || Task.isCancelled { throw CancellationError() }

            let relative = relativePath(from: localURL, to: entry)
            let remoteEntry = remotePath + relative.replacingOccurrences(of: "\\", with: "/")

            let entryIsDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if entryIsDir {
                try await expectStatusOK(SFTPRequestBuilder.mkdir(id: nextID(), path: remoteEntry))
            } else {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: entry.path)[.size] as? NSNumber)?.int64Value ?? 0
                let capturedCompleted = bytesCompleted
                let capturedTotal = totalBytes
                let capturedStarted = started
                try await uploadFile(
                    localPath: entry.path,
                    remotePath: remoteEntry,
                    jobID: jobID,
                    onProgress: { fileFraction, _ in
                        let fileContribution = Int64(Double(fileSize) * fileFraction)
                        let overall = capturedCompleted + fileContribution
                        let overallFraction = capturedTotal > 0 ? min(max(Double(overall) / Double(capturedTotal), 0), 1) : 0
                        let elapsed = Date().timeIntervalSince(capturedStarted)
                        let overallSpeed: Int64? = elapsed > 0 ? Int64(Double(overall) / elapsed) : nil
                        await onProgress(overallFraction, overallSpeed)
                    },
                    cancellation: cancellation
                )
                bytesCompleted += fileSize
            }
        }
        await onProgress(1, nil)
    }

    public func downloadFolder(
        remotePath: String,
        localPath: String,
        jobID: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        let tree = try await buildRemoteTree(at: remotePath)
        let totalBytes = tree.reduce(into: Int64(0)) { acc, entry in
            if entry.kind == .file { acc += entry.size ?? 0 }
        }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: localPath),
            withIntermediateDirectories: true
        )

        var bytesCompleted: Int64 = 0
        let started = Date()

        for entry in tree {
            if await cancellation() || Task.isCancelled { throw CancellationError() }

            let relative = String(entry.path.dropFirst(remotePath.count))
            let localEntry = localPath + relative

            switch entry.kind {
            case .folder:
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: localEntry),
                    withIntermediateDirectories: true
                )
            case .file, .symbolicLink, .unknown:
                let fileSize = entry.size ?? 0
                let capturedCompleted = bytesCompleted
                let capturedTotal = totalBytes
                let capturedStarted = started
                try await downloadFile(
                    remotePath: entry.path,
                    localPath: localEntry,
                    jobID: jobID,
                    onProgress: { fileFraction, _ in
                        let fileContribution = Int64(Double(fileSize) * fileFraction)
                        let overall = capturedCompleted + fileContribution
                        let overallFraction = capturedTotal > 0 ? min(max(Double(overall) / Double(capturedTotal), 0), 1) : 0
                        let elapsed = Date().timeIntervalSince(capturedStarted)
                        let overallSpeed: Int64? = elapsed > 0 ? Int64(Double(overall) / elapsed) : nil
                        await onProgress(overallFraction, overallSpeed)
                    },
                    cancellation: cancellation
                )
                bytesCompleted += fileSize
            }
        }
        await onProgress(1, nil)
    }

    // MARK: - Private helpers

    private func localEntries(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var dirs: [URL] = []
        var files: [URL] = []
        for case let url as URL in enumerator {
            let resolvedURL = url.resolvingSymlinksInPath()
            let isDir = (try? resolvedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir { dirs.append(resolvedURL) } else { files.append(resolvedURL) }
        }
        return dirs + files
    }

    private func relativePath(from root: URL, to entry: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
        let entryPath = entry.resolvingSymlinksInPath().path
        guard entryPath.hasPrefix(rootPath) else {
            return "/" + entry.lastPathComponent
        }
        let relative = String(entryPath.dropFirst(rootPath.count))
        return relative.hasPrefix("/") ? relative : "/" + relative
    }

    func rawDirectoryEntries(at path: String) async throws -> [SFTPNameEntry] {
        let handle = try await expectHandle(SFTPRequestBuilder.opendir(id: nextID(), path: path))
        var entries: [SFTPNameEntry] = []
        while true {
            let packet = try await self.send(SFTPRequestBuilder.readdir(id: nextID(), handle: handle))
            switch packet.type {
            case .name:
                entries.append(contentsOf: try SFTPNameParser.parseNamePacketPayload(packet.payload))
            case .status:
                let status = try SFTPStatus.parse(payload: packet.payload)
                if status.code == .eof {
                    try? await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
                    return entries
                }
                if let error = status.remoteError(fallbackPath: path) {
                    throw error
                }
            default:
                throw RemoteClientError.commandFailed("Unexpected SFTP response while listing \(path).")
            }
        }
    }

    private func buildRemoteTree(at path: String) async throws -> [FileItem] {
        let rawEntries = try await rawDirectoryEntries(at: path)
        var result: [FileItem] = []

        var dirs: [FileItem] = []
        var files: [FileItem] = []

        for entry in rawEntries {
            let item = entry.fileItem(parentPath: path)
            if item.kind == .folder { dirs.append(item) } else { files.append(item) }
        }

        result.append(contentsOf: dirs)
        result.append(contentsOf: files)

        for dir in dirs {
            let children = try await buildRemoteTree(at: dir.path)
            result.append(contentsOf: children)
        }

        return result
    }
}

private extension SFTPNameEntry {
    func fileItem(parentPath: String) -> FileItem {
        let path = parentPath == "/" ? "/\(filename)" : "\(parentPath)/\(filename)"
        return FileItem(
            name: filename,
            path: path,
            kind: attributes.fileKind,
            size: attributes.size.map(Int64.init),
            modifiedAt: attributes.modifiedAt,
            permissions: attributes.permissions.map { String($0, radix: 8) },
            owner: attributes.uid.map(String.init),
            group: attributes.gid.map(String.init),
            source: .remote,
            isHidden: filename.hasPrefix(".")
        )
    }
}
