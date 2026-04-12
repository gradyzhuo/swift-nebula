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
