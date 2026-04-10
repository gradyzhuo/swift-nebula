# Reliability Adoption Design

**Date:** 2026-04-10
**Status:** Approved
**Scope:** swift-nebula adoption of swift-nmtp reliability sub-system (Phase 1)

---

## Goal

Adopt the three reliability mechanisms introduced by swift-nmtp — request timeout, heartbeat dead-connection detection, and graceful shutdown — so that swift-nebula's typed clients and test lifecycle behave correctly in production.

## Context

swift-nmtp's reliability plan adds:
- `NMTClient.request(matter:timeout:)` — default `.seconds(30)`
- `NMTClient.connect(heartbeatInterval:heartbeatMissedLimit:)` — default 30 s / 2
- `NMTServer.bind(heartbeatInterval:heartbeatMissedLimit:)` — default 30 s / 2
- `NMTServer.shutdown(gracePeriod:)` — draining graceful stop

All changes are backwards-compatible: nebula compiles unchanged. This spec covers the proactive improvements nebula should make on top of that baseline.

---

## Changes

### 1. Typed Client Timeout (High Priority)

**Files:** `Sources/Nebula/NMT/NMTClient+Astral.swift`

Each typed client (`IngressClient`, `GalaxyClient`, `StellarClient`) gains a `defaultTimeout: Duration = .seconds(30)` parameter on `connect()`, stored as an instance property. Every method that calls `base.request()` gains a `timeout: Duration? = nil` parameter; `nil` falls back to `defaultTimeout`.

```swift
// connect
public static func connect(
    to address: SocketAddress,
    tls: NebulaTLSContext? = nil,
    defaultTimeout: Duration = .seconds(30),
    eventLoopGroup: MultiThreadedEventLoopGroup? = nil
) async throws -> GalaxyClient

// method
public func find(namespace: String, timeout: Duration? = nil) async throws -> FindResult {
    // ...
    let reply = try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
    // ...
}
```

`StellarClient.connect()` does not take a `tls` parameter; the same `defaultTimeout` parameter is added in the same position.

Affected methods per client:

| Client | Methods |
|--------|---------|
| `IngressClient` | `find`, `registerGalaxy`, `enqueue`, `findGalaxy`, `unregister`, `clone` |
| `GalaxyClient` | `request`, `find`, `register`, `register(astral:)`, `unregister`, `clone` |
| `StellarClient` | `request`, `clone` |

`GalaxyClient.register(astral:listeningOn:)` delegates to `register(namespace:address:identifier:timeout:)` and passes the `timeout` parameter through.

---

### 2. GalaxyClient Forwarding Method (Low Priority)

**File:** `Sources/Nebula/NMT/NMTClient+Astral.swift`

`GalaxyClient.request(matter:)` currently hides the timeout from callers (used by `StandardIngress`). Add a `timeout` parameter:

```swift
public func request(matter: Matter, timeout: Duration? = nil) async throws -> Matter {
    try await base.request(matter: matter, timeout: timeout ?? defaultTimeout)
}
```

`StandardIngress` call sites are unchanged — `nil` falls back to `defaultTimeout`.

---

### 3. Test Teardown (Medium Priority)

**File:** `Tests/NebulaTests/NebulaTLSContextTests.swift`

Replace four synchronous `closeNow()` teardown calls with async `shutdown()`:

```swift
// Before
defer { server.closeNow() }

// After
defer { Task { try? await server.shutdown() } }
```

This aligns with `NebulaTests.swift` style and makes teardown semantically closer to production behaviour.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/Nebula/NMT/NMTClient+Astral.swift` | Add `defaultTimeout` to all three clients; add `timeout` parameter to all methods |
| `Tests/NebulaTests/NebulaTLSContextTests.swift` | Replace `closeNow()` with `shutdown()` in 4 defer blocks |

---

## Testing Strategy (TDD order)

Tests are written before implementation in the following order:

1. **Typed client timeout compiles** — call `GalaxyClient.connect(to:defaultTimeout:)` and `find(namespace:timeout:)` in a test; assert compile succeeds
2. **Timeout default is forwarded** — connect with `defaultTimeout: .milliseconds(100)`, hit a silent server, assert `NMTPError.timeout` fires within ~100 ms
3. **Per-method override works** — connect with `defaultTimeout: .seconds(30)`, call with `timeout: .milliseconds(100)`, assert same fast timeout
4. **Forwarding method exposes timeout** — `GalaxyClient.request(matter:timeout:)` passes timeout through correctly (shares test infrastructure with #2)
5. **Test teardown compiles** — verify `NebulaTLSContextTests` builds and passes with `shutdown()` teardown

---

## Non-Goals

- Configuring `heartbeatInterval`/`heartbeatMissedLimit` per client — the swift-nmtp defaults (30 s / 2) are used as-is
- Changing `NebulaTests.swift` teardown — already uses `stop()` which is acceptable
- Auto-reconnect — separate sub-system
