//
//  Satellite.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation

/// A broker subscriber that receives async events pushed from `BrokerAmas` via Galaxy.
///
/// `namespace` is the broker topic. `subscription` is the group name for fan-out.
/// Incoming events arrive via `events: AsyncStream<EnqueueBody>`.
///
/// The default implementation is `Moon` — discovers Galaxy via Ingress and
/// connects directly. Custom implementations can plug in different transports.
public protocol Satellite: Astral {
    /// The subscription group this node belongs to.
    var subscription: String { get }

    /// Server-pushed events from `BrokerAmas`.
    var events: AsyncStream<EnqueueBody> { get }
}

extension Satellite {
    public static var category: AstralCategory { .satellite }
}
