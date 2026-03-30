//
//  Moon.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation
import NIO

/// The standard `Satellite` implementation.
///
/// On init, `Moon` discovers the Galaxy address via Ingress (`findGalaxy`),
/// connects directly to Galaxy, and joins the subscription group. Galaxy then
/// pushes `.enqueue` Matter onto the connection; `Moon` forwards them to `events`.
///
/// ```swift
/// let moon = try await Moon(
///     ingressClient: ingressClient,
///     topic: "production.orders",
///     subscription: "fulfillment"
/// )
/// for await event in moon.events {
///     try await handleOrder(event)
/// }
/// ```
public actor Moon: Satellite {
    public let identifier: UUID
    public let name: String
    public let namespace: String      // = topic
    public let subscription: String

    /// Server-pushed events from Galaxy's `BrokerAmas`.
    public let events: AsyncStream<EnqueueBody>

    private let galaxyClient: NMTClient<GalaxyTarget>
    private let eventContinuation: AsyncStream<EnqueueBody>.Continuation

    public init(
        ingressClient: NMTClient<IngressTarget>,
        topic: String,
        subscription: String,
        name: String = "moon",
        identifier: UUID = UUID()
    ) async throws {
        self.identifier = identifier
        self.name = name
        self.namespace = topic
        self.subscription = subscription

        // Discover Galaxy via Ingress
        guard let galaxyAddress = try await ingressClient.findGalaxy(topic: topic) else {
            throw NebulaError.fail(message: "No Galaxy found for broker topic: \(topic)")
        }

        // Connect directly to Galaxy
        let client = try await NMTClient.connect(to: galaxyAddress, as: .galaxy)
        self.galaxyClient = client

        // Wire up event stream
        var cont: AsyncStream<EnqueueBody>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont

        // Subscribe with Galaxy
        let body = SubscribeBody(topic: topic, subscription: subscription)
        let envelope = try Matter.make(type: .subscribe, body: body)
        _ = try await client.request(envelope: envelope)

        // Forward Galaxy server-push → events stream
        Task {
            for await matter in client.pushes {
                guard matter.type == .enqueue,
                      let pushed = try? matter.decodeBody(EnqueueBody.self)
                else { continue }
                cont.yield(pushed)
            }
        }
    }
}
