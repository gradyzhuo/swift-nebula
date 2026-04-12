// Sources/Nebula/NMT/MatterBehavior.swift

import NMTP

/// A Nebula class-2 typed payload that can be dispatched by `NMTDispatcher`.
///
/// Conforming types carry their own `typeID` (dispatch key) and `type`
/// (NMTP frame classification). The dispatcher uses `typeID` to route
/// incoming Matter to the registered handler, and `type` to set the
/// correct frame type when building the outgoing Matter.
///
/// Define factory methods using constrained extensions for dot-syntax:
/// ```swift
/// extension MatterBehavior where Self == FindMatter {
///     public static func find(namespace: String) -> FindMatter { FindMatter(namespace: namespace) }
/// }
/// // Usage:
/// try await client.request(.find(namespace: "production.echo"), timeout: .seconds(5))
/// ```
public protocol MatterBehavior: Codable, Sendable {
    /// Class-2 dispatch key. Unique per Nebula message type.
    static var typeID: UInt16 { get }
    /// NMTP wire frame classification for this action.
    static var type: MatterType { get }
}
