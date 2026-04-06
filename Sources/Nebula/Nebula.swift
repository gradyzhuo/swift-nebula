//
//  Nebula.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO
import NMTP

public final class Nebula: Sendable {

    public static let standard: Nebula = Nebula()

    private init() {}
}

// MARK: - Server Helpers

extension Nebula {

    /// Bind an NMT server with the given handler on the specified address.
    /// Pass a `NebulaTLSContext` to enable mTLS on all incoming connections.
    public static func bind(
        _ handler: some NMTServerTarget,
        on address: SocketAddress,
        tls: NebulaTLSContext? = nil,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        try await NMTServer.bind(on: address, handler: handler, tls: tls, eventLoopGroup: eventLoopGroup)
    }
}
