//
//  StandardIngress.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation
import NIO

/// The root Discovery node for the Nebula network.
///
/// Ingress is the single entry point that Planet connects to.
/// Galaxies register themselves with Ingress on startup.
/// When Planet sends a `find`, Ingress routes to the appropriate Galaxy
/// based on the first segment of the namespace (the Galaxy name).
///
/// Default port: 22400
public actor StandardIngress {
    public static let defaultPort: Int = 22400

    public let identifier: UUID
    public let name: String

    /// Galaxy name → address mapping.
    private var galaxyRegistry: [String: SocketAddress] = [:]
    /// Cached NMTClients to Galaxies for forwarding find requests.
    private var galaxyClients: [String: NMTClient<GalaxyTarget>] = [:]

    public init(name: String = "ingress", identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
    }
}

// MARK: - NMTServerTarget

extension StandardIngress: NMTServerTarget {

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

extension StandardIngress {

    /// Handle Galaxy registration: Galaxy sends its name and address.
    private func handleRegister(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        galaxyRegistry[body.namespace] = address
        return try envelope.reply(body: RegisterReplyBody(status: "ok"))
    }

    /// Handle find from Planet: extract Galaxy name (first namespace segment),
    /// forward to the appropriate Galaxy, relay the response.
    private func handleFind(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(FindBody.self)
        let galaxyName = String(body.namespace.split(separator: ".").first ?? Substring(body.namespace))

        guard let galaxyAddress = galaxyRegistry[galaxyName] else {
            throw NebulaError.discoveryFailed(name: galaxyName)
        }

        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let findEnvelope = try Matter.make(type: .find, body: body)
        let galaxyReply = try await client.request(envelope: findEnvelope)
        let replyBody = try galaxyReply.decodeBody(FindReplyBody.self)
        return try envelope.reply(body: replyBody)
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
        if let existing = galaxyClients[name] {
            return existing
        }
        let client = try await NMTClient.connect(to: address, as: .galaxy)
        galaxyClients[name] = client
        return client
    }
}
