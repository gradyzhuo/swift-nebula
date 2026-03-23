//
//  Nebula.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class Nebula: Sendable {

    public static let standard: Nebula = Nebula()

    /// The active Discovery service used to resolve Galaxy names.
    /// Defaults to `LocalDiscovery`. Replace with a cloud-backed implementation for Layer 2.
    nonisolated(unsafe) public static var discovery: any NebulaDiscovery = LocalDiscovery()

    private init() {}
}

// MARK: - Server Helpers

extension Nebula {

    public static func server<Target: NMTServerTarget>(
        with target: Target
    ) -> NMTServerBuilder<Target> {
        NMTServerBuilder(target: target)
    }
}

// MARK: - Client Helpers

extension Nebula {

    /// Create a `RoguePlanet` connected to a Galaxy at the given `SocketAddress`.
    public static func planet(
        name: String,
        connectingTo galaxyAddress: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> RoguePlanet {
        let client = try await NMTClient.connect(
            to: galaxyAddress,
            as: .galaxy,
            eventLoopGroup: eventLoopGroup
        )
        return RoguePlanet(name: name, galaxyClient: client)
    }

    /// Create a `BoundPlanet` pre-configured with a specific service endpoint from a URI.
    ///
    /// - Discovery mode (no port): `nmtp://embedding.ml.production/w2v/wordVector`
    ///   Resolves the Galaxy via `Nebula.discovery` using the last namespace segment.
    /// - Explicit mode (with port): `nmtp://[::1]:9000/embedding.ml.production/w2v/wordVector`
    ///   Connects directly without Discovery.
    public static func planet(
        connecting uriString: String,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> BoundPlanet {
        let uri = try NebulaURI(uriString)

        guard let service = uri.service else {
            throw NebulaError.invalidURI("URI must include service: \(uriString)")
        }
        guard let method = uri.method else {
            throw NebulaError.invalidURI("URI must include method: \(uriString)")
        }

        let galaxyAddress: SocketAddress
        if let host = uri.explicitGalaxyHost, let port = uri.explicitGalaxyPort {
            galaxyAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
        } else {
            galaxyAddress = try await discovery.resolve(uri.galaxyName)
        }

        let client = try await NMTClient.connect(to: galaxyAddress, as: .galaxy, eventLoopGroup: eventLoopGroup)
        let rogPlanet = RoguePlanet(name: "planet", galaxyClient: client)
        return BoundPlanet(planet: rogPlanet, namespace: uri.namespace, service: service, method: method)
    }
}
