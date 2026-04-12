# Nebula Wire Protocol DocC Spec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a DocC-based Nebula wire protocol specification in swift-nebula, deployed to GitHub Pages as the authoritative reference for all language implementations.

**Architecture:** Add a `Nebula.docc` catalog to the existing `Nebula` target. Articles are Markdown files covering wire format, message types, behavior catalog, node semantics, and conformance tests. Conformance test cases are JSON files embedded in the catalog. GitHub Actions deploys rendered documentation to GitHub Pages on every push to `main`.

**Tech Stack:** Swift DocC, `swift-docc-plugin`, GitHub Actions, GitHub Pages.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Package.swift` | Add `swift-docc-plugin` dependency |
| Create | `Sources/Nebula/Nebula.docc/Nebula.md` | Landing page |
| Create | `Sources/Nebula/Nebula.docc/Articles/WireFormat.md` | Matter header + payload layout |
| Create | `Sources/Nebula/Nebula.docc/Articles/MatterTypes.md` | Wire type semantics |
| Create | `Sources/Nebula/Nebula.docc/Articles/BehaviorCatalog.md` | All behaviorIDs, schemas, status codes |
| Create | `Sources/Nebula/Nebula.docc/Articles/NodeBehavior.md` | Ingress / Stellar / Galaxy / Broker |
| Create | `Sources/Nebula/Nebula.docc/Articles/ConformanceTests.md` | Test schema guide + file index |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/register.json` | Register test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/find.json` | Find test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/mutate.json` | Mutate test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/get.json` | Get test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/unregister.json` | Unregister test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/enqueue.json` | Enqueue test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/ack.json` | Ack test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/subscribe.json` | Subscribe test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/unsubscribe.json` | Unsubscribe test cases |
| Create | `Sources/Nebula/Nebula.docc/ConformanceTests/event.json` | Event test cases |
| Create | `.github/workflows/docc.yml` | Build + deploy to GitHub Pages |

---

### Task 1: Add swift-docc-plugin and create catalog stub

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Nebula/Nebula.docc/Nebula.md`

- [ ] **Step 1: Add swift-docc-plugin to Package.swift**

Replace the entire `Package.swift` with:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-nebula",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Nebula",
            targets: ["Nebula"]),
    ],
    dependencies: [
        .package(url: "https://github.com/OffskyLab/swift-nmtp.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.7"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [
                .product(name: "NMTP", package: "swift-nmtp"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "MessagePacker", package: "MessagePacker"),
            ]),
        .testTarget(
            name: "NebulaTests",
            dependencies: [
                "Nebula",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]),
    ]
)
```

- [ ] **Step 2: Create the minimal catalog stub**

Create `Sources/Nebula/Nebula.docc/Nebula.md`:

```markdown
# Nebula

Nebula is a distributed service mesh built on the NMTP wire protocol.

## Topics

### Protocol Reference

- <doc:WireFormat>
- <doc:MatterTypes>
- <doc:BehaviorCatalog>
- <doc:NodeBehavior>
- <doc:ConformanceTests>
```

- [ ] **Step 3: Verify documentation builds**

Run:
```bash
cd /path/to/swift-nebula
swift package generate-documentation --target Nebula
```

Expected: build succeeds, output ends with `Generated documentation archive at ...`

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/Nebula/Nebula.docc/Nebula.md
git commit -m "docs: add swift-docc-plugin and Nebula.docc catalog stub"
```

---

### Task 2: Write WireFormat article

**Files:**
- Create: `Sources/Nebula/Nebula.docc/Articles/WireFormat.md`

- [ ] **Step 1: Create the article**

Create `Sources/Nebula/Nebula.docc/Articles/WireFormat.md`:

```markdown
# Wire Format

Every unit of communication in Nebula is called a **Matter**. This article defines the binary layout of a Matter on the wire.

## Matter Header

The header is always **27 bytes**, fixed.

