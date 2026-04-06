# Broker TDD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full TDD test coverage for `InMemoryQueueStorage` and `BrokerAmas`, and fix one pre-existing bug discovered in the process.

**Architecture:** Two new test files — `QueueStorageTests.swift` (5 unit tests, no network) and `BrokerAmasTests.swift` (10 integration tests using `EmbeddedChannel` and `InMemoryQueueStorage`). One bug fix in `QueueStorage.swift`: duplicate-ID append creates duplicate `order` entries.

**Tech Stack:** Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), `NIOEmbedded.EmbeddedChannel`, `@testable import Nebula`

---

## Task 1: QueueStorage unit tests + duplicate-ID fix

**Files:**
- Create: `Tests/NebulaTests/QueueStorageTests.swift`
- Modify: `Sources/Nebula/Broker/QueueStorage.swift:30-34`

- [ ] **Step 1: Create the test file**

```swift
// Tests/NebulaTests/QueueStorageTests.swift
import Testing
import Foundation
@testable import Nebula

@Suite("InMemoryQueueStorage")
struct QueueStorageTests {

    private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
        QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                     method: "method", arguments: [])
    }

    @Test func append_storesMessage() async {
        let storage = InMemoryQueueStorage()
        let msg = makeMessage()
        await storage.append(msg)
        let messages = await storage.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].id == msg.id)
    }

    @Test func append_duplicateID_overwrites() async {
        let storage = InMemoryQueueStorage()
        let id = UUID()
        let msg1 = makeMessage(id: id)
        let msg2 = QueuedMatter(id: id, namespace: "other.ns", service: "svc2",
                                method: "m2", arguments: [])
        await storage.append(msg1)
        await storage.append(msg2)
        let messages = await storage.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].namespace == "other.ns")
    }

    @Test func remove_deletesMessage() async {
        let storage = InMemoryQueueStorage()
        let msg = makeMessage()
        await storage.append(msg)
        await storage.remove(id: msg.id)
        let messages = await storage.pendingMessages()
        #expect(messages.isEmpty)
    }

    @Test func remove_nonexistentID_noError() async {
        let storage = InMemoryQueueStorage()
        await storage.remove(id: UUID())  // must not crash
    }

    @Test func pendingMessages_preservesInsertionOrder() async {
        let storage = InMemoryQueueStorage()
        let ids = [UUID(), UUID(), UUID()]
        for id in ids {
            await storage.append(makeMessage(id: id))
        }
        let messages = await storage.pendingMessages()
        #expect(messages.map(\.id) == ids)
    }
}
```

- [ ] **Step 2: Run to confirm `append_duplicateID_overwrites` fails**

```bash
swift test --filter NebulaTests/QueueStorageTests/append_duplicateID_overwrites
```

Expected: **FAIL** — `messages.count` is 2 instead of 1 (current `append` pushes `id` to `order` twice).

- [ ] **Step 3: Fix the duplicate-ID bug in `InMemoryQueueStorage.append`**

In `Sources/Nebula/Broker/QueueStorage.swift`, replace:

```swift
public func append(_ message: QueuedMatter) {
    messages[message.id] = message
    order.append(message.id)
}
```

with:

```swift
public func append(_ message: QueuedMatter) {
    if messages[message.id] == nil {
        order.append(message.id)
    }
    messages[message.id] = message
}
```

- [ ] **Step 4: Run all QueueStorage tests**

```bash
swift test --filter NebulaTests/QueueStorageTests
```

Expected: **5/5 PASS**

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
swift test
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Tests/NebulaTests/QueueStorageTests.swift \
        Sources/Nebula/Broker/QueueStorage.swift
git commit -m "[ADD] QueueStorageTests: 5 unit tests; fix duplicate-ID append bug"
```

---

## Task 2: BrokerAmas — init, subscribe, enqueue tests

**Files:**
- Create: `Tests/NebulaTests/BrokerAmasTests.swift`

- [ ] **Step 1: Create the test file with helpers and first 4 tests**

```swift
// Tests/NebulaTests/BrokerAmasTests.swift
import Testing
import Foundation
import NIO
import NIOEmbedded
import NMTP
@testable import Nebula

@Suite("BrokerAmas")
struct BrokerAmasTests {

    // MARK: - Helpers

