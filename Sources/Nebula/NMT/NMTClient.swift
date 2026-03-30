//
//  NMTClient.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class NMTClient<Target: NMTClientTarget>: @unchecked Sendable {
    public let targetAddress: SocketAddress
    public let target: Target

    /// Server-push stream: unsolicited inbound Matter (no pending request match).
    /// Satellite subscribes here to receive Galaxy-pushed `.enqueue` events.
    public let pushes: AsyncStream<Matter>

    private let channel: Channel
    private let pendingRequests: PendingRequests
    private let pushContinuation: AsyncStream<Matter>.Continuation

    internal init(
        targetAddress: SocketAddress,
        target: Target,
        channel: Channel,
        pendingRequests: PendingRequests,
        pushes: AsyncStream<Matter>,
        pushContinuation: AsyncStream<Matter>.Continuation
    ) {
        self.targetAddress = targetAddress
        self.target = target
        self.channel = channel
        self.pendingRequests = pendingRequests
        self.pushes = pushes
        self.pushContinuation = pushContinuation
    }
}

// MARK: - Connect

extension NMTClient {

    public static func connect(
        to address: SocketAddress,
        as target: Target,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTClient<Target> {
        let elg = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let pendingRequests = PendingRequests()

        // Build client first to get the push continuation
        var cont: AsyncStream<Matter>.Continuation!
        let pushes = AsyncStream<Matter> { cont = $0 }

        let inboundHandler = NMTClientInboundHandler(
            pendingRequests: pendingRequests,
            pushContinuation: cont
        )

        let channel = try await ClientBootstrap(group: elg)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(MatterDecoder()),
                    MessageToByteHandler(MatterEncoder()),
                    inboundHandler,
                ])
            }
            .connect(to: address)
            .get()

        return NMTClient(
            targetAddress: address,
            target: target,
            channel: channel,
            pendingRequests: pendingRequests,
            pushes: pushes,
            pushContinuation: cont
        )
    }
}

// MARK: - Send

extension NMTClient {

    /// Fire-and-forget: send a Matter without waiting for a reply.
    public func fire(envelope: Matter) {
        channel.writeAndFlush(envelope, promise: nil)
    }

    /// Send a Matter and wait for a reply (matched by matterID).
    public func request(envelope: Matter) async throws -> Matter {
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.register(id: envelope.matterID, continuation: continuation)
            channel.writeAndFlush(envelope, promise: nil)
        }
    }

    public func close() async throws {
        try await channel.close().get()
    }
}

// MARK: - PendingRequests

final class PendingRequests: @unchecked Sendable {
    private var waiting: [UUID: CheckedContinuation<Matter, Error>] = [:]
    private let lock = NSLock()

    func register(id: UUID, continuation: CheckedContinuation<Matter, Error>) {
        lock.lock()
        waiting[id] = continuation
        lock.unlock()
    }

    /// Returns true if the envelope matched a pending request, false if it is a server-push.
    @discardableResult
    func fulfill(_ envelope: Matter) -> Bool {
        lock.lock()
        let continuation = waiting.removeValue(forKey: envelope.matterID)
        lock.unlock()
        continuation?.resume(returning: envelope)
        return continuation != nil
    }

    func fail(id: UUID, error: Error) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

// MARK: - NMTClientInboundHandler

private final class NMTClientInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Matter

    private let pendingRequests: PendingRequests
    private let pushContinuation: AsyncStream<Matter>.Continuation

    init(pendingRequests: PendingRequests, pushContinuation: AsyncStream<Matter>.Continuation) {
        self.pendingRequests = pendingRequests
        self.pushContinuation = pushContinuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        if !pendingRequests.fulfill(envelope) {
            pushContinuation.yield(envelope)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
