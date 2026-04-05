import NMTP

/// A type that handles incoming Matter for a specific Nebula node role.
///
/// `NMTServerTarget` is an alias for `NMTHandler` from the NMTP transport layer.
/// Conforming types (Galaxy, Stellar, Ingress) implement `handle(matter:channel:)`
/// to process incoming Matter and optionally return a reply.
public typealias NMTServerTarget = NMTHandler
