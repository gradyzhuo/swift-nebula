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

    /// LoadBalanceCluster instances keyed by namespace (RPC path).
    private var managedClusters: [String: LoadBalanceCluster] = [:]
    /// BrokerCluster instances keyed by namespace (broker path).
    private var managedBrokerClusters: [String: BrokerCluster] = [:]

    /// Global default retry policy for all BrokerCluster instances.
    private let defaultRetryPolicy: RetryPolicy
    /// Per-namespace retry policy overrides.
    private var retryPolicyOverrides: [String: RetryPolicy] = [:]

    /// Optional TLS context forwarded to all outbound NMT connections.
    private let tls: NebulaTLSContext?

    public init(
        name: String,
        tls: NebulaTLSContext? = nil,
        identifier: UUID = UUID(),
        retryPolicy: RetryPolicy = .default
    ) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.tls = tls
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
        let cluster = try clusterFor(namespace: body.namespace)
        try await cluster.addStellar(namespace: body.namespace, endpoint: address)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleFind(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(FindBody.self)

        guard let cluster = managedClusters[body.namespace] else {
            return try envelope.reply(body: FindReplyBody())
        }

        let address = try await cluster.allocateStellar(for: body.namespace)
        return try envelope.reply(body: FindReplyBody(
            stellarHost: address.ipAddress,
            stellarPort: address.port
        ))
    }

    private func handleUnregister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(UnregisterBody.self)

        guard let cluster = managedClusters[body.namespace] else {
            return try envelope.reply(body: UnregisterReplyBody())
        }

        await cluster.removeStellar(namespace: body.namespace, host: body.host, port: body.port)
        let next = try? await cluster.allocateStellar(for: body.namespace)
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
        let broker = try brokerClusterFor(namespace: body.namespace)
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
        for broker in managedBrokerClusters.values {
            await broker.acknowledge(matterID: matterID)
        }
        return nil
    }

    private func handleSubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(SubscribeBody.self)
        let broker = try brokerClusterFor(namespace: body.topic)
        await broker.subscribe(subscription: body.subscription, channel: channel)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleUnsubscribe(envelope: Matter, channel: Channel) async throws -> Matter? {
        let body = try envelope.decodeBody(UnsubscribeBody.self)
        guard let broker = managedBrokerClusters[body.topic] else { return nil }
        await broker.unsubscribe(subscription: body.subscription, channel: channel)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }
}

// MARK: - Cluster Management

extension StandardGalaxy {

    private func clusterFor(namespace: String) throws -> LoadBalanceCluster {
        if let existing = managedClusters[namespace] { return existing }
        let segments = namespace.split(separator: ".")
        let clusterName = segments.count > 1 ? String(segments[1]) : namespace
        let cluster = try LoadBalanceCluster(name: clusterName, namespace: namespace)
        managedClusters[namespace] = cluster
        return cluster
    }

    private func brokerClusterFor(namespace: String) throws -> BrokerCluster {
        if let existing = managedBrokerClusters[namespace] { return existing }
        let segments = namespace.split(separator: ".")
        let clusterName = segments.count > 1 ? String(segments[1]) : namespace
        let policy = retryPolicyOverrides[namespace] ?? defaultRetryPolicy
        let broker = try BrokerCluster(name: clusterName, namespace: namespace, retryPolicy: policy)
        managedBrokerClusters[namespace] = broker
        return broker
    }
}

// MARK: - Programmatic Registration

extension StandardGalaxy {

    /// Register a Stellar endpoint under a namespace (server-side, in-process).
    public func register(namespace: String, stellarEndpoint: SocketAddress) async throws {
        let cluster = try clusterFor(namespace: namespace)
        try await cluster.addStellar(namespace: namespace, endpoint: stellarEndpoint)
    }
}
