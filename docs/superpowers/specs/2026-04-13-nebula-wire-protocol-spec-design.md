# Nebula Wire Protocol Spec Design

## Goal

Define a normative Nebula wire protocol specification, published as DocC documentation on GitHub Pages from the `swift-nebula` repo. This spec is the authoritative reference for all language implementations (Swift, Kotlin, Python, etc.).

## Architecture

**Location:** `Sources/Nebula/Nebula.docc/` — DocC catalog attached to the existing `Nebula` target.

**Published via:** `swift-docc-plugin` + GitHub Actions → GitHub Pages.

**Structure:**
```
Sources/Nebula/Nebula.docc/
├── Nebula.md                        ← landing page
├── Articles/
│   ├── WireFormat.md                ← Matter header layout, payload formats
│   ├── MatterTypes.md               ← MatterType enum semantics
│   ├── BehaviorCatalog.md           ← all behaviorIDs, schemas, semantics
│   ├── NodeBehavior.md              ← Ingress / Stellar / Galaxy / Broker
│   └── ConformanceTests.md          ← conformance test schema + index
└── ConformanceTests/
    ├── clone.json
    ├── register.json
    ├── find.json
    ├── execute.json
    ├── get.json
    ├── unregister.json
    ├── enqueue.json
    ├── ack.json
    ├── subscribe.json
    ├── unsubscribe.json
    └── event.json

.github/workflows/docc.yml           ← build + deploy to GitHub Pages
```

---

## Wire Format

### Matter Header (27 bytes, fixed)

| Offset | Size | Field     | Description |
|--------|------|-----------|-------------|
| 0–3    | 4    | Magic     | `0x4E 0x42 0x4C 0x41` ("NBLA") |
| 4      | 1    | Version   | `0x01` |
| 5      | 1    | TTL       | Hop count for `event`; `0x00` for all others |
| 6      | 1    | MatterType| See MatterType table below |
| 7–22   | 16   | MatterID  | UUID (big-endian bytes) |
| 23–26  | 4    | Length    | Payload length (big-endian UInt32) |

### Payload Format

**command / query / event:**
```
[behaviorID: 2 bytes big-endian][body: N bytes]
```

**reply:**
```
[behaviorID: 2 bytes big-endian][statusCode: 2 bytes big-endian][body: N bytes]
```

- `behaviorID`: identifies the Nebula behavior (see Behavior Catalog). Echoes the request's behaviorID.
- `statusCode`: HTTP-like status code in reply only. `0x00C8` = 200 OK, `0x01F4` = 500, etc.
- `body`: JSON-encoded application payload.

### MatterType Values

| Value  | Name      | Description |
|--------|-----------|-------------|
| `0x00` | heartbeat | Keep-alive, no payload |
| `0x01` | command   | Request with side effects |
| `0x02` | query     | Read-only request, safe to retry |
| `0x03` | event     | Server-pushed, no reply expected |
| `0x04` | reply     | Response to command or query |

---

## Behavior Catalog

**Naming:** In the Nebula protocol layer the dispatch key is called `behaviorID` (not `typeID`). `typeID` is a swift-nmtp wire-layer implementation detail.

| behaviorID | Name        | Wire Type | Node      | Change from current |
|------------|-------------|-----------|-----------|---------------------|
| `0x0001`   | Clone       | command   | Ingress   | unchanged |
| `0x0002`   | Register    | command   | Ingress   | unchanged |
| `0x0003`   | Find        | **query** | Ingress   | wire type command→query; FindGalaxy merged in |
| `0x0004`   | Execute     | command   | Stellar   | renamed from Call |
| `0x0005`   | Get         | **query** | Stellar   | **new** |
| `0x0008`   | Unregister  | command   | Ingress   | unchanged |
| `0x0009`   | Enqueue     | command   | Ingress / Galaxy | unchanged |
| `0x000A`   | Ack         | command   | Galaxy    | unchanged |
| `0x000B`   | Subscribe   | command   | Galaxy    | unchanged |
| `0x000C`   | Unsubscribe | command   | Galaxy    | unchanged |
| `0x000D`   | Event       | event     | Galaxy→Client | unchanged |
| ~~`0x000E`~~ | ~~FindGalaxy~~ | removed | — | merged into Find |

---

## Message Schemas

### Find (0x0003) — query → Ingress

**Request body:**
```json
{ "namespace": "a.b.c" }
```

**Reply body (200 OK):**
```json
{
  "astrals": [
    { "namespace": "a",     "astralType": "galaxy",  "host": "10.0.0.1", "port": 7001 },
    { "namespace": "a.b.c", "astralType": "stellar", "host": "10.0.0.2", "port": 7002 }
  ]
}
```

- Ingress returns all matching astrals for the namespace and its parent namespaces.
- `astralType` values: `ingress`, `stellar`, `galaxy`.
- Empty `astrals` array with `statusCode = 404` if no match found.

### Execute (0x0004) — command → Stellar

**Request body:**
```json
{
  "namespace": "a.b.c",
  "service": "UserService",
  "method": "createUser",
  "arguments": [ "<msgpack-base64-encoded values>" ]
}
```

