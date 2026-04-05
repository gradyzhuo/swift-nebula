# 0001: Ingress-Rooted Target Facade

**Status:** Draft  
**Date:** 2026-04-01

## Summary

This proposal redesigns the public `Nebula` facade as an ingress-rooted staged API.

The public API will have one entry point:

```swift
# a ingress connection client
Nebula.ingress(on: ...) # default client
Nebula.ingress(on: ..., as: .client)

# a ingres server configuration
Nebula.ingress(on: ..., as: .server)
 
# run a ingress server and listening to address
let ingress = Nebula.ingress(on: {address}, as: .server).serve()



```

From that root, the user moves through staged transitions:

- client flow: `ingress -> client -> find -> service -> call`
- server flow: `ingress -> server -> register galaxy -> bind -> register stellar -> bind`

The goal is not just a fluent API. The goal is to encode legal transitions into the type system so invalid paths are not exposed at all.

## Motivation

The current facade is still entity-oriented:

```swift
Nebula.server(with: galaxy)
Nebula.planet(connecting: uri, service: "w2v")
Nebula.moon(connecting: uri, service: "w2v")
```

This has a few problems:

1. The facade is not aligned with the lower-level target model already present in `NMTClient<Target>` and `NMTServerTarget`.
2. `Planet` and `Moon` are promoted as primary user concepts, even though they are really convenience wrappers over target-specific capabilities.
3. The current API cannot strongly guide the user toward valid flows.
4. If `Ingress` is intended to be the single system root, the public API should reflect that directly.

This proposal makes `Ingress` the single public root and uses staged types to constrain what can happen next.

## Design Goals

1. `Ingress` is the only public facade root.
2. Public API is capability-driven, not entity-driven.
3. Each stage only exposes the next legal operations.
4. Existing core runtime types remain intact in Phase 1.
5. Existing public APIs remain available during migration.

## Non-Goals

1. Rewriting `NMTClient`, `NMTServer`, `RoguePlanet`, `Comet`, or `Subscriber` in Phase 1.
2. Deprecating old facade APIs in the first proposal stage.
3. Solving every target type in the first implementation. Phase 1 focuses on Galaxy and Stellar RPC.

## Proposed User API

### Client Flow

```swift
let result: Embedding = try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.stellar("production.ml.embedding"))
    .service("w2v")
    .call(
        "wordVector",
        arguments: [.init(name: "words", value: .array(["slow"]))],
        as: Embedding.self
    )
```

```swift
let moon = try await Nebula
    .ingress(on: ingressAddress)
    .client()
    .find(.stellar("production.ml.embedding"))
    .service("w2v")
    .moon()
```

### Server Flow

```swift
let galaxy = try await Nebula
    .ingress(on: ingressAddress)
    .server()
    .register(.galaxy(name: "production"))
    .bind(on: galaxyAddress)
```

Stellar 可從 `GalaxyServerHandle` 衍生（in-process 便利寫法）：

```swift
let stellar = try await galaxy
    .register(.stellar(namespace: "production.ml.embedding"))
    .services([embeddingService])
    .bind(on: stellarAddress)
```

也可以從 Ingress root 獨立出發（支援分散式部署，Stellar 不需與 Galaxy 同機）：

```swift
let stellar = try await Nebula
    .ingress(on: ingressAddress)
    .server()
    .register(.stellar(namespace: "production.ml.embedding"))
    .services([embeddingService])
    .bind(on: stellarAddress)
```

兩種寫法的 `bind(on:)` 內部走相同路徑：bind Stellar NMT server → 向 Ingress 查詢 Galaxy 位址 → 向 Galaxy 送 `.register`。

## Type Model

### Root

```swift
public enum Nebula {
    public static func ingress(
        on address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) -> NebulaIngressRoot
}
```

```swift
public struct NebulaIngressRoot: Sendable {
    public func client() -> NebulaClientStage
    public func server() -> NebulaServerStage
}
```

### Client Stages

```swift
public struct NebulaClientStage: Sendable {
    public func find(_ target: StellarLookupTarget) async throws -> StellarLookupStage
}
```

```swift
public struct StellarLookupTarget: Sendable {
    public let namespace: String

    public static func stellar(_ namespace: String) -> Self
}
```

```swift
public struct StellarLookupStage: Sendable {
    public func service(_ name: String) -> NebulaServiceStage
}
```

```swift
public struct NebulaServiceStage: Sendable {
    public func call(
        _ method: String,
        arguments: [Argument]
    ) async throws -> Data?

    public func call<T: Decodable>(
        _ method: String,
        arguments: [Argument],
        as type: T.Type
    ) async throws -> T

    public func moon() -> Moon
}
```

