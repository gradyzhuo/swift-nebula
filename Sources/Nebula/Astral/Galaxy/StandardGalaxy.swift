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

    /// Internally managed Amas instances keyed by namespace.
    /// Amas handles load balancing, pool management, and future features (e.g. MessageQueue).
    private var managedAmas: [String: LoadBalanceAmas] = [:]

    public init(name: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
    }
}

// MARK: - NMTServerTarget

extension StandardGalaxy: NMTServerTarget {

    public func handle(envelope: Matter) async throws -> Matter? {
        switch envelope.type {
        case .register:
            return try await handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .unregister:
            return try await handleUnregister(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }
}

// MARK: - NMT Handlers

extension StandardGalaxy {

    /// Handle Stellar registration: delegate to Amas (auto-created per namespace).
    private func handleRegister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        let amas = try amasFor(namespace: body.namespace)
        try await amas.addStellar(namespace: body.namespace, endpoint: address)
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    /// Handle find: delegate round-robin allocation to Amas.
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

    /// Handle unregister (failover): delegate to Amas, return next Stellar.
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

// MARK: - Amas Management

extension StandardGalaxy {

    /// Get or create an Amas for the given namespace.
    private func amasFor(namespace: String) throws -> LoadBalanceAmas {
        if let existing = managedAmas[namespace] {
            return existing
        }
        let segments = namespace.split(separator: ".")
        let amasName = segments.count > 1 ? String(segments[1]) : namespace
        let amas = try LoadBalanceAmas(name: amasName, namespace: namespace)
        managedAmas[namespace] = amas
        return amas
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
