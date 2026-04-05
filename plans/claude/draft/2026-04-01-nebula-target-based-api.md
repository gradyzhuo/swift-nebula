# Nebula Facade → Target-Based API

**Date:** 2026-04-01
**Status:** Draft

## Overview

將 `Nebula` facade 從靜態工廠方法（`Nebula.planet(connecting:)` / `Nebula.server(with:)`）重新設計為泛型 `Nebula<Target>` service class，讓編譯器在 IDE 補全階段就限制每種節點角色的可用操作，取代現有 runtime 行為差異。

## Background

現有 `Nebula` facade 是一個空白 `final class`，所有功能都是靜態方法：

```swift
Nebula.server(with: galaxy)      // → NMTServerBuilder<Target>
Nebula.planet(connecting:service:) // → RoguePlanet
Nebula.moon(connecting:service:)   // → Moon
```

問題：
- `NMTServerBuilder` 是 indirection layer，帶來額外的概念負擔
- Planet 與 Moon 各自有一個工廠方法，但 Moon 只是 Planet 的 proxy，理應從 planet 衍生
- 沒有 `Comet` 的 facade 入口（必須手動組裝）
- 使用者無法從型別看出哪些操作合法（e.g., Galaxy 沒有 `add(service:)`，但現在只有文件說明）

Target-Based API 可以在 **編譯期** 解決這些問題。

## Design

### 能力矩陣

| 操作 | `GalaxyTarget` | `StellarTarget` | `PlanetTarget` | `CometTarget` |
|------|:-:|:-:|:-:|:-:|
| `bind(on:)` | ✅ | ✅ | ❌ | ❌ |
| `add(service:)` | ❌ | ✅ | ❌ | ❌ |
| `use(_ middleware:)` | ❌ | ✅ | ❌ | ❌ |
| `configure(namespace:retryPolicy:)` | ✅ | ❌ | ❌ | ❌ |
| `call(method:arguments:)` | ❌ | ❌ | ✅ | ❌ |
| `moon()` | ❌ | ❌ | ✅ | ❌ |
| `enqueue(service:method:arguments:)` | ❌ | ❌ | ❌ | ✅ |

### 三層 Protocol 架構

```
NebulaTarget (base)
    │
    ├── NebulaServable ──────────── bind(on:) 可用
    │       ├── associatedtype WrappedServerTarget: NMTServerTarget
    │       └── var serverTarget: WrappedServerTarget { get }
    │
    ├── NebulaCallable ──────────── call() / moon() 可用
    │       ├── var namespace: String { get }
    │       └── var service: String { get }
    │
    └── NebulaEnqueuable ────────── enqueue() 可用
            └── var namespace: String { get }
```

### Concrete Target Types

```swift
// Server targets
public struct GalaxyTarget: NebulaServable {
    public typealias WrappedServerTarget = StandardGalaxy
    let galaxy: StandardGalaxy
    public var serverTarget: StandardGalaxy { galaxy }
}

public struct StellarTarget: NebulaServable {
    public typealias WrappedServerTarget = ServiceStellar
    let stellar: ServiceStellar
    public var serverTarget: ServiceStellar { stellar }
}

// Client targets
public struct PlanetTarget: NebulaCallable {
    let planet: RoguePlanet
    public var namespace: String { planet.namespace }
    public var service: String { planet.service }
}

public struct CometTarget: NebulaEnqueuable {
    let comet: Comet
    public var namespace: String { comet.namespace }
}
```

### `Nebula<Target>` Service Class

```swift
public final class Nebula<Target: NebulaTarget>: Sendable {
    let target: Target
    private init(target: Target) { self.target = target }
}
```

### Static Factory Methods（每個 Target type 一組）

```swift
// Galaxy server
extension Nebula where Target == GalaxyTarget {
    public static func galaxy(_ galaxy: StandardGalaxy) -> Nebula<GalaxyTarget>
}

// Stellar server
extension Nebula where Target == StellarTarget {
    public static func stellar(_ stellar: ServiceStellar) -> Nebula<StellarTarget>
}

// Planet client (async — needs network connection)
extension Nebula where Target == PlanetTarget {
    public static func planet(
        connecting uriString: String,
        service: String,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> Nebula<PlanetTarget>
}

// Comet client (async — needs network connection)
extension Nebula where Target == CometTarget {
    public static func comet(
        connecting uriString: String,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> Nebula<CometTarget>
}
```

### Conditional Extensions（操作附加）

```swift
// ── Shared: all server targets ──────────────────────────────────────
extension Nebula where Target: NebulaServable {
    public func bind(
        on address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer<Target.WrappedServerTarget>
}

// ── Stellar-only ─────────────────────────────────────────────────────
extension Nebula where Target == StellarTarget {
    @discardableResult
    public func add(service: Service) -> Self

    @discardableResult
    public func use(_ middleware: any NMTMiddleware) -> Self
}

// ── Galaxy-only ──────────────────────────────────────────────────────
extension Nebula where Target == GalaxyTarget {
    public func configure(namespace: String, retryPolicy: RetryPolicy) async
}

// ── Planet-only ──────────────────────────────────────────────────────
extension Nebula where Target == PlanetTarget {
    public func call(method: String, arguments: [Argument]) async throws -> Data?
    public func call<T: Decodable>(method: String, arguments: [Argument], as type: T.Type) async throws -> T
    public func moon() -> Moon
}

// ── Comet-only ───────────────────────────────────────────────────────
extension Nebula where Target == CometTarget {
    public func enqueue(
        service: String,
        method: String,
        arguments: [Argument],
        namespace: String?
    ) async throws
}
```

