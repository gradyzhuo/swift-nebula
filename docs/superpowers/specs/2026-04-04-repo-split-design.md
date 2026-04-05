# Nebula Repo Split: NMTP / Server / Client

**Date:** 2026-04-04
**Status:** Draft

## Overview

Split the monolithic `swift-nebula` package into three independent repos, separated by architectural layer:

1. **`swift-nmtp`** — NMTP 協議的 Swift 實作（純傳輸，無框架語義）
2. **`swift-nebula`** — Nebula server 框架（spec 持有者）
3. **`swift-nebula-client`** — Nebula 的 Swift client（多語言 client 之一）

## Motivation

### 協議層 vs 框架層

NMTP (Nebula Matter Transfer Protocol) 是傳輸協議——它只管「怎麼把 Matter 從 A 送到 B」。Nebula 是建立在 NMTP 之上的框架——它賦予節點 cosmic 語義（Galaxy、Stellar、Planet）、定義 service discovery、load balancing、failover。

目前兩層混在同一個 package 裡，導致：

- Client 必須編譯 server code
- 協議層被框架概念污染（`NMTClient<GalaxyTarget>` 的泛型就是框架語義洩漏到協議層）
- 無法讓其他語言只實作 NMTP 協議來建立 client

### 多語言 Client

未來 client 可能有 Python、Go、JavaScript 等語言的實作。每個語言各自實作 NMTP 協議和 Nebula client spec。Swift client 只是其中之一，不應享有與 server 共用 Swift code 的特權。

Client 對齊 server 的方式是追版本和 spec，不是共用 Swift 原始碼。

## Design Principle

```
NMTP (協議)     ← 只知道 Matter 怎麼收發，不知道對象是誰
                   像萬有引力——只管傳遞的力，不管被牽引的星體叫什麼

Nebula (框架)   ← 在 NMTP 之上建立 Astral 階層、命名、規則
                   像物理學——用概念去命名那股看不見的力量
```

## Repositories

### swift-nmtp

NMTP 協議的完整 Swift 實作。無泛型、無框架語義。

**Contents:**

| 模組 | 內容 |
|------|------|
| `Matter/` | `Matter` struct, `MatterType` enum, 所有 body codables (`CallBody`, `FindBody`, `RegisterBody`, etc.) |
| `NMT/` | `NMTClient` (無泛型), `NMTServer` (無泛型), `NMTHandler` protocol |
| `Codec/` | `EnvelopeEncoder`, `EnvelopeDecoder` (NIO handlers), `MatterEncoder`, `MatterDecoder` |
| Root | `Argument`, `ArgumentValue`, `NMTPError` |

**`NMTClient` (無泛型):**

```swift
public class NMTClient: Sendable {
    public static func connect(to address: SocketAddress) async throws -> NMTClient
    public func request(matter: Matter) async throws -> Matter
    public func send(matter: Matter) async throws
}
```

**`NMTServer` (無泛型):**

```swift
public class NMTServer: Sendable {
    public static func bind(on address: SocketAddress, handler: NMTHandler) async throws -> NMTServer
}

public protocol NMTHandler: Sendable {
    func handle(matter: Matter, channel: Channel) async throws -> Matter?
}
```

**不包含:**

- `NMTPNode` protocol (協議層無消費者；節點身份交換已由 `CloneReplyBody` 承載)
- `NMTClientTarget`, `NMTServerTarget` (框架層的泛型 target 概念)
- `Astral`, `AstralCategory` (框架語義)
- `NMTClient+Astral` convenience methods (框架語義: register, find, unregister)
- `Service`, `Method` (server 框架概念)
- `NebulaURI` (框架概念)
- `NMTServerBuilder` (框架 convenience)

**Dependencies:**

- swift-nio
- swift-nio-extras
- MessagePacker
- swift-log

### swift-nebula

Nebula server 框架。**Nebula spec 的持有者**——定義 Astral 角色、namespace 規則、AstralCategory mapping。

**Contents:**

| 模組 | 內容 |
|------|------|
| `Astral/` | `Astral: NMTPNode` protocol, `ServerAstral` protocol, `AstralCategory` enum |
| `Ingress/` | `StandardIngress` |
| `Galaxy/` | `StandardGalaxy`, `Galaxy` protocol |
| `Amas/` | `LoadBalanceAmas`, `BrokerAmas` |
| `Stellar/` | `ServiceStellar`, `Stellar` protocol, `Service`, `Method` |
| `Broker/` | `QueueStorage`, `QueuedMatter`, `RetryPolicy` |
| `Registry/` | `ServiceRegistry` protocol, `InMemoryServiceRegistry` |
| `Auth/` | `NMTMiddleware` protocol |
| `NMT+Nebula/` | `register()`, `find()`, `unregister()`, `findGalaxy()` 等 convenience（包裝 `NMTClient`，加框架語義）|
| `Resource/` | `NebulaURI` |
| Root | `Nebula.swift` (facade) |

