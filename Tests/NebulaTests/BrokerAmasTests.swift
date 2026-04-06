// Tests/NebulaTests/BrokerAmasTests.swift
import Testing
import Foundation
import NIO
import NIOEmbedded
import NMTP
import Synchronization
@testable import Nebula

// MARK: - Test Helpers

/// A thread-safe store for Matter objects captured during testing.
final class MatterCapture: @unchecked Sendable {
    private let mutex = Mutex<[Matter]>([])

    func record(_ matter: Matter) {
        mutex.withLock { $0.append(matter) }
    }

    func snapshot() -> [Matter] {
        mutex.withLock { $0 }
    }
}

/// Outbound handler that captures any `Matter` written to the channel.
final class CapturingHandler: ChannelOutboundHandler {
    typealias OutboundIn = Matter
    typealias OutboundOut = Matter

    let capture: MatterCapture

    init(capture: MatterCapture) {
        self.capture = capture
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let matter = unwrapOutboundIn(data)
        capture.record(matter)
        context.write(data, promise: promise)
    }
}

/// Creates an EmbeddedChannel with a CapturingHandler installed and returns both.
func makeCapturingChannel() throws -> (EmbeddedChannel, MatterCapture) {
    let capture = MatterCapture()
    let channel = EmbeddedChannel()
    try channel.pipeline.addHandler(CapturingHandler(capture: capture)).wait()
    return (channel, capture)
}

// MARK: - Suite

@Suite("BrokerAmas")
struct BrokerAmasTests {

    // MARK: - Helpers

    private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
        QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                     method: "method", arguments: [])
    }

    /// Broker with default (slow) timeout — for tests that don't exercise ACK timeout.
    private func makeBroker(
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerAmas {
        try BrokerAmas(name: "broker", namespace: "test.broker",
                       active: active, parked: parked)
    }

    /// Broker with a very short ACK timeout — for retry/park tests.
    private func fastBroker(
        maxRetries: Int = 2,
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerAmas {
        try BrokerAmas(name: "broker", namespace: "test.broker",
                       active: active, parked: parked,
                       retryPolicy: RetryPolicy(maxRetries: maxRetries,
                                                ackTimeout: .milliseconds(50)))
    }

    // MARK: - Init

    @Test func init_withDotInName_throws() {
        #expect(throws: (any Error).self) {
            try BrokerAmas(name: "bad.name", namespace: "test.broker")
        }
    }

    // MARK: - Subscribe / Unsubscribe

    @Test func unsubscribe_preventsOutbound() async throws {
        let broker = try makeBroker()
        let (channel, capture) = try makeCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)
        await broker.unsubscribe(subscription: "g1", channel: channel)

        try await broker.enqueue(message: makeMessage())
        await Task.yield()
        await Task.yield()

        #expect(capture.snapshot().isEmpty)
    }

    // MARK: - Enqueue

    @Test func enqueue_noSubscribers_persistsToActiveOnly() async throws {
        let active = InMemoryQueueStorage()
        let broker = try makeBroker(active: active)
        let msg = makeMessage()

        try await broker.enqueue(message: msg)

        let messages = await active.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].id == msg.id)
    }

    @Test func enqueue_withSubscriber_channelReceivesEnqueueMatter() async throws {
        let broker = try makeBroker()
        let (channel, capture) = try makeCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        // Allow the unstructured Task spawned inside BrokerAmas.send() to execute.
        try await Task.sleep(for: .milliseconds(50))

        let matters = capture.snapshot()
        let matter = try #require(matters.first)
        #expect(matter.type == .enqueue)
        #expect(matter.matterID == msg.id)
    }
}