### 使用範例（對比）

**Before:**
```swift
// Server
let server = try await Nebula.server(with: galaxy).bind(on: address)

// Client
let planet = try await Nebula.planet(connecting: "nmtp://...", service: "orders")
let moon   = try await Nebula.moon(connecting: "nmtp://...", service: "orders")
```

**After:**
```swift
// Server — Galaxy
let galaxyNode = Nebula.galaxy(myGalaxy)
let server = try await galaxyNode.bind(on: address)

// Server — Stellar (builder-style chaining preserved)
let stellarNode = Nebula.stellar(myStellar)
    .use(LoggingMiddleware())
    .add(service: orderService)
let server = try await stellarNode.bind(on: address)

// Galaxy 配置
await galaxyNode.configure(namespace: "prod.orders", retryPolicy: .aggressive)

// Client — Planet
let planetNode = try await Nebula.planet(connecting: "nmtp://...", service: "orders")
let result = try await planetNode.call(method: "create", arguments: [...])

// Client — Moon (從 Planet 衍生，不另開連線)
let moon = planetNode.moon()
let data = try await moon.embed(word: "hello")

// Client — Comet
let cometNode = try await Nebula.comet(connecting: "nmtp+broker://...")
try await cometNode.enqueue(service: "orderService", method: "process", arguments: [...])

// 編譯期錯誤範例：
try await galaxyNode.call(method: "x")   // ❌ GalaxyTarget 沒有 call
try await planetNode.bind(on: address)   // ❌ PlanetTarget 沒有 bind
stellarNode.configure(...)               // ❌ StellarTarget 沒有 configure
```

### 什麼會被移除

| 移除 | 替代 |
|------|------|
| `Nebula.standard` (unused singleton) | 刪除 |
| `Nebula.server(with:)` | `Nebula.galaxy()` / `Nebula.stellar()` |
| `Nebula.planet(connecting:service:)` | `Nebula.planet(connecting:service:)` (同名，不同回傳型別) |
| `Nebula.moon(connecting:service:)` | `planetNode.moon()` |
| `NMTServerBuilder<Target>` | 吸收進 `Nebula<Target> where Target: NebulaServable` |

### 什麼不動

- `StandardGalaxy`, `ServiceStellar`, `RoguePlanet`, `Comet`, `Moon` — 內部 actor/class，不改
- `NMTServerTarget`, `NMTClientTarget` — 低層 protocol，不改
- `NMTServer<Target>` — 仍為實際 running server，不改
- `NMTClient<Target>` — 仍為低層連線，不改

## Implementation Steps

1. [ ] 新增 `Sources/Nebula/Nebula/NebulaTarget.swift`
   - 定義 `NebulaTarget`、`NebulaServable`、`NebulaCallable`、`NebulaEnqueuable`

2. [ ] 新增 `Sources/Nebula/Nebula/NebulaServerTargets.swift`
   - 定義 `GalaxyTarget`、`StellarTarget`

3. [ ] 新增 `Sources/Nebula/Nebula/NebulaClientTargets.swift`
   - 定義 `PlanetTarget`、`CometTarget`

4. [ ] 改寫 `Sources/Nebula/Nebula.swift`
   - `Nebula<Target>` generic class
   - 移除 `Nebula.standard`、`Nebula.server(with:)`、`Nebula.planet(...)`、`Nebula.moon(...)`

5. [ ] 新增 `Sources/Nebula/Nebula/Nebula+Server.swift`
   - Factory: `Nebula.galaxy()`, `Nebula.stellar()`
   - `bind(on:)` conditional extension
   - `add(service:)`, `use(_:)` for StellarTarget
   - `configure(namespace:retryPolicy:)` for GalaxyTarget

6. [ ] 新增 `Sources/Nebula/Nebula/Nebula+Client.swift`
   - Factory: `Nebula.planet(connecting:service:)`, `Nebula.comet(connecting:)`
   - `call(method:arguments:)`, `moon()` for PlanetTarget
   - `enqueue(...)` for CometTarget

7. [ ] 刪除 `Sources/Nebula/NMT/NMTServerBuilder.swift`

8. [ ] 更新 `samples/demo/` 及所有 test 中使用舊 API 的呼叫端

## Open Questions

1. **`NMTServerBuilder` 是 public API** — 如果有外部使用者（非 demo），需要 deprecation period 而非直接刪除。目前 demo 是唯一使用方，直接刪除應可接受，待確認。

2. **`Nebula<StellarTarget>` 的 Sendable** — `ServiceStellar` 是 `@unchecked Sendable`，`StellarTarget` struct 包住它後也需要 `@unchecked Sendable`。這是否可接受，還是應讓 `StellarTarget` 改為 final class？

3. **`Nebula.comet(connecting:)` 的 URI scheme** — 目前 Comet 用 `nmtp+broker://` scheme，但 `NebulaURI` 只 parse `nmtp://`。`comet` factory 是否複用 `NebulaURI` 或另寫 parser？

4. **`configure(namespace:retryPolicy:)` 時機** — Galaxy 是 actor，所以 `configure` 需要 `async`。但如果使用者在 `bind()` 之後才 configure，時序是否有問題？是否需要讓 factory 接受 configuration closure 以確保 setup 在 bind 前完成？

5. **`moon()` 是否應該保留為 `Nebula` static factory** — `Nebula.moon(connecting:service:)` 開兩次連線（planet + moon）的問題本來存在。改成 `planetNode.moon()` 明確解決這問題。但要確認沒有人依賴舊的 `moon()` shortcut 語法。
