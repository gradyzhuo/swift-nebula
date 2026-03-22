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

Run these in four separate terminals to test end-to-end:

```bash
swift run GalaxyServer    # T1: Start registry (port 9000)
swift run AmasServer      # T2: Start router (port 8001)
swift run StellaireServer # T3: Start service host (port 7000+)
swift run AmasClient      # T4: Make a client call
```

## Architecture

swift-nebula is a Swift-native distributed RPC framework using a custom binary protocol (NMT) over TCP via Swift NIO, designed for low-latency internal service-to-service communication.

### Cosmic Hierarchy

```
Galaxy  →  Amas  →  Stellar  →  Service  →  Method
(registry)  (router)  (host)
                                  Planet (client)
```

- **Galaxy** (`StandardGalaxy`): Service registry. Tracks which Amas hosts which namespaces. Default port 9000.
- **Amas** (`DirectAmas`): Routing layer. Manages connections to Stellars and forwards calls. Default port 8001.
- **Stellar** (`ServiceStellar`): Service provider. Hosts named `Service` objects, each with `Method`s. Default port 7000+.
- **Planet** (`RoguePlanet`): Client. Connects to an Amas and makes RPC calls.

Service address format: `{galaxy}.{amas}.{stellar}` (e.g., `nebula.production.ml.embedding`)

### Wire Protocol (NMT — Nebula Matter Transfer)

27-byte fixed header + MessagePack body:

```
| Magic "NBLA" (4) | Version (1) | Type (1) | Flags (1) | MessageID/UUID (16) | Length (4) | Body (N) |
```

Message types: `clone`, `register`, `find`, `call`, `reply`, `activate`, `heartbeat`

### Key Packages

| Path | Role |
|------|------|
| `Sources/Nebula/Envelope/` | Wire format: header struct, message type enum, body codables |
| `Sources/Nebula/NMT/` | TCP server/client (NIO), encoder/decoder handlers, high-level register/find/clone API |
| `Sources/Nebula/Registry/` | `ServiceRegistry` protocol + `InMemoryServiceRegistry` actor |
| `Sources/Nebula/Astral/` | Galaxy, Amas, Stellar, Planet entity protocols and implementations |
| `Sources/Nebula/Resource/` | `Service`, `Method`, `Argument` definitions |

### Design Patterns

- All server entities (`StandardGalaxy`, `DirectAmas`, `ServiceStellar`, `InMemoryServiceRegistry`) are **actors** for thread-safety.
- NMTClient matches replies to pending requests using UUID `messageID` from the envelope header, using `CheckedContinuation`.
- NIO pipeline uses `ByteToMessageHandler(EnvelopeDecoder)` and `MessageToByteHandler(EnvelopeEncoder)`.

### Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO handler utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — binary serialization
