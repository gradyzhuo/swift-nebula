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
    ///
    /// URI format: `nmtp://host:port/namespace/service/method`
    /// - host:port = Ingress address
    /// - namespace = forward order: galaxy.amas.stellar (e.g. `production.ml.embedding`)
    public static func planet(
        connecting uriString: String,
        service: String,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> RoguePlanet {
        let uri = try NebulaURI(uriString)

        let ingressAddress = try SocketAddress.makeAddressResolvingHost(
            uri.ingressHost, port: uri.ingressPort
        )
        print(ingressAddress)
        let client = try await NMTClient.connect(
            to: ingressAddress,
            as: .ingress,
            eventLoopGroup: eventLoopGroup
        )
        return .init(ingressClient: client, identifier: .init(), namespace: uri.namespace, service: service)
    }
}