| Offset | Size (bytes) | Field | Description |
|--------|-------------|-------|-------------|
| 0–3 | 4 | Magic | `0x4E 0x42 0x4C 0x41` ("NBLA") |
| 4 | 1 | Version | `0x01` |
| 5 | 1 | TTL | Hop count for `event` matters; `0x00` for all others |
| 6 | 1 | MatterType | Wire classification — see <doc:MatterTypes> |
| 7–22 | 16 | MatterID | UUID correlating request ↔ reply (big-endian bytes) |
| 23–26 | 4 | Length | Payload byte count (big-endian `UInt32`) |

## Payload Format

The payload format depends on the **MatterType** field in the header.

### command, query, event

```
[behaviorID: 2 bytes, big-endian UInt16][body: N bytes]
```

### reply

```
[behaviorID: 2 bytes, big-endian UInt16][statusCode: 2 bytes, big-endian UInt16][body: N bytes]
```

### heartbeat

No payload. `Length` field is `0`.

## Field Semantics

**behaviorID** — Identifies the Nebula behavior being invoked (see <doc:BehaviorCatalog>).
In a `reply`, `behaviorID` echoes the request's `behaviorID`.

**statusCode** — Present only in `reply` matters. HTTP-like status codes:

| Code | Meaning |
|------|---------|
| `200` | OK — operation succeeded |
| `404` | Not Found — requested astral or resource does not exist |
| `409` | Conflict — resource already exists |
| `500` | Internal Error — server-side failure |

**body** — JSON-encoded application payload. UTF-8. May be empty (`Length` = 2 for command/query/event, `Length` = 4 for reply with no body beyond the status code).

## Example: Find Request

A `Find` query for namespace `"a.b.c"` (body = `{"namespace":"a.b.c"}`, 20 bytes):

```
4E 42 4C 41        ← Magic "NBLA"
01                 ← Version 1
00                 ← TTL 0
02                 ← MatterType: query (0x02)
[16 bytes]         ← MatterID (UUID)
00 00 00 16        ← Length: 22 bytes (2 behaviorID + 20 body)
00 03              ← behaviorID: Find (0x0003)
7B 22 6E 61 6D 65
73 70 61 63 65 22
3A 22 61 2E 62 2E
63 22 7D           ← body: {"namespace":"a.b.c"}
```

## Example: Find Reply

A `Find` reply with status 200 (body = `{"astrals":[...]}`, N bytes):

```
4E 42 4C 41        ← Magic "NBLA"
01                 ← Version 1
00                 ← TTL 0
04                 ← MatterType: reply (0x04)
[16 bytes]         ← MatterID (same UUID as request)
00 00 00 XX        ← Length: 4 + N bytes (2 behaviorID + 2 statusCode + N body)
00 03              ← behaviorID: Find (0x0003)
00 C8              ← statusCode: 200
[N bytes]          ← body: {"astrals":[...]}
```
```

- [ ] **Step 2: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS — no warnings about unknown article links.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nebula/Nebula.docc/Articles/WireFormat.md
git commit -m "docs: add WireFormat article"
```

---

### Task 3: Write MatterTypes article

**Files:**
- Create: `Sources/Nebula/Nebula.docc/Articles/MatterTypes.md`

- [ ] **Step 1: Create the article**

Create `Sources/Nebula/Nebula.docc/Articles/MatterTypes.md`:

