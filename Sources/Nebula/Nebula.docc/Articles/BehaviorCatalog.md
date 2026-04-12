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
