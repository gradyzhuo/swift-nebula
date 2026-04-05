# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build
swift build
swift build -c release

# Test
swift test

# Run a single test
swift test --filter NebulaTests.<TestClassName>/<testMethodName>
```

## Demo Workflow

The demo is a standalone package under `samples/demo/`:

```bash
cd samples/demo
swift run    # Starts Galaxy + Stellar + Planet client together; Ctrl+C to stop
```

## Architecture

swift-nebula is a Swift-native distributed RPC framework using a custom binary protocol (NMT) over TCP via Swift NIO, designed for low-latency internal service-to-service communication.

### Layer Boundaries

This repo is **Layer 1: the protocol and routing layer**. It is infrastructure, not an application.

- **Layer 1 (this repo)**: NMT protocol, node roles, service discovery, load balancing, failover. Runs anywhere, no cloud dependency.
- **Layer 2 (future "Nebula" system)**: Orchestration — spawning Amas/Stellar nodes as containers on cloud infrastructure. Requires a "universe" (cloud environment) to operate. Will be implemented separately and call into Layer 1 APIs.

### Cosmic Hierarchy

```
Galaxy  →  manages  →  Amas  →  pool of  →  Stellar  →  Service  →  Method
(registry)            (load balancer)         (host)

Planet (client) ──────────────────────────────► Stellar (direct, fast path)
                                                    │ on failure
                                              ◄─────┘ notify Amas → get next Stellar
```

- **Galaxy** (`StandardGalaxy`): Service registry. When `register(namespace:stellarEndpoint:)` is called, Galaxy automatically creates and manages a `LoadBalanceAmas` for that namespace. Default port 9000.
- **Amas** (`LoadBalanceAmas`): Load balancer only. Maintains a pool of Stellar connections per namespace, distributes via round-robin. Amas is always system-managed by Galaxy — never created manually. Default port auto-assigned.
- **Stellar** (`ServiceStellar`): Service provider. Hosts named `Service` objects, each with `Method`s. Default port 7000+.
- **Planet** (`RoguePlanet`): Client actor. Connects to Galaxy on startup, then calls Stellars **directly** (no Amas hop in the normal path). Amas is used only for failover.

### Planet Connection Model

1. `planet.call(namespace:...)` → checks per-namespace connection cache
2. Cache miss: asks Galaxy `find(namespace:)` → gets `(stellarAddress, amasAddress)`
3. Connects directly to Stellar, caches the connection (+ Amas client for failover)
4. **Failover** (Stellar unreachable): notifies Amas `.unregister(namespace, deadHost, deadPort)` → Amas removes dead Stellar, returns next address → Planet reconnects directly and retries

### Nebula Type

`Nebula` is the high-level facade:
- **Now**: Wraps `NMTServer.bind` and `NMTClient.connect` with simpler, semantic APIs (`Nebula.serve`, `Nebula.planet`)
- **Future**: Will also contain cloud orchestration operations (find a node, spin up a container for Amas/Stellar)

### Wire Protocol (NMT — Nebula Matter Transfer)

The unit transmitted between nodes is called `Matter` — matching the M in NMT. Celestial bodies communicate by transferring Matter through the Nebula.

27-byte fixed header + MessagePack body:

```
| Magic "NBLA" (4) | Version (1) | Type (1) | Flags (1) | MessageID/UUID (16) | Length (4) | Body (N) |
```

Matter types (`MatterType`): `clone`, `register`, `find`, `call`, `reply`, `activate`, `heartbeat`, `unregister`

### Naming Convention

All identifiers must follow the cosmic metaphor established by the protocol:

- The transmitted unit is **`Matter`** — not "message", "envelope", or "packet"
- The type enum is **`MatterType`** — not `MessageType`
- The unique ID in the header is **`messageID`** — this is an intentional exception; it is a technical field name, not a domain concept
- New types, protocols, and structs introduced in `Sources/Nebula/Matter/` must use `Matter`-based naming

Do not introduce generic networking terminology (`message`, `packet`, `frame`, `envelope`) as type or enum names — use the established cosmic vocabulary instead.

### Key Packages

| Path | Role |
|------|------|
| `Sources/Nebula/Matter/` | Wire format: `Matter` struct (header), `MatterType` enum, body codables |
| `Sources/Nebula/NMT/` | TCP server/client (NIO), matter codec handlers, high-level register/find/unregister API |
| `Sources/Nebula/Registry/` | `ServiceRegistry` protocol + `InMemoryServiceRegistry` actor |
| `Sources/Nebula/Astral/` | Galaxy, Amas, Stellar, Planet entity protocols and implementations |
| `Sources/Nebula/Resource/` | `Service`, `Method`, `Argument` definitions |

### Design Patterns

- All server entities (`StandardGalaxy`, `LoadBalanceAmas`, `ServiceStellar`, `InMemoryServiceRegistry`, `RoguePlanet`) are **actors** for thread-safety.
- `NMTClient` matches replies to pending requests using UUID `messageID` from the envelope header, using `CheckedContinuation`.
- NIO pipeline uses `ByteToMessageHandler(EnvelopeDecoder)` and `MessageToByteHandler(EnvelopeEncoder)`.
- `NMTServer.bind` stores `channel.localAddress` (not the requested address), so port 0 works correctly for OS-assigned ports.

### Platform Policy: Linux First

This project and all related repos (`swift-nmtp`, `swift-nebula-client`) are **Linux-first**. All three repos run as server infrastructure on Linux.

- **Do not use Apple-only APIs** — no `import os`, no `OSAllocatedUnfairLock`, no `Foundation` types that are macOS-only.
- **Use cross-platform Swift stdlib and open-source packages only.** Prefer `Synchronization.Mutex` over `OSAllocatedUnfairLock`, `NIOLock` over `NSLock`, etc.
- **macOS is development-only.** The minimum macOS version is set to `.macOS(.v15)` solely so `Synchronization.Mutex` compiles on Apple platforms during local development. It is not a supported deployment target.
- When in doubt, check that the API exists in the Swift open-source repo or swift-corelibs — not just the Apple SDK.

### Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO handler utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — binary serialization