**Dependencies:**

- swift-nmtp

**Notes:**

- `Astral` protocol 繼承 `NMTPNode`（from swift-nmtp），加入 `namespace`、framework-level 行為
- `AstralCategory` enum 的 raw values 是 Nebula spec 的一部分
- `ServerAstral` 繼承 `Astral` + conform `NMTHandler`（from swift-nmtp）
- `NMTClient+Nebula` 的 convenience methods 包裝純 `NMTClient`，加入 `register`/`find`/`unregister` 等 Nebula 語義操作

### swift-nebula-client

Nebula 的 Swift client 實作。多語言 client 之一，對齊 Nebula server 的 spec。

**Contents:**

| 模組 | 內容 |
|------|------|
| `Astral/` | `Astral: NMTPNode` protocol, `AstralCategory` enum (**自己定義，對齊 Nebula spec**) |
| `Planet/` | `Planet` protocol, `RoguePlanet` actor, `Moon`, `MethodProxy`, `Satellite` protocol |
| `Comet/` | `Comet` actor |
| `Subscriber/` | `Subscriber` |
| `NMT+Nebula/` | Client 側的 Nebula convenience（包裝 `NMTClient`）|

**Dependencies:**

- swift-nmtp

**Notes:**

- `Astral` protocol 和 `AstralCategory` 在 client 自己定義一份，對齊 Nebula spec
- 這與其他語言的 client 一致——Python client 也會自己定義 `AstralCategory`
- Client 對齊版本的方式是追 Nebula spec，不是共用 Swift code

## Boundary Decisions

### NMTClient / NMTServer 無泛型

現有的 `NMTClient<Target>` 和 `NMTServer<Target>` 的泛型參數是框架概念（「我連的是 Galaxy 還是 Stellar」）。協議層不該知道這件事。

- `swift-nmtp`：`NMTClient`（無泛型）只管 connect + send/receive Matter
- `swift-nebula`：在 `NMTClient` 之上包裝 Nebula 語義（register、find 等）
- `swift-nebula-client`：在 `NMTClient` 之上包裝 client 語義（call、failover 等）

### Astral 不共用

`Astral` protocol 和 `AstralCategory` 是框架語義，server 和 client 各自定義。理由：

- 未來 client 會有其他語言實作，不可能共用 Swift code
- 即使同是 Swift，也不應為了避免重複定義而強迫共用
- Client 對齊 server 的方式是追版本，不是 import 同一份原始碼

### NMTPNode 不在協議層

`NMTPNode` protocol 在 swift-nmtp 層沒有消費者——`NMTClient` 和 `NMTServer` 都不 constrain against 它。節點身份交換（`.clone`）已由 `CloneReplyBody`（plain struct: identifier, name, category）承載。`NMTPNode` 是框架語義，由 `Astral` protocol 在 Nebula 框架層各自定義。

### Service / Method 在 Stellar 模組

`Service` 和 `Method` 只有 `ServiceStellar` 使用，放在 Stellar 模組目錄下，不再放 Resource/。

## Migration Strategy

1. **Create `swift-nmtp`**: new repo, extract `Matter/`, codec, `NMTClient`/`NMTServer`（移除泛型）, `NMTPNode`, `Argument`, `ArgumentValue`. `swift build` to verify.
2. **Restructure `swift-nebula`**: depend on `swift-nmtp`, 移除已搬走的檔案, 加入 `NMT+Nebula/` convenience, 移動 `Service`/`Method` 到 `Stellar/`. `swift build` to verify.
3. **Create `swift-nebula-client`**: new repo, depend on `swift-nmtp`, 搬入 Planet/Comet/Subscriber, 自行定義 `Astral`/`AstralCategory`. `swift build` to verify.
4. **Migrate `samples/demo/`**: update demo `Package.swift` to depend on `swift-nebula` + `swift-nebula-client`, verify `swift run`.
5. **Migrate tests**: split into per-repo tests.

Git history 不帶過去。各新 repo 從 initial commit 開始。舊 `swift-nebula` repo 先保留。

## What is NOT in scope

- Staged facade API (proposal 0001) — deferred until repos are stable
- `NebulaServiceLifecycle` — excluded
- `Discovery/` — evaluate during implementation
- `Logging/ColorLogHandler` — evaluate during implementation

## Open Questions

1. **`Discovery/`** — `LocalDiscovery` and `NebulaDiscovery` may be used by both sides. Evaluate during implementation.
2. **`Logging/ColorLogHandler`** — utility code; evaluate whether it belongs in swift-nebula or should be dropped.
3. **Library product naming** — `NMTP` / `Nebula` / `NebulaClient` are working names. May rename later.
4. **NMTClient+Nebula convenience 的 API 形式** — 是直接在 NMTClient 上加 extension methods，還是包裝成獨立的 helper type？待實作時決定。
