//
//  Nebula.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public final class Nebula {

    public static let standard: Nebula = Nebula()

    private init() {}
}

// MARK: - Server Helpers

extension Nebula {

    public static func serve(
        _ astral: some ServerAstral,
        on address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        return try await NMTServer.bind(
            on: address,
            delegate: astral,
            eventLoopGroup: eventLoopGroup
        )
    }
}

// MARK: - Client Helpers

extension Nebula {

    public static func planet(
        name: String,
        connectingTo galaxyAddress: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> RoguePlanet {
        let client = try await NMTClient.connect(to: galaxyAddress, eventLoopGroup: eventLoopGroup)
        return RoguePlanet(name: name, galaxyClient: client)
    }
}
