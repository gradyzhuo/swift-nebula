//
//  StandardGalaxy.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO
import NMTP

public actor StandardGalaxy: Galaxy {
    public static let defaultPort: Int = 62200

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

    public func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        switch matter.type {
        case .register:
            return try await handleRegister(envelope: matter)
        case .find:
            return try await handleFind(envelope: matter)
        case .unregister:
            return try await handleUnregister(envelope: matter)
        case .clone:
            return try makeCloneReply(envelope: matter)
        case .enqueue:
            return try await handleEnqueue(envelope: matter)
        case .ack:
            return try await handleAck(envelope: matter)
        case .subscribe:
            return try await handleSubscribe(envelope: matter, channel: channel)
        case .unsubscribe:
            return try await handleUnsubscribe(envelope: matter, channel: channel)
        default:
            return nil
        }
    }
}

// MARK: - RPC Handlers

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
        let message = QueuedMatter(
            id: envelope.matterID,
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
        guard let matterID = UUID(uuidString: body.matterID) else { return nil }
        for broker in managedBrokerAmas.values {
            await broker.acknowledge(matterID: matterID)
        }
        return nil
    }

    private func handleSubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(SubscribeBody.self)
        let broker = try brokerAmasFor(namespace: body.topic)
        await broker.subscribe(subscription: body.subscription, channel: channel)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleUnsubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(UnsubscribeBody.self)
        guard let broker = managedBrokerAmas[body.topic] else { return nil }
        await broker.unsubscribe(subscription: body.subscription, channel: channel)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
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
