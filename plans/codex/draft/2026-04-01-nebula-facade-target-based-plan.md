# Nebula Facade Target-Based Migration Plan

**Date:** 2026-04-01
**Status:** Draft

## Goal

將 `Nebula` facade 從目前的 entity-based convenience API，重構成 target-based facade API。

這次調整的核心不是單純改名，而是把對外 API 的能力邊界，對齊底層已經存在的 target abstraction：

- `NMTClient<Target>`
- `NMTServerTarget`
- `NMTClientTarget`

也就是說，`Nebula` 不再主要暴露 `planet`、`moon`、`server(with:)` 這種 astral noun API，而是暴露「連到哪種 target，就得到哪組能力」的 facade。

## Current State

目前底層其實已經是 target-based：

- `NMTClient<IngressTarget>` 有 `find`、`registerGalaxy`、`unregister`、`enqueue`
- `NMTClient<GalaxyTarget>` 有 `find`、`register`、`unregister`
- `NMTClient<StellarTarget>` 承接 call 路徑
- `NMTServer.bind(on:target:)` 本身也已經收 `NMTServerTarget`

但最上層 facade 仍然是 entity-based：

```swift
Nebula.server(with: ingress)
Nebula.server(with: galaxy)
Nebula.planet(connecting: uri, service: service)
Nebula.moon(connecting: uri, service: service)
```

這造成幾個問題：

- facade 與底層抽象方向不一致
- `Planet` / `Moon` 成為主要心智模型，但它們其實只是某些 target 能力的包裝
- `Moon` 是 `Planet` 的語法糖，卻佔用一級入口
- API surface 不容易隨新 target 擴充
- README 與使用者心智會被 astral naming 綁住，而不是 capability-based design

## Design Principle

我會用這個原則收斂 API：

1. `Target` 代表 capability boundary，不代表 domain object
2. `Nebula` 只負責進入某個 target capability
3. `Planet` / `Moon` / `Comet` 可以保留，但退居為 convenience layer
4. 既有 `NMTClient<Target>` extension 盡量不重寫，只往 facade wrapper 提升
5. migration 先加新 API，再 deprecate 舊 API，不直接破壞

## Proposed API Shape

### Server Side

```swift
let ingressServer = try await Nebula
    .serve(target: ingress)
    .bind(on: ingressAddress)

let galaxyServer = try await Nebula
    .serve(target: galaxy)
    .bind(on: galaxyAddress)

let stellarServer = try await Nebula
    .serve(target: stellar)
    .bind(on: stellarAddress)
```

這裡 `serve(target:)` 的語意比 `server(with:)` 更接近 target-based facade。

### Client Side

```swift
let ingress = try await Nebula.connect(to: ingressAddress, as: .ingress)
let galaxy = try await Nebula.connect(to: galaxyAddress, as: .galaxy)
let stellar = try await Nebula.connect(to: stellarAddress, as: .stellar)
```

或支援 URI convenience：

```swift
let ingress = try await Nebula.connect(to: "nmtp://[::1]:22400", as: .ingress)
```

### Capability-Oriented Usage

```swift
let ingress = try await Nebula.connect(to: "nmtp://[::1]:22400", as: .ingress)
let service = ingress
    .namespace("production.ml.embedding")
    .service("w2v")

let result: Embedding = try await service.call(
    "wordVector",
    as: Embedding.self,
    arguments: [.init(name: "words", value: .array(["slow", "fast"]))]
)
```

這個方向的重點是：

- 先得到 `IngressTarget` connection
- 再 bind `namespace`
- 再 bind `service`
- 最後執行 `call`

也就是把既有 `RoguePlanet` 的 connection cache / failover 行為，收斂到一個 service-bound handle 裡，而不是讓使用者先理解 `Planet`

## Proposed Types

### 1. `NebulaConnection<Target>`

```swift
public struct NebulaConnection<Target: NMTClientTarget>: Sendable {
    public let client: NMTClient<Target>
}
```

用途：

