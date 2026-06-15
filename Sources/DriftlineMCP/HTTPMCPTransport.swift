import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

// MARK: - HTTPMCPServer

public actor HTTPMCPServer {
    private let server: MCPServer
    private let port: Int
    private let bearerToken: String
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(server: MCPServer, port: Int, bearerToken: String) {
        self.server = server
        self.port = port
        self.bearerToken = bearerToken
    }

    public func start() async throws {
        guard self.channel == nil else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let engine = self.server.makeEngine()
        let token = self.bearerToken
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPMCPHandler(engine: engine, bearerToken: token))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        do {
            self.channel = try await bootstrap.bind(host: "127.0.0.1", port: self.port).get()
            self.group = group
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    public func localPort() -> Int? {
        self.channel?.localAddress?.port
    }

    public func stop() async {
        let channel = self.channel
        let group = self.group
        self.channel = nil
        self.group = nil
        try? await channel?.close().get()
        try? await group?.shutdownGracefully()
    }
}

// MARK: - HTTPMCPHandler

private final class HTTPMCPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let engine: MCPEngine
    private let bearerToken: String
    private var head: HTTPRequestHead?
    private var body = ByteBuffer()
    private var authorized = false

    init(engine: MCPEngine, bearerToken: String) {
        self.engine = engine
        self.bearerToken = bearerToken
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case let .head(head):
            self.head = head
            self.body.clear()
            self.authorized = self.isAuthorized(head)
        case var .body(buffer):
            self.body.writeBuffer(&buffer)
        case .end:
            guard let head else {
                self.send(status: .badRequest, body: JSONRPCResponse.invalidRequest(), context: context)
                return
            }
            self.handleRequest(head: head, body: self.body, context: context)
        }
    }

    private func handleRequest(head: HTTPRequestHead, body: ByteBuffer, context: ChannelHandlerContext) {
        guard head.uri == "/mcp" else {
            self.send(status: .notFound, text: "Not found", context: context)
            return
        }
        guard head.method == .POST else {
            self.send(status: .methodNotAllowed, text: "Method not allowed", context: context)
            return
        }
        guard self.validOrigin(head) else {
            self.send(status: .forbidden, body: JSONRPCResponse.invalidRequest(detail: "Invalid Origin"), context: context)
            return
        }
        guard self.authorized else {
            self.send(status: .unauthorized, body: JSONRPCResponse.invalidRequest(detail: "Unauthorized"), context: context)
            return
        }

        var buffer = body
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            self.send(status: .badRequest, body: JSONRPCResponse.parseError(), context: context)
            return
        }
        guard let value = try? JSONValueDecoder.decode(Data(bytes)) else {
            self.send(status: .badRequest, body: JSONRPCResponse.parseError(), context: context)
            return
        }

        let writer = HTTPResponseWriter(context: context)
        Task {
            let response = await self.engine.handle(value)
            if let response {
                writer.execute {
                    self.send(status: .ok, body: response, context: writer.context)
                }
            } else {
                writer.execute {
                    self.send(status: .accepted, text: "", context: writer.context)
                }
            }
        }
    }

    private func isAuthorized(_ head: HTTPRequestHead) -> Bool {
        head.headers["authorization"].contains("Bearer \(self.bearerToken)")
    }

    private func validOrigin(_ head: HTTPRequestHead) -> Bool {
        guard let origin = head.headers["origin"].first else { return true }
        guard let components = URLComponents(string: origin), let host = components.host else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func send(status: HTTPResponseStatus, body: JSONValue, context: ChannelHandlerContext) {
        let data = (try? JSONValueEncoder.encode(body)) ?? Data()
        self.send(status: status, data: data, contentType: "application/json", context: context)
    }

    private func send(status: HTTPResponseStatus, text: String, context: ChannelHandlerContext) {
        self.send(status: status, data: Data(text.utf8), contentType: "text/plain; charset=utf-8", context: context)
    }

    private func send(status: HTTPResponseStatus, data: Data, contentType: String, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(data.count)")
        var responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        responseHead.headers.add(name: "Connection", value: "close")
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

private struct HTTPResponseWriter: @unchecked Sendable {
    let context: ChannelHandlerContext

    func execute(_ operation: @escaping @Sendable () -> Void) {
        self.context.eventLoop.execute(operation)
    }
}
