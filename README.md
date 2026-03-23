<p align="center">
  <img src="assets/logo.png" width="228" alt="swift-nebula logo" />
</p>

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

Services register under a namespaced address following reverse-DNS convention: `{stellar}.{amas}.{galaxy}`

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

Nebula uses its own binary wire protocol — **NMT (Nebula Matter Transfer)** — over TCP with a compact 27-byte fixed header.

### Why "Matter"?

In networking, the unit of transmission is conventionally called an *envelope* — a wrapper with a header describing the contents inside. Nebula uses the same structural concept: a fixed-length header carrying routing metadata, followed by a serialized body.

The name `Matter` is intentional. In the Nebula metaphor, celestial bodies (Galaxy, Amas, Stellar, Planet) communicate by transferring *matter* through the nebula — just as stars exchange energy and particles across space. `Matter` is the M in **NMT (Nebula Matter Transfer)**: it is the thing being transmitted, not just a technical wrapper.

Same structure as an envelope. Different name — because in this universe, what flows between nodes *is* matter.

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

- Swift 6.0+
- macOS 13+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-nebula.git", from: "0.0.1"),
],
targets: [
    // Core protocol and transport
    .target(name: "MyTarget", dependencies: ["Nebula"]),

    // Optional: NMTServer conformance to ServiceLifecycle.Service
    .target(name: "MyTarget", dependencies: ["Nebula", "NebulaServiceLifecycle"]),
]
```

## Quick Start

### 1. Register your Galaxy with Discovery

```swift
import Nebula
import NIO

// Map a logical name to the Galaxy's address — no hardcoded IPs in your call sites
await Nebula.discovery.register("production", at: SocketAddress(ipAddress: "::1", port: 9000))
```

### 2. Start a Galaxy (registry)

```swift
let galaxy = StandardGalaxy(name: "nebula")
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: "::1", port: 9000))
try await galaxyServer.listen()
```

### 3. Define and start a Stellar (service host)

Galaxy automatically creates and manages a `LoadBalanceAmas` for the namespace.

```swift
import Nebula
import MessagePacker

let stellar = ServiceStellar(name: "Embedding", namespace: "embedding.ml.production")

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

let stellarServer = try await Nebula.server(with: stellar)
    .bind(on: SocketAddress(ipAddress: "::1", port: 7000))

// Register with Galaxy — Amas is created automatically
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

try await stellarServer.listen()
```

### 4. Call from a Planet (client)

Use an `nmtp://` URI to address a service. The Galaxy name (`production`) is resolved via `Nebula.discovery`.

```swift
import Nebula

let planet = try await Nebula.planet(
    connecting: "nmtp://embedding.ml.production/w2v/wordVector"
)

let result = try await planet.call(
    arguments: ["words": ["慢跑", "反光", "排汗"]]
)
```

Arguments support strings, integers, doubles, booleans, and arrays — expressed as Swift literals via `ArgumentValue`.

### URI Format

```
nmtp://embedding.ml.production/w2v/wordVector?key=value
       └─────────────────────┘ └──┘ └────────┘
       namespace               svc  method
       └──────────────────────────────────────── "production" (last segment) → Galaxy via Nebula.discovery
```

Namespace follows reverse-DNS convention — most specific first, Galaxy (environment) last.

You can also provide an explicit Galaxy address (bypasses Discovery):

```
nmtp://[::1]:9000/embedding.ml.production/w2v/wordVector
```

## Running the Demo

```bash
cd samples/demo
swift run
```

All servers (Galaxy, Stellar) and the client task start together and shut down gracefully on Ctrl+C.

## Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — MessagePack serialization
- [swift-server/swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) — graceful shutdown (`NebulaServiceLifecycle` target only)

## Status

Active development. Core protocol and transport layer complete.
