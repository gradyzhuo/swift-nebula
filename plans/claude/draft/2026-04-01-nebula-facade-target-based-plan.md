# Nebula Facade → Target-Based API Migration Plan

## Context

Facade API 要改為 target-based，以 Ingress 為唯一入口，透過 role（client/server）和 target type 決定可用能力。Core layer（Galaxy, Planet, Comet, Subscriber）維持 entity-based 不動，facade 是 core entities 的包裝層。

## API Overview

```swift
// ── Client Side ──

// RPC call
let stellar = try await Nebula
    .ingress(on: ingressAddr, as: .client)
    .find(of: .stellar("production.ml.embedding"))
let result: Embedding = try await stellar
    .call(service: "w2v", method: "wordVector", arguments: [...])
    .as(Embedding.self)

// Async enqueue
let comet = try await Nebula
    .ingress(on: ingressAddr, as: .client)
    .find(of: .comet("production.orders"))
try await comet.enqueue(service: "orderService", method: "process", arguments: [...])

// Broker subscribe
let sub = try await Nebula
    .ingress(on: ingressAddr, as: .client)
    .find(of: .subscriber("production.orders", subscription: "fulfillment"))
for await event in sub.events { ... }

// URI convenience (仍保留)
let stellar = try await Nebula.connect(to: "nmtp://localhost:6224/production/ml/embedding")

// ── Server Side ──

// Galaxy: bind → register with Ingress
let galaxy = try await Nebula
    .ingress(on: ingressAddr, as: .server)
    .register(as: .galaxy(name: "production"))
    .bind(on: galaxyAddress)

// Stellar: bind → register with Galaxy (Galaxy 是 Stellar 的 parent)
let stellar = try await galaxy
    .register(as: .stellar(name: "ml.embedding", services: [embeddingService]))
    .bind(on: stellarAddress)
```

---

## Type System Design

### Step 1: Role Protocol — `IngressRole`

**新檔**: `Sources/Nebula/Facade/IngressRole.swift`

```swift
public protocol IngressRole: Sendable {}

public struct ClientRole: IngressRole {
    public init() {}
}

public struct ServerRole: IngressRole {
    public init() {}
}

extension IngressRole where Self == ClientRole {
    public static var client: ClientRole { .init() }
}

extension IngressRole where Self == ServerRole {
    public static var server: ServerRole { .init() }
}
```

### Step 2: Ingress Context — `IngressContext<Role>`

**新檔**: `Sources/Nebula/Facade/IngressContext.swift`

```swift
public struct IngressContext<Role: IngressRole>: Sendable {
    internal let address: SocketAddress
    internal let eventLoopGroup: MultiThreadedEventLoopGroup?
}
```

- `Nebula.ingress(on:as:)` 是 **sync** — 只建立 context，不連線
- 實際 `NMTClient<IngressTarget>` 連線延遲到 `find()` / `register()` 時

### Step 3: Find Target Protocol（Client 用）

**新檔**: `Sources/Nebula/Facade/FindTarget.swift`

```swift
public protocol FindTarget: Sendable {
    associatedtype Handle: Sendable
}

public struct StellarFindTarget: FindTarget {
    public typealias Handle = StellarHandle
    public let namespace: String
}

public struct CometFindTarget: FindTarget {
    public typealias Handle = CometHandle
    public let namespace: String
}

public struct SubscriberFindTarget: FindTarget {
    public typealias Handle = SubscriberHandle
    public let topic: String
    public let subscription: String
}

// Static factories（讓 .stellar("ns") 語法成立）
extension FindTarget where Self == StellarFindTarget {
    public static func stellar(_ namespace: String) -> StellarFindTarget {
        .init(namespace: namespace)
    }
}

extension FindTarget where Self == CometFindTarget {
    public static func comet(_ namespace: String) -> CometFindTarget {
        .init(namespace: namespace)
    }
}

extension FindTarget where Self == SubscriberFindTarget {
    public static func subscriber(_ topic: String, subscription: String) -> SubscriberFindTarget {
        .init(topic: topic, subscription: subscription)
    }
}
```

### Step 4: Register Target Protocol（Server 用）

**新檔**: `Sources/Nebula/Facade/RegisterTarget.swift`

```swift
public protocol RegisterTarget: Sendable {
    associatedtype Builder: Sendable
}

public struct GalaxyRegisterTarget: RegisterTarget {
    public typealias Builder = GalaxyServerBuilder
    public let name: String
}

public struct StellarRegisterTarget: RegisterTarget {
    public typealias Builder = StellarServerBuilder
    public let name: String
    public let services: [Service]
}

extension RegisterTarget where Self == GalaxyRegisterTarget {
    public static func galaxy(name: String) -> GalaxyRegisterTarget {
        .init(name: name)
    }
}

extension RegisterTarget where Self == StellarRegisterTarget {
    public static func stellar(name: String, services: [Service]) -> StellarRegisterTarget {
        .init(name: name, services: services)
    }
}
```