```markdown
# MatterTypes

Nebula uses five wire types to classify every Matter on the wire.

## Type Table

| Value | Name | Has Reply | Description |
|-------|------|-----------|-------------|
| `0x00` | `heartbeat` | No | Keep-alive. No payload. Sent periodically to detect dead connections. |
| `0x01` | `command` | Yes | Request that may mutate server state. |
| `0x02` | `query` | Yes | Read-only request. Must not mutate server state. Safe to retry. |
| `0x03` | `event` | No | Server-pushed message. TTL-limited multi-hop delivery. |
| `0x04` | `reply` | No | Response to a `command` or `query`. Contains a `statusCode`. |

## command vs query

Both `command` and `query` are request/reply pairs. The distinction is a **semantic contract**:

- A `command` is a write operation — it may create, update, or delete state.
- A `query` is a read operation — it must not modify any state and is safe to retry on failure.

Servers may apply different policies based on wire type (e.g., idempotency checks for `command`, aggressive caching for `query`).

## event and TTL

An `event` matter is pushed from a Galaxy node to subscribed clients. The `TTL` header field controls how many hops the event may traverse. Each forwarding hop decrements TTL by 1. A matter with `TTL = 0` is not forwarded further.

Default TTL: `7`. Maximum: `15`.

## reply and MatterID Correlation

A `reply` matter's `MatterID` is identical to the originating `command` or `query` matter's `MatterID`. Clients use this to match replies to their pending requests.

A `reply` always carries a `statusCode` in its payload (see <doc:WireFormat>). A `statusCode` of `200` means success; any other value means failure.
```

- [ ] **Step 2: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nebula/Nebula.docc/Articles/MatterTypes.md
git commit -m "docs: add MatterTypes article"
```

---

### Task 4: Write BehaviorCatalog article

**Files:**
- Create: `Sources/Nebula/Nebula.docc/Articles/BehaviorCatalog.md`

- [ ] **Step 1: Create the article**

Create `Sources/Nebula/Nebula.docc/Articles/BehaviorCatalog.md`:

```markdown
# Behavior Catalog

A **behavior** is a Nebula-layer operation identified by a `behaviorID` (`UInt16`). The `behaviorID` is the first 2 bytes of every Matter payload.

> Note: In NMTP (the wire transport layer), this field is called `typeID`. Nebula calls it `behaviorID` to distinguish application-layer dispatch from transport-layer framing.

## Behavior Table

| behaviorID | Name | Wire Type | Target Node |
|------------|------|-----------|-------------|
| `0x0002` | Register | command | Ingress |
| `0x0003` | Find | query | Ingress |
| `0x0004` | Mutate | command | Stellar |
| `0x0005` | Get | query | Stellar |
| `0x0008` | Unregister | command | Ingress |
| `0x0009` | Enqueue | command | Ingress / Galaxy |
| `0x000A` | Ack | command | Galaxy |
| `0x000B` | Subscribe | command | Galaxy |
| `0x000C` | Unsubscribe | command | Galaxy |
| `0x000D` | Event | event | Galaxy → Client |

---

## Register (0x0002)

A Stellar node registers itself with an Ingress node, making its services discoverable.

**Request body:**
```json
{
  "namespace": "a.b.c",
  "service": "UserService",
  "host": "10.0.0.2",
  "port": 7002
}
```

**Reply body (200):**
```json
{ "status": "registered" }
```

**Error codes:** `409` if the namespace+host+port combination is already registered.

---

## Find (0x0003)

A client queries Ingress for all reachable astrals under a given namespace. Ingress returns matching entries for the namespace and its parent namespaces.

**Request body:**
```json
{ "namespace": "a.b.c" }
```

**Reply body (200):**
```json
{
  "astrals": [
    { "namespace": "a",     "astralType": "galaxy",  "host": "10.0.0.1", "port": 7001 },
    { "namespace": "a.b.c", "astralType": "stellar", "host": "10.0.0.2", "port": 7002 }
  ]
}
```

- `astralType` values: `ingress`, `stellar`, `galaxy`
- `astrals` is an empty array when nothing matches (status `404`)

**Error codes:** `404` if no astrals found for the namespace.

---

## Mutate (0x0004)

Invoke a method on a Stellar service that may mutate state. The client must connect directly to the Stellar after discovering its address via `Find`.

**Request body:**
```json
{
  "namespace": "a.b.c",
  "service": "UserService",
  "method": "createUser",
  "arguments": ["<msgpack bytes, base64-encoded>"]
}
```

