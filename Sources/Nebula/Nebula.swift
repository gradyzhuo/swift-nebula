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

    /// Create a `RoguePlanet` connected to an Ingress at the given `SocketAddress`.
    public static func planet(
        name: String,
        connectingTo ingressAddress: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> RoguePlanet {
        let client = try await NMTClient.connect(
            to: ingressAddress,
            as: .ingress,
            eventLoopGroup: eventLoopGroup
        )
        return RoguePlanet(name: name, ingressClient: client)
    }

    /// Create a `BoundPlanet` pre-configured with a specific service endpoint from a URI.
    ///
    /// URI format: `nmtp://host:port/namespace/service/method`
    /// - host:port = Ingress address
    /// - namespace = forward order: galaxy.amas.stellar (e.g. `production.ml.embedding`)
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

        let ingressAddress = try SocketAddress.makeAddressResolvingHost(
            uri.ingressHost, port: uri.ingressPort
        )
        let client = try await NMTClient.connect(
            to: ingressAddress,
            as: .ingress,
            eventLoopGroup: eventLoopGroup
        )
        let rogPlanet = RoguePlanet(name: "planet", ingressClient: client)
        return BoundPlanet(
            planet: rogPlanet,
            namespace: uri.namespace,
            service: service,
            method: method
        )
    }
}