- 成為 facade 的 client-side 主型別
- 對外隱藏低層 `NMTClient` 的直接使用
- 用 conditional extension 暴露 target-specific API

### 2. `NebulaServiceHandle`

```swift
public struct NebulaServiceHandle: Sendable {
    public let namespace: String
    public let service: String
}
```

實際上它需要持有：

- ingress connection
- namespace
- service
- direct stellar connection cache
- failover policy

這個型別本質上就是把目前 `RoguePlanet` 的行為，從 astral-named object 收斂成 capability-bound handle。

### 3. `Moon` 作為 DSL Adapter

`Moon` 保留，但定位調整成：

- 不是 primary facade
- 是 `NebulaServiceHandle` 的 dynamic member DSL

例如：

```swift
let moon = service.moon()
let result: Embedding = try await moon.wordVector.call(as: Embedding.self, words: ["slow"])
```

## Capability Mapping

### `NebulaConnection<IngressTarget>`

應暴露：

- `find(namespace:)`
- `registerGalaxy(name:address:identifier:)`
- `unregister(namespace:host:port:)`
- `enqueue(namespace:service:method:arguments:)`
- `namespace(_:) -> NebulaNamespaceHandle`

### `NebulaConnection<GalaxyTarget>`

應暴露：

- `find(namespace:)`
- `register(namespace:address:identifier:)`
- `register(astral:listeningOn:)`
- `unregister(namespace:host:port:)`

### `NebulaConnection<StellarTarget>`

應暴露：

- `call(namespace:service:method:arguments:)`
- `call(namespace:service:method:arguments:as:)`

### `NebulaServer`

server-side facade 不需要另一套抽象；保留 `NMTServerBuilder<Target>` 也可以，但我會建議至少改 façade naming：

- from: `Nebula.server(with:)`
- to: `Nebula.serve(target:)`

如果想再進一步，可考慮把 `NMTServerBuilder<Target>` rename 成更中性的 `NebulaServerBuilder<Target>`，但這不是 migration 第一階段的必要工作。

## What Should Happen to Existing Types

### `RoguePlanet`

保留，但角色改為 internal implementation detail 或 compatibility layer。

理由：

- 它已經實作好 direct stellar connection cache
- 它已經處理 failover
- 它可以作為 `NebulaServiceHandle` 的底層實作

不建議第一版直接刪，因為那會把 facade migration 變成 transport reimplementation。

### `Moon`

保留，但降級成 optional syntax sugar。

不應再讓 `Nebula.moon(connecting:service:)` 成為主要入口。

### `Comet`

如果要維持一致性，未來也應走 target-based facade，而不是單獨保留 astral-named static factory。

## Migration Strategy

### Phase 1: Add New API Without Breaking Old API

新增：

- `Nebula.connect(to:as:)`
- `Nebula.connect(to uriString:as:)`
- `Nebula.serve(target:)`
- `NebulaConnection<Target>`
- `NebulaServiceHandle`

此階段不移除：

- `Nebula.server(with:)`
- `Nebula.planet(connecting:service:)`
- `Nebula.moon(connecting:service:)`

目標是先把新 facade 建出來，讓 README、demo、tests 可以開始遷移。

### Phase 2: Move README and Samples

更新文件與 sample code，讓主路徑改成 target-based：

- server startup 用 `serve(target:)`
- client call 用 `connect(to:as:)`
- `planet` / `moon` 放到 convenience section

### Phase 3: Deprecate Old Facade API

為以下 API 加上 deprecation：

- `Nebula.server(with:)`
- `Nebula.planet(connecting:service:)`
- `Nebula.moon(connecting:service:)`

message 應明確指出替代路徑，例如：

```swift
@available(*, deprecated, message: "Use Nebula.serve(target:) instead.")
@available(*, deprecated, message: "Use Nebula.connect(to:as:) and bind namespace/service instead.")
```

### Phase 4: Major Release Cleanup

等新 API 穩定、sample 全部切完、外部使用者有遷移期後，再考慮移除舊 facade。

