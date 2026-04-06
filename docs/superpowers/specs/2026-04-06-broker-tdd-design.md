# Broker TDD — Design Spec

**Date:** 2026-04-06
**Repo:** `swift-nebula`

---

## Context

`BrokerAmas` was implemented without TDD. The code exists and compiles, but none of its behaviours are verified by tests. This spec defines the test coverage needed to make `BrokerAmas` trustworthy.

### Components under test

| File | Role |
|------|------|
| `Sources/Nebula/Broker/QueueStorage.swift` | `QueueStorage` protocol + `InMemoryQueueStorage` actor |
| `Sources/Nebula/Broker/QueuedMatter.swift` | Value type for queued messages |
| `Sources/Nebula/Broker/BrokerAmas.swift` | Main actor: subscribe, enqueue, dispatch, ACK, retry, park |
| `Sources/Nebula/Broker/RetryPolicy.swift` | Configuration: maxRetries, ackTimeout |

---

## Design Decisions

### ACK timeout in tests
`scheduleAckTimeout` uses `Task.sleep(for: retryPolicy.ackTimeout)`. Default is 30 s — unusable in tests.
**Fix:** inject `RetryPolicy(maxRetries: N, ackTimeout: .milliseconds(50))` in every test that exercises the timeout path. No clock abstraction needed; the existing `RetryPolicy` init already accepts any `Duration`.

### Channel verification
`BrokerAmas.send()` calls `channel.writeAndFlush()`. Tests use `EmbeddedChannel` (already used in the existing test suite) and call `channel.readOutbound(as: Matter.self)` to assert the correct Matter was written.

### State verification
Actor-internal state (`pendingAcks`, queue contents) is verified indirectly via the public/internal API:
- `active.pendingMessages()` — reflects enqueue + remove
- `parked.pendingMessages()` — reflects park
- `acknowledge()` + subsequent queue checks — reflects ACK removal

### Inner Task synchronisation
`send()` spawns a `Task { }` inside the actor. After calling `enqueue()`, tests must yield the run loop so the inner task executes before asserting outbound channel data. Use `await Task.yield()` (one or two yields as needed).

---

## Test Files

### `Tests/NebulaTests/QueueStorageTests.swift`

Unit tests for `InMemoryQueueStorage`. No network, no actor coordination.

| Test | What it verifies |
|------|-----------------|
| `append_storesMessage` | `pendingMessages()` returns the appended message |
| `append_duplicateID_overwrites` | Appending the same ID twice yields one entry |
| `remove_deletesMessage` | `pendingMessages()` is empty after remove |
| `remove_nonexistentID_noError` | Removing an unknown ID does not throw |
| `pendingMessages_preservesInsertionOrder` | Three messages returned in append order |

### `Tests/NebulaTests/BrokerAmasTests.swift`

Integration tests for `BrokerAmas`. Uses `EmbeddedChannel` for subscriber channels and `InMemoryQueueStorage` for both active and parked queues.

| Test | What it verifies |
|------|-----------------|
| `init_withDotInName_throws` | Name containing `.` throws `NebulaError` |
| `subscribe_then_unsubscribe_channelListEmpty` | Channel is removed after unsubscribe |
| `enqueue_noSubscribers_persistsToActiveOnly` | Active queue has message; no channel outbound |
| `enqueue_withSubscriber_channelReceivesEnqueueMatter` | `EmbeddedChannel.readOutbound()` returns a `.enqueue` Matter with correct matterID |
| `enqueue_fanOut_allGroupsReceive` | Two subscription groups each get one channel write |
| `dispatch_roundRobin_withinGroup` | Two consecutive enqueues alternate between two channels in the same group |
| `acknowledge_removesFromActiveQueue` | Active queue is empty and no retry fires after ACK |
| `acknowledge_unknownID_noEffect` | ACKing an unknown matterID does not throw or crash |
| `ackTimeout_belowMaxRetries_retryCountIncrements` | After timeout with retries remaining, message is re-dispatched with incremented retryCount |
| `ackTimeout_maxRetriesExhausted_messageParked` | After timeout at maxRetries, message appears in parked queue and not in active |
| `sendFailure_parks` | When channel write throws, message moves directly to parked queue |

---

## Test Helpers

```swift
private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
    QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                 method: "method", arguments: [])
}

private func makeBroker(maxRetries: Int = 3,
                        ackTimeout: Duration = .seconds(30)) throws -> BrokerAmas {
    try BrokerAmas(name: "broker", namespace: "test.broker",
                   retryPolicy: RetryPolicy(maxRetries: maxRetries,
                                            ackTimeout: ackTimeout))
}

private func fastBroker() throws -> BrokerAmas {
    try makeBroker(maxRetries: 2, ackTimeout: .milliseconds(50))
}
```

---

## Non-Goals

- No end-to-end broker test over real TCP (that belongs to a future integration test suite).
- No persistent `QueueStorage` implementation — only `InMemoryQueueStorage` is tested here.
- No test for `BrokerAmas` receiving NMT wire messages directly — that is covered by the NMT handler layer.
