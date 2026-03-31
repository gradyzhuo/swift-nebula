//
//  LoadBalanceAmas.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

private struct StellarConnection {
    let client: NMTClient<StellarTarget>
    let address: SocketAddress
}

private struct PendingStellar {
    let task: Task<NMTClient<StellarTarget>, Error>
    let address: SocketAddress
}

/// Amas that manages a pool of Stellar instances with round-robin load balancing.
/// Used internally by Galaxy — not exposed as a standalone TCP server.
/// Future: may also manage MessageQueue and other per-namespace features.
public actor LoadBalanceAmas: Amas {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    private var stellarPools: [String: [StellarConnection]] = [:]
    private var pendingConnections: [String: [PendingStellar]] = [:]
    private var roundRobinIndex: [String: Int] = [:]

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        guard !name.contains(".") else {
            throw NebulaError.fail(message: "Amas name must not contain '.': \"\(name)\"")
        }
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }
}

// MARK: - Stellar Pool Management

extension LoadBalanceAmas {

    /// Add a Stellar to the pool.
    public func addStellar(namespace: String, endpoint: SocketAddress) async throws {
        let pending = PendingStellar(
            task: Task { try await NMTClient.connect(to: endpoint, as: .stellar) },
            address: endpoint
        )
        pendingConnections[namespace, default: []].append(pending)
    }

    /// Returns the next Stellar address via round-robin.
    func allocateStellar(for namespace: String) async throws -> SocketAddress {
        let pool = try await resolvedPool(for: namespace)
        let index = advance(namespace: namespace, poolCount: pool.count)
        return pool[index].address
    }

    /// Remove a Stellar from the pool (e.g. when Planet reports it as dead).
    func removeStellar(namespace: String, host: String, port: Int) {
        stellarPools[namespace]?.removeAll { $0.address.ipAddress == host && $0.address.port == port }
        pendingConnections[namespace]?.removeAll { $0.address.ipAddress == host && $0.address.port == port }
        if let pool = stellarPools[namespace], !pool.isEmpty {
            roundRobinIndex[namespace] = (roundRobinIndex[namespace] ?? 0) % pool.count
        } else {
            roundRobinIndex.removeValue(forKey: namespace)
        }
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
