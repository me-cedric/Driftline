import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

public actor NativeSFTPConnectionPool {
    private var connections: [UUID: NativeSFTPConnection] = [:]

    public init() {}

    public func insert(_ connection: NativeSFTPConnection, for sessionID: UUID) {
        connections[sessionID] = connection
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
        try? await sftpChannel.close().get()
        try? await sftpChannel.closeFuture.get()
        try? await channel.close().get()
        try? await channel.closeFuture.get()
        try? await group.shutdownGracefully()
    }

    public func listDirectory(at path: String, preferences: FileListPreferences) async throws -> [FileItem] {
        let handle = try await expectHandle(SFTPRequestBuilder.opendir(id: nextID(), path: path))
        var entries: [SFTPNameEntry] = []
        while true {
            let packet = try await send(SFTPRequestBuilder.readdir(id: nextID(), handle: handle))
            switch packet.type {
            case .name:
                entries.append(contentsOf: try SFTPNameParser.parseNamePacketPayload(packet.payload))
            case .status:
                let status = try SFTPStatus.parse(payload: packet.payload)
                if status.code == .eof {
                    try? await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
                    return FileItemSorter.sort(entries.map { $0.fileItem(parentPath: path) }.filter { preferences.showHiddenFiles || !$0.isHidden }, preferences: preferences)
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
        try await expectStatusOK(SFTPRequestBuilder.mkdir(id: nextID(), path: remoteChildPath(parent: path, name: name)))
    }

    public func renameItem(at path: String, to newName: String) async throws {
        try await expectStatusOK(SFTPRequestBuilder.rename(id: nextID(), oldPath: path, newPath: remoteChildPath(parent: URL(fileURLWithPath: path).deletingLastPathComponent().path, name: newName)))
    }

    public func deleteItem(at path: String) async throws {
        let kind = try await stat(path: path).fileKind
        switch kind {
        case .folder:
            let entries = try await rawDirectoryEntries(at: path)
            for entry in entries {
                let child = entry.fileItem(parentPath: path)
                try await deleteItem(at: child.path)
            }
            try await expectStatusOK(SFTPRequestBuilder.rmdir(id: nextID(), path: path))
        case .file, .symbolicLink, .unknown:
            try await expectStatusOK(SFTPRequestBuilder.remove(id: nextID(), path: path))
        }
    }

    public func itemExists(at path: String) async throws -> Bool {
        do {
            _ = try await stat(path: path)
            return true
        } catch let error as NativeSFTPStatusError where error.status.code == .noSuchFile {
            return false
        }
    }

    public func uploadFile(
        localPath: String,
        remotePath: String,
        jobID: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        let localURL = URL(fileURLWithPath: localPath)
        let fileHandle = try FileHandle(forReadingFrom: localURL)
        defer { try? fileHandle.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try await expectHandle(SFTPRequestBuilder.open(
            id: nextID(),
            path: remotePath,
            pflags: SFTPOpenPFlags.write | SFTPOpenPFlags.create | SFTPOpenPFlags.truncate
        ))

        var offset: UInt64 = 0
        let started = Date()
        do {
            while true {
                if await cancellation() || Task.isCancelled {
                    throw CancellationError()
                }
                let data = try fileHandle.read(upToCount: Int(Self.transferChunkSize)) ?? Data()
                if data.isEmpty { break }
                try await expectStatusOK(SFTPRequestBuilder.write(id: nextID(), handle: handle, offset: offset, data: data))
                offset += UInt64(data.count)
                await onProgress(progress(done: Int64(offset), total: total), speed(done: Int64(offset), started: started))
            }
            try await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
            await onProgress(1, speed(done: Int64(offset), started: started))
        } catch {
            try? await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
            throw error
        }
    }

    public func downloadFile(
        remotePath: String,
        localPath: String,
        jobID: TransferJobID,
        onProgress: @Sendable (Double, Int64?) async -> Void,
        cancellation: @Sendable () async -> Bool
    ) async throws {
        let attrs = try await stat(path: remotePath)
        let total = attrs.size.map(Int64.init) ?? 0
        let handle = try await expectHandle(SFTPRequestBuilder.open(id: nextID(), path: remotePath, pflags: SFTPOpenPFlags.read))

        let localURL = URL(fileURLWithPath: localPath)
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: localPath, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }

        var offset: UInt64 = 0
        let started = Date()
        do {
            while true {
                if await cancellation() || Task.isCancelled {
                    throw CancellationError()
                }
                let packet = try await send(SFTPRequestBuilder.read(id: nextID(), handle: handle, offset: offset, length: Self.transferChunkSize))
                switch packet.type {
                case .data:
                    var reader = SFTPDataReader(data: packet.payload)
                    let data = try reader.readBinaryString()
                    if data.isEmpty { continue }
                    try fileHandle.write(contentsOf: data)
                    offset += UInt64(data.count)
                    await onProgress(progress(done: Int64(offset), total: total), speed(done: Int64(offset), started: started))
                case .status:
                    let status = try SFTPStatus.parse(payload: packet.payload)
                    if status.code == .eof {
                        try await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
                        await onProgress(1, speed(done: Int64(offset), started: started))
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
            try? await expectStatusOK(SFTPRequestBuilder.close(id: nextID(), handle: handle))
            throw error
        }
    }

    private func stat(path: String) async throws -> SFTPAttributes {
        let packet = try await send(SFTPRequestBuilder.lstat(id: nextID(), path: path))
        switch packet.type {
        case .attrs:
            var reader = SFTPDataReader(data: packet.payload)
            return try SFTPAttributes.parse(from: &reader)
        case .status:
            throw NativeSFTPStatusError(status: try SFTPStatus.parse(payload: packet.payload), path: path)
        default:
            throw RemoteClientError.commandFailed("Unexpected SFTP response while reading metadata for \(path).")
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

    func send(_ packet: SFTPPacket) async throws -> SFTPPacket {
        try Task.checkCancellation()
        return try await handler.send(packet, on: sftpChannel).get()
    }

    func nextID() -> UInt32 {
        defer { nextRequestID = nextRequestID &+ 1 }
        return nextRequestID
    }

    private func remoteChildPath(parent: String, name: String) -> String {
        parent == "/" ? "/\(name)" : "/\(parent.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(name)"
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
        guard case .byteBuffer(let buffer) = channelData.data else { return }

        inboundData.append(contentsOf: buffer.readableBytesView)
        do {
            while inboundData.count >= 5 {
                let decoded = try SFTPPacket.decodeOne(from: inboundData)
                inboundData = decoded.remaining
                dispatch(decoded.packet)
            }
        } catch SFTPPacketError.incompletePacket {
            return
        } catch {
            failAll(error)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failAll(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        failAll(RemoteClientError.connectionFailed("The SFTP channel closed."))
    }

    private func dispatch(_ packet: SFTPPacket) {
        if packet.type == .version {
            var reader = SFTPDataReader(data: packet.payload)
            do {
                versionPromise?.succeed(try reader.readUInt32())
            } catch {
                versionPromise?.fail(error)
            }
            versionPromise = nil
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
        versionPromise?.fail(error)
        versionPromise = nil
        for promise in pending.values {
            promise.fail(error)
        }
        pending.removeAll()
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
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func record(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if storedError == nil {
            storedError = error
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
        errorBox.record(error)
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
