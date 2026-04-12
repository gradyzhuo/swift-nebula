// Sources/Nebula/Astral/Galaxy/StandardGalaxy.swift

import Foundation
import NIO
import NMTP

public actor StandardGalaxy: Galaxy {
    public static let defaultPort: Int = 62200

    public let identifier: UUID
    public let name: String

    private var managedClusters: [String: LoadBalanceCluster] = [:]
    private var managedBrokerClusters: [String: BrokerCluster] = [:]
    private let defaultRetryPolicy: RetryPolicy
    private var retryPolicyOverrides: [String: RetryPolicy] = [:]
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

    public func configure(namespace: String, retryPolicy: RetryPolicy) {
        retryPolicyOverrides[namespace] = retryPolicy
    }
}

// MARK: - Dispatcher registration

extension StandardGalaxy {

    public func register(on dispatcher: NMTDispatcher) {
        dispatcher.register(RegisterMatter.self) { [unowned self] matter, _ in
            try await self.handleRegister(matter)
        }
        dispatcher.register(FindMatter.self) { [unowned self] matter, _ in
            try await self.handleFind(matter)
        }
        dispatcher.register(UnregisterMatter.self) { [unowned self] matter, _ in
            try await self.handleUnregister(matter)
        }
        dispatcher.register(CloneMatter.self) { [unowned self] _, _ in
            await self.cloneReply()
        }
        dispatcher.register(EnqueueMatter.self) { [unowned self] matter, _ in
            try await self.handleEnqueue(matter)
        }
        dispatcher.register(AckMatter.self) { [unowned self] matter, _ in
            await self.handleAck(matter)
        }
        dispatcher.register(SubscribeMatter.self) { [unowned self] matter, channel in
            try await self.handleSubscribe(matter, channel: channel)
        }
        dispatcher.register(UnsubscribeMatter.self) { [unowned self] matter, channel in
            await self.handleUnsubscribe(matter, channel: channel)
        }
    }
}

// MARK: - RPC Handlers

extension StandardGalaxy {

    private func handleRegister(_ matter: RegisterMatter) async throws -> RegisterReplyMatter {
        let address = try SocketAddress.makeAddressResolvingHost(matter.host, port: matter.port)
        let cluster = try clusterFor(namespace: matter.namespace)
        try await cluster.addStellar(namespace: matter.namespace, endpoint: address)
        return RegisterReplyMatter(status: "ok")
    }

    private func handleFind(_ matter: FindMatter) async throws -> FindReplyMatter {
        guard let cluster = managedClusters[matter.namespace] else {
            return FindReplyMatter()
        }
        let address = try await cluster.allocateStellar(for: matter.namespace)
        return FindReplyMatter(stellarHost: address.ipAddress, stellarPort: address.port)
    }

    private func handleUnregister(_ matter: UnregisterMatter) async throws -> UnregisterReplyMatter {
        guard let cluster = managedClusters[matter.namespace] else {
            return UnregisterReplyMatter()
        }
        await cluster.removeStellar(namespace: matter.namespace, host: matter.host, port: matter.port)
        let next = try? await cluster.allocateStellar(for: matter.namespace)
        return UnregisterReplyMatter(nextHost: next?.ipAddress, nextPort: next?.port)
    }

    private func cloneReply() -> CloneReplyMatter {
        CloneReplyMatter(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.galaxy.rawValue
        )
    }
}

// MARK: - Broker Handlers

extension StandardGalaxy {

    private func handleEnqueue(_ matter: EnqueueMatter) async throws -> RegisterReplyMatter {
        let broker = try brokerClusterFor(namespace: matter.namespace)
        let message = QueuedMatter(
            id: UUID(),
            namespace: matter.namespace,
            service: matter.service,
            method: matter.method,
            arguments: matter.arguments
        )
        try await broker.enqueue(message: message)
        return RegisterReplyMatter(status: "queued")
    }

    private func handleAck(_ matter: AckMatter) async {
        guard let matterID = UUID(uuidString: matter.matterID) else { return }
        for broker in managedBrokerClusters.values {
            await broker.acknowledge(matterID: matterID)
        }
    }

    private func handleSubscribe(_ matter: SubscribeMatter, channel: Channel) async throws -> RegisterReplyMatter {
        let broker = try brokerClusterFor(namespace: matter.topic)
        await broker.subscribe(subscription: matter.subscription, channel: channel)
        return RegisterReplyMatter(status: "ok")
    }

    private func handleUnsubscribe(_ matter: UnsubscribeMatter, channel: Channel) async {
        guard let broker = managedBrokerClusters[matter.topic] else { return }
        await broker.unsubscribe(subscription: matter.subscription, channel: channel)
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

    public func register(namespace: String, stellarEndpoint: SocketAddress) async throws {
        let cluster = try clusterFor(namespace: namespace)
        try await cluster.addStellar(namespace: namespace, endpoint: stellarEndpoint)
    }
}
