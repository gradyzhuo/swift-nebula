//
//  StandardIngress.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation
import NIO

/// The root entry point for the Nebula network.
///
/// Ingress is a Galaxy routing table — it knows which Galaxy lives where.
/// Galaxies register themselves with Ingress on startup.
/// When Planet sends a `find` or `unregister`, Ingress routes to the appropriate Galaxy.
///
/// Default port: 2240
public actor StandardIngress {
    public static let defaultPort: Int = 6224

    public let identifier: UUID
    public let name: String

    /// Galaxy name → address mapping.
    private var galaxyRegistry: [String: SocketAddress] = [:]
    /// Cached NMTClients to Galaxies.
    private var galaxyClients: [String: NMTClient<GalaxyTarget>] = [:]

    public init(name: String = "ingress", identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
    }
}

// MARK: - NMTServerTarget

extension StandardIngress: NMTServerTarget {

    public func handle(envelope: Matter, channel: Channel) async throws -> Matter? {
        switch envelope.type {
        case .register:
            return try handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .unregister:
            return try await handleUnregister(envelope: envelope)
        case .enqueue:
            return try await handleEnqueue(envelope: envelope)
        case .findGalaxy:
            return try handleFindGalaxy(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }
}

// MARK: - NMT Handlers

extension StandardIngress {

    /// Handle Galaxy registration: Galaxy sends its name and address.
    private func handleRegister(envelope: Matter) throws -> Matter {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        galaxyRegistry[body.namespace] = address
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    /// Handle find from Planet: extract Galaxy name, forward to Galaxy, relay response.
    private func handleFind(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(FindBody.self)
        let galaxyName = String(body.namespace.split(separator: ".").first ?? Substring(body.namespace))

        guard let galaxyAddress = galaxyRegistry[galaxyName] else {
            return try envelope.reply(body: FindReplyBody())
        }

        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let findEnvelope = try Matter.make(type: .find, body: body)
        let galaxyReply = try await client.request(envelope: findEnvelope)
        let replyBody = try galaxyReply.decodeBody(FindReplyBody.self)
        return try envelope.reply(body: replyBody)
    }

    /// Handle unregister from Planet (failover): forward to Galaxy.
    private func handleUnregister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(UnregisterBody.self)
        let galaxyName = String(body.namespace.split(separator: ".").first ?? Substring(body.namespace))

        guard let galaxyAddress = galaxyRegistry[galaxyName] else {
            return try envelope.reply(body: UnregisterReplyBody())
        }

        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let unregEnvelope = try Matter.make(type: .unregister, body: body)
        let galaxyReply = try await client.request(envelope: unregEnvelope)
        let replyBody = try galaxyReply.decodeBody(UnregisterReplyBody.self)
        return try envelope.reply(body: replyBody)
    }

    /// Handle enqueue from Comet: forward to the Galaxy that owns the namespace.
    private func handleEnqueue(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(EnqueueBody.self)
        let galaxyName = String(body.namespace.split(separator: ".").first ?? Substring(body.namespace))

        guard let galaxyAddress = galaxyRegistry[galaxyName] else {
            return try envelope.reply(body: RegisterReplyBody(status: "no-galaxy"))
        }

        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let enqueueEnvelope = try Matter.make(type: .enqueue, body: body)
        let galaxyReply = try await client.request(envelope: enqueueEnvelope)
        let replyBody = try galaxyReply.decodeBody(RegisterReplyBody.self)
        return try envelope.reply(body: replyBody)
    }

    /// Handle broker Galaxy discovery: return the Galaxy address for a given topic.
    private func handleFindGalaxy(envelope: Matter) throws -> Matter {
        let body = try envelope.decodeBody(FindGalaxyBody.self)
        let galaxyName = String(body.topic.split(separator: ".").first ?? Substring(body.topic))

        guard let address = galaxyRegistry[galaxyName] else {
            return try envelope.reply(body: FindGalaxyReplyBody())
        }
        return try envelope.reply(body: FindGalaxyReplyBody(
            galaxyHost: address.ipAddress,
            galaxyPort: address.port
        ))
    }

    private func makeCloneReply(envelope: Matter) throws -> Matter {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: 0  // Ingress is infrastructure, not an Astral node
        )
        return try envelope.reply(body: reply)
    }
}

// MARK: - Galaxy Client Cache

extension StandardIngress {

    private func galaxyClient(
        for name: String,
        at address: SocketAddress
    ) async throws -> NMTClient<GalaxyTarget> {
        if let existing = galaxyClients[name], existing.targetAddress == address {
            return existing
        }
        let client = try await NMTClient.connect(to: address, as: .galaxy)
        galaxyClients[name] = client
        return client
    }
}
