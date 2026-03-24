//
//  Planet.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO
import MessagePacker

public protocol Planet: Astral {}

extension Planet {
    public static var category: AstralCategory { .planet }
}

private struct PlanetConnection {
    var stellarClient: NMTClient<StellarTarget>
    var stellarAddress: SocketAddress
    /// Amas client for failover — nil if this namespace has no Amas.
    var amasClient: NMTClient<AmasTarget>?
    var amasAddress: SocketAddress?
}

/// A Planet that connects directly to Stellars and uses Amas as a failover path.
/// - Normal path: Planet → Ingress → find Stellar → Planet connects directly to Stellar
/// - Failover path: Stellar unreachable → notify Amas → get next Stellar → reconnect directly
public actor RoguePlanet: Planet {
    public let identifier: UUID
    public let name: String
    public let service: String

    private let ingressClient: NMTClient<IngressTarget>
    /// Per-namespace connection cache.
    private var connections: [String: PlanetConnection] = [:]

    public init(ingressClient: NMTClient<IngressTarget>, identifier: UUID = UUID(), namespace: String, service: String) {
        self.identifier = identifier
        self.name = namespace
        self.ingressClient = ingressClient
        self.service = service
    }
}

// MARK: - Service Call

extension RoguePlanet {

    public func call(
        method: String,
        arguments: [Argument] = []
    ) async throws -> Data? {
        let body = CallBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let conn = try await connection(for: namespace)
        do {
            return try await perform(body: body, via: conn.stellarClient)
        } catch {
            return try await failover(namespace: namespace, deadConnection: conn, body: body)
        }
    }

    public func call<T: Decodable>(
        method: String,
        arguments: [Argument] = [],
        as type: T.Type
    ) async throws -> T {
        guard let data = try await call(
            method: method,
            arguments: arguments
        ) else {
            throw NebulaError.fail(message: "No result from \(namespace).\(service).\(method)")
        }
        return try MessagePackDecoder().decode(type, from: data)
    }
}

// MARK: - Connection Management

extension RoguePlanet {

    /// Returns the cached connection for the namespace, or establishes one via Ingress.
    private func connection(for namespace: String) async throws -> PlanetConnection {
        if let conn = connections[namespace] { return conn }

        let result = try await ingressClient.find(namespace: namespace)
        guard let stellarAddress = result.stellarAddress else {
            throw NebulaError.serviceNotFound(namespace: namespace)
        }

        let stellarClient = try await NMTClient.connect(to: stellarAddress, as: .stellar)
        var amasClient: NMTClient<AmasTarget>?
        if let amasAddress = result.amasAddress {
            amasClient = try await NMTClient.connect(to: amasAddress, as: .amas)
        }

        let conn = PlanetConnection(
            stellarClient: stellarClient,
            stellarAddress: stellarAddress,
            amasClient: amasClient,
            amasAddress: result.amasAddress
        )
        connections[namespace] = conn
        return conn
    }

    private func perform(body: CallBody, via client: NMTClient<StellarTarget>) async throws -> Data? {
        let envelope = try Matter.make(type: .call, body: body)
        let replyMatter = try await client.request(envelope: envelope)
        let reply = try replyMatter.decodeBody(CallReplyBody.self)
        if let error = reply.error {
            throw NebulaError.fail(message: error)
        }
        return reply.result
    }
}

// MARK: - Failover

extension RoguePlanet {

    /// Called when a direct Stellar connection fails.
    /// Notifies the Amas, gets the next Stellar address, reconnects directly, and retries.
    private func failover(
        namespace: String,
        deadConnection: PlanetConnection,
        body: CallBody
    ) async throws -> Data? {
        guard let amasClient = deadConnection.amasClient else {
            connections.removeValue(forKey: namespace)
            throw NebulaError.serviceNotFound(namespace: namespace)
        }

        let result = try await amasClient.unregister(
            namespace: namespace,
            host: deadConnection.stellarAddress.ipAddress ?? "",
            port: deadConnection.stellarAddress.port ?? 0
        )

        guard let nextAddress = result.nextAddress else {
            connections.removeValue(forKey: namespace)
            throw NebulaError.serviceNotFound(namespace: namespace)
        }

        let newClient = try await NMTClient.connect(to: nextAddress, as: .stellar)
        connections[namespace] = PlanetConnection(
            stellarClient: newClient,
            stellarAddress: nextAddress,
            amasClient: amasClient,
            amasAddress: deadConnection.amasAddress
        )

        return try await perform(body: body, via: newClient)
    }
}