**Reply body (200):**
```json
{ "result": "<msgpack bytes, base64-encoded>" }
```

`result` may be `null` if the method returns nothing.

**Error codes:** `404` if the service or method is not found. `500` if the method throws.

---

## Get (0x0005)

Invoke a read-only method on a Stellar service. Identical schema to `Mutate`. Semantic contract: the method must not mutate state.

**Request body:**
```json
{
  "namespace": "a.b.c",
  "service": "UserService",
  "method": "findUser",
  "arguments": ["<msgpack bytes, base64-encoded>"]
}
```

**Reply body (200):**
```json
{ "result": "<msgpack bytes, base64-encoded>" }
```

**Error codes:** `404` if service or method not found. `500` if the method throws.

---

## Unregister (0x0008)

Remove a Stellar instance from Ingress's registry. Used when a Stellar shuts down or becomes unavailable. Ingress returns the next available Stellar for the same namespace, if any.

**Request body:**
```json
{
  "namespace": "a.b.c",
  "host": "10.0.0.2",
  "port": 7002
}
```

**Reply body (200):**
```json
{
  "nextAstral": {
    "namespace": "a.b.c",
    "astralType": "stellar",
    "host": "10.0.0.3",
    "port": 7002
  }
}
```

`nextAstral` is `null` if no other Stellar is registered for this namespace.

**Error codes:** `404` if the specified Stellar is not registered.

---

## Enqueue (0x0009)

Submit a job to a Galaxy broker for async processing. The Galaxy routes the job to a Stellar worker based on `topic`.

**Request body:**
```json
{
  "namespace": "a.b",
  "topic": "production.orders",
  "service": "OrderService",
  "method": "processOrder",
  "arguments": ["<msgpack bytes, base64-encoded>"]
}
```

- `namespace`: Nebula namespace backing this operation.
- `topic`: Galaxy routing key.
- `service` / `method` / `arguments`: forwarded to the Stellar worker.

**Reply body (200):**
```json
{ "status": "queued" }
```

**Error codes:** `404` if no Galaxy found for `topic`. `500` on broker failure.

---

## Ack (0x000A)

Acknowledge that a previously delivered event has been processed. Prevents redelivery.

**Request body:**
```json
{ "matterID": "<uuid>" }
```

`matterID` is the `MatterID` of the `Event` matter being acknowledged.

**Reply body (200):**
```json
{ "status": "acknowledged" }
```

**Error codes:** `404` if the matterID is not found or already acknowledged.

---

## Subscribe (0x000B)

Register a subscription on a Galaxy node to receive events for a `topic` under a named `subscription` group.

**Request body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment"
}
```

**Reply body (200):**
```json
{ "status": "subscribed" }
```

**Error codes:** `404` if the topic does not exist on this Galaxy. `409` if the subscription name is already registered.

---

## Unsubscribe (0x000C)

Remove a subscription from a Galaxy node.

**Request body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment"
}
```

**Reply body (200):**
```json
{ "status": "unsubscribed" }
```

**Error codes:** `404` if the subscription is not found.

---

## Event (0x000D)

A Galaxy node pushes a queued job to a subscriber. No reply is expected. The subscriber must send an `Ack` to confirm processing.

**Body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment",
  "namespace": "a.b",
  "service": "OrderService",
  "method": "processOrder",
  "arguments": ["<msgpack bytes, base64-encoded>"],
  "retryCount": 0
}
```

- `retryCount`: number of previous delivery attempts. `0` on first delivery.
```

- [ ] **Step 2: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nebula/Nebula.docc/Articles/BehaviorCatalog.md
git commit -m "docs: add BehaviorCatalog article"
```

---

### Task 5: Write NodeBehavior article

**Files:**
- Create: `Sources/Nebula/Nebula.docc/Articles/NodeBehavior.md`

- [ ] **Step 1: Create the article**

Create `Sources/Nebula/Nebula.docc/Articles/NodeBehavior.md`:

```markdown
# Node Behavior

