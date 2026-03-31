//
//  NMTServer.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import Logging
import NIO

public final class NMTServer<Target: NMTServerTarget>: Sendable {
    public let address: SocketAddress
    public let target: Target
    private let channel: Channel
    /// Non-nil only when NMTServer created the ELG itself (no caller-supplied group).
    private let ownedEventLoopGroup: MultiThreadedEventLoopGroup?

    internal init(
        address: SocketAddress,
        target: Target,
        channel: Channel,
        ownedEventLoopGroup: MultiThreadedEventLoopGroup?
    ) {
        self.address = address
        self.target = target
        self.channel = channel
        self.ownedEventLoopGroup = ownedEventLoopGroup
    }
}

// MARK: - Bind

extension NMTServer {

    public static func bind(
        on address: SocketAddress,
        target: Target,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer<Target> {
        let owned = eventLoopGroup == nil ? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount) : nil
        let elg = eventLoopGroup ?? owned!
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
        return NMTServer(address: boundAddress, target: target, channel: channel, ownedEventLoopGroup: owned)
    }
}

// MARK: - Listen / Stop

extension NMTServer {

    public func listen() async throws {
        try await channel.closeFuture.get()
        try await ownedEventLoopGroup?.shutdownGracefully()
    }

    public func stop() async throws {
        try await channel.close().get()
        try await ownedEventLoopGroup?.shutdownGracefully()
    }

    /// Close the channel immediately without waiting (safe to call from sync contexts).
    public func closeNow() {
        channel.close(promise: nil)
    }
}

// MARK: - NMTServerInboundHandler

private final class NMTServerInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = Matter
    typealias OutboundOut = Matter

    private let target: any NMTServerTarget
    private let logger = Logger(label: "nebula.nmt.server")

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
                logger.error("handler error: \(error)")
                channel.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
