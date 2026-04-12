// Sources/Nebula/NMT/NMTClient+Astral.swift

import Foundation
import NIO
import NMTP

// MARK: - NMTClient + MatterBehavior

extension NMTClient {
    /// Send a MatterBehavior-typed request and return the raw Matter reply.
    public func request<A: MatterBehavior>(
        _ action: A,
        timeout: Duration = .seconds(30)
    ) async throws -> Matter {
        let matter = try Matter.make(action)
        return try await request(matter: matter, timeout: timeout)
    }
}

// MARK: - Result Types

public struct FindResult: Sendable {
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    public let nextAddress: SocketAddress?
}

// MARK: - IngressClient

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

    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let reply = try await base.request(.find(namespace: namespace), timeout: timeout ?? defaultTimeout)
        let replyMatter = try reply.decode(FindReplyMatter.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyMatter.stellarHost, let port = replyMatter.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    public func registerGalaxy(
        name: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let reply = try await base.request(
            .register(namespace: name, host: address.ipAddress ?? "0.0.0.0",
                      port: address.port ?? 0, identifier: identifier.uuidString),
            timeout: timeout ?? defaultTimeout
        )
        let replyMatter = try reply.decode(RegisterReplyMatter.self)
        guard replyMatter.status == "ok" else {
            throw NebulaError.fail(message: "Register Galaxy failed: \(replyMatter.status)")
        }
    }

    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = [],
        timeout: Duration? = nil
    ) async throws {
        let reply = try await base.request(
            .enqueue(namespace: namespace, service: service, method: method,
                     arguments: arguments.toEncoded()),
            timeout: timeout ?? defaultTimeout
        )
        let replyMatter = try reply.decode(RegisterReplyMatter.self)
        guard replyMatter.status == "queued" else {
            throw NebulaError.fail(message: "Enqueue failed: \(replyMatter.status)")
        }
    }

    public func findGalaxy(topic: String, timeout: Duration? = nil) async throws -> SocketAddress? {
        let reply = try await base.request(.findGalaxy(topic: topic), timeout: timeout ?? defaultTimeout)
        let replyMatter = try reply.decode(FindGalaxyReplyMatter.self)
        guard let host = replyMatter.galaxyHost, let port = replyMatter.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }

    public func unregister(
        namespace: String,
        host: String,
        port: Int,
        timeout: Duration? = nil
    ) async throws -> UnregisterResult {
        let reply = try await base.request(
            .unregister(namespace: namespace, host: host, port: port),
            timeout: timeout ?? defaultTimeout
        )
        let replyMatter = try reply.decode(UnregisterReplyMatter.self)
        let nextAddress: SocketAddress? = try {
            guard let h = replyMatter.nextHost, let p = replyMatter.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(h, port: p)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    public func clone(timeout: Duration? = nil) async throws -> CloneReplyMatter {
        let reply = try await base.request(.clone(), timeout: timeout ?? defaultTimeout)
        return try reply.decode(CloneReplyMatter.self)
    }
}

// MARK: - GalaxyClient

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

    public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
        try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    }

    public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
        let reply = try await base.request(.find(namespace: namespace), timeout: timeout ?? defaultTimeout)
        let replyMatter = try reply.decode(FindReplyMatter.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyMatter.stellarHost, let port = replyMatter.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    public func register(
        namespace: String,
        address: SocketAddress,
        identifier: UUID,
        timeout: Duration? = nil
    ) async throws {
        let reply = try await base.request(
            .register(namespace: namespace, host: address.ipAddress ?? "::1",
                      port: address.port ?? 0, identifier: identifier.uuidString),
            timeout: timeout ?? defaultTimeout
        )
        let replyMatter = try reply.decode(RegisterReplyMatter.self)
        guard replyMatter.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyMatter.status)")
        }
    }

    public func register(astral: some Astral, listeningOn address: SocketAddress, timeout: Duration? = nil) async throws {
        try await register(namespace: astral.namespace, address: address, identifier: astral.identifier, timeout: timeout)
    }

    public func unregister(namespace: String, host: String, port: Int, timeout: Duration? = nil) async throws -> UnregisterResult {
        let reply = try await base.request(
            .unregister(namespace: namespace, host: host, port: port),
            timeout: timeout ?? defaultTimeout
        )
        let replyMatter = try reply.decode(UnregisterReplyMatter.self)
        let nextAddress: SocketAddress? = try {
            guard let h = replyMatter.nextHost, let p = replyMatter.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(h, port: p)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    public func clone(timeout: Duration? = nil) async throws -> CloneReplyMatter {
        let reply = try await base.request(.clone(), timeout: timeout ?? defaultTimeout)
        return try reply.decode(CloneReplyMatter.self)
    }
}

// MARK: - StellarClient

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

    public func clone(timeout: Duration? = nil) async throws -> CloneReplyMatter {
        let reply = try await base.request(.clone(), timeout: timeout ?? defaultTimeout)
        return try reply.decode(CloneReplyMatter.self)
    }
}
