# swift-nebula

swift-nebula is a Swift-native distributed service framework designed for internal communication in high-performance environments — where HTTP is too slow, too verbose, and too exposed.

## Why Nebula?

Most microservice teams default to HTTP for everything — including internal service-to-service calls. This works, but it comes with costs:

- Every internal hop carries the overhead of HTTP headers, serialization, and layer traversal
- Reverse proxies repeat that cost at each layer
- For AI-heavy teams running Python inference services, every millisecond matters — and internal HTTP is often the silent bottleneck

Nebula is built around a different premise: internal services deserve a faster, leaner, and more opaque protocol.

## How It Works

Nebula organizes services into a cosmic hierarchy:

```
Galaxy   →  the service registry and coordinator
  └── Amas   →  load balancer, manages a pool of Stellars per namespace
        └── Stellar   →  the actual service provider
```

Services register under a namespaced address: `{galaxy}.{amas}.{stellar}`

A Planet (client) asks Galaxy to discover the Stellar address, then **connects directly** — no Amas hop on every call. Amas is managed by Galaxy automatically and only intervenes during failover.

| Role | Type | Description |
|------|------|-------------|
| **Galaxy** | `StandardGalaxy` | Service registry. Automatically creates and manages a `LoadBalanceAmas` per namespace when a Stellar registers. |
| **Amas** | `LoadBalanceAmas` | Load balancer. Maintains a pool of Stellars, distributes via round-robin. System-managed by Galaxy — not created manually. |
| **Stellar** | `ServiceStellar` | Service host. Runs one or more named `Service` objects, each with methods. |
| **Planet** | `RoguePlanet` | Client actor. Connects directly to Stellars. Falls back through Amas when a Stellar becomes unreachable. |

### Planet Connection Model

```
Normal:   Planet ──────────────────────────────► Stellar
Failover: Planet → notify Amas (dead Stellar) → get next Stellar → reconnect directly
```

## The Protocol

Nebula uses its own binary wire protocol — **NMT (Nebula Matter Transfer)** — over TCP with a compact 27-byte fixed header. The unit transmitted between nodes is called `Matter`, matching the M in NMT.

```
┌─────────────┬─────────┬──────┬───────┬─────────────────────┬────────────────┬──────────────┐
│  Magic (4)  │ Ver (1) │ Type │ Flags │    MessageID (16)   │  Length (4)    │  Body (N)    │
│  "NBLA"     │  0x01   │ (1)  │  (1)  │       UUID          │  UInt32 BE     │  MessagePack │
└─────────────┴─────────┴──────┴───────┴─────────────────────┴────────────────┴──────────────┘
```

No HTTP. No Protobuf schema files. Binary, fast, and purpose-built.

The body is serialized with **MessagePack** (via [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker)).

### Message Types

| Value | Name | Description |
|-------|------|-------------|
| `0x01` | `clone` | Fetch remote identity info |
| `0x02` | `register` | Register a namespace (Stellar→Amas, Amas→Galaxy) |
| `0x03` | `find` | Look up a namespace — returns Stellar + Amas addresses |
| `0x04` | `call` | Invoke a service method |
| `0x05` | `reply` | Response to any of the above |
| `0x06` | `activate` | Reserved |
| `0x07` | `heartbeat` | Reserved |
| `0x08` | `unregister` | Notify Amas that a Stellar is unreachable; returns next available Stellar |

## Design Goals

- **Zero HTTP for internal traffic** — TCP + MessagePack, not REST
- **Namespace-based discovery** — services are addressable by logical name, not hardcoded IPs
- **Planet connects directly to Stellar** — zero intermediate hops on the normal call path
- **Amas as load balancer and failover** — system-managed, not user-facing
- **Swift-native** — built on Swift NIO with async/await and Actor, not callback chains
- **Embeddable by default** — no external dependencies required to get started

## Requirements

- Swift 5.9+
- macOS 13+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-nebula.git", from: "0.0.1"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["Nebula"]),
]
```

## Quick Start

### 1. Start a Galaxy (registry)

```swift
import Nebula
import NIO

let address = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxy = StandardGalaxy(name: "nebula")
let server = try await NMTServer.bind(on: address, delegate: galaxy)
try await server.listen()
```

### 2. Define a Stellar (service host)

Register the Stellar with Galaxy — Galaxy automatically creates and manages a `LoadBalanceAmas` for the namespace.

```swift
import Nebula
import NIO

let stellar = ServiceStellar(name: "Embedding", namespace: "production.ml.embedding")

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let server = try await NMTServer.bind(on: stellarAddress, delegate: stellar)

// Register with Galaxy — Amas is created automatically
let galaxyClient = try await NMTClient.connect(to: SocketAddress(ipAddress: "::1", port: 9000))
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

try await server.listen()
```

### 3. Call from a Planet (client)

Planet connects to Galaxy, then calls Stellars directly.

```swift
import Nebula
import NIO

let planet = try await Nebula.planet(name: "client", connectingTo: SocketAddress(ipAddress: "::1", port: 9000))

let result = try await planet.call(
    namespace: "production.ml.embedding",
    service: "w2v",
    method: "wordVector",
    arguments: [try Argument.wrap(key: "words", value: ["慢跑", "反光", "排汗"])]
)
```

## Running the Demo

```bash
# Terminal 1 — Galaxy
swift run GalaxyServer

# Terminal 2 — Stellar
swift run StellaireServer

# Terminal 3 — Client
swift run AmasClient
```

## Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — MessagePack serialization

## Status

Active development. Core protocol and transport layer complete.
