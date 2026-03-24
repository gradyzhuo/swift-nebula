//
//  Stellar.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

public protocol Stellar: Astral {
    /// Fully qualified namespace in forward order, e.g. "production.ml.embedding"
    var namespace: String { get }
}

extension Stellar {
    public static var category: AstralCategory { .stellar }
}

public typealias ServiceVersion = String

/// A Stellar that hosts named Services.
open class ServiceStellar: @unchecked Sendable, Stellar {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    public internal(set) var availableServices: [ServiceVersion: Service] = [:]

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }

    @discardableResult
    public func add(service: Service) -> Self {
        availableServices[service.name] = service
        return self
    }
}

// MARK: - NMTServerTarget

extension ServiceStellar: NMTServerTarget {

    public func handle(envelope: Matter) async throws -> Matter? {
        switch envelope.type {
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

extension ServiceStellar {

    private func handleCall(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(CallBody.self)

        guard let service = availableServices[body.service] else {
            throw NebulaError.serviceNotFound(namespace: body.service)
        }

        let arguments = body.arguments.map { Argument(key: $0.key, data: $0.value) }
        let result = try await service.perform(method: body.method, with: arguments)

        let reply = CallReplyBody(result: result)
        return try envelope.reply(body: reply)
    }

    private func makeCloneReply(envelope: Matter) throws -> Matter {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.stellar.rawValue
        )
        return try envelope.reply(body: reply)
    }
}
