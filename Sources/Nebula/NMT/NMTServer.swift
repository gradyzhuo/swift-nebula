//
//  NMTServer.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class NMTServer<Target: NMTServerTarget>: Sendable {
    public let address: SocketAddress
    public let target: Target
    private let channel: Channel

    internal init(address: SocketAddress, target: Target, channel: Channel) {
        self.address = address
        self.target = target
        self.channel = channel
    }
}

// MARK: - Bind

extension NMTServer {

    public static func bind(
        on address: SocketAddress,
        target: Target,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer<Target> {
        let elg = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let handler = NMTServerInboundHandler(target: target)

        let channel = try await ServerBootstrap(group: elg)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(MatterDecoder()),
                    MessageToByteHandler(MatterEncoder()),
                    handler,
                ])
            }
            .bind(to: address)
            .get()

        let boundAddress = channel.localAddress ?? address
        return NMTServer(address: boundAddress, target: target, channel: channel)
    }
}

// MARK: - Listen / Stop

extension NMTServer {

    public func listen() async throws {
        try await channel.closeFuture.get()
    }

    public func stop() async throws {
        try await channel.close().get()
    }
}

// MARK: - NMTServerInboundHandler

private final class NMTServerInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = Matter
    typealias OutboundOut = Matter

    private let target: any NMTServerTarget

    init(target: some NMTServerTarget) {
        self.target = target
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let channel = context.channel

        Task {
            do {
                if let reply = try await target.handle(envelope: envelope, channel: channel) {
                    channel.writeAndFlush(reply, promise: nil)
                }
            } catch {
                channel.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
