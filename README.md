# swift-nebula

swift-nebula is a Swift-native distributed service framework designed for internal communication in high-performance environments — where HTTP is too slow, too verbose, and too exposed.

## Why Nebula?

Most microservice teams default to HTTP for everything — including internal service-to-service calls. This works, but it comes with costs:

- Every internal hop carries the overhead of HTTP headers, serialization, and layer traversal
- Reverse proxies repeat that cost at each layer
- For AI-heavy teams running Python inference services, every millisecond matters — and internal HTTP is often the silent bottleneck

Nebula is built around a different premise: internal services deserve a faster, leaner, and more opaque protocol.

## How It Works

Nebula organizes services into a three-tier cosmic hierarchy:

```
Galaxy   →  the service registry and coordinator
  └── Amas   →  the routing layer, manages a group of Stellars
        └── Stellar   →  the actual service provider
```

Services register under a namespaced address: `{galaxy}.{amas}.{stellar}`

A client queries the Galaxy to discover the right Amas, then communicates directly through the Amas to the target Stellar — no repeated traversal on every call.

| Role | Type | Description |
|------|------|-------------|
| **Galaxy** | `StandardGalaxy` | Service registry. Tracks which Amas hosts which namespaces. |
| **Amas** | `DirectAmas` | Router. Accepts calls from Planets and forwards them to the correct Stellar. |
| **Stellar** | `ServiceStellar` | Service host. Runs one or more named `Service` objects, each with methods. |
| **Planet** | `RoguePlanet` | Client. Connects to an Amas and makes RPC calls. |

## The Protocol

Nebula uses its own binary wire protocol — **NMT (Nebula Matter Transfer)** — over TCP with a compact 27-byte fixed header:

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
| `0x03` | `find` | Look up a namespace address |
| `0x04` | `call` | Invoke a service method (Planet→Amas→Stellar) |
| `0x05` | `reply` | Response to any of the above |
| `0x06` | `activate` | Reserved |
| `0x07` | `heartbeat` | Reserved |

## Design Goals

- **Zero HTTP for internal traffic** — TCP + MessagePack, not REST
- **Namespace-based discovery** — services are addressable by logical name, not hardcoded IPs
- **Amas as the stable routing core** — error handling and failover live in the Amas layer, not scattered across clients
- **Swift-native** — built on Swift NIO with async/await and Actor, not callback chains
- **Embeddable by default** — no external dependencies required to get started; cluster mode with etcd available for production

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

### 2. Start an Amas (router)

```swift
import Nebula
import NIO

let amasAddress = try SocketAddress(ipAddress: "::1", port: 8001)
let amas = DirectAmas(name: "ml-amas", namespace: "production.ml")
let server = try await NMTServer.bind(on: amasAddress, delegate: amas)

let galaxyClient = try await NMTClient.connect(to: SocketAddress(ipAddress: "::1", port: 9000))
try await galaxyClient.register(astral: amas, listeningOn: amasAddress)

try await server.listen()
```

### 3. Define a Stellar (service host)

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

let amasClient = try await NMTClient.connect(to: SocketAddress(ipAddress: "::1", port: 8001))
try await amasClient.register(astral: stellar, listeningOn: stellarAddress)

try await server.listen()
```

### 4. Call from a Planet (client)

```swift
import Nebula
import NIO

let planet = try await Nebula.planet(name: "client", connecting: SocketAddress(ipAddress: "::1", port: 8001))

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

# Terminal 2 — Amas
swift run AmasServer

# Terminal 3 — Stellar
swift run StellaireServer

# Terminal 4 — Client
swift run AmasClient
```

## Dependencies

- [apple/swift-nio](https://github.com/apple/swift-nio) — async TCP networking
- [apple/swift-nio-extras](https://github.com/apple/swift-nio-extras) — NIO utilities
- [hirotakan/MessagePacker](https://github.com/hirotakan/MessagePacker) — MessagePack serialization

## Status

Active development. Core protocol and transport layer complete. Galaxy cluster mode (etcd backend) in progress.