Nebula consists of four node types. Each node listens for specific behaviors and ignores others.

## Ingress

Ingress is the **discovery and routing** node. Clients connect to Ingress first to find other nodes.

**Handled behaviors:**

| Behavior | Description |
|----------|-------------|
| `Register` (0x0002) | Stellar registers itself, advertising its namespace + address |
| `Find` (0x0003) | Client queries for astrals under a namespace |
| `Unregister` (0x0008) | Stellar removes itself from the registry |
| `Enqueue` (0x0009) | Client submits a job; Ingress forwards to the correct Galaxy |

**Typical client flow:**
1. Client connects to Ingress.
2. Client sends `Find` to discover the Stellar or Galaxy for its target namespace.
3. Client connects directly to the discovered astral.
4. Client disconnects from Ingress (optional — connection may be reused for future finds).

## Stellar

Stellar is the **service execution** node. Clients connect directly to Stellar (after discovering it via Ingress) to invoke service methods.

**Handled behaviors:**

| Behavior | Description |
|----------|-------------|
| `Mutate` (0x0004) | Invoke a side-effectful service method |
| `Get` (0x0005) | Invoke a read-only service method |

**Failover:** If a Stellar becomes unreachable, the client should send `Unregister` to Ingress for that Stellar's address. Ingress replies with `nextAstral` — the next available Stellar for the same namespace. The client reconnects to the new Stellar.

## Galaxy

Galaxy is the **pub/sub broker** node. Clients connect directly to Galaxy (after discovering it via Ingress `Find`) to publish or subscribe to event streams.

**Handled behaviors:**

| Behavior | Description |
|----------|-------------|
| `Enqueue` (0x0009) | Client publishes a job to a topic |
| `Ack` (0x000A) | Client acknowledges a delivered event |
| `Subscribe` (0x000B) | Client registers a subscription |
| `Unsubscribe` (0x000C) | Client removes a subscription |
| `Event` (0x000D) | Galaxy pushes a pending job to the subscriber (server→client) |

**Subscription lifecycle:**
1. Client sends `Subscribe` with a `topic` and `subscription` name.
2. Galaxy confirms with `status: "subscribed"`.
3. Galaxy pushes `Event` matters to the client as jobs become available.
4. Client processes each event and sends `Ack` with the event's `matterID`.
5. Unacknowledged events are redelivered after a timeout (server-configured). `retryCount` increments on each redelivery.
6. Client sends `Unsubscribe` to stop receiving events.

## Broker

The Broker is an internal component of the Galaxy node responsible for persistent job storage, retry logic, and subscription management. It is not directly addressable by external clients; all interaction happens through the Galaxy's behaviors above.
```

- [ ] **Step 2: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nebula/Nebula.docc/Articles/NodeBehavior.md
git commit -m "docs: add NodeBehavior article"
```

---

### Task 6: Write ConformanceTests article

**Files:**
- Create: `Sources/Nebula/Nebula.docc/Articles/ConformanceTests.md`

- [ ] **Step 1: Create the article**

Create `Sources/Nebula/Nebula.docc/Articles/ConformanceTests.md`:

```markdown
# Conformance Tests

Each Nebula behavior has a JSON file describing test cases. A conformance test runner connects to a live Nebula Ingress, executes each case, and verifies the response.

## Test Case Schema

Each file follows this schema:

```json
{
  "behavior": "<name>",
  "behaviorID": "0x000N",
  "matterType": "command | query | event",
  "description": "<one-line description>",
  "cases": [
    {
      "name": "<snake_case test name>",
      "request": { "<field>": "<value>" },
      "expectedStatusCode": 200,
      "expectedReply": { "<field>": "<value or matcher>" }
    }
  ]
}
```

### Matchers

`expectedReply` uses **partial matching**: only the fields specified are checked. Additional fields in the actual reply are ignored.

Special matcher values:

| Value | Meaning |
|-------|---------|
| `"<any string>"` | Any non-null string |
| `"<any int>"` | Any integer |
| `"<any uuid>"` | Any valid UUID string |
| `"<any array>"` | Any non-empty array |
| `null` | Field must be absent or null |

### No-reply behaviors

For `event` (0x000D), the `expectedReply` field is absent. The test verifies that the Galaxy pushes an `Event` matter after an `Enqueue`.

## Test Files

- ``find.json``
- ``register.json``
- ``mutate.json``
- ``get.json``
- ``unregister.json``
- ``enqueue.json``
- ``ack.json``
- ``subscribe.json``
- ``unsubscribe.json``
- ``event.json``

## Implementing a Runner

A conformance test runner must:

1. Connect to a running Nebula Ingress at a configurable address.
2. For each test case in each JSON file:
   a. Encode the `request` body as JSON.
   b. Create a Matter with `matterType` and `behaviorID` from the file.
   c. Send the Matter and await the reply (timeout: 5 seconds).
   d. Assert `reply.statusCode == expectedStatusCode`.
   e. Assert `reply.body` matches `expectedReply` using partial matching.
3. Report pass/fail per case.
```

- [ ] **Step 2: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nebula/Nebula.docc/Articles/ConformanceTests.md
git commit -m "docs: add ConformanceTests article"
```

---

### Task 7: Write conformance test JSON files

**Files:**
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/register.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/find.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/mutate.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/get.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/unregister.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/enqueue.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/ack.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/subscribe.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/unsubscribe.json`
- Create: `Sources/Nebula/Nebula.docc/ConformanceTests/event.json`

- [ ] **Step 1: Create register.json**