### Step 5: Client Handles（`find` 的回傳型別）

**新檔**: `Sources/Nebula/Facade/StellarHandle.swift`

```swift
public struct StellarHandle: Sendable {
    // 內部持有 RoguePlanet（connection cache + failover）
    private let planet: RoguePlanet

    public func call(service: String, method: String, arguments: [Argument] = []) async throws -> CallResult {
        // 需要在 RoguePlanet 調整：目前 service 是 init 時綁定的
        // 這裡改為每次 call 時傳入 service
    }

    public func moon(service: String) -> Moon { ... }
}

/// call() 的回傳型別，支援 .as(T.self) chain decode
public struct CallResult: Sendable {
    public let data: Data?

    public func `as`<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data else {
            throw NebulaError.fail(message: "No result data")
        }
        return try MessagePackDecoder().decode(type, from: data)
    }
}
```

Usage:
```swift
// Raw data
let raw = try await stellar.call(service: "w2v", method: "wordVector", arguments: [...])

// Typed decode via chain
let result: Embedding = try await stellar
    .call(service: "w2v", method: "wordVector", arguments: [...])
    .as(Embedding.self)
```

> **注意**：目前 `RoguePlanet` 在 init 時綁定 `service`，但新 API 的 `StellarHandle` 綁定的是 namespace（到 Stellar 層級），`service` 在 `call` 時才指定。需要調整 `RoguePlanet` 或新建一個不綁 service 的 variant。

**新檔**: `Sources/Nebula/Facade/CometHandle.swift`

```swift
public struct CometHandle: Sendable {
    private let comet: Comet

    public func enqueue(service: String, method: String, arguments: [Argument] = []) async throws { ... }
}
```

**新檔**: `Sources/Nebula/Facade/SubscriberHandle.swift`

```swift
public struct SubscriberHandle: Sendable {
    private let subscriber: Subscriber

    public var events: AsyncStream<EnqueueBody> { subscriber.events }
}
```

### Step 6: Server Builders（`register` 的回傳型別）

**新檔**: `Sources/Nebula/Facade/GalaxyServerBuilder.swift`

```swift
public struct GalaxyServerBuilder: Sendable {
    private let galaxy: StandardGalaxy
    private let ingressClient: NMTClient<IngressTarget>

    public func bind(on address: SocketAddress) async throws -> GalaxyServerHandle {
        let server = try await NMTServer.bind(on: address, target: galaxy)
        // 自動向 Ingress 註冊
        try await ingressClient.registerGalaxy(
            name: galaxy.name,
            address: server.address,
            identifier: galaxy.identifier
        )
        return GalaxyServerHandle(server: server, ingressClient: ingressClient, galaxy: galaxy)
    }
}
```

**新檔**: `Sources/Nebula/Facade/GalaxyServerHandle.swift`

`galaxy.bind()` 回傳 `GalaxyServerHandle`，支援 `.register(as: .stellar(...))` 讓 Stellar 向這個 Galaxy 註冊：

```swift
public struct GalaxyServerHandle: Sendable {
    public let server: NMTServer<StandardGalaxy>
    internal let ingressClient: NMTClient<IngressTarget>
    internal let galaxy: StandardGalaxy

    /// Stellar 透過 Galaxy 註冊
    public func register(as target: StellarRegisterTarget) -> StellarServerBuilder {
        StellarServerBuilder(
            stellar: ServiceStellar(name: target.name, services: target.services),
            galaxyAddress: server.address,
            galaxyName: galaxy.name
        )
    }
}
```

**新檔**: `Sources/Nebula/Facade/StellarServerBuilder.swift`

```swift
public struct StellarServerBuilder: Sendable {
    private let stellar: ServiceStellar
    private let galaxyAddress: SocketAddress
    private let galaxyName: String

    public func bind(on address: SocketAddress) async throws -> NMTServer<ServiceStellar> {
        let server = try await NMTServer.bind(on: address, target: stellar)
        // 連線到 Galaxy 並註冊
        let galaxyClient = try await NMTClient.connect(to: galaxyAddress, as: .galaxy)
        try await galaxyClient.register(
            namespace: "\(galaxyName).\(stellar.name)",
            address: server.address,
            identifier: stellar.identifier
        )
        return server
    }
}
```

Server 使用流程：
```swift
// 1. Galaxy bind + register with Ingress
let galaxy = try await Nebula
    .ingress(on: ingressAddr, as: .server)
    .register(as: .galaxy(name: "production"))
    .bind(on: galaxyAddress)

// 2. Stellar bind + register with Galaxy
let stellar = try await galaxy
    .register(as: .stellar(name: "ml.embedding", services: [embeddingService]))
    .bind(on: stellarAddress)
```

