//
//  NMTClient+Astral.swift
//

import Foundation
import NIO
import NMTP

// MARK: - Result Types

public struct FindResult: Sendable {
    /// Direct Stellar endpoint to connect to.
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    /// Next available Stellar endpoint after removing the dead one (nil = pool exhausted).
    public let nextAddress: SocketAddress?
}

// MARK: - IngressClient

/// A typed NMT client connected to an Ingress node.
public struct IngressClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> IngressClient {
        let base = try await NMTClient.connect(to: address, tls: tls, eventLoopGroup: eventLoopGroup)
        return IngressClient(base: base, defaultTimeout: defaultTimeout)
    }

    public var pushes: AsyncStream<Matter> { base.pushes }

    public func close() async throws { try await base.close() }

    /// Find the Stellar address for a namespace via Ingress → Galaxy.
    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a Galaxy with Ingress (Galaxy name → address).
    public func registerGalaxy(
        name: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let body = RegisterBody(
            namespace: name,
            host: address.ipAddress ?? "0.0.0.0",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register Galaxy failed: \(replyBody.status)")
        }
    }

    /// Enqueue an async task via Ingress → Galaxy → BrokerCluster.
    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = [],
        timeout: Duration? = nil
    ) async throws {
        let body = EnqueueBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let matter = try Matter.make(type: .enqueue, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "queued" else {
            throw NebulaError.fail(message: "Enqueue failed: \(replyBody.status)")
        }
    }

    /// Find the Galaxy address that manages a broker topic via Ingress.
    public func findGalaxy(topic: String, timeout: Duration? = nil) async throws -> SocketAddress? {
        let body = FindGalaxyBody(topic: topic)
        let matter = try Matter.make(type: .findGalaxy, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindGalaxyReplyBody.self)
        guard let host = replyBody.galaxyHost, let port = replyBody.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }

    /// Notify Ingress that a Stellar is dead (forwarded to Galaxy). Returns next Stellar.
    public func unregister(
        namespace: String,
        host: String,
        port: Int,
        timeout: Duration? = nil
    ) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}

// MARK: - GalaxyClient

/// A typed NMT client connected to a Galaxy node.
public struct GalaxyClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> GalaxyClient {
        let base = try await NMTClient.connect(to: address, tls: tls, eventLoopGroup: eventLoopGroup)
        return GalaxyClient(base: base, defaultTimeout: defaultTimeout)
    }

    public var pushes: AsyncStream<Matter> { base.pushes }

    public func close() async throws { try await base.close() }

    /// Forward a raw Matter (used by Ingress for routing).
    public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
        try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    }

    /// Find the Stellar address for a namespace.
    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    /// Register a namespace → address mapping in Galaxy.
    public func register(
        namespace: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let body = RegisterBody(
            namespace: namespace,
            host: address.ipAddress ?? "::1",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyBody.status)")
        }
    }

    /// Register a ServerAstral with Galaxy.
    public func register(
        astral: some Astral,
        listeningOn address: SocketAddress,
        timeout: Duration? = nil
    ) async throws {
        try await register(
            namespace: astral.namespace,
            address: address,
            identifier: astral.identifier,
            timeout: timeout
        )
    }

    /// Notify Galaxy that a Stellar is dead. Returns the next available Stellar address.
    public func unregister(
        namespace: String,
        host: String,
        port: Int,
        timeout: Duration? = nil
    ) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}

// MARK: - StellarClient

/// A typed NMT client connected to a Stellar node.
public struct StellarClient: Sendable {
    public var address: SocketAddress { base.targetAddress }
    internal let base: NMTClient
    private let defaultTimeout: Duration

    private init(base: NMTClient, defaultTimeout: Duration) {
        self.base = base
        self.defaultTimeout = defaultTimeout
    }

    public static func connect(
        to address: SocketAddress,
        defaultTimeout: Duration = .seconds(30),
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> StellarClient {
        let base = try await NMTClient.connect(to: address, eventLoopGroup: eventLoopGroup)
        return StellarClient(base: base, defaultTimeout: defaultTimeout)
    }

    public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
        try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    }

    public func close() async throws { try await base.close() }

    /// Fetch the remote node's identity info.
    public func clone(timeout: Duration? = nil) async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}