**Reply body (200 OK):**
```json
{ "result": "<msgpack-base64-encoded value>" }
```

### Get (0x0005) — query → Stellar

Same schema as Execute. Semantic contract: the called method must not mutate state.

### Clone (0x0001) — command → Ingress

**Request body:**
```json
{ "namespace": "a.b.c" }
```

**Reply body (200 OK):**
```json
{ "cloneID": "<uuid>" }
```

### Register (0x0002) — command → Ingress

**Request body:**
```json
{
  "namespace": "a.b.c",
  "service": "UserService",
  "host": "10.0.0.2",
  "port": 7002
}
```

**Reply body (200 OK):**
```json
{ "status": "registered" }
```

### Unregister (0x0008) — command → Ingress

**Request body:**
```json
{
  "namespace": "a.b.c",
  "host": "10.0.0.2",
  "port": 7002
}
```

**Reply body (200 OK):**
```json
{
  "nextAstral": { "namespace": "a.b.c", "astralType": "stellar", "host": "10.0.0.3", "port": 7002 }
}
```
`nextAstral` is `null` if no other Stellar is available.

### Enqueue (0x0009) — command → Ingress or Galaxy

**Request body:**
```json
{
  "topic": "production.orders",
  "service": "OrderService",
  "method": "processOrder",
  "arguments": [ "<msgpack-base64-encoded values>" ]
}
```
- `topic`: Galaxy routing key (e.g. `"production.orders"`)
- `service` / `method` / `arguments`: forwarded to the Stellar worker that processes the job

**Reply body (200 OK):**
```json
{ "status": "queued" }
```

### Ack (0x000A) — command → Galaxy

**Request body:**
```json
{ "matterID": "<uuid>" }
```

**Reply body (200 OK):**
```json
{ "status": "acknowledged" }
```

### Subscribe (0x000B) — command → Galaxy

**Request body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment"
}
```

**Reply body (200 OK):**
```json
{ "status": "subscribed" }
```

### Unsubscribe (0x000C) — command → Galaxy

**Request body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment"
}
```

**Reply body (200 OK):**
```json
{ "status": "unsubscribed" }
```

### Event (0x000D) — event, Galaxy → Client

No reply expected.

**Body:**
```json
{
  "topic": "production.orders",
  "subscription": "fulfillment",
  "namespace": "a",
  "service": "OrderService",
  "method": "processOrder",
  "arguments": [ "<msgpack-base64-encoded values>" ],
  "retryCount": 0
}
```

---

## Status Codes

| Code | Meaning |
|------|---------|
| `200` | OK — operation succeeded |
| `404` | Not Found — requested astral or resource does not exist |
| `409` | Conflict — resource already exists (e.g. duplicate Register) |
| `500` | Internal Error — server-side failure |

---

## Conformance Test Schema

Each behavior has one JSON file under `ConformanceTests/`. Schema:

```json
{
  "behavior": "find",
  "behaviorID": "0x0003",
  "matterType": "query",
  "description": "Find returns all matching astrals for a namespace",
  "cases": [
    {
      "name": "find_stellar_and_galaxy",
      "request": { "namespace": "a.b.c" },
      "expectedStatusCode": 200,
      "expectedReply": {
        "astrals": [
          { "namespace": "a",     "astralType": "galaxy" },
          { "namespace": "a.b.c", "astralType": "stellar" }
        ]
      }
    },
    {
      "name": "find_not_found",
      "request": { "namespace": "x.y.z" },
      "expectedStatusCode": 404,
      "expectedReply": { "astrals": [] }
    }
  ]
}
```

`expectedReply` uses partial matching — only specified fields are checked, `host`/`port` are ignored in test assertions.

---

## GitHub Actions — DocC Deploy

`.github/workflows/docc.yml` triggers on push to `main`:
1. `swift package generate-documentation` via `swift-docc-plugin`
2. Deploy static output to `gh-pages` branch
3. GitHub Pages serves from `gh-pages`

---

## Implementation Impact

This spec introduces **breaking changes** to swift-nmtp and swift-nebula:

| Repo | Change |
|------|--------|
| `swift-nmtp` | `MatterPayload` for reply: add `statusCode: UInt16` field |
| `swift-nebula` | All reply encoding/decoding updates; `Call` → `Execute`; `Find` wire type → query + merged FindGalaxy; new `Get` behavior; remove `FindGalaxy`; `Unregister` reply schema: `nextHost`/`nextPort` → `nextAstral` object |
| `swift-nebula-client` | All of the above + migration to swift-nmtp 0.1.0 API |

**Recommended implementation order:**
1. Update `MatterPayload` in swift-nmtp → release `0.2.0`
2. Update swift-nebula server → release next version
3. Migrate swift-nebula-client

---

## Out of Scope

- Transport-level TLS configuration (covered by swift-nmtp docs)
- WebSocket transport specifics (covered by swift-nmtp docs)
- Broker persistence / delivery guarantees (implementation detail, not wire protocol)
- Conformance test runner / reference server (future: Phase 2)
