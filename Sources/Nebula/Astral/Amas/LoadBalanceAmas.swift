//
//  LoadBalanceAmas.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

private struct StellarConnection {
    let client: NMTClient
    let address: SocketAddress
}

private struct PendingStellar {
    let task: Task<NMTClient, Error>
    let address: SocketAddress
}

/// Amas that distributes calls across multiple Stellar instances using round-robin.
public actor LoadBalanceAmas: Amas {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    private var stellarPools: [String: [StellarConnection]] = [:]
    private var pendingConnections: [String: [PendingStellar]] = [:]
    private var roundRobinIndex: [String: Int] = [:]

    public init(name: String, namespace: String, identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }
}

// MARK: - NMTServerDelegate

extension LoadBalanceAmas: NMTServerDelegate {

    public func handle(envelope: Envelope) async throws -> Envelope? {
        switch envelope.type {
        case .register:
            return try await handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .call:
            return try await handleCall(envelope: envelope)
        case .unregister:
            return try await handleUnregister(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }
}

// MARK: - Handlers

extension LoadBalanceAmas {

    private func handleRegister(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        try await addStellar(namespace: body.namespace, endpoint: address)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleFind(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(FindBody.self)
        let address = try? await allocateStellar(for: body.namespace)
        let reply = FindReplyBody(
            stellarHost: address?.ipAddress,
            stellarPort: address?.port
        )
        return try envelope.reply(body: reply)
    }

    private func handleCall(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(CallBody.self)
        let conn = try await nextConnection(for: body.namespace)
        let forwardEnvelope = try Envelope.make(type: .call, body: body)
        let reply = try await conn.client.request(envelope: forwardEnvelope)
        return Envelope(type: .reply, messageID: envelope.messageID, body: reply.body)
    }

    private func handleUnregister(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(UnregisterBody.self)
        removeStellar(namespace: body.namespace, host: body.host, port: body.port)
        let next = try? await allocateStellar(for: body.namespace)
        let reply = UnregisterReplyBody(nextHost: next?.ipAddress, nextPort: next?.port)
        return try envelope.reply(body: reply)
    }

    private func makeCloneReply(envelope: Envelope) throws -> Envelope {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.amas.rawValue
        )
        return try envelope.reply(body: reply)
    }
}

// MARK: - Stellar Pool Management

extension LoadBalanceAmas {

    /// Add a Stellar to the pool (called by Galaxy or via NMT register message).
    public func addStellar(namespace: String, endpoint: SocketAddress) async throws {
        let pending = PendingStellar(
            task: Task { try await NMTClient.connect(to: endpoint) },
            address: endpoint
        )
        pendingConnections[namespace, default: []].append(pending)
    }

    /// Returns the next Stellar address via round-robin (advances the counter).
    /// Called by Galaxy when responding to a Planet's `find` request.
    func allocateStellar(for namespace: String) async throws -> SocketAddress {
        let pool = try await resolvedPool(for: namespace)
        let index = advance(namespace: namespace, poolCount: pool.count)
        return pool[index].address
    }

    /// Remove a Stellar from the pool (e.g. when Planet reports it as dead).
    private func removeStellar(namespace: String, host: String, port: Int) {
        stellarPools[namespace]?.removeAll { $0.address.ipAddress == host && $0.address.port == port }
        pendingConnections[namespace]?.removeAll { $0.address.ipAddress == host && $0.address.port == port }
        // Keep round-robin index in bounds
        if let pool = stellarPools[namespace], !pool.isEmpty {
            roundRobinIndex[namespace] = (roundRobinIndex[namespace] ?? 0) % pool.count
        } else {
            roundRobinIndex.removeValue(forKey: namespace)
        }
    }

    private func nextConnection(for namespace: String) async throws -> StellarConnection {
        let pool = try await resolvedPool(for: namespace)
        let index = advance(namespace: namespace, poolCount: pool.count)
        return pool[index]
    }

    private func resolvedPool(for namespace: String) async throws -> [StellarConnection] {
        if let pending = pendingConnections[namespace], !pending.isEmpty {
            var resolved: [StellarConnection] = []
            for p in pending {
                let client = try await p.task.value
                resolved.append(StellarConnection(client: client, address: p.address))
            }
            stellarPools[namespace, default: []].append(contentsOf: resolved)
            pendingConnections.removeValue(forKey: namespace)
        }
        guard let pool = stellarPools[namespace], !pool.isEmpty else {
            throw NebulaError.serviceNotFound(namespace: namespace)
        }
        return pool
    }

    private func advance(namespace: String, poolCount: Int) -> Int {
        let index = (roundRobinIndex[namespace] ?? 0) % poolCount
        roundRobinIndex[namespace] = index + 1
        return index
    }
}
