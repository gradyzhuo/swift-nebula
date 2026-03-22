//
//  NMTServer.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public protocol NMTServerDelegate: Sendable {
    /// Handle an incoming envelope. Return a reply envelope, or nil for no reply.
    func handle(envelope: Envelope) async throws -> Envelope?
}

public final class NMTServer: Sendable {
    public let address: SocketAddress
    private let channel: Channel

    internal init(address: SocketAddress, channel: Channel) {
        self.address = address
        self.channel = channel
    }
}

// MARK: - Bind

extension NMTServer {

    public static func bind(
        on address: SocketAddress,
        delegate: some NMTServerDelegate,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        let elg = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let handler = NMTServerInboundHandler(delegate: delegate)

        let channel = try await ServerBootstrap(group: elg)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(EnvelopeDecoder()),
                    MessageToByteHandler(EnvelopeEncoder()),
                    handler,
                ])
            }
            .bind(to: address)
            .get()

        return NMTServer(address: address, channel: channel)
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
    typealias InboundIn  = Envelope
    typealias OutboundOut = Envelope

    private let delegate: any NMTServerDelegate

    init(delegate: some NMTServerDelegate) {
        self.delegate = delegate
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let channel = context.channel

        Task {
            do {
                if let reply = try await delegate.handle(envelope: envelope) {
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
