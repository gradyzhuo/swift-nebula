//
//  NMTClient+Astral.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

// MARK: - Result Types

public struct FindResult: Sendable {
    /// Direct Stellar endpoint to connect to.
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    /// Next available Stellar endpoint after removing the dead one (nil = pool exhausted).
    public let nextAddress: SocketAddress?
}

// MARK: - Ingress Operations

extension NMTClient where Target == IngressTarget {

    /// Find the Stellar address for a namespace via Ingress → Galaxy.
    public func find(namespace: String) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let envelope = try Matter.make(type: .find, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(FindReplyBody.self)

        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a Galaxy with Ingress (Galaxy name → address).
    public func registerGalaxy(name: String, address: SocketAddress, identifier: UUID) async throws {
        let body = RegisterBody(
            namespace: name,
            host: address.ipAddress ?? "0.0.0.0",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let envelope = try Matter.make(type: .register, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register Galaxy failed: \(replyBody.status)")
        }
    }

    /// Enqueue an async task via Ingress → Galaxy → BrokerAmas.
    /// Returns once BrokerAmas confirms receipt.
    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = []
    ) async throws {
        let body = EnqueueBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let envelope = try Matter.make(type: .enqueue, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "queued" else {
            throw NebulaError.fail(message: "Enqueue failed: \(replyBody.status)")
        }
    }

    /// Find the Galaxy address that manages a broker topic via Ingress.
    public func findGalaxy(topic: String) async throws -> SocketAddress? {
        let body = FindGalaxyBody(topic: topic)
        let envelope = try Matter.make(type: .findGalaxy, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(FindGalaxyReplyBody.self)

        guard let host = replyBody.galaxyHost, let port = replyBody.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }

    /// Notify Ingress that a Stellar is dead (forwarded to Galaxy). Returns next Stellar.
    public func unregister(namespace: String, host: String, port: Int) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let envelope = try Matter.make(type: .unregister, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)

        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        return UnregisterResult(nextAddress: nextAddress)
    }
}

// MARK: - Galaxy Operations

extension NMTClient where Target == GalaxyTarget {

    /// Find the Stellar address for a namespace.
    public func find(namespace: String) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let envelope = try Matter.make(type: .find, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(FindReplyBody.self)

        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a namespace → address mapping in Galaxy.
    public func register(namespace: String, address: SocketAddress, identifier: UUID) async throws {
        let body = RegisterBody(
            namespace: namespace,
            host: address.ipAddress ?? "::1",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let envelope = try Matter.make(type: .register, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyBody.status)")
        }
    }

    /// Register a ServerAstral with Galaxy.
    public func register(astral: some Astral, listeningOn address: SocketAddress) async throws {
        try await register(
            namespace: astral.namespace,
            address: address,
            identifier: astral.identifier
        )
    }

    /// Notify Galaxy that a Stellar is dead. Returns the next available Stellar address.
    public func unregister(namespace: String, host: String, port: Int) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let envelope = try Matter.make(type: .unregister, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)

        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        return UnregisterResult(nextAddress: nextAddress)
    }
}

// MARK: - Any Astral Node Operations

extension NMTClient where Target: AstralClientTarget {

    /// Fetch the remote node's identity info (works on any Astral node).
    public func clone() async throws -> CloneReplyBody {
        let envelope = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await request(envelope: envelope)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}
