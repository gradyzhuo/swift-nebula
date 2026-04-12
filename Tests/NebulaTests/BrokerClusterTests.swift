// Tests/NebulaTests/BrokerClusterTests.swift
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

/// Creates a thread-safe NIOAsyncTestingChannel with a CapturingHandler installed.
/// NIOAsyncTestingChannel uses a thread-safe event loop, so it is safe to use when
/// eventLoop.execute is called from a Task (e.g. BrokerCluster.send / ACK timeout).
func makeAsyncCapturingChannel() -> (NIOAsyncTestingChannel, MatterCapture) {
    let capture = MatterCapture()
    let channel = NIOAsyncTestingChannel()
    channel.pipeline.addHandler(CapturingHandler(capture: capture)).whenSuccess { _ in }
    return (channel, capture)
}

// MARK: - Suite

@Suite("BrokerCluster")
struct BrokerClusterTests {

    // MARK: - Helpers

    private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
        QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                     method: "method", arguments: [])
    }

    /// Broker with default (slow) timeout — for tests that don't exercise ACK timeout.
    private func makeBroker(
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerCluster {
        try BrokerCluster(name: "broker", namespace: "test.broker",
                       active: active, parked: parked)
    }

    /// Broker with a very short ACK timeout — for retry/park tests.
    private func fastBroker(
        maxRetries: Int = 2,
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerCluster {
        try BrokerCluster(name: "broker", namespace: "test.broker",
                       active: active, parked: parked,
                       retryPolicy: RetryPolicy(maxRetries: maxRetries,
                                                ackTimeout: .milliseconds(50)))
    }

    // MARK: - Init

    @Test func init_withDotInName_throws() {
        #expect(throws: (any Error).self) {
            try BrokerCluster(name: "bad.name", namespace: "test.broker")
        }
    }

    // MARK: - Subscribe / Unsubscribe

    @Test func unsubscribe_preventsOutbound() async throws {
        let broker = try makeBroker()
        let (channel, capture) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)
        await broker.unsubscribe(subscription: "g1", channel: channel)

        try await broker.enqueue(message: makeMessage())
        await (channel.eventLoop as! NIOAsyncTestingEventLoop).run()

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
        let (channel, capture) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await (channel.eventLoop as! NIOAsyncTestingEventLoop).run()

        let matters = capture.snapshot()
        let matter = try #require(matters.first)
        #expect(matter.type == .command)
        #expect(matter.matterID == msg.id)
    }

    // MARK: - Fan-out

    @Test func enqueue_fanOut_allSubscriptionGroupsReceiveMessage() async throws {
        let broker = try makeBroker()
        let (channel1, capture1) = makeAsyncCapturingChannel()
        let (channel2, capture2) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel1)
        await broker.subscribe(subscription: "g2", channel: channel2)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await (channel1.eventLoop as! NIOAsyncTestingEventLoop).run()
        await (channel2.eventLoop as! NIOAsyncTestingEventLoop).run()

        let matters1 = capture1.snapshot()
        let matter1 = try #require(matters1.first)
        #expect(matter1.type == .command)
        #expect(matter1.matterID == msg.id)

        let matters2 = capture2.snapshot()
        let matter2 = try #require(matters2.first)
        #expect(matter2.type == .command)
        #expect(matter2.matterID == msg.id)
    }

    // MARK: - Round-robin

    @Test func enqueue_roundRobin_alternatesAcrossChannelsInSameGroup() async throws {
        let broker = try makeBroker()
        let (channel1, capture1) = makeAsyncCapturingChannel()
        let (channel2, capture2) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel1)
        await broker.subscribe(subscription: "g1", channel: channel2)

        let msg1 = makeMessage()
        let msg2 = makeMessage()
        try await broker.enqueue(message: msg1)
        try await broker.enqueue(message: msg2)
        await (channel1.eventLoop as! NIOAsyncTestingEventLoop).run()
        await (channel2.eventLoop as! NIOAsyncTestingEventLoop).run()

        // msg1 → channel1 (index 0), msg2 → channel2 (index 1)
        let matters1 = capture1.snapshot()
        #expect(matters1.count == 1)
        #expect(matters1[0].matterID == msg1.id)

        let matters2 = capture2.snapshot()
        #expect(matters2.count == 1)
        #expect(matters2[0].matterID == msg2.id)
    }

    // MARK: - ACK

    @Test func acknowledge_removesFromActiveQueue() async throws {
        let active = InMemoryQueueStorage()
        let broker = try makeBroker(active: active)
        let (channel, _) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await (channel.eventLoop as! NIOAsyncTestingEventLoop).run()

        await broker.acknowledge(matterID: msg.id)

        let messages = await active.pendingMessages()
        #expect(messages.isEmpty)
    }

    @Test func acknowledge_unknownID_noEffect() async throws {
        let broker = try makeBroker()
        // Must not crash or throw for an unknown ID
        await broker.acknowledge(matterID: UUID())
    }

    // MARK: - Timeout / Retry

    @Test func ackTimeout_belowMaxRetries_retryCountIncrements() async throws {
        let active = InMemoryQueueStorage()
        let broker = try fastBroker(maxRetries: 2, active: active)
        // Use a thread-safe async testing channel so that eventLoop.execute
        // called from the timeout Task does not violate EmbeddedEventLoop's
        // single-thread invariant.
        let (channel, _) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)

        // Poll for the first retry (ackTimeout=50ms). Acknowledge as soon as
        // we observe retryCount=1 to cancel the pending second timeout and
        // keep the test deterministic across slow CI runners.
        var messages: [QueuedMatter] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            messages = await active.pendingMessages()
            if messages.first?.retryCount == 1 {
                await broker.acknowledge(matterID: msg.id)
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        // handleTimeout should have incremented retryCount and re-appended to active.
        #expect(messages.count == 1)
        #expect(messages.first?.retryCount == 1)

        // Drain any pending tasks on the async testing event loop to avoid deinit crash.
        await (channel.eventLoop as! NIOAsyncTestingEventLoop).run()
    }

    @Test func ackTimeout_maxRetriesExhausted_messageParked() async throws {
        let active = InMemoryQueueStorage()
        let parked = InMemoryQueueStorage()
        let broker = try fastBroker(maxRetries: 1, active: active, parked: parked)
        let (channel, _) = makeAsyncCapturingChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await (channel.eventLoop as! NIOAsyncTestingEventLoop).run()

        // Wait for ACK timeout to fire and park the message
        try await Task.sleep(for: .milliseconds(150))

        let activeMessages = await active.pendingMessages()
        #expect(activeMessages.isEmpty)

        let parkedMessages = await parked.pendingMessages()
        #expect(parkedMessages.count == 1)
        #expect(parkedMessages[0].id == msg.id)
    }
}