    private func makeMessage(id: UUID = UUID()) -> QueuedMatter {
        QueuedMatter(id: id, namespace: "test.ns", service: "svc",
                     method: "method", arguments: [])
    }

    /// Broker with default (slow) timeout — for tests that don't exercise ACK timeout.
    private func makeBroker(
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerAmas {
        try BrokerAmas(name: "broker", namespace: "test.broker",
                       active: active, parked: parked)
    }

    /// Broker with a very short ACK timeout — for retry/park tests.
    private func fastBroker(
        maxRetries: Int = 2,
        active: InMemoryQueueStorage = InMemoryQueueStorage(),
        parked: InMemoryQueueStorage = InMemoryQueueStorage()
    ) throws -> BrokerAmas {
        try BrokerAmas(name: "broker", namespace: "test.broker",
                       active: active, parked: parked,
                       retryPolicy: RetryPolicy(maxRetries: maxRetries,
                                                ackTimeout: .milliseconds(50)))
    }

    // MARK: - Init

    @Test func init_withDotInName_throws() {
        #expect(throws: (any Error).self) {
            try BrokerAmas(name: "bad.name", namespace: "test.broker")
        }
    }

    // MARK: - Subscribe / Unsubscribe

    @Test func unsubscribe_preventsOutbound() async throws {
        let broker = try makeBroker()
        let channel = EmbeddedChannel()
        await broker.subscribe(subscription: "g1", channel: channel)
        await broker.unsubscribe(subscription: "g1", channel: channel)

        try await broker.enqueue(message: makeMessage())
        await Task.yield()
        await Task.yield()

        let outbound = try channel.readOutbound(as: Matter.self)
        #expect(outbound == nil)
    }

    // MARK: - Enqueue

    @Test func enqueue_noSubscribers_persistsToActiveOnly() async throws {
        let active = InMemoryQueueStorage()
        let broker = try makeBroker(active: active)
        let msg = makeMessage()

        try await broker.enqueue(message: msg)

        let messages = await active.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].id == msg.id)
    }

    @Test func enqueue_withSubscriber_channelReceivesEnqueueMatter() async throws {
        let broker = try makeBroker()
        let channel = EmbeddedChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await Task.yield()
        await Task.yield()

        let matter = try #require(try channel.readOutbound(as: Matter.self))
        #expect(matter.type == .enqueue)
        #expect(matter.matterID == msg.id)
    }
}
```

- [ ] **Step 2: Run to verify tests compile and pass**

```bash
swift test --filter NebulaTests/BrokerAmasTests
```

Expected: **4/4 PASS**

- [ ] **Step 3: Commit**

```bash
git add Tests/NebulaTests/BrokerAmasTests.swift
git commit -m "[ADD] BrokerAmasTests: init, subscribe, enqueue tests (4 cases)"
```

---

## Task 3: BrokerAmas — fan-out and round-robin tests

**Files:**
- Modify: `Tests/NebulaTests/BrokerAmasTests.swift` (append to existing file)

- [ ] **Step 1: Add fan-out and round-robin tests inside `BrokerAmasTests`**

Append inside the `BrokerAmasTests` struct, after the existing tests:

```swift
    // MARK: - Dispatch

    @Test func enqueue_fanOut_allGroupsReceive() async throws {
        let broker = try makeBroker()
        let channel1 = EmbeddedChannel()
        let channel2 = EmbeddedChannel()
        await broker.subscribe(subscription: "group1", channel: channel1)
        await broker.subscribe(subscription: "group2", channel: channel2)

        try await broker.enqueue(message: makeMessage())
        await Task.yield()
        await Task.yield()

        let matter1 = try channel1.readOutbound(as: Matter.self)
        let matter2 = try channel2.readOutbound(as: Matter.self)
        #expect(matter1 != nil)
        #expect(matter2 != nil)
    }

    @Test func dispatch_roundRobin_withinGroup() async throws {
        let broker = try makeBroker()
        let channel1 = EmbeddedChannel()
        let channel2 = EmbeddedChannel()
        await broker.subscribe(subscription: "g1", channel: channel1)
        await broker.subscribe(subscription: "g1", channel: channel2)

        let msg1 = makeMessage()
        let msg2 = makeMessage()

        try await broker.enqueue(message: msg1)
        await Task.yield()
        await Task.yield()
        try await broker.enqueue(message: msg2)
        await Task.yield()
        await Task.yield()

        // First message → index 0 (channel1), second → index 1 (channel2)
        let outbound1 = try #require(try channel1.readOutbound(as: Matter.self))
        let outbound2 = try #require(try channel2.readOutbound(as: Matter.self))
        #expect(outbound1.matterID == msg1.id)
        #expect(outbound2.matterID == msg2.id)
        // Neither channel should have a second message
        #expect(try channel1.readOutbound(as: Matter.self) == nil)
        #expect(try channel2.readOutbound(as: Matter.self) == nil)
    }
