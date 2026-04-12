# swift-nebula × swift-nmtp Migration Design

**Date:** 2026-04-12
**Status:** Approved
**Scope:** swift-nmtp (rename), swift-nebula (migration to new NMTP API)

---

## Goal

Refactor swift-nebula to use the current swift-nmtp API. The old NMTP bundled Nebula-specific types (`Argument`, `MatterType` enum, `decodeBody`, `reply(body:)`) and MessagePack encoding. The new NMTP is a clean transport layer with no application-level opinions. This migration aligns swift-nebula to that separation.

---

## Naming & Responsibility Realignment

### Section 1：NMTP rename

| Before | After | Location |
|--------|-------|----------|
| `MatterBehavior` (enum) | `MatterType` | NMTP |
| `Matter.behavior` | `Matter.type` | NMTP |
| `MatterPayload.type: UInt16` | `MatterPayload.typeID: UInt16` | NMTP |

**Rationale:** `MatterBehavior` describes "what type of frame is this?" at the wire level — command frame, query frame, event frame, heartbeat frame. Calling this `type` is accurate. The name `MatterBehavior` is freed up and returned to Nebula for application-layer use.

`MatterPayload.typeID` avoids a name collision with `Matter.type`.

### Why `MatterType` stays in NMTP

The `M` in NMTP stands for Matter. NMTP's `Matter` struct is correct and stays as-is. The renamed `MatterType` is integral to NMTP's own identity — it describes what type of Matter frame is being transferred.

---

## Section 2：Nebula New Types

### `MatterBehavior` (Nebula, protocol)

Nebula reclaims the `MatterBehavior` name as a **protocol** for class-2 typed content — the application-layer payload that goes inside a `Matter`.

```swift
public protocol MatterBehavior: Codable {
    static var typeID: UInt16 { get }
    static var type: MatterType { get }  // maps to NMTP's MatterType
}
```

Each Nebula message type owns its metadata:

```swift
struct FindMatter: MatterBehavior {
    static let typeID: UInt16 = 0x0003
    static let type: MatterType = .query
    let namespace: String
}
```

Factory methods use constrained extensions (SwiftUI-style dot syntax):

```swift
extension MatterBehavior where Self == FindMatter {
    public static func find(namespace: String) -> FindMatter {
        FindMatter(namespace: namespace)
    }
}

// Usage:
try await base.request(.find(namespace: "production.ml"), timeout: ...)
```

### `NMTDispatcher` (Nebula)

Implements `NMTHandler`. Receives a `Matter`, extracts `typeID` from the payload, looks up the registered handler, MessagePack-decodes the body, calls the handler, encodes the reply.

```swift
public final class NMTDispatcher: NMTHandler, Sendable {
    // Handler with reply
    public func register<A: MatterBehavior, R: Encodable>(
        _ type: A.Type,
        handler: @escaping @Sendable (A, Channel) async throws -> R
    )
    // Handler with no reply (events etc.)
    public func register<A: MatterBehavior>(
        _ type: A.Type,
        handler: @escaping @Sendable (A, Channel) async throws -> Void
    )
}
```

### `Argument` (moved to Nebula)

`Argument` was in old NMTP but is Nebula-specific (RPC call arguments). Moved to Nebula unchanged:

```swift
public struct Argument: Sendable {
    public let key: String
    public let data: Data
}
```

---

## Section 3：Node Changes (Galaxy / Stellar / Ingress)

`switch matter.type` is replaced with `register(on:)`. Each node declares what it handles:

```swift
// Before (StandardGalaxy.swift)
func handle(matter: Matter, channel: Channel) async throws -> Matter? {
    switch matter.type {
    case .find:     return try await handleFind(matter)
    case .register: return try await handleRegister(matter)
    ...
    }
}

// After
func register(on dispatcher: NMTDispatcher) {
    dispatcher.register(FindMatter.self) { [unowned self] matter, channel in
        let result = await self.findStellar(namespace: matter.namespace)
        return FindReplyMatter(stellarHost: result?.host, stellarPort: result?.port)
    }
    dispatcher.register(RegisterMatter.self) { [unowned self] matter, channel in
        await self.addStellar(namespace: matter.namespace, host: matter.host, port: matter.port)
        return RegisterReplyMatter(status: "ok")
    }
}
```

`Nebula.bind()` accepts a `NMTDispatcher`:

```swift
let dispatcher = NMTDispatcher()
await galaxy.register(on: dispatcher)
await stellar.register(on: dispatcher)
let server = try await Nebula.bind(dispatcher, on: address, tls: tls)
```

`NMTServerTarget` typealias is deleted. `ServiceStellar`'s `NMTMiddleware` chain is preserved — middleware runs before the dispatcher calls any handler.

**Design rationale (OCP + SRP):** Adding a new message type requires only a new `*Matter` struct and a `register` call. No existing dispatch code is touched.

