//
//  Comet.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation
import NIO
import MessagePacker

/// An async message producer that enqueues tasks into `BrokerAmas` via Ingress.
///
/// Unlike `RoguePlanet` (RPC, waits for result), `Comet` confirms the message is
/// queued and moves on. `BrokerAmas` handles delivery, retry, and parking.
///
/// Stellar can create a `Comet` internally to emit events into a broker namespace.
///
/// ```swift
/// let comet = try await Nebula.comet(connecting: "nmtp+broker://localhost:2240/production/orders/jobs")
/// try await comet.enqueue(service: "orderService", method: "process", arguments: [...])
/// ```
public actor Comet: Astral {
    public static var category: AstralCategory { .comet }

    public let identifier: UUID
    public let name: String

    private let ingressClient: NMTClient<IngressTarget>
    private let defaultNamespace: String

    public init(
        ingressClient: NMTClient<IngressTarget>,
        name: String = "comet",
        namespace: String,
        identifier: UUID = UUID()
    ) {
        self.identifier = identifier
        self.name = name
        self.ingressClient = ingressClient
        self.defaultNamespace = namespace
    }
}

// MARK: - Enqueue

extension Comet {

    /// Enqueue a task. Returns once BrokerAmas confirms receipt ("queued").
    /// - Throws if Ingress/Galaxy/BrokerAmas is unreachable (caller may retry).
    public func enqueue(
        service: String,
        method: String,
        arguments: [Argument] = [],
        namespace: String? = nil
    ) async throws {
        let ns = namespace ?? defaultNamespace
        try await ingressClient.enqueue(
            namespace: ns,
            service: service,
            method: method,
            arguments: arguments
        )
    }
}
