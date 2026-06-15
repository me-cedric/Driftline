import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

public actor NativeSFTPConnectionPool {
    private var connections: [UUID: NativeSFTPConnection] = [:]

    public init() {}

    public func insert(_ connection: NativeSFTPConnection, for sessionID: UUID) {
        self.connections[sessionID] = connection
    }

    public func connection(for sessionID: UUID) throws -> NativeSFTPConnection {
        guard let connection = connections[sessionID] else {
            throw RemoteClientError.connectionFailed("The native SFTP session is no longer active.")
        }
        return connection
    }

    public func remove(sessionID: UUID) async {
        guard let connection = connections.removeValue(forKey: sessionID) else { return }
        await connection.close()
    }
}

public actor NativeSFTPConnection {
    private static let transferChunkSize: UInt32 = 32 * 1024
    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let sftpChannel: Channel
    private let handler: NativeSFTPChannelHandler
    private var nextRequestID: UInt32 = 1

    private init(
        group: MultiThreadedEventLoopGroup,
        channel: Channel,
        sftpChannel: Channel,
        handler: NativeSFTPChannelHandler
    ) {
        self.group = group
        self.channel = channel
        self.sftpChannel = sftpChannel
        self.handler = handler
    }

    public static func connect(
        profile: ServerProfile,
        authDelegate: NIOSSHClientUserAuthenticationDelegate,
        hostTrustStore: HostTrustStore
    ) async throws -> NativeSFTPConnection {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let errorBox = NativeSFTPConnectionErrorBox()
        do {
            let hostTrustDelegate = NativeSFTPHostTrustDelegate(host: profile.host, port: profile.port, hostTrustStore: hostTrustStore)
            let bootstrap = ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let sshHandler = NIOSSHHandler(
                            role: .client(
                                .init(
                                    userAuthDelegate: authDelegate,
                                    serverAuthDelegate: hostTrustDelegate
                                )
                            ),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                        try channel.pipeline.syncOperations.addHandler(sshHandler)
                        try channel.pipeline.syncOperations.addHandler(NativeSFTPErrorHandler(errorBox: errorBox))
                    }
                }
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

            let channel = try await bootstrap.connect(host: profile.host, port: profile.port).get()
            let childHandler = NativeSFTPChannelHandler()
            let sftpChannel = try await channel.eventLoop.submit {
                let sshHandler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                let promise = channel.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                    childChannel.pipeline.addHandler(childHandler)
                }
                return promise.futureResult
            }.flatMap { $0 }.get()

            try await sftpChannel.pipeline.triggerUserOutboundEvent(
                SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
            ).get()
            try await childHandler.initialize(on: sftpChannel).get()

            return NativeSFTPConnection(group: group, channel: channel, sftpChannel: sftpChannel, handler: childHandler)
        } catch {
            try? await group.shutdownGracefully()
            if let recordedError = errorBox.error {
                throw recordedError
            }
            throw error
        }
    }

    public func close() async {
        try? await self.sftpChannel.close().get()
        try? await self.sftpChannel.closeFuture.get()
        try? await self.channel.close().get()
        try? await self.channel.closeFuture.get()
        try? await self.group.shutdownGracefully()
    }

    public func listDirectory(at path: String, preferences: FileListPreferences) async throws -> [FileItem] {
        let resolvedPath = try await self.resolveRemotePath(path)
        let handle = try await expectHandle(SFTPRequestBuilder.opendir(id: self.nextID(), path: resolvedPath))
        var entries: [SFTPNameEntry] = []
        while true {
            let packet = try await send(SFTPRequestBuilder.readdir(id: self.nextID(), handle: handle))
            switch packet.type {
            case .name:
                try entries.append(contentsOf: SFTPNameParser.parseNamePacketPayload(packet.payload))
            case .status:
                let status = try SFTPStatus.parse(payload: packet.payload)
                if status.code == .eof {
                    try? await self.expectStatusOK(SFTPRequestBuilder.close(id: self.nextID(), handle: handle))
                    return FileItemSorter.sort(entries.map { $0.fileItem(parentPath: resolvedPath) }.filter { preferences.showHiddenFiles || !$0.isHidden }, preferences: preferences)
                }
                if let error = status.remoteError(fallbackPath: path) {
                    throw error
                }
            default:
                throw RemoteClientError.commandFailed("Unexpected SFTP response while listing \(path).")
            }
        }
    }

    public func createFolder(named name: String, in path: String) async throws {
        let resolvedPath = try await self.resolveRemotePath(path)
        try await self.expectStatusOK(SFTPRequestBuilder.mkdir(id: self.nextID(), path: self.remoteChildPath(parent: resolvedPath, name: name)))
    }

    public func renameItem(at path: String, to newName: String) async throws {
        let resolvedPath = try await self.resolveRemotePath(path)
        try await self.expectStatusOK(SFTPRequestBuilder.rename(id: self.nextID(), oldPath: resolvedPath, newPath: self.remoteChildPath(parent: self.remoteParentPath(of: resolvedPath), name: newName)))
    }

    public func deleteItem(at path: String) async throws {
        let path = try await self.resolveRemotePath(path)
        let kind = try await stat(path: path).fileKind
        switch kind {
        case .folder:
            let entries = try await rawDirectoryEntries(at: path)
            for entry in entries {
                let child = entry.fileItem(parentPath: path)
                try await self.deleteItem(at: child.path)
            }
            try await self.expectStatusOK(SFTPRequestBuilder.rmdir(id: self.nextID(), path: path))
        case .file, .symbolicLink, .unknown:
            try await self.expectStatusOK(SFTPRequestBuilder.remove(id: self.nextID(), path: path))
        }
    }

    public func itemExists(at path: String) async throws -> Bool {
        let path = try await self.resolveRemotePath(path)
        do {
            _ = try await self.stat(path: path)
            return true
        } catch let error as NativeSFTPStatusError where error.status.code == .noSuchFile {
            return false
        }
    }

    public func uploadFile(
        localPath: String,
        remotePath: String,
        jobID _: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        try await self.checkTransferCancellation(cancellation)
        let remotePath = try await self.resolveRemotePath(remotePath)
        let localURL = URL(fileURLWithPath: localPath)
        let fileHandle = try FileHandle(forReadingFrom: localURL)
        defer { try? fileHandle.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try await expectHandle(SFTPRequestBuilder.open(
            id: self.nextID(),
            path: remotePath,
            pflags: SFTPOpenPFlags.write | SFTPOpenPFlags.create | SFTPOpenPFlags.truncate
        ))

        var offset: UInt64 = 0
        let started = Date()
        do {
            while true {
                try await self.checkTransferCancellation(cancellation)
                let data = try fileHandle.read(upToCount: Int(Self.transferChunkSize)) ?? Data()
                if data.isEmpty { break }
                try await self.expectStatusOK(SFTPRequestBuilder.write(id: self.nextID(), handle: handle, offset: offset, data: data))
                offset += UInt64(data.count)
                await onProgress(self.progress(done: Int64(offset), total: total), self.speed(done: Int64(offset), started: started))
            }
            try await self.expectStatusOK(SFTPRequestBuilder.close(id: self.nextID(), handle: handle))
            await onProgress(1, self.speed(done: Int64(offset), started: started))
        } catch {
            try? await self.expectStatusOK(SFTPRequestBuilder.close(id: self.nextID(), handle: handle))
            throw error
        }
    }

    public func downloadFile(
        remotePath: String,
        localPath: String,
        jobID _: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        try await self.checkTransferCancellation(cancellation)
        let remotePath = try await self.resolveRemotePath(remotePath)
        let attrs = try await stat(path: remotePath)
        let total = attrs.size.map(Int64.init) ?? 0
        let handle = try await expectHandle(SFTPRequestBuilder.open(id: self.nextID(), path: remotePath, pflags: SFTPOpenPFlags.read))

        let localURL = URL(fileURLWithPath: localPath)
        let destination = AtomicDownloadDestination(finalURL: localURL)
        let fileHandle = try destination.prepare()
        var committed = false
        defer {
            try? fileHandle.close()
            if !committed {
                destination.cleanup()
            }
        }

        var offset: UInt64 = 0
        let started = Date()
        do {
            while true {
                try await self.checkTransferCancellation(cancellation)
                let packet = try await send(SFTPRequestBuilder.read(id: self.nextID(), handle: handle, offset: offset, length: Self.transferChunkSize))
                switch packet.type {
                case .data:
                    var reader = SFTPDataReader(data: packet.payload)
                    let data = try reader.readBinaryString()
                    if data.isEmpty { continue }
                    try fileHandle.write(contentsOf: data)
                    offset += UInt64(data.count)
                    await onProgress(self.progress(done: Int64(offset), total: total), self.speed(done: Int64(offset), started: started))
                case .status:
                    let status = try SFTPStatus.parse(payload: packet.payload)
                    if status.code == .eof {
                        try await self.expectStatusOK(SFTPRequestBuilder.close(id: self.nextID(), handle: handle))
                        try fileHandle.close()
                        try destination.commit()
                        committed = true
                        await onProgress(1, self.speed(done: Int64(offset), started: started))
                        return
                    }
                    if let error = status.remoteError(fallbackPath: remotePath) {
                        throw error
                    }
                default:
                    throw RemoteClientError.commandFailed("Unexpected SFTP response while downloading \(remotePath).")
                }
            }
        } catch {
            try? await self.expectStatusOK(SFTPRequestBuilder.close(id: self.nextID(), handle: handle))
            throw error
        }
    }

    private func stat(path: String) async throws -> SFTPAttributes {
        let packet = try await send(SFTPRequestBuilder.lstat(id: self.nextID(), path: path))
        switch packet.type {
        case .attrs:
            var reader = SFTPDataReader(data: packet.payload)
            return try SFTPAttributes.parse(from: &reader)
        case .status:
            throw try NativeSFTPStatusError(status: SFTPStatus.parse(payload: packet.payload), path: path)
        default:
            throw RemoteClientError.commandFailed("Unexpected SFTP response while reading metadata for \(path).")
        }
    }

    public func resolveRemotePath(_ path: String) async throws -> String {
        if path == "~" {
            return try await self.realPath(".")
        }
        if path.hasPrefix("~/") {
            let homePath = try await self.realPath(".")
            let suffix = String(path.dropFirst(2))
            return self.remotePathAppending(homePath, suffix)
        }
        return path
    }

    private func realPath(_ path: String) async throws -> String {
        let packet = try await send(SFTPRequestBuilder.realpath(id: self.nextID(), path: path))
        switch packet.type {
        case .name:
            let entries = try SFTPNameParser.parseNamePacketPayload(packet.payload)
            guard let resolved = entries.first?.filename else {
                throw RemoteClientError.commandFailed("Remote path resolution returned no path.")
            }
            return resolved
        case .status:
            let status = try SFTPStatus.parse(payload: packet.payload)
            throw status.remoteError(fallbackPath: path) ?? RemoteClientError.commandFailed("Remote path resolution failed.")
        default:
            throw RemoteClientError.commandFailed("Unexpected SFTP response while resolving \(path).")
        }
    }

    func expectHandle(_ packet: SFTPPacket) async throws -> Data {
        let response = try await send(packet)
        switch response.type {
        case .handle:
            var reader = SFTPDataReader(data: response.payload)
            return try reader.readBinaryString()
        case .status:
            let status = try SFTPStatus.parse(payload: response.payload)
            throw status.remoteError() ?? RemoteClientError.commandFailed("SFTP handle request failed.")
        default:
            throw RemoteClientError.commandFailed("Unexpected SFTP response.")
        }
    }

    func expectStatusOK(_ packet: SFTPPacket) async throws {
        let response = try await send(packet)
        guard response.type == .status else {
            throw RemoteClientError.commandFailed("Unexpected SFTP response.")
        }
        let status = try SFTPStatus.parse(payload: response.payload)
        if let error = status.remoteError() {
            throw error
        }
    }

    func createDirectoryIfNeeded(at path: String) async throws {
        do {
            try await self.expectStatusOK(SFTPRequestBuilder.mkdir(id: self.nextID(), path: path))
        } catch {
            let attrs = try? await self.stat(path: path)
            if attrs?.fileKind == .folder {
                return
            }
            throw error
        }
    }

    func checkTransferCancellation(_ cancellation: @Sendable () async -> Bool) async throws {
        if await cancellation() || Task.isCancelled {
            throw CancellationError()
        }
    }

    func send(_ packet: SFTPPacket) async throws -> SFTPPacket {
        try Task.checkCancellation()
        return try await self.handler.send(packet, on: self.sftpChannel).get()
    }

    func nextID() -> UInt32 {
        defer { nextRequestID = nextRequestID &+ 1 }
        return self.nextRequestID
    }

    private func remoteChildPath(parent: String, name: String) -> String {
        parent == "/" ? "/\(name)" : "/\(parent.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(name)"
    }

    private func remoteParentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return "/" }
        if slash == trimmed.startIndex { return "/" }
        return String(trimmed[..<slash])
    }

    private func remotePathAppending(_ base: String, _ suffix: String) -> String {
        guard !suffix.isEmpty else { return base }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmedBase.isEmpty ? "/\(suffix)" : "\(trimmedBase)/\(suffix)"
    }

    private func progress(done: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    private func speed(done: Int64, started: Date) -> Int64? {
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 0 else { return nil }
        return Int64(Double(done) / elapsed)
    }
}

