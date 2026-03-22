//
//  DirectAmas.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

/// Amas that manages a pool of Stellars and forwards calls directly.
public actor DirectAmas: Amas {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    /// namespace → established NMTClient (ready to use)
    private var stellars: [String: NMTClient] = [:]

    /// namespace → in-progress connection Task (solves actor re-entrancy)
    private var pendingConnections: [String: Task<NMTClient, Error>] = [:]

    public init(name: String, namespace: String, identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }
}

// MARK: - NMTServerDelegate

extension DirectAmas: NMTServerDelegate {

    public func handle(envelope: Envelope) async throws -> Envelope? {
        switch envelope.type {
        case .register:
            return try await handleRegister(envelope: envelope)
        case .find:
            return try await handleFind(envelope: envelope)
        case .call:
            return try await handleCall(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }
}

// MARK: - Handlers

extension DirectAmas {

    private func handleRegister(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)

        // Kick off a connection Task immediately (synchronous, no actor suspension yet).
        // Storing the Task before any await prevents race conditions with handleCall.
        let task = Task<NMTClient, Error> {
            try await NMTClient.connect(to: address)
        }
        pendingConnections[body.namespace] = task

        let reply = RegisterReplyBody(status: "ok")
        return try envelope.reply(body: reply)
    }

    private func handleFind(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(FindBody.self)
        let found = stellars[body.namespace] != nil || pendingConnections[body.namespace] != nil
        let reply = FindReplyBody(address: found ? body.namespace : nil)
        return try envelope.reply(body: reply)
    }

    private func handleCall(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(CallBody.self)

        let stellarClient = try await stellarClient(for: body.namespace)

        let forwardEnvelope = try Envelope.make(type: .call, body: body)
        let reply = try await stellarClient.request(envelope: forwardEnvelope)
        return Envelope(type: .reply, messageID: envelope.messageID, body: reply.body)
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

// MARK: - Stellar Connection Management

extension DirectAmas {

    /// Get an established NMTClient for the given namespace.
    /// Waits for a pending connection if one is in progress.
    private func stellarClient(for namespace: String) async throws -> NMTClient {
        if let client = stellars[namespace] {
            return client
        }
        guard let task = pendingConnections[namespace] else {
            throw NebulaError.serviceNotFound(namespace: namespace)
        }
        // Await the connection (actor re-enters when task completes, safe with Task cache)
        let client = try await task.value
        stellars[namespace] = client
        pendingConnections.removeValue(forKey: namespace)
        return client
    }
}
