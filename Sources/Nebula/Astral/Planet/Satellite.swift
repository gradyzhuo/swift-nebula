//
//  Satellite.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

/// A typed proxy over a `RoguePlanet`.
///
/// Conforming types wrap a Planet connection and expose remote methods
/// via `@dynamicMemberLookup`. The standard implementation is `Moon`.
public protocol Satellite: Sendable {
    var planet: RoguePlanet { get }
}
