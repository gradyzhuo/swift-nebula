//
//  BrokerAmas.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation
import NIO

/// An Amas that handles async messaging — MQ and Pub/Sub.
///
/// Unlike `LoadBalanceAmas` (load balancer only), `BrokerAmas` manages:
/// - A topic + subscription model (fan-out to all groups, round-robin within each group)
/// - At-least-once delivery via ACK + retry
/// - Parked messages when retries are exhausted
///
/// `BrokerAmas` is system-managed by Galaxy for `nmtp+broker://` namespaces.
public actor BrokerAmas: Amas {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    let active: any QueueStorage
    let parked: any QueueStorage
    let retryPolicy: RetryPolicy

    /// subscription name → list of subscriber channels
    private var subscriptions: [String: [Channel]] = [:]
    /// matterID → (subscription, channel) waiting for ACK
    private var pendingAcks: [UUID: PendingAck] = [:]
    private var roundRobinIndex: [String: Int] = [:]

    public init(
        name: String,
        namespace: String,
        identifier: UUID = UUID(),
        active: any QueueStorage = InMemoryQueueStorage(),
        parked: any QueueStorage = InMemoryQueueStorage(),
        retryPolicy: RetryPolicy = .default
    ) throws {
        guard !name.contains(".") else {
            throw NebulaError.fail(message: "BrokerAmas name must not contain '.': \"\(name)\"")
        }
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
        self.active = active
        self.parked = parked
        self.retryPolicy = retryPolicy
    }
}

// MARK: - Subscription Management

extension BrokerAmas {

    /// Register a subscriber channel under a named subscription group.
    /// The group is created implicitly on first join.
    func subscribe(subscription: String, channel: Channel) {
        subscriptions[subscription, default: []].append(channel)
    }

    func unsubscribe(subscription: String, channel: Channel) {
        subscriptions[subscription]?.removeAll {
            $0.remoteAddress == channel.remoteAddress
        }
    }
}

// MARK: - Enqueue & Dispatch

extension BrokerAmas {

    /// Accept an inbound message from Comet, persist it, and start dispatch.
    func enqueue(message: QueuedMatter) async throws {
        try await active.append(message)
        await dispatch(message: message)
    }

    /// Fan-out the message to all subscription groups, round-robin within each group.
    private func dispatch(message: QueuedMatter) async {
        guard !subscriptions.isEmpty else { return }

        for (subscription, channels) in subscriptions {
            guard !channels.isEmpty else { continue }
            let index = (roundRobinIndex[subscription] ?? 0) % channels.count
            roundRobinIndex[subscription] = index + 1
            let channel = channels[index]
            send(message: message, to: channel, subscription: subscription)
        }
    }

    private func send(message: QueuedMatter, to channel: Channel, subscription: String) {
        Task {
            do {
                let body = EnqueueBody(
                    namespace: message.namespace,
                    service: message.service,
                    method: message.method,
                    arguments: message.arguments
                )
                let envelope = try Matter.make(
                    type: .enqueue,
                    body: body,
                    matterID: message.id
                )
                channel.writeAndFlush(envelope, promise: nil)
                pendingAcks[message.id] = PendingAck(
                    message: message,
                    subscription: subscription,
                    channel: channel,
                    sentAt: Date()
                )
                try await scheduleAckTimeout(for: message)
            } catch {
                await park(message: message)
            }
        }
    }

    private func scheduleAckTimeout(for message: QueuedMatter) async throws {
        try await Task.sleep(for: retryPolicy.ackTimeout)

        guard pendingAcks[message.id] != nil else { return }  // already ACKed
        await handleTimeout(matterID: message.id)
    }
}

// MARK: - ACK & Retry

extension BrokerAmas {

    /// Called when a subscriber sends back an `.ack` for a message.
    func acknowledge(matterID: UUID) async {
        guard pendingAcks.removeValue(forKey: matterID) != nil else { return }
        try? await active.remove(id: matterID)
    }

    private func handleTimeout(matterID: UUID) async {
        guard let pending = pendingAcks.removeValue(forKey: matterID) else { return }
        var message = pending.message
        message.retryCount += 1

        if message.retryCount >= retryPolicy.maxRetries {
            await park(message: message)
        } else {
            try? await active.append(message)
            await dispatch(message: message)
        }
    }

    private func park(message: QueuedMatter) async {
        try? await active.remove(id: message.id)
        try? await parked.append(message)
    }
}

// MARK: - Supporting Types

private struct PendingAck {
    let message: QueuedMatter
    let subscription: String
    let channel: Channel
    let sentAt: Date
}
