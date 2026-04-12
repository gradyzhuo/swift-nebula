// Sources/Nebula/Astral/Stellar/Stellar.swift

import Foundation
import NIO
import NMTP

public protocol Stellar: Astral {
    var namespace: String { get }
}

extension Stellar {
    public static var category: AstralCategory { .stellar }
}

public typealias ServiceVersion = String

/// A Stellar that hosts named Services.
///
/// Middlewares are stacked via ``use(_:)`` before calling ``register(on:)``.
/// Last registered middleware runs outermost (first to receive each matter).
public actor ServiceStellar: Stellar {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    private var availableServices: [ServiceVersion: Service] = [:]
    private var chain: NMTMiddlewareNext?
    private var pendingMiddlewares: [any NMTMiddleware] = []

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }

    public func use(_ middleware: any NMTMiddleware) {
        pendingMiddlewares.append(middleware)
    }

    public func add(service: Service) {
        availableServices[service.name] = service
    }
}

// MARK: - Dispatcher registration

extension ServiceStellar {

    public func register(on dispatcher: NMTDispatcher) {
        buildChain(dispatcher: dispatcher)

        dispatcher.register(CallMatter.self) { [unowned self] _, _ in
            // The dispatcher will not actually call this — we intercept earlier via NMTHandler.
            // Body unused; real dispatch goes through handle(matter:channel:).
            fatalError("CallMatter should be handled via ServiceStellar.handle(matter:channel:) middleware path")
        }
        dispatcher.register(EnqueueMatter.self) { [unowned self] _, _ in
            fatalError("EnqueueMatter should be handled via ServiceStellar.handle(matter:channel:) middleware path")
        }
        dispatcher.register(CloneMatter.self) { [unowned self] _, _ in
            await self.cloneReply()
        }
    }

    private func buildChain(dispatcher: NMTDispatcher) {
        chain = nil
        for middleware in pendingMiddlewares {
            let inner: NMTMiddlewareNext = chain ?? { [unowned self] matter in
                try await self.coreDispatch(matter: matter)
            }
            let captured = middleware
            chain = { matter in try await captured.handle(matter, next: inner) }
        }
    }
}

// MARK: - NMTHandler (preserves middleware path for direct unit-test invocation)

extension ServiceStellar: NMTHandler {

    public func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        if let chain {
            return try await chain(matter)
        }
        return try await coreDispatch(matter: matter)
    }
}

// MARK: - Core dispatch

extension ServiceStellar {

    private func coreDispatch(matter: Matter) async throws -> Matter? {
        guard let payload = try? matter.decodePayload() else { return nil }
        switch payload.typeID {
        case CallMatter.typeID:
            let body = try matter.decode(CallMatter.self)
            return try await handleCall(body, originalMatter: matter)
        case EnqueueMatter.typeID:
            let body = try matter.decode(EnqueueMatter.self)
            return try await handleEnqueue(body, originalMatter: matter)
        case CloneMatter.typeID:
            return try matter.makeReply(body: cloneReply())
        default:
            return nil
        }
    }

    private func handleCall(_ matter: CallMatter, originalMatter: Matter) async throws -> Matter {
        guard let service = availableServices[matter.service] else {
            throw NebulaError.serviceNotFound(namespace: matter.service)
        }
        let arguments = matter.arguments.map { Argument(key: $0.key, data: $0.value) }
        let result = try await service.perform(method: matter.method, with: arguments)
        return try originalMatter.makeReply(body: CallReplyMatter(result: result))
    }

    private func handleEnqueue(_ matter: EnqueueMatter, originalMatter: Matter) async throws -> Matter {
        guard let service = availableServices[matter.service] else {
            throw NebulaError.serviceNotFound(namespace: matter.service)
        }
        let arguments = matter.arguments.map { Argument(key: $0.key, data: $0.value) }
        _ = try await service.perform(method: matter.method, with: arguments)
        return try originalMatter.makeReply(body: AckMatter(matterID: originalMatter.matterID.uuidString))
    }

    private func cloneReply() -> CloneReplyMatter {
        CloneReplyMatter(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.stellar.rawValue
        )
    }
}