### Server Stages

```swift
public struct NebulaServerStage: Sendable {
    // Galaxy 路徑
    public func register(_ target: GalaxyRegistrationTarget) -> GalaxyServerDraft
    // Stellar 路徑（獨立，不需 GalaxyServerHandle）
    public func register(_ target: StellarRegistrationTarget) -> StellarServerDraft
}
```

```swift
public struct GalaxyRegistrationTarget: Sendable {
    public let name: String

    public static func galaxy(name: String) -> Self
}
```

```swift
/// Galaxy 的設定草稿，尚未啟動。
/// `bind(on:)` 執行兩步驟：
///   1. 以 `galaxyAddress` 啟動 Galaxy NMT server
///   2. 向 Ingress 送 `.register(name, galaxyAddress)`，完成 Galaxy 自我登記
public struct GalaxyServerDraft: Sendable {
    public func bind(on address: SocketAddress) async throws -> GalaxyServerHandle
}
```

```swift
public struct GalaxyServerHandle: Sendable {
    // NMTServer 設為 internal；對外只暴露生命週期操作
    internal let server: NMTServer<StandardGalaxy>

    public func shutdown() async throws
    public func waitForClose() async throws

    // 便利 shorthand：從已啟動的 Galaxy 衍生 Stellar（in-process）
    public func register(_ target: StellarRegistrationTarget) -> StellarServerDraft
}
```

```swift
/// namespace 必須是完整路徑，例如 "production.ml.embedding"。
/// 第一段（"production"）為 Galaxy 名稱，Ingress 據此路由。
public struct StellarRegistrationTarget: Sendable {
    public let namespace: String

    public static func stellar(namespace: String) -> Self
}
```

```swift
/// Stellar 的設定草稿，尚未啟動。
/// `bind(on:)` 執行三步驟：
///   1. 以 `stellarAddress` 啟動 Stellar NMT server
///   2. 向 Ingress 送 `findGalaxy(namespace)` 取得 Galaxy 位址
///   3. 向 Galaxy 送 `.register(namespace, stellarAddress)` 完成登記
/// 前提：對應的 Galaxy 必須已向 Ingress 完成 `.register`，否則步驟 2 回傳空結果。
public struct StellarServerDraft: Sendable {
    public func services(_ services: [Service]) -> Self
    public func use(_ middleware: any NMTMiddleware) -> Self
    public func bind(on address: SocketAddress) async throws -> NMTServer<ServiceStellar>
}
```

## Stage Semantics

### `NebulaIngressRoot`

Holds shared ingress bootstrap state:

- ingress address
- optional event loop group
- optional future shared config

It does not expose any network operation directly.

### `NebulaClientStage`

Only supports lookup operations.
It cannot register servers or bind anything.

### `NebulaServerStage`

Supports Galaxy registration and Stellar registration.
Two overloads of `register(_:)` return different draft types.
It cannot perform lookup or service invocation.

### `StellarLookupStage`

Represents a resolved Stellar namespace.
Holds an already-connected `NMTClient<IngressTarget>` and the namespace string.
It is not yet bound to a service name.

### `NebulaServiceStage`

Represents a resolved namespace and bound service.
`RoguePlanet` is eagerly created here (in `service(_:)`) using the `NMTClient<IngressTarget>` from `StellarLookupStage`.
It can invoke methods or derive a `Moon` DSL object synchronously.

### `GalaxyServerDraft`

Represents a Galaxy prepared for bind, but not yet running.
`bind(on:)` performs two steps: (1) start the Galaxy NMT server, (2) register the bound address with Ingress.

### `GalaxyServerHandle`

Represents a running Galaxy already registered with Ingress.
It can derive a `StellarServerDraft` as a convenience shorthand for in-process setup.
The `NMTServer` field is internal; lifecycle is managed via `shutdown()` / `waitForClose()`.

### `StellarServerDraft`

Represents a Stellar configuration draft that can accept services and middleware before binding.
`bind(on:)` performs three steps: (1) start the Stellar NMT server, (2) query Ingress via `findGalaxy` to resolve the Galaxy address, (3) register the bound address with Galaxy.

**Prerequisite**: The Galaxy for this namespace must already be registered with Ingress before `bind(on:)` is called.

### Namespace Contract

All namespace strings use full dot-separated paths (e.g. `"production.ml.embedding"`).
The first segment is the Galaxy name. Ingress and all runtime components rely on this contract.

## Invalid Paths by Construction

The following operations should not exist in the public staged API:

```swift
Nebula.ingress(on: addr).client().register(...)
Nebula.ingress(on: addr).server().find(...)
Nebula.ingress(on: addr).client().find(...).bind(...)
Nebula.ingress(on: addr).server().register(...).call(...)
```

This is the main value of the proposal. The facade should not just document valid flows. It should make invalid flows unavailable.

## Internal Mapping

Phase 1 should reuse existing runtime components behind the facade.

### Client Side

`NebulaServiceStage` should initially wrap `RoguePlanet`.

Recommended Phase 1 mapping:

- `find(.stellar(namespace))` connects to Ingress (`NMTClient<IngressTarget>`) and resolves the namespace; `StellarLookupStage` holds this client and the namespace
- `.service(name)` synchronously creates `RoguePlanet(ingressClient:namespace:service:)` using the client from `StellarLookupStage`
- `NebulaServiceStage` holds the `RoguePlanet`; `moon()` is synchronous

This avoids rewriting cache and failover behavior in Phase 1.

### Server Side

- `GalaxyServerDraft` wraps `StandardGalaxy` plus the ingress address
- `GalaxyServerDraft.bind(on:)` starts the Galaxy NMT server and registers its address with Ingress via `.register`
- `GalaxyServerHandle` wraps the running `NMTServer<StandardGalaxy>` (internal) and the `StandardGalaxy` actor reference
- `StellarServerDraft` wraps configuration (namespace, services, middlewares) plus the ingress address

`StellarServerDraft.bind(on:)` is responsible for:

1. Binding the Stellar NMT server
2. Connecting to Ingress and calling `findGalaxy(namespace)` to resolve the Galaxy address
3. Connecting to Galaxy and registering the namespace and bound address

This path works for both in-process and distributed deployments. `GalaxyServerHandle.register(.stellar(...))` is a convenience shorthand that creates a `StellarServerDraft` pre-populated with the same ingress address.

## Why This Proposal Avoids Extra Generic Layers

This proposal intentionally does not introduce:

- `Role` protocols
- generic `FindTarget` protocols
- generic `RegisterTarget` protocols

Those abstractions tend to look flexible but often collapse into overload-based implementation anyway. The staged API already gives enough structure. Adding weak generic layers on top would make the facade harder to read without improving safety.

## Migration Plan

### Phase 1

Implement the minimum staged API for RPC:

1. `Nebula.ingress(on:)`
2. `.client()` and `.server()`
3. `.find(.stellar(...)).service(...).call(...)`
4. `.register(.galaxy(...)).bind(...)`
5. `GalaxyServerHandle.register(.stellar(...)).services(...).bind(...)`
6. `.moon()` as sugar on `NebulaServiceStage`

Keep old APIs intact:

- `Nebula.server(with:)`
- `Nebula.planet(...)`
- `Nebula.moon(...)`

No deprecation in Phase 1.

### Phase 2

Extend staged client flow for async messaging:

- `.find(.comet(...))`
- `.find(.subscriber(...))`

Only after Phase 1 is stable should the broker-related targets be added to the public staged API.

### Phase 3

Update README and demos so the staged ingress-rooted API becomes the main documented path.

### Phase 4

Deprecate old facade entry points once the new path is validated.

## Verification

1. `swift build` succeeds with both old and new APIs present.
2. `swift test` passes unchanged existing tests.
3. Add staged facade tests for:
   - ingress client lookup to stellar call
   - ingress server registration to galaxy bind
   - galaxy child registration to stellar bind
   - `moon()` derived from service stage
4. `samples/demo` should be migrated after Phase 1 API is stable.

## Open Questions

1. ~~Should `StellarRegistrationTarget` store a full namespace or a relative child namespace under the Galaxy?~~ **Resolved**: Always full namespace (e.g. `"production.ml.embedding"`). Runtime depends on this contract.
2. ~~Should `NebulaServiceStage` eagerly create `RoguePlanet`, or lazily create it on first call?~~ **Resolved**: Eagerly in `service(_:)`, so `moon()` can be synchronous.
3. ~~Should `GalaxyServerHandle` expose any low-level escape hatch, or remain strictly staged?~~ **Resolved**: `NMTServer` is internal; expose `shutdown()` / `waitForClose()` only.
4. When `Comet` and `Subscriber` are introduced, should they share `find(...)` shape or use more explicit entrypoints? (`Comet` and `Subscriber` have different lookup flows; defer to Phase 2.)

## Decision

Adopt an ingress-rooted staged facade as the long-term public API direction.

Phase 1 should implement the narrowest useful slice first:

- ingress root
- client RPC staged flow
- server Galaxy and Stellar staged flow

Do not widen the proposal to every target type before the staged model proves itself on the main RPC path.