## Implementation Plan

1. 新增 facade wrapper 型別
   - 新增 `NebulaConnection<Target>`
   - 新增 `NebulaNamespaceHandle`
   - 新增 `NebulaServiceHandle`

2. 在 `Nebula.swift` 上新增新入口
   - `serve(target:)`
   - `connect(to:as:)`
   - `connect(to uriString:as:)`

3. 將 target-specific 能力提升到 facade
   - `NebulaConnection<IngressTarget>`
   - `NebulaConnection<GalaxyTarget>`
   - `NebulaConnection<StellarTarget>`

4. 把 `RoguePlanet` 封裝到 `NebulaServiceHandle`
   - 先用 adapter 包起來，不重寫 failover
   - 確認新 facade 行為與舊 planet 一致

5. 將 `Moon` 改成從 service handle 衍生
   - 例如 `service.moon()`
   - `Nebula.moon(connecting:)` 改成 compatibility shim

6. 更新 README
   - Quick Start 改成 target-based path
   - 保留 convenience section 介紹 `planet` / `moon`

7. 更新 demo
   - sample main files 改用 `serve(target:)`
   - client sample 改用 `connect(to:as:)`

8. 新增 facade migration tests
   - `connect(to:as:)` works
   - `IngressTarget` facade can resolve namespace
   - `NebulaServiceHandle` can call and fail over
   - old `planet` API still works as compatibility layer

## File-Level Plan

第一個 PR 我會鎖定這幾類檔案：

- `Sources/Nebula/Nebula.swift`
- `Sources/Nebula/NMT/NMTClient+Astral.swift`
- `Sources/Nebula/Astral/Planet/Planet.swift`
- `Sources/Nebula/Astral/Planet/Moon.swift`
- `README.md`
- `samples/demo/Sources/Client/main.swift`
- `Tests/NebulaTests/NebulaTests.swift`

另建新檔：

- `Sources/Nebula/Facade/NebulaConnection.swift`
- `Sources/Nebula/Facade/NebulaNamespaceHandle.swift`
- `Sources/Nebula/Facade/NebulaServiceHandle.swift`

如果你不想引入 `Facade/` 子資料夾，也可以平鋪在 `Sources/Nebula/`，但我傾向把新的 façade layer 集中，避免和 transport / astral / resource 混在一起。

## Risks

### 1. 只是改名，沒有真正改抽象

如果最後只是：

- `planet` 改叫 `service`
- `server(with:)` 改叫 `serve(target:)`

那其實沒有完成 target-based facade，只是 rename。

所以 migration 成敗的關鍵，在於是否真的引入：

- target-bound connection
- namespace-bound handle
- service-bound handle

### 2. 過早刪除 `Planet`

`RoguePlanet` 已經承載重要 runtime 行為。第一階段直接砍掉，很容易把 facade migration 變成 failover regression。

### 3. Facade 與 Low-Level API 雙軌失焦

如果新 facade 沒有明確成為 README 主線，使用者最後還是會直接用 `NMTClient.connect(...)`。

所以文件更新不能延後太久。

## Recommended First PR Scope

第一個 PR 不要追求一次到位。我建議只做：

1. 新增 `Nebula.connect(to:as:)`
2. 新增 `Nebula.serve(target:)`
3. 新增 `NebulaConnection<Target>`
4. 新增 `NebulaServiceHandle`，內部先包 `RoguePlanet`
5. README Quick Start 改走新 API
6. 保留所有舊 API，不標 deprecated

這樣可以先驗證新 facade 方向正不正，再進入第二個 PR 做 deprecation 與 sample cleanup。

## Expected Outcome

完成後，Nebula 的主 API 會從：

- 以 astral noun 為中心
- 以 convenience factory 為中心

轉成：

- 以 target capability 為中心
- 以 connection / bind / call 為中心

這會讓 facade 與底層 transport 模型一致，也讓未來新增 broker、subscriber、streaming target 時，有一條一致的 API 擴充路徑。
