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

/// A client-side planet that calls services through an Amas.
public final class RoguePlanet: Planet {
    public let identifier: UUID
    public let name: String

    private let amasClient: NMTClient

    public init(name: String, amasClient: NMTClient, identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
        self.amasClient = amasClient
    }
}

// MARK: - Service Call

extension RoguePlanet {

    public func call(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = []
    ) async throws -> Data? {
        let body = CallBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let envelope = try Envelope.make(type: .call, body: body)
        let replyEnvelope = try await amasClient.request(envelope: envelope)
        let reply = try replyEnvelope.decodeBody(CallReplyBody.self)

        if let error = reply.error {
            throw NebulaError.fail(message: error)
        }
        return reply.result
    }

    public func call<T: Decodable>(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = [],
        as type: T.Type
    ) async throws -> T {
        guard let data = try await call(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments
        ) else {
            throw NebulaError.fail(message: "No result from \(namespace).\(service).\(method)")
        }
        return try MessagePackDecoder().decode(type, from: data)
    }
}
