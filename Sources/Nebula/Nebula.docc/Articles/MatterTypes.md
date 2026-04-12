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
