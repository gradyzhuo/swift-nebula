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
