//
//  StandardGalaxy.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public actor StandardGalaxy: Galaxy {
    public let identifier: UUID
    public let name: String
    public let registry: any ServiceRegistry

    /// Internally managed LoadBalanceAmas instances keyed by namespace.
    private var managedAmas: [String: ManagedAmasEntry] = [:]

    public init(name: String, identifier: UUID = UUID(), registry: (any ServiceRegistry)? = nil) {
        self.identifier = identifier
        self.name = name
        self.registry = registry ?? InMemoryServiceRegistry()
    }
}

// MARK: - NMTServerDelegate

extension StandardGalaxy: NMTServerDelegate {

    public func handle(envelope: Matter) async throws -> Matter? {
        switch envelope.type {
        case .register:
            return try await handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }
}

// MARK: - NMT Handlers

extension StandardGalaxy {

    private func handleRegister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        try await registry.register(namespace: body.namespace, address: address)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    private func handleFind(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(FindBody.self)

        // If there's a managed Amas for this namespace, return Stellar + Amas addresses
        if let entry = managedAmas[body.namespace] {
            let stellarAddress = try await entry.allocateStellar(for: body.namespace)
            let amasAddress = entry.server.address
            let reply = FindReplyBody(
                stellarHost: stellarAddress.ipAddress,
                stellarPort: stellarAddress.port,
                amasHost: amasAddress.ipAddress,
                amasPort: amasAddress.port
            )
            return try envelope.reply(body: reply)
        }

        // Fall back: direct Stellar registered without Amas
        let address = try await registry.find(namespace: body.namespace)
        let reply = FindReplyBody(
            stellarHost: address?.ipAddress,
            stellarPort: address?.port
        )
        return try envelope.reply(body: reply)
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

// MARK: - Galaxy Protocol: Managed Amas Registration

extension StandardGalaxy {

    public func register(namespace: String, stellarEndpoint: SocketAddress) async throws {
        if let entry = managedAmas[namespace] {
            try await entry.addStellar(namespace: namespace, endpoint: stellarEndpoint)
        } else {
            let amas = LoadBalanceAmas(name: namespace, namespace: namespace)
            let server = try await NMTServer.bind(
                on: SocketAddress(ipAddress: "::1", port: 0),
                delegate: amas
            )
            let entry = ManagedAmasEntry(amas: amas, server: server)
            managedAmas[namespace] = entry
            try await entry.addStellar(namespace: namespace, endpoint: stellarEndpoint)
        }
    }
}

// MARK: - ManagedAmasEntry

private struct ManagedAmasEntry {
    let amas: LoadBalanceAmas
    let server: NMTServer

    func addStellar(namespace: String, endpoint: SocketAddress) async throws {
        try await amas.addStellar(namespace: namespace, endpoint: endpoint)
    }

    func allocateStellar(for namespace: String) async throws -> SocketAddress {
        return try await amas.allocateStellar(for: namespace)
    }
}
