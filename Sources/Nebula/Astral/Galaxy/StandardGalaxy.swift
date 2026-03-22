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

    public init(name: String, identifier: UUID = UUID(), registry: (any ServiceRegistry)? = nil) {
        self.identifier = identifier
        self.name = name
        self.registry = registry ?? InMemoryServiceRegistry()
    }
}

// MARK: - NMTServerDelegate

extension StandardGalaxy: NMTServerDelegate {

    public func handle(envelope: Envelope) async throws -> Envelope? {
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

// MARK: - Handlers

extension StandardGalaxy {

    private func handleRegister(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(RegisterBody.self)
        let address = try SocketAddress.makeAddressResolvingHost(body.host, port: body.port)
        try await registry.register(namespace: body.namespace, address: address)
        let reply = RegisterReplyBody(status: "ok")
        return try envelope.reply(body: reply)
    }

    private func handleFind(envelope: Envelope) async throws -> Envelope {
        let body = try envelope.decodeBody(FindBody.self)
        let address = try await registry.find(namespace: body.namespace)
        let reply = FindReplyBody(address: address?.description)
        return try envelope.reply(body: reply)
    }

    private func makeCloneReply(envelope: Envelope) throws -> Envelope {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.galaxy.rawValue
        )
        return try envelope.reply(body: reply)
    }
}

// MARK: - String Address Helper

private extension String {
    var host: String {
        guard let colonIndex = lastIndex(of: ":") else { return self }
        return String(self[startIndex..<colonIndex])
    }

    var port: Int {
        guard let colonIndex = lastIndex(of: ":"),
              let port = Int(self[index(after: colonIndex)...]) else { return 0 }
        return port
    }
}
