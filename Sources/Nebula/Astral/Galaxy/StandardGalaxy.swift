//
//  StandardGalaxy.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public actor StandardGalaxy: Galaxy {
    public static let defaultPort: Int = 2240

    public let identifier: UUID
    public let name: String

    /// LoadBalanceAmas instances keyed by namespace (RPC path).
    private var managedAmas: [String: LoadBalanceAmas] = [:]
    /// BrokerAmas instances keyed by namespace (broker path).
    private var managedBrokerAmas: [String: BrokerAmas] = [:]

    /// Global default retry policy for all BrokerAmas instances.
    private let defaultRetryPolicy: RetryPolicy
    /// Per-namespace retry policy overrides.
    private var retryPolicyOverrides: [String: RetryPolicy] = [:]

    public init(
        name: String,
        identifier: UUID = UUID(),
        retryPolicy: RetryPolicy = .default
    ) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.defaultRetryPolicy = retryPolicy
    }

    /// Override the retry policy for a specific broker namespace.
    public func configure(namespace: String, retryPolicy: RetryPolicy) {
        retryPolicyOverrides[namespace] = retryPolicy
    }
}

// MARK: - NMTServerTarget

extension StandardGalaxy: NMTServerTarget {

    public func handle(envelope: Matter, channel: Channel) async throws -> Matter? {
        switch envelope.type {
        case .register:
            return try await handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .unregister:
            return try await handleUnregister(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        case .enqueue:
            return try await handleEnqueue(envelope: envelope)
        case .ack:
            return try await handleAck(envelope: envelope)
        case .subscribe:
            return try await handleSubscribe(envelope: envelope, channel: channel)
        case .unsubscribe:
            return try await handleUnsubscribe(envelope: envelope, channel: channel)
        default:
            return nil
        }
    }
}

// MARK: - RPC Handlers (unchanged)

extension StandardGalaxy {

    private func handleRegister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        let amas = try amasFor(namespace: body.namespace)
        try await amas.addStellar(namespace: body.namespace, endpoint: address)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleFind(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(FindBody.self)

        guard let amas = managedAmas[body.namespace] else {
            return try envelope.reply(body: FindReplyBody())
        }

        let address = try await amas.allocateStellar(for: body.namespace)
        return try envelope.reply(body: FindReplyBody(
            stellarHost: address.ipAddress,
            stellarPort: address.port
        ))
    }

    private func handleUnregister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(UnregisterBody.self)

        guard let amas = managedAmas[body.namespace] else {
            return try envelope.reply(body: UnregisterReplyBody())
        }

        await amas.removeStellar(namespace: body.namespace, host: body.host, port: body.port)
        let next = try? await amas.allocateStellar(for: body.namespace)
        return try envelope.reply(body: UnregisterReplyBody(
            nextHost: next?.ipAddress,
            nextPort: next?.port
        ))
    }

    private func makeCloneReply(envelope: Matter) throws -> Matter {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.galaxy.rawValue
        )
        return try envelope.reply(body: reply)
    }
}

// MARK: - Broker Handlers

extension StandardGalaxy {

    private func handleEnqueue(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(EnqueueBody.self)
        let broker = try brokerAmasFor(namespace: body.namespace)
        let message = QueuedMessage(
            id: envelope.messageID,
            namespace: body.namespace,
            service: body.service,
            method: body.method,
            arguments: body.arguments
        )
        try await broker.enqueue(message: message)
        return try envelope.reply(body: RegisterReplyBody(status: "queued"))
    }

    private func handleAck(envelope: Matter) async throws -> Matter? {
        let body = try envelope.decodeBody(AckBody.self)
        guard let messageID = UUID(uuidString: body.messageID) else { return nil }
        // Find the BrokerAmas that owns this message (search all brokers)
        for broker in managedBrokerAmas.values {
            await broker.acknowledge(messageID: messageID)
        }
        return nil
    }

    private func handleSubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(SubscribeBody.self)
        let broker = try brokerAmasFor(namespace: body.topic)
        await broker.subscribe(subscription: body.subscription, channel: channel)
        return nil
    }

    private func handleUnsubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(UnsubscribeBody.self)
        guard let broker = managedBrokerAmas[body.topic] else { return nil }
        await broker.unsubscribe(subscription: body.subscription, channel: channel)
        return nil
    }
}

// MARK: - Amas Management

extension StandardGalaxy {

    private func amasFor(namespace: String) throws -> LoadBalanceAmas {
        if let existing = managedAmas[namespace] { return existing }
        let segments = namespace.split(separator: ".")
        let amasName = segments.count > 1 ? String(segments[1]) : namespace
        let amas = try LoadBalanceAmas(name: amasName, namespace: namespace)
        managedAmas[namespace] = amas
        return amas
    }

    private func brokerAmasFor(namespace: String) throws -> BrokerAmas {
        if let existing = managedBrokerAmas[namespace] { return existing }
        let segments = namespace.split(separator: ".")
        let amasName = segments.count > 1 ? String(segments[1]) : namespace
        let policy = retryPolicyOverrides[namespace] ?? defaultRetryPolicy
        let broker = try BrokerAmas(name: amasName, namespace: namespace, retryPolicy: policy)
        managedBrokerAmas[namespace] = broker
        return broker
    }
}

// MARK: - Programmatic Registration

extension StandardGalaxy {

    /// Register a Stellar endpoint under a namespace (server-side, in-process).
    public func register(namespace: String, stellarEndpoint: SocketAddress) async throws {
        let amas = try amasFor(namespace: namespace)
        try await amas.addStellar(namespace: namespace, endpoint: stellarEndpoint)
    }
}