### Step 7: `IngressContext` Extensions — find / register

**新檔**: `Sources/Nebula/Facade/IngressContext+Client.swift`

```swift
extension IngressContext where Role == ClientRole {

    /// Generic find: 根據 target type 回傳對應的 Handle
    public func find<T: FindTarget>(of target: T) async throws -> T.Handle {
        // 1. connect to Ingress
        // 2. dispatch based on T
        // 需要用 type check 或把邏輯放在各 FindTarget 的 extension
    }
}
```

> **實作細節**：`find<T: FindTarget>(of:) -> T.Handle` 的 generic dispatch 需要每個 `FindTarget` 自己知道怎麼 resolve。可以在 protocol 加一個 internal `resolve` method，或用 overloaded concrete methods：
>
> ```swift
> public func find(of target: StellarFindTarget) async throws -> StellarHandle { ... }
> public func find(of target: CometFindTarget) async throws -> CometHandle { ... }
> public func find(of target: SubscriberFindTarget) async throws -> SubscriberHandle { ... }
> ```
>
> **建議用 overload** — 每個 find 的內部邏輯不同（Stellar 需要 find + connect，Comet 只需要 Ingress client，Subscriber 需要 findGalaxy + connect + subscribe），generic dispatch 反而繞路。

**新檔**: `Sources/Nebula/Facade/IngressContext+Server.swift`

```swift
extension IngressContext where Role == ServerRole {
    /// Galaxy 向 Ingress 註冊
    public func register(as target: GalaxyRegisterTarget) async throws -> GalaxyServerBuilder { ... }
    // Stellar 不在這裡 — Stellar 透過 GalaxyServerHandle.register(as:) 註冊
}
```

### Step 8: Nebula Entry Point

**修改**: `Sources/Nebula/Nebula.swift`

```swift
extension Nebula {
    public static func ingress<Role: IngressRole>(
        on address: SocketAddress,
        as role: Role,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) -> IngressContext<Role> {
        IngressContext(address: address, eventLoopGroup: eventLoopGroup)
    }
}
```

舊 API（`server(with:)`, `planet(...)`, `moon(...)`）保留不動、不 deprecate。

---

## Core Layer 調整（最小幅度）

### `RoguePlanet` — service 解耦

目前 `RoguePlanet.init` 綁定 `service`，`call(method:)` 不帶 service。
新 facade 的 `StellarHandle` 需要在 call 時才指定 service。

**方案**：在 `RoguePlanet` 新增一個 `call(service:method:arguments:)` overload，內部的 `CallBody` 用傳入的 service 而非 `self.service`。原有 `call(method:)` 保留不動。

---

## New Files Summary

```
Sources/Nebula/Facade/
├── IngressRole.swift               # ClientRole / ServerRole
├── IngressContext.swift             # IngressContext<Role>
├── IngressContext+Client.swift      # find(of:) overloads
├── IngressContext+Server.swift      # register(as:) — Galaxy only
├── FindTarget.swift                 # StellarFindTarget / CometFindTarget / SubscriberFindTarget
├── RegisterTarget.swift             # GalaxyRegisterTarget / StellarRegisterTarget
├── CallResult.swift                 # call() 回傳型別，支援 .as(T.self)
├── StellarHandle.swift              # wraps RoguePlanet
├── CometHandle.swift                # wraps Comet
├── SubscriberHandle.swift           # wraps Subscriber
├── GalaxyServerBuilder.swift        # bind → GalaxyServerHandle
├── GalaxyServerHandle.swift         # galaxy.register(as: .stellar(...))
└── StellarServerBuilder.swift       # bind + auto-register with Galaxy
```

## Modified Files

| File | Change |
|------|--------|
| `Sources/Nebula/Nebula.swift` | 新增 `ingress(on:as:)` entry point |
| `Sources/Nebula/Astral/Planet/Planet.swift` | 新增 `call(service:method:arguments:)` overload |
| `samples/demo/Sources/Galaxy/main.swift` | 改用新 facade API |

## NOT Changed (Phase 1)

- `RoguePlanet`, `Moon`, `Comet`, `Subscriber` — 保留為 core entity
- `Nebula.server(with:)`, `Nebula.planet(...)`, `Nebula.moon(...)` — 保留不 deprecate
- `NMTClient`, `NMTServer`, `NMTServerBuilder` — 不動
- `NMTClientTarget`, `NMTServerTarget` — 不動

---

## Verification

1. `swift build` — 新 + 舊 API 都能編譯
2. `swift test` — 既有 tests 全過
3. `cd samples/demo && swift run` — demo 用新 API 正常運作
4. 新增 facade tests：find → call、comet → enqueue、subscriber → events、server register → bind
