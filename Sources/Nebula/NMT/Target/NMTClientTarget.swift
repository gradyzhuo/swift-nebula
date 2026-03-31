//
//  NMTClientTarget.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

/// A type that identifies which kind of node an NMTClient is connected to.
///
/// The target constrains which API operations are available on a given client:
/// - `GalaxyTarget` — find / register / unregister operations
/// - `StellarTarget` — call operations
public protocol NMTClientTarget: Sendable {}

/// Marker for clients connected to any Astral node (Galaxy / Stellar).
/// Enables `clone()` which retrieves the remote node's identity.
public protocol AstralClientTarget: NMTClientTarget {}

// MARK: - Concrete Targets

public struct IngressTarget: AstralClientTarget {
    public init() {}
}

public struct GalaxyTarget: AstralClientTarget {
    public init() {}
}

public struct StellarTarget: AstralClientTarget {
    public init() {}
}

// MARK: - Static Factories

extension NMTClientTarget where Self == IngressTarget {
    public static var ingress: IngressTarget { .init() }
}

extension NMTClientTarget where Self == GalaxyTarget {
    public static var galaxy: GalaxyTarget { .init() }
}

extension NMTClientTarget where Self == StellarTarget {
    public static var stellar: StellarTarget { .init() }
}
