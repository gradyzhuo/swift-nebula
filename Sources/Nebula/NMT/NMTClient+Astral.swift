//
//  NMTClient+Astral.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

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
        let envelope = try Envelope.make(type: .register, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyBody.status)")
        }
    }

    /// Find the address of a service by namespace.
    public func find(namespace: String) async throws -> String? {
        let body = FindBody(namespace: namespace)
        let envelope = try Envelope.make(type: .find, body: body)
        let reply = try await request(envelope: envelope)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        return replyBody.address
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
        let envelope = try Envelope.make(type: .clone, body: CloneBody())
        let reply = try await request(envelope: envelope)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}


