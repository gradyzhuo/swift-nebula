/// The next handler in a Nebula middleware chain.
///
/// Call this to forward the envelope to the next middleware (or the core
/// dispatch handler). You can inspect or replace the envelope before
/// forwarding, and inspect or replace the reply on the way back.
public typealias NMTMiddlewareNext = @Sendable (Matter) async throws -> Matter?

/// A middleware that wraps Nebula message handling.
///
/// Middlewares are executed in registration order (first registered = outermost).
/// Each middleware receives the incoming ``Matter`` envelope and a `next`
/// closure that forwards to the next middleware in the chain.
///
/// ```swift
/// // Pre + post processing
/// public struct LoggingMiddleware: NMTMiddleware {
///     public func handle(_ envelope: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
///         print("→ \(envelope.type)")
///         let reply = try await next(envelope)
///         print("← \(reply?.type.rawValue ?? 0)")
///         return reply
///     }
/// }
///
/// // Short-circuit (e.g. rate limiting)
/// public struct RateLimitMiddleware: NMTMiddleware {
///     public func handle(_ envelope: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
///         guard !isThrottled() else { throw NMTError.rateLimited }
///         return try await next(envelope)
///     }
/// }
/// ```
///
/// Register on a ``ServiceStellar`` with ``ServiceStellar/use(_:)``.
public protocol NMTMiddleware: Sendable {
    func handle(_ envelope: Matter, next: NMTMiddlewareNext) async throws -> Matter?
}
