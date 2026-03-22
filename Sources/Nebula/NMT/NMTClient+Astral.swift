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
    /// Amas endpoint for failover (nil = no Amas, no failover available).
    public let amasAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    /// Next available Stellar endpoint after removing the dead one (nil = pool exhausted).
    public let nextAddress: SocketAddress?
}

// MARK: - Galaxy Operations

extension NMTClient {

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

    /// Find the Stellar (and optional Amas) address for a namespace.
    public func find(namespace: String) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let envelope = try Matter.make(type: .find, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(FindReplyBody.self)

        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        let amasAddress: SocketAddress? = try {
            guard let host = replyBody.amasHost, let port = replyBody.amasPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()

        return FindResult(stellarAddress: stellarAddress, amasAddress: amasAddress)
    }

    /// Notify an Amas that a Stellar is dead. Returns the next available Stellar address.
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

// MARK: - Stellar / Amas Registration

extension NMTClient {

    /// Register a Stellar with this Amas (or register an Amas with a Galaxy).
    public func register(astral: some Astral, listeningOn address: SocketAddress) async throws {
        try await register(
            namespace: astral.namespace,
            address: address,
            identifier: astral.identifier
        )
    }
}

// MARK: - Clone

extension NMTClient {

    /// Fetch the remote astral's identity info.
    public func clone() async throws -> CloneReplyBody {
        let envelope = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await request(envelope: envelope)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}
