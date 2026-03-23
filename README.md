<p align="center">
  <img src="assets/logo.png" width="228" alt="swift-nebula logo" />
</p>

# swift-nebula

> [!WARNING]
> This package is in early development. Many features are not yet implemented and the API is subject to breaking changes. Do not use in production.

swift-nebula is a Swift-native distributed service framework designed for internal communication in high-performance environments — where HTTP is too slow, too verbose, and too exposed.

## Why Nebula?

Most microservice teams default to HTTP for everything — including internal service-to-service calls. This works, but it comes with costs:

- Every internal hop carries the overhead of HTTP headers, serialization, and layer traversal
- Reverse proxies repeat that cost at each layer
- For AI-heavy teams running Python inference services, every millisecond matters — and internal HTTP is often the silent bottleneck

Nebula is built around a different premise: internal services deserve a faster, leaner, and more opaque protocol.

## How It Works

Nebula organizes services into a cosmic hierarchy, with an **Ingress** as the infrastructure entry point:

```
Ingress   →  root discovery node, the single entry point for clients
  └── Galaxy   →  service registry and coordinator
        └── Amas   →  load balancer, manages a pool of Stellars per namespace
              └── Stellar   →  the actual service provider
```

Services register under a namespaced address following **forward order** (matching the discovery path): `{galaxy}.{amas}.{stellar}`

A Planet (client) connects to **Ingress** to discover the Stellar address, then **connects directly** — no intermediate hops on every call. Amas is managed by Galaxy automatically and only intervenes during failover.

| Role | Type | Description |
|------|------|-------------|
| **Ingress** | `StandardIngress` | Root discovery node. Galaxies register with Ingress on startup. Planet sends `find` here; Ingress routes to the appropriate Galaxy. Default port **22400**. |
| **Galaxy** | `StandardGalaxy` | Service registry. Automatically creates and manages a `LoadBalanceAmas` per namespace when a Stellar registers. |
| **Amas** | `LoadBalanceAmas` | Load balancer. Maintains a pool of Stellars, distributes via round-robin. System-managed by Galaxy — not created manually. |
| **Stellar** | `ServiceStellar` | Service host. Runs one or more named `Service` objects, each with methods. |
| **Planet** | `RoguePlanet` | Client actor. Discovers Stellar via Ingress, then connects directly. Falls back through Amas when a Stellar becomes unreachable. |

### Planet Connection Model

```
Discovery: Planet → Ingress → Galaxy → return Stellar address
Normal:    Planet ──────────────────────────────► Stellar (direct)
Failover:  Planet → notify Amas (dead Stellar) → get next Stellar → reconnect directly
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
| `0x02` | `register` | Register a namespace (Stellar→Galaxy, Galaxy→Ingress) |
| `0x03` | `find` | Look up a namespace — returns Stellar + Amas addresses |
| `0x04` | `call` | Invoke a service method |
| `0x05` | `reply` | Response to any of the above |
| `0x06` | `activate` | Reserved |
| `0x07` | `heartbeat` | Reserved |
| `0x08` | `unregister` | Notify Amas that a Stellar is unreachable; returns next available Stellar |

## Design Goals

- **Zero HTTP for internal traffic** — TCP + MessagePack, not REST
- **Namespace-based discovery** — services are addressable by logical name, not hardcoded IPs
- **Ingress as single entry point** — Planet only needs to know the Ingress address
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

### 1. Start an Ingress (discovery root)

```swift
import Nebula
import NIO

let ingressAddress = try SocketAddress(ipAddress: "::1", port: 22400)
let ingress = StandardIngress(name: "ingress")
let ingressServer = try await Nebula.server(with: ingress).bind(on: ingressAddress)
```

### 2. Start a Galaxy and register with Ingress

```swift
let galaxy = StandardGalaxy(name: "production")
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: "::1", port: 0))  // dynamic port

// Register Galaxy with Ingress
let ingressClient = try await NMTClient.connect(to: ingressAddress, as: .ingress)
try await ingressClient.registerGalaxy(
    name: "production",
    address: galaxyServer.address,
    identifier: galaxy.identifier
)
```

### 3. Define and start a Stellar (service host)

Galaxy automatically creates and manages a `LoadBalanceAmas` for the namespace.

```swift
import MessagePacker

let stellar = ServiceStellar(name: "Embedding", namespace: "production.ml.embedding")

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

let stellarServer = try await Nebula.server(with: stellar)
    .bind(on: SocketAddress(ipAddress: "::1", port: 7000))

// Register with Galaxy — Amas is created automatically
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarServer.address)
```

### 4. Call from a Planet (client)

Use an `nmtp://` URI to address a service. Host:port is the Ingress address.

```swift
let planet = try await Nebula.planet(
    connecting: "nmtp://[::1]:22400/production.ml.embedding/w2v/wordVector"
)

let result = try await planet.call(
    arguments: ["words": ["慢跑", "反光", "排汗"]]
)
```

Arguments support strings, integers, doubles, booleans, and arrays — expressed as Swift literals via `ArgumentValue`.

### URI Format

```
nmtp://localhost:22400/production.ml.embedding/w2v/wordVector
       └─────────────┘ └──────────────────────┘ └──┘ └────────┘
       Ingress address  namespace                svc  method
                        └── production = Galaxy
                        └── ml         = Amas
                        └── embedding  = Stellar
```

Namespace follows **forward order** — broadest first, most specific last. Reading left to right matches the discovery routing path: Ingress → Galaxy → Amas → Stellar.

## Running the Demo

```bash
cd samples/demo
swift run
```

All servers (Ingress, Galaxy, Stellar) and the client task start together and shut down gracefully on Ctrl+C.

## Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — MessagePack serialization
- [swift-server/swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) — graceful shutdown (`NebulaServiceLifecycle` target only)

## Status

Active development. Core protocol and transport layer complete.
