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
///
/// Middlewares can be added via ``use(_:)`` before the server starts.
/// They are executed in registration order (first registered = outermost),
/// wrapping the core dispatch handler.
///
/// ```swift
/// let stellar = try ServiceStellar(name: "account", namespace: "production.mendesky")
///     .use(LoggingMiddleware())
///     .use(LDAPAuthMiddleware(config: ldapConfig))
///     .add(service: accountService)
/// ```
open class ServiceStellar: @unchecked Sendable, Stellar {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    public internal(set) var availableServices: [ServiceVersion: Service] = [:]
    private var middlewares: [any NMTMiddleware] = []

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }

    /// Appends a middleware to the chain. Returns `self` for fluent chaining.
    @discardableResult
    public func use(_ middleware: any NMTMiddleware) -> Self {
        middlewares.append(middleware)
        return self
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
        let chain = buildChain(from: middlewares)
        return try await chain(envelope)
    }
}

// MARK: - Middleware chain

extension ServiceStellar {

    /// Builds the middleware chain by folding the array around the core dispatch handler.
    /// Snapshot `middlewares` once so concurrent `use()` calls during setup can't
    /// produce a torn read on the hot path.
    private func buildChain(from middlewares: [any NMTMiddleware]) -> NMTMiddlewareNext {
        let core: NMTMiddlewareNext = { [self] envelope in
            try await self.coreDispatch(envelope: envelope)
        }
        return middlewares.reversed().reduce(core) { next, middleware in
            { envelope in try await middleware.handle(envelope, next: next) }
        }
    }
}

// MARK: - Core dispatch (no middleware)

extension ServiceStellar {

    private func coreDispatch(envelope: Matter) async throws -> Matter? {
        switch envelope.type {
        case .call:
            return try await handleCall(envelope: envelope)
        case .clone:
            return try makeCloneReply(envelope: envelope)
        default:
            return nil
        }
    }

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