private final class NativeSFTPChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private var pending: [UInt32: EventLoopPromise<SFTPPacket>] = [:]
    private var versionPromise: EventLoopPromise<UInt32>?
    private var inboundData = Data()

    func initialize(on channel: Channel) -> EventLoopFuture<Void> {
        let promise = channel.eventLoop.makePromise(of: UInt32.self)
        return channel.eventLoop.submit {
            self.versionPromise = promise
            self.write(SFTPRequestBuilder.initialize(), on: channel, promise: nil)
        }.flatMap {
            promise.futureResult.map { _ in () }
        }
    }

    func send(_ packet: SFTPPacket, on channel: Channel) -> EventLoopFuture<SFTPPacket> {
        guard let requestID = packet.requestID else {
            return channel.eventLoop.makeFailedFuture(RemoteClientError.commandFailed("SFTP requests require an id."))
        }
        let promise = channel.eventLoop.makePromise(of: SFTPPacket.self)
        channel.eventLoop.execute {
            self.pending[requestID] = promise
            let writePromise = channel.eventLoop.makePromise(of: Void.self)
            writePromise.futureResult.whenFailure { error in
                self.pending.removeValue(forKey: requestID)
                promise.fail(error)
            }
            self.write(packet, on: channel, promise: writePromise)
        }
        return promise.futureResult
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard channelData.type == .channel else { return }
        guard case let .byteBuffer(buffer) = channelData.data else { return }

        self.inboundData.append(contentsOf: buffer.readableBytesView)
        do {
            while self.inboundData.count >= 5 {
                let decoded = try SFTPPacket.decodeOne(from: self.inboundData)
                self.inboundData = decoded.remaining
                self.dispatch(decoded.packet)
            }
        } catch SFTPPacketError.incompletePacket {
            return
        } catch {
            self.failAll(error)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.failAll(error)
        context.close(promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        self.failAll(RemoteClientError.connectionFailed("The SFTP channel closed."))
    }

    private func dispatch(_ packet: SFTPPacket) {
        if packet.type == .version {
            var reader = SFTPDataReader(data: packet.payload)
            do {
                try self.versionPromise?.succeed(reader.readUInt32())
            } catch {
                self.versionPromise?.fail(error)
            }
            self.versionPromise = nil
            return
        }

        guard let requestID = packet.requestID, let promise = pending.removeValue(forKey: requestID) else {
            return
        }
        promise.succeed(packet)
    }

    private func write(_ packet: SFTPPacket, on channel: Channel, promise: EventLoopPromise<Void>?) {
        var buffer = channel.allocator.buffer(capacity: packet.encoded().count)
        buffer.writeBytes(packet.encoded())
        channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)), promise: promise)
    }

    private func failAll(_ error: Error) {
        self.versionPromise?.fail(error)
        self.versionPromise = nil
        for promise in self.pending.values {
            promise.fail(error)
        }
        self.pending.removeAll()
    }
}

private struct NativeSFTPStatusError: Error {
    var status: SFTPStatus
    var path: String
}

private final class NativeSFTPConnectionErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        self.lock.lock()
        defer { lock.unlock() }
        return self.storedError
    }

    func record(_ error: Error) {
        self.lock.lock()
        defer { lock.unlock() }
        if self.storedError == nil {
            self.storedError = error
        }
    }
}

private final class NativeSFTPErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    private let errorBox: NativeSFTPConnectionErrorBox

    init(errorBox: NativeSFTPConnectionErrorBox) {
        self.errorBox = errorBox
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.errorBox.record(error)
        context.close(promise: nil)
    }
}

extension NativeSFTPChannelHandler: @unchecked Sendable {}

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