```json
{
  "behavior": "register",
  "behaviorID": "0x0002",
  "matterType": "command",
  "description": "Stellar registers itself with Ingress",
  "cases": [
    {
      "name": "register_success",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "host": "127.0.0.1",
        "port": 9001
      },
      "expectedStatusCode": 200,
      "expectedReply": { "status": "registered" }
    },
    {
      "name": "register_conflict",
      "precondition": "register_success must run first",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "host": "127.0.0.1",
        "port": 9001
      },
      "expectedStatusCode": 409,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 2: Create find.json**

```json
{
  "behavior": "find",
  "behaviorID": "0x0003",
  "matterType": "query",
  "description": "Client queries Ingress for astrals under a namespace",
  "cases": [
    {
      "name": "find_stellar",
      "precondition": "register_success from register.json must run first",
      "request": { "namespace": "conformance.test" },
      "expectedStatusCode": 200,
      "expectedReply": {
        "astrals": [
          {
            "namespace": "conformance.test",
            "astralType": "stellar",
            "host": "<any string>",
            "port": "<any int>"
          }
        ]
      }
    },
    {
      "name": "find_not_found",
      "request": { "namespace": "nonexistent.namespace" },
      "expectedStatusCode": 404,
      "expectedReply": { "astrals": [] }
    },
    {
      "name": "find_parent_namespace",
      "precondition": "Galaxy registered under 'conformance' namespace",
      "request": { "namespace": "conformance.test" },
      "expectedStatusCode": 200,
      "expectedReply": {
        "astrals": "<any array>"
      }
    }
  ]
}
```

- [ ] **Step 3: Create mutate.json**

```json
{
  "behavior": "mutate",
  "behaviorID": "0x0004",
  "matterType": "command",
  "description": "Client invokes a side-effectful method on Stellar",
  "cases": [
    {
      "name": "mutate_success",
      "precondition": "Stellar connected with TestService.echo method registered",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "method": "echo",
        "arguments": []
      },
      "expectedStatusCode": 200,
      "expectedReply": { "result": "<any string>" }
    },
    {
      "name": "mutate_method_not_found",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "method": "nonexistentMethod",
        "arguments": []
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 4: Create get.json**

```json
{
  "behavior": "get",
  "behaviorID": "0x0005",
  "matterType": "query",
  "description": "Client invokes a read-only method on Stellar",
  "cases": [
    {
      "name": "get_success",
      "precondition": "Stellar connected with TestService.ping method registered",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "method": "ping",
        "arguments": []
      },
      "expectedStatusCode": 200,
      "expectedReply": { "result": "<any string>" }
    },
    {
      "name": "get_method_not_found",
      "request": {
        "namespace": "conformance.test",
        "service": "TestService",
        "method": "nonexistentMethod",
        "arguments": []
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 5: Create unregister.json**

```json
{
  "behavior": "unregister",
  "behaviorID": "0x0008",
  "matterType": "command",
  "description": "Remove a Stellar from Ingress registry",
  "cases": [
    {
      "name": "unregister_last_stellar_no_next",
      "precondition": "Only one Stellar registered for conformance.test",
      "request": {
        "namespace": "conformance.test",
        "host": "127.0.0.1",
        "port": 9001
      },
      "expectedStatusCode": 200,
      "expectedReply": { "nextAstral": null }
    },
    {
      "name": "unregister_not_found",
      "request": {
        "namespace": "conformance.test",
        "host": "127.0.0.1",
        "port": 9999
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 6: Create enqueue.json**

```json
{
  "behavior": "enqueue",
  "behaviorID": "0x0009",
  "matterType": "command",
  "description": "Submit a job to a Galaxy broker",
  "cases": [
    {
      "name": "enqueue_success",
      "precondition": "Galaxy registered for topic conformance.jobs",
      "request": {
        "namespace": "conformance",
        "topic": "conformance.jobs",
        "service": "TestService",
        "method": "processJob",
        "arguments": []
      },
      "expectedStatusCode": 200,
      "expectedReply": { "status": "queued" }
    },
    {
      "name": "enqueue_topic_not_found",
      "request": {
        "namespace": "conformance",
        "topic": "nonexistent.topic",
        "service": "TestService",
        "method": "processJob",
        "arguments": []
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 7: Create ack.json**

```json
{
  "behavior": "ack",
  "behaviorID": "0x000A",
  "matterType": "command",
  "description": "Acknowledge a delivered event",
  "cases": [
    {
      "name": "ack_success",
      "precondition": "An Event has been received with a known matterID",
      "request": { "matterID": "<uuid of received event>" },
      "expectedStatusCode": 200,
      "expectedReply": { "status": "acknowledged" }
    },
    {
      "name": "ack_not_found",
      "request": { "matterID": "00000000-0000-0000-0000-000000000000" },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 8: Create subscribe.json**

```json
{
  "behavior": "subscribe",
  "behaviorID": "0x000B",
  "matterType": "command",
  "description": "Register a subscription on Galaxy",
  "cases": [
    {
      "name": "subscribe_success",
      "precondition": "Galaxy running with topic conformance.jobs",
      "request": {
        "topic": "conformance.jobs",
        "subscription": "test-runner"
      },
      "expectedStatusCode": 200,
      "expectedReply": { "status": "subscribed" }
    },
    {
      "name": "subscribe_conflict",
      "precondition": "subscribe_success must run first",
      "request": {
        "topic": "conformance.jobs",
        "subscription": "test-runner"
      },
      "expectedStatusCode": 409,
      "expectedReply": {}
    },
    {
      "name": "subscribe_topic_not_found",
      "request": {
        "topic": "nonexistent.topic",
        "subscription": "test-runner"
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 9: Create unsubscribe.json**

```json
{
  "behavior": "unsubscribe",
  "behaviorID": "0x000C",
  "matterType": "command",
  "description": "Remove a subscription from Galaxy",
  "cases": [
    {
      "name": "unsubscribe_success",
      "precondition": "subscribe_success must run first",
      "request": {
        "topic": "conformance.jobs",
        "subscription": "test-runner"
      },
      "expectedStatusCode": 200,
      "expectedReply": { "status": "unsubscribed" }
    },
    {
      "name": "unsubscribe_not_found",
      "request": {
        "topic": "conformance.jobs",
        "subscription": "nonexistent-subscription"
      },
      "expectedStatusCode": 404,
      "expectedReply": {}
    }
  ]
}
```

- [ ] **Step 10: Create event.json**

```json
{
  "behavior": "event",
  "behaviorID": "0x000D",
  "matterType": "event",
  "description": "Galaxy pushes a queued job to a subscriber",
  "cases": [
    {
      "name": "event_delivered_after_enqueue",
      "precondition": "subscribe_success must run first; then enqueue_success must run",
      "trigger": "enqueue",
      "expectedPush": {
        "topic": "conformance.jobs",
        "subscription": "test-runner",
        "namespace": "conformance",
        "service": "TestService",
        "method": "processJob",
        "arguments": [],
        "retryCount": 0
      }
    },
    {
      "name": "event_redelivered_after_no_ack",
      "precondition": "event_delivered_after_enqueue must run; do NOT send Ack; wait for server ackTimeout",
      "trigger": "timeout",
      "expectedPush": {
        "topic": "conformance.jobs",
        "subscription": "test-runner",
        "retryCount": 1
      }
    }
  ]
}
```

- [ ] **Step 11: Verify documentation builds**

Run:
```bash
swift package generate-documentation --target Nebula
```

Expected: PASS.

- [ ] **Step 12: Commit**

```bash
git add Sources/Nebula/Nebula.docc/ConformanceTests/
git commit -m "docs: add conformance test JSON files for all behaviors"
```

---

### Task 8: Set up GitHub Actions for DocC deployment

**Files:**
- Create: `.github/workflows/docc.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/docc.yml`:

```yaml
name: Deploy DocC to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Generate documentation
        run: |
          swift package \
            --allow-writing-to-directory ./docs-output \
            generate-documentation \
            --target Nebula \
            --disable-indexing \
            --output-path ./docs-output \
            --transform-for-static-hosting \
            --hosting-base-path swift-nebula

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs-output

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

> Note: Replace `swift-nebula` in `--hosting-base-path` with the actual GitHub repo name if different.

- [ ] **Step 2: Enable GitHub Pages in repo settings**

In the GitHub repo → Settings → Pages:
- Source: **GitHub Actions**

This only needs to be done once manually in the browser.

- [ ] **Step 3: Verify the workflow file parses correctly**

Run:
```bash
cat .github/workflows/docc.yml
```

Expected: clean YAML, no parse errors.

- [ ] **Step 4: Commit and push**

```bash
git add .github/workflows/docc.yml
git commit -m "ci: add GitHub Actions workflow to deploy DocC to GitHub Pages"
git push origin main
```

Expected: GitHub Actions triggers the workflow. Documentation becomes available at `https://<org>.github.io/swift-nebula/documentation/nebula/`.

---

## Self-Review

**Spec coverage:**
- ✅ DocC catalog structure (Task 1)
- ✅ Wire format (Task 2)
- ✅ MatterType semantics (Task 3)
- ✅ All behaviors with schemas (Task 4)
- ✅ Node behavior / sequence flows (Task 5)
- ✅ Conformance test schema + article (Task 6)
- ✅ All 10 conformance test JSON files (Task 7)
- ✅ GitHub Actions deployment (Task 8)

**Placeholder scan:** None found. All articles have complete content, all JSON files have complete test cases.

**Type consistency:**
- `behaviorID` used consistently throughout (not `typeID`)
- `astralType` values consistent: `ingress`, `stellar`, `galaxy`
- `matterType` values consistent: `command`, `query`, `event`
- Status codes consistent: `200`, `404`, `409`, `500`
