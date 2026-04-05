# 0002: Broker Targets in Ingress-Staged Facade

**Status:** Draft  
**Date:** 2026-04-01

## Summary

This proposal extends the staged ingress-rooted facade from `0001` to cover broker-oriented targets:

- `Comet`
- `Subscriber`

The public root remains:

```swift
Nebula.ingress(on: ...)
```

The new staged client flows become:

- RPC: `ingress -> client -> find stellar -> service -> call`
- MQ enqueue: `ingress -> client -> find comet -> enqueue`
- subscription: `ingress -> client -> find subscriber -> events`

This keeps the public API consistent while allowing async messaging targets to join the same facade architecture.

## Motivation

`0001` intentionally focused on the main RPC path first. That was the right cut, because the staged model needs to prove itself on the simplest and most central flow before expanding.

However, if `Ingress` is the single public root, then broker-related targets should eventually follow the same model. Otherwise the facade becomes split again:

- RPC through staged facade
- messaging through direct entity factories or low-level clients

That would recreate the inconsistency the redesign is trying to remove.

## Design Goals

1. Keep `Ingress` as the single public facade root.
2. Extend the same staged client model to broker targets.
3. Keep target capability boundaries explicit.
4. Reuse existing `Comet` and `Subscriber` runtime components in Phase 1.
5. Avoid introducing generic protocol layers that do not materially improve safety.

## Non-Goals

1. Redesigning broker wire protocol.
2. Changing `BrokerAmas`, `Comet`, or `Subscriber` internals in the first proposal stage.
3. Unifying RPC and broker lookup into one overly-generic target abstraction if their runtime behavior differs too much.

## Proposed User API

### Enqueue Flow

```swift
let comet = try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.comet("production.orders"))

try await comet.enqueue(
    service: "orderService",
    method: "process",
    arguments: [.init(name: "orderID", value: .string("A001"))]
)
```

### Subscription Flow

```swift
let subscriber = try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.subscriber("production.orders", subscription: "fulfillment"))

for await event in subscriber.events {
    // handle event
}
```

### Optional Fluent Shape

If desired, both targets can also support a small amount of staged refinement:

```swift
try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.comet("production.orders"))
    .enqueue(service: "orderService", method: "process", arguments: [...])
```

```swift
let events = try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.subscriber("production.orders", subscription: "fulfillment"))
    .events
```

No extra stage is required unless the runtime later needs more bind-time configuration.

## Type Model

### Extended Client Stage

```swift
public struct NebulaClientStage: Sendable {
    public func find(_ target: StellarLookupTarget) async throws -> StellarLookupStage
    public func find(_ target: CometLookupTarget) async throws -> CometHandle
    public func find(_ target: SubscriberLookupTarget) async throws -> SubscriberHandle
}
```

### Broker Lookup Targets

```swift
public struct CometLookupTarget: Sendable {
    public let topic: String

    public static func comet(_ topic: String) -> Self
}
```

```swift
public struct SubscriberLookupTarget: Sendable {
    public let topic: String
    public let subscription: String

    public static func subscriber(_ topic: String, subscription: String) -> Self
}
```

### Broker Handles

```swift
public struct CometHandle: Sendable {
    public func enqueue(
        service: String,
        method: String,
        arguments: [Argument]
    ) async throws
}
```

```swift
public struct SubscriberHandle: Sendable {
    public var events: AsyncStream<EnqueueBody> { get }
}
```

## Stage Semantics

### `find(.comet(topic))`

Returns a `CometHandle` bound to a broker topic.

The handle can:

- enqueue work

The handle cannot:

- call RPC methods
- bind servers
- register targets

### `find(.subscriber(topic, subscription))`

Returns a `SubscriberHandle` bound to:

- broker topic
- subscription group

The handle can:

- expose an event stream

The handle cannot:

- enqueue work
- call RPC methods
- bind servers

## Internal Mapping

Phase 1 should reuse the current runtime objects behind the facade.

### `CometHandle`

`CometHandle` should wrap `Comet`.

Recommended lookup path:

1. connect to Ingress
2. resolve broker routing information through the existing ingress-facing API
3. construct `Comet`
4. return `CometHandle`

### `SubscriberHandle`

`SubscriberHandle` should wrap `Subscriber`.

Recommended lookup path:

1. connect to Ingress
2. resolve the responsible Galaxy or broker route
3. construct `Subscriber`
4. expose the underlying event stream through the facade handle

This keeps the new public facade thin while reusing the existing async messaging runtime.

## Why Broker Targets Are Not Forced Into the RPC Stages

`Stellar` lookup leads naturally to:

- namespace resolution
- service binding
- method invocation

Broker targets do not share that shape:

- `Comet` is topic-bound and immediately enqueue-capable
- `Subscriber` is topic-plus-subscription-bound and immediately stream-capable

For that reason, this proposal keeps a consistent root and lookup shape, but does not force a fake shared post-lookup stage where none exists.

Consistency should come from:

- one public root
- one client stage
- one `find(...)` concept

Not from inventing identical stage chains for fundamentally different capabilities.

## Invalid Paths by Construction

These operations should not exist:

```swift
Nebula.ingress(on: addr).client().find(.comet("orders")).call(...)
Nebula.ingress(on: addr).client().find(.subscriber("orders", subscription: "a")).enqueue(...)
Nebula.ingress(on: addr).client().find(.comet("orders")).bind(...)
Nebula.ingress(on: addr).client().find(.subscriber("orders", subscription: "a")).service(...)
```

As with `0001`, invalid capability paths should be removed from the API surface entirely.

## Relationship to `0001`

This proposal is an extension of `0001`, not an alternative to it.

`0001` defines the staged ingress-rooted facade model and the initial RPC slice.

`0002` adds the broker-oriented targets to that same model using the same principles:

- ingress-rooted
- staged where necessary
- capability-specific handles
- reuse of existing runtime internals

## Migration Plan

### Phase 1

Add broker client lookup targets and handles:

1. `CometLookupTarget`
2. `SubscriberLookupTarget`
3. `NebulaClientStage.find(.comet(...))`
4. `NebulaClientStage.find(.subscriber(...))`
5. `CometHandle.enqueue(...)`
6. `SubscriberHandle.events`

### Phase 2

Add tests covering:

1. ingress client to comet enqueue
2. ingress client to subscriber events
3. capability isolation between RPC and broker handles

### Phase 3

Update documentation examples so all public client entrypoints are rooted at:

```swift
Nebula.ingress(on: ...)
```

## Verification

1. `swift build` succeeds with both old and new APIs.
2. `swift test` passes existing suites unchanged.
3. Add facade tests for:
   - broker enqueue
   - broker subscribe
   - handle capability isolation
4. Demo code can be updated after the new staged broker API proves stable.

## Open Questions

1. Should `SubscriberHandle.events` expose raw `EnqueueBody`, or a more facade-specific event wrapper?
2. Should `CometHandle` eventually support retry or producer configuration through an intermediate draft stage?
3. Should broker lookup accept URI-based convenience in the public staged API, or stay address-rooted only?
4. Does `find(.comet(...))` need to resolve through `findGalaxy(topic:)` explicitly in facade code, or should that remain fully hidden in the wrapped runtime object?

## Decision

Adopt broker targets into the ingress-rooted staged facade as client-side capability handles.

Do not force broker operations into the RPC service-call stage model. Keep the shared structure at the ingress root and lookup layers, then let each target expose its own capability surface.
