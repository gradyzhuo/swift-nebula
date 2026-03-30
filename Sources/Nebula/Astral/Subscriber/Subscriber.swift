//
//  Subscriber.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation
import NIO

/// A broker subscriber that receives async events pushed from `BrokerAmas` via Galaxy.
///
/// Discovers the Galaxy address via Ingress (`findGalaxy`), connects directly,
/// and joins a subscription group. Incoming events arrive via `events`.
///
/// ```swift
/// let subscriber = try await Subscriber(
///     ingressClient: ingressClient,
///     topic: "production.orders",
///     subscription: "fulfillment"
/// )
/// for await event in subscriber.events {
///     try await handleOrder(event)
/// }
/// ```
public actor Subscriber {
    public let topic: String
    public let subscription: String

    /// Server-pushed events from Galaxy's `BrokerAmas`.
    public let events: AsyncStream<EnqueueBody>

    private let galaxyClient: NMTClient<GalaxyTarget>
    private let eventContinuation: AsyncStream<EnqueueBody>.Continuation

    public init(
        ingressClient: NMTClient<IngressTarget>,
        topic: String,
        subscription: String
    ) async throws {
        self.topic = topic
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