```

- [ ] **Step 2: Run new tests**

```bash
swift test --filter NebulaTests/BrokerAmasTests
```

Expected: **6/6 PASS**

- [ ] **Step 3: Commit**

```bash
git add Tests/NebulaTests/BrokerAmasTests.swift
git commit -m "[ADD] BrokerAmasTests: fan-out and round-robin dispatch tests"
```

---

## Task 4: BrokerAmas — ACK, timeout, and park tests

**Files:**
- Modify: `Tests/NebulaTests/BrokerAmasTests.swift` (append to existing file)

- [ ] **Step 1: Add ACK tests inside `BrokerAmasTests`**

Append inside the `BrokerAmasTests` struct:

```swift
    // MARK: - ACK

    @Test func acknowledge_removesFromActiveQueue() async throws {
        let active = InMemoryQueueStorage()
        let broker = try makeBroker(active: active)
        let msg = makeMessage()

        try await broker.enqueue(message: msg)
        await broker.acknowledge(matterID: msg.id)

        let messages = await active.pendingMessages()
        #expect(messages.isEmpty)
    }

    @Test func acknowledge_unknownID_noEffect() async throws {
        let broker = try makeBroker()
        await broker.acknowledge(matterID: UUID())  // must not crash
    }

    // MARK: - ACK Timeout

    @Test func ackTimeout_belowMaxRetries_retryCountIncrements() async throws {
        let active = InMemoryQueueStorage()
        let broker = try fastBroker(maxRetries: 2, active: active)
        let channel = EmbeddedChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        let msg = makeMessage()
        try await broker.enqueue(message: msg)
        await Task.yield()

        // Drain the initial dispatch from the channel
        _ = try channel.readOutbound(as: Matter.self)

        // Wait for the 50 ms ACK timeout to fire and re-dispatch
        try await Task.sleep(for: .milliseconds(150))
        await Task.yield()
        await Task.yield()

        // Channel should have received the retry dispatch
        let retryMatter = try #require(try channel.readOutbound(as: Matter.self))
        #expect(retryMatter.matterID == msg.id)

        // Active queue should still hold the message (now with retryCount = 1)
        let messages = await active.pendingMessages()
        #expect(messages.count == 1)
        #expect(messages[0].retryCount == 1)
    }

    @Test func ackTimeout_maxRetriesExhausted_messageParked() async throws {
        let active = InMemoryQueueStorage()
        let parked = InMemoryQueueStorage()
        // maxRetries: 1 → after one timeout, retryCount becomes 1 >= 1 → park immediately
        let broker = try fastBroker(maxRetries: 1, active: active, parked: parked)
        let channel = EmbeddedChannel()
        await broker.subscribe(subscription: "g1", channel: channel)

        try await broker.enqueue(message: makeMessage())
        await Task.yield()

        // Wait for the 50 ms timeout to fire and park the message
        try await Task.sleep(for: .milliseconds(150))
        await Task.yield()
        await Task.yield()

        let activeMessages = await active.pendingMessages()
        let parkedMessages = await parked.pendingMessages()
        #expect(activeMessages.isEmpty)
        #expect(parkedMessages.count == 1)
    }
```

- [ ] **Step 2: Run all BrokerAmas tests**

```bash
swift test --filter NebulaTests/BrokerAmasTests
```

Expected: **10/10 PASS**

- [ ] **Step 3: Run full test suite**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/NebulaTests/BrokerAmasTests.swift
git commit -m "[ADD] BrokerAmasTests: ACK, timeout retry, and park tests"
```

---

## Non-Goals (out of scope for this plan)

- `sendFailure_parks` — `channel.writeAndFlush(_, promise: nil)` is fire-and-forget; triggering the `catch` path requires either injecting a mock channel or refactoring `send()`. Deferred to a future design change.
- End-to-end broker test over real TCP.
- Persistent `QueueStorage` implementations.