---

## Section 4：Client-Side Changes

`NMTClient` gains a `MatterBehavior` overload (Nebula extension):

```swift
// Matter+Nebula.swift (Nebula extension on NMTP's Matter)
extension Matter {
    static func make<A: MatterBehavior>(_ action: A) throws -> Matter { ... }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { ... }
}

// NMTClient+Nebula.swift
extension NMTClient {
    public func request<A: MatterBehavior>(
        _ action: A,
        timeout: Duration = .seconds(30)
    ) async throws -> Matter {
        let matter = try Matter.make(action)  // Nebula extension, MessagePack encode
        return try await request(matter: matter, timeout: timeout)
    }
}
```

`IngressClient`, `GalaxyClient`, `StellarClient` public APIs are unchanged. Internal call sites use the new syntax:

```swift
// Before
let matter = try Matter.make(type: .find, body: body)
let reply = try await base.request(matter: matter, timeout: ...)
let replyBody = try reply.decodeBody(FindReplyBody.self)

// After
let reply = try await base.request(.find(namespace: namespace), timeout: ...)
let replyMatter = try reply.decode(FindReplyMatter.self)
```

---

## Section 5：Supporting Details

### Renamed Message Types

All `*Body` / `*ReplyBody` types are renamed to `*Matter` / `*ReplyMatter`:

| Before | After |
|--------|-------|
| `FindBody` / `FindReplyBody` | `FindMatter` / `FindReplyMatter` |
| `RegisterBody` / `RegisterReplyBody` | `RegisterMatter` / `RegisterReplyMatter` |
| `CallBody` / `CallReplyBody` | `CallMatter` / `CallReplyMatter` |
| `UnregisterBody` / `UnregisterReplyBody` | `UnregisterMatter` / `UnregisterReplyMatter` |
| `EnqueueBody` / `EnqueueReplyBody` | `EnqueueMatter` / `EnqueueReplyMatter` |
| `CloneBody` / `CloneReplyBody` | `CloneMatter` / `CloneReplyMatter` |
| `AckBody` | `AckMatter` |
| `SubscribeBody` / `SubscribeReplyBody` | `SubscribeMatter` / `SubscribeReplyMatter` |
| `UnsubscribeBody` | `UnsubscribeMatter` |
| `FindGalaxyBody` / `FindGalaxyReplyBody` | `FindGalaxyMatter` / `FindGalaxyReplyMatter` |

### Encoding

Nebula uses **MessagePack** for body encoding (binary, not human-readable — intentional). `MessagePacker` is added back as a swift-nebula dependency. NMTP itself has no encoding opinion.

### Middleware

`NMTMiddleware` protocol and `ServiceStellar.use(_:)` are unchanged. The middleware chain executes before `NMTDispatcher` dispatches to a handler.

### NMTPeer

`NMTPeer` references `MatterBehavior` (now renamed to `MatterType` in NMTP). Update all `MatterBehavior` references in `NMTPeer` to `MatterType`.

### Removed

- `NMTServerTarget` typealias (was just `typealias NMTServerTarget = NMTHandler`)
- All `*Body` / `*ReplyBody` types (replaced by `*Matter` / `*ReplyMatter`)
- Old `Matter.make(type:body:)`, `Matter.decodeBody(_:)`, `Matter.reply(body:)` helpers (these were in old NMTP, replaced by Nebula-local extensions)

---

## Affected Files

### swift-nmtp
- `Sources/NMTP/Matter/MatterBehavior.swift` → rename file and type to `MatterType`
- `Sources/NMTP/Matter/Matter.swift` → `behavior` field → `type`
- `Sources/NMTP/Matter/Matter+Coding.swift` → update references
- `Sources/NMTPeer/` → update `MatterBehavior` → `MatterType` references

### swift-nebula
- `Package.swift` — add `MessagePacker` dependency
- `Sources/Nebula/NMT/MatterBehavior.swift` — NEW (protocol)
- `Sources/Nebula/NMT/NMTDispatcher.swift` — NEW
- `Sources/Nebula/NMT/Argument.swift` — NEW (moved from old NMTP)
- `Sources/Nebula/NMT/Matter+Nebula.swift` — NEW (make/decode helpers, constrained factory extensions)
- `Sources/Nebula/NMT/Target/NMTServerTarget.swift` — DELETE
- `Sources/Nebula/Astral/Galaxy/StandardGalaxy.swift` — switch → register(on:)
- `Sources/Nebula/Astral/Stellar/Stellar.swift` — switch → register(on:)
- `Sources/Nebula/Ingress/StandardIngress.swift` — switch → register(on:)
- `Sources/Nebula/NMT/NMTClient+Astral.swift` — update to new API
- `Sources/Nebula/Nebula.swift` — bind() accepts NMTDispatcher
- All `*Body` files — renamed to `*Matter`
