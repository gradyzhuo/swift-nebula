# Remove @unchecked Sendable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate every `@unchecked Sendable` from `Sources/` in `swift-nmtp` and `swift-nebula` by using correct Swift 6 concurrency primitives.

**Architecture:** `PendingRequests` (NIO sync path) uses `Synchronization.Mutex`; `Service` and `ServiceStellar` (async paths) become `actor`s; NIO handler annotations are fixed by the cascade. All changes are TDD — failing test first, minimal implementation to pass.

**Tech Stack:** Swift 6.0, Swift Testing (`@Test`/`#expect`), XCTest, SwiftNIO, `Synchronization.Mutex`

---

## File Map

| File | Change |
|------|--------|
| `swift-nmtp/Sources/NMTP/NMT/PendingRequests.swift` | Replace `NSLock` with `Mutex`; `Sendable` (not `@unchecked`) |
| `swift-nmtp/Sources/NMTP/NMT/NMTClient.swift` | `@unchecked Sendable` → `Sendable` on class + handler |
| `swift-nmtp/Sources/NMTP/NMT/NMTServer.swift` | `@unchecked Sendable` → `Sendable` on handler |
| `swift-nmtp/Tests/NMTPTests/NMTIntegrationTests.swift` | Add `PendingRequests` unit tests |
| `swift-nebula/Sources/Nebula/Resource/Service.swift` | `class` → `actor`; `add()` returns `Void` |
| `swift-nebula/Sources/Nebula/Astral/Stellar/Stellar.swift` | `open class` → `actor`; `use()`/`add()` return `Void` |
| `swift-nebula/Tests/NebulaTests/NebulaTests.swift` | Add `await` to `add()`/`use()` calls; add actor concurrency tests |
| `swift-nebula/samples/demo/Sources/Stellar/main.swift` | Add `await` to `add()` calls |

---

## Task 1: Baseline — verify all existing tests pass

**Repos:** `swift-nmtp`, `swift-nebula`

- [ ] **Step 1: Run swift-nmtp tests**

```bash
cd /path/to/swift-nmtp
swift test
```

Expected: All tests pass. Note the count — we must not regress.

- [ ] **Step 2: Run swift-nebula tests**

```bash
cd /path/to/swift-nebula
swift test
```

Expected: All tests pass.

---

## Task 2: swift-nmtp — fix PendingRequests

**Files:**
- Modify: `Sources/NMTP/NMT/PendingRequests.swift`
- Modify: `Tests/NMTPTests/NMTIntegrationTests.swift`

### Background

`PendingRequests` stores a `[UUID: CheckedContinuation<Matter, Error>]` dictionary protected
by `NSLock`. `NSLock` is not `Sendable`, so the type uses `@unchecked Sendable` to silence
the compiler. The fix: replace `NSLock` + bare `var` with a single
`Mutex<[UUID: CheckedContinuation<Matter, Error>]>` from the Swift 6 `Synchronization` module.
`Mutex` IS `Sendable`, so the `@unchecked` can be dropped.

`resume()` must be called **outside** the lock closure to avoid scheduling work while the lock
is held.

- [ ] **Step 3: Write the failing tests**

Add to the bottom of `Tests/NMTPTests/NMTIntegrationTests.swift`:

```swift
// MARK: - PendingRequests unit tests

final class PendingRequestsTests: XCTestCase {

    /// register + fulfill from a concurrent Task returns the correct Matter.
    func testFulfillReturnsCorrectMatter() async throws {
        let pending = PendingRequests()
        let expected = Matter(type: .reply, body: Data("hello".utf8))

        let received: Matter = try await withCheckedThrowingContinuation { continuation in
            pending.register(id: expected.matterID, continuation: continuation)
            Task { pending.fulfill(expected) }
        }

        XCTAssertEqual(received.matterID, expected.matterID)
        XCTAssertEqual(received.body, Data("hello".utf8))
    }

    /// fulfill with an unknown UUID returns false and does not crash.
    func testFulfillUnknownIdReturnsFalse() {
        let pending = PendingRequests()
        let unknown = Matter(type: .call, body: Data())
        XCTAssertFalse(pending.fulfill(unknown))
    }

    /// failAll resumes every registered continuation with the given error.
    func testFailAllResumesAllContinuations() async throws {
        let pending = PendingRequests()
        let ids = (0..<5).map { _ in UUID() }

        await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    do {
                        let _: Matter = try await withCheckedThrowingContinuation { cont in
                            pending.register(id: id, continuation: cont)
                        }
                        XCTFail("Expected connectionClosed error")
                    } catch let e as NMTPError {
                        XCTAssertEqual(e, NMTPError.connectionClosed)
                    }
                }
            }
            // Give registrations a moment to settle, then fail all
            try? await Task.sleep(nanoseconds: 10_000_000)
            pending.failAll(error: NMTPError.connectionClosed)
        }
    }
}
```

- [ ] **Step 4: Run to confirm they compile and pass against old code**

```bash
cd /path/to/swift-nmtp
swift test --filter PendingRequestsTests
```

Expected: Tests compile and pass (old NSLock code is functionally correct; this step confirms
the test logic itself is valid).

- [ ] **Step 5: Implement the fix in PendingRequests.swift**

Replace the entire file content:

```swift
import Foundation
import Synchronization

final class PendingRequests: Sendable {
    private let waiting: Mutex<[UUID: CheckedContinuation<Matter, Error>]> = Mutex([:])

    func register(id: UUID, continuation: CheckedContinuation<Matter, Error>) {
        waiting.withLock { $0[id] = continuation }
    }

    @discardableResult
    func fulfill(_ matter: Matter) -> Bool {
        let continuation = waiting.withLock { $0.removeValue(forKey: matter.matterID) }
        continuation?.resume(returning: matter)
        return continuation != nil
    }

    func fail(id: UUID, error: Error) {
        let continuation = waiting.withLock { $0.removeValue(forKey: id) }
        continuation?.resume(throwing: error)
    }

    func failAll(error: Error) {
        let all = waiting.withLock { dict -> [CheckedContinuation<Matter, Error>] in
            let values = Array(dict.values)
            dict.removeAll()
            return values
        }
        all.forEach { $0.resume(throwing: error) }
    }
}
```

- [ ] **Step 6: Run the new tests**

```bash
swift test --filter PendingRequestsTests
```

Expected: All 3 tests pass.

- [ ] **Step 7: Run the full swift-nmtp suite**

```bash
swift test
```

Expected: All tests pass (same count as baseline).

- [ ] **Step 8: Commit**

```bash
git add Sources/NMTP/NMT/PendingRequests.swift Tests/NMTPTests/NMTIntegrationTests.swift
git commit -m "[REFACTOR] PendingRequests: replace NSLock with Mutex, drop @unchecked Sendable"
```

---

## Task 3: swift-nmtp — remove @unchecked from NMTClient and handlers

**Files:**
- Modify: `Sources/NMTP/NMT/NMTClient.swift`
- Modify: `Sources/NMTP/NMT/NMTServer.swift`

Now that `PendingRequests` is correctly `Sendable`, the three remaining `@unchecked` annotations
are mechanical: all stored properties are `let` and `Sendable`, so the compiler can verify them.

- [ ] **Step 9: Update NMTClient.swift**

Change line 4:
```swift
// Before
public final class NMTClient: @unchecked Sendable {
// After
public final class NMTClient: Sendable {
```

Change line 78:
```swift
// Before
private final class NMTClientInboundHandler: ChannelInboundHandler, @unchecked Sendable {
// After
private final class NMTClientInboundHandler: ChannelInboundHandler, Sendable {
```

- [ ] **Step 10: Update NMTServer.swift**

Change line 61:
```swift
// Before
private final class NMTServerInboundHandler: ChannelInboundHandler, @unchecked Sendable {
// After
private final class NMTServerInboundHandler: ChannelInboundHandler, Sendable {
```

- [ ] **Step 11: Build to confirm no errors**

```bash
swift build
```

Expected: Build succeeds with no warnings about Sendable.

- [ ] **Step 12: Run the full suite**

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 13: Commit**

```bash
git add Sources/NMTP/NMT/NMTClient.swift Sources/NMTP/NMT/NMTServer.swift
git commit -m "[REFACTOR] NMTClient/handlers: drop @unchecked, let Sendable be verified by compiler"
```

---

## Task 4: swift-nebula — Service → actor

**Files:**
- Modify: `Sources/Nebula/Resource/Service.swift`
- Modify: `Tests/NebulaTests/NebulaTests.swift`

### Background

`Service` stores `var methods: [String: any Method]`. With `class`, mutation is unprotected.
Converting to `actor` gives Swift's runtime automatic isolation — the `methods` dict is only
ever accessed on the actor's executor. The `@discardableResult -> Self` builder pattern is
removed: actors do not need method chaining since callers already hold the reference.

- [ ] **Step 14: Write a failing test for concurrent Service access**

Add at the bottom of `Tests/NebulaTests/NebulaTests.swift`:

```swift
// MARK: - Suite 3: Service actor

@Suite("Service Actor")
struct ServiceActorTests {

    /// Concurrent add + perform must not crash and must return correct results.
    @Test func concurrentAddAndPerform() async throws {
        let svc = Service(name: "math")
        await svc.add(method: "double") { args in
            guard let first = args.first else { return nil }
            let n = try first.unwrap(as: Int.self)
            return try JSONEncoder().encode(n * 2)
        }

        // Launch 20 concurrent calls
        try await withThrowingTaskGroup(of: Data?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let arg = try Argument.wrap(key: "x", value: 1)
                    return try await svc.perform(method: "double", with: [arg])
                }
            }
            for try await result in group {
                let value = try JSONDecoder().decode(Int.self, from: result!)
                #expect(value == 2)
            }
        }
    }
}
```

- [ ] **Step 15: Run to confirm it fails (compilation error — `add()` not yet async)**

```bash
cd /path/to/swift-nebula
swift test --filter "ServiceActorTests"
```

Expected: Compiler error — `add(method:)` not yet actor-isolated (returns `Self`, not `Void`).

- [ ] **Step 16: Replace Service.swift**

```swift
import Foundation
import NMTP

public actor Service {
    public let name: String
    public let version: String?
    public internal(set) var methods: [String: any Method] = [:]

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

// MARK: - Method Management

extension Service {

    public func add(method: ServiceMethod) {
        methods[method.name] = method
    }

    public func add(method name: String, action: @escaping MethodAction) {
        methods[name] = ServiceMethod(name: name, action: action)
    }
}

// MARK: - Invocation

extension Service {

    public func perform(method name: String, with arguments: [Argument]) async throws -> Data? {
        guard let method = methods[name] else {
            throw NebulaError.methodNotFound(service: self.name, method: name)
        }
        return try await method.invoke(arguments: arguments)
    }
}
```

- [ ] **Step 17: Update existing call sites in NebulaTests.swift**

In `echoStellar()` (two places), change:
```swift
// Before
private func echoStellar() throws -> ServiceStellar {
    let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
    let svc = Service(name: "echo")
    svc.add(method: "ping") { _ in Data([1]) }
    stellar.add(service: svc)
    return stellar
}
// After
private func echoStellar() async throws -> ServiceStellar {
    let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
    let svc = Service(name: "echo")
    await svc.add(method: "ping") { _ in Data([1]) }
    stellar.add(service: svc)       // stellar.add stays sync until Task 5
    return stellar
}
```

Also update all callers of `echoStellar()`:
```swift
// Before
let stellar = try echoStellar()
// After
let stellar = try await echoStellar()
```

And in `bindEchoStellar(namespace:)`:
```swift
// Before
private func bindEchoStellar(namespace: String) async throws -> NMTServer {
    let stellar = try ServiceStellar(name: "echo", namespace: namespace)
    let svc = Service(name: "echo")
    svc.add(method: "ping") { _ in Data([1]) }
    stellar.add(service: svc)
    return try await NMTServer.bind(on: try loopbackPort0(), handler: stellar)
}
// After
private func bindEchoStellar(namespace: String) async throws -> NMTServer {
    let stellar = try ServiceStellar(name: "echo", namespace: namespace)
    let svc = Service(name: "echo")
    await svc.add(method: "ping") { _ in Data([1]) }
    stellar.add(service: svc)       // stellar.add stays sync until Task 5
    return try await NMTServer.bind(on: try loopbackPort0(), handler: stellar)
}
```

- [ ] **Step 18: Run new test to confirm it passes**

```bash
swift test --filter "ServiceActorTests"
```

Expected: PASS.

- [ ] **Step 19: Run full suite**

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 20: Commit**

```bash
git add Sources/Nebula/Resource/Service.swift Tests/NebulaTests/NebulaTests.swift
git commit -m "[REFACTOR] Service: class → actor, drop @unchecked Sendable"
```

---

## Task 5: swift-nebula — ServiceStellar → actor

**Files:**
- Modify: `Sources/Nebula/Astral/Stellar/Stellar.swift`
- Modify: `Tests/NebulaTests/NebulaTests.swift`
- Modify: `samples/demo/Sources/Stellar/main.swift`

### Background

`ServiceStellar` is `open class` but is never subclassed. In Swift POP design, extensibility
is expressed through protocols, not inheritance. Converting to `actor` drops `open`, gives
proper isolation for `availableServices` and `chain`, and satisfies `NMTHandler` (which requires
`async throws` — actor-isolated async methods satisfy async protocol requirements).

Builder methods `use()` and `add(service:)` return `Void` — actors don't need `Self`-chaining.

- [ ] **Step 21: Write a failing test for concurrent ServiceStellar access**

Add to `ServiceActorTests` in `NebulaTests.swift`:

```swift
/// Concurrent handle() calls on the same ServiceStellar must all succeed.
@Test func concurrentHandleCalls() async throws {
    let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
    let svc = Service(name: "echo")
    await svc.add(method: "ping") { _ in Data([1]) }
    await stellar.add(service: svc)     // add() returns Void after this task

    let body = CallBody(namespace: "test.echo", service: "echo", method: "ping", arguments: [])
    let matter = try Matter.make(type: .call, body: body)

    try await withThrowingTaskGroup(of: Matter?.self) { group in
        for _ in 0..<20 {
            group.addTask {
                try await stellar.handle(matter: matter, channel: EmbeddedChannel())
            }
        }
        for try await reply in group {
            let replyBody = try #require(reply).decodeBody(CallReplyBody.self)
            #expect(replyBody.error == nil)
        }
    }
}
```

- [ ] **Step 22: Run to confirm it fails (stellar.add not yet async)**

```bash
swift test --filter "ServiceActorTests/concurrentHandleCalls"
```

Expected: Compiler error — `stellar.add(service:)` returns `Self` and is not yet async.

- [ ] **Step 23: Replace Stellar.swift**

```swift
import Foundation
import NIO
import NMTP

public protocol Stellar: Astral {
    var namespace: String { get }
}

extension Stellar {
    public static var category: AstralCategory { .stellar }
}

public typealias ServiceVersion = String

/// A Stellar that hosts named Services.
///
/// Middlewares are stacked via ``use(_:)`` before the server starts.
/// Each call to `use()` wraps the current chain from the outside, so the
/// **last-registered middleware runs outermost** (first to receive each matter).
///
/// ```swift
/// let stellar = try ServiceStellar(name: "account", namespace: "production.mendesky")
/// await stellar.use(LoggingMiddleware())      // inner — runs second
/// await stellar.use(LDAPAuthMiddleware(...))  // outer — runs first
/// await stellar.add(service: accountService)
/// ```
public actor ServiceStellar: Stellar {
    public let identifier: UUID
    public let name: String
    public let namespace: String

    private var availableServices: [ServiceVersion: Service] = [:]
    private var chain: NMTMiddlewareNext?

    public init(name: String, namespace: String, identifier: UUID = UUID()) throws {
        try Self.validateName(name)
        self.identifier = identifier
        self.name = name
        self.namespace = namespace
    }

    public func use(_ middleware: any NMTMiddleware) {
        let inner: NMTMiddlewareNext = chain ?? { [unowned self] matter in
            try await self.coreDispatch(matter: matter)
        }
        chain = { matter in try await middleware.handle(matter, next: inner) }
    }

    public func add(service: Service) {
        availableServices[service.name] = service
    }
}

// MARK: - NMTServerTarget

extension ServiceStellar: NMTServerTarget {

    public func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        if let chain {
            return try await chain(matter)
        }
        return try await coreDispatch(matter: matter)
    }
}

// MARK: - Core dispatch (no middleware)

extension ServiceStellar {

    private func coreDispatch(matter: Matter) async throws -> Matter? {
        switch matter.type {
        case .call:
            return try await handleCall(envelope: matter)
        case .enqueue:
            return try await handleEnqueue(envelope: matter)
        case .clone:
            return try makeCloneReply(envelope: matter)
        default:
            return nil
        }
    }

    private func handleCall(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(CallBody.self)

        guard let service = availableServices[body.service] else {
            throw NebulaError.serviceNotFound(namespace: body.service)
        }

        let arguments = body.arguments.map { Argument(key: $0.key, data: $0.value) }
        let result = try await service.perform(method: body.method, with: arguments)

        let reply = CallReplyBody(result: result)
        return try envelope.reply(body: reply)
    }

    private func handleEnqueue(envelope: Matter) async throws -> Matter {
        let body = try envelope.decodeBody(EnqueueBody.self)

        guard let service = availableServices[body.service] else {
            throw NebulaError.serviceNotFound(namespace: body.service)
        }

        let arguments = body.arguments.map { Argument(key: $0.key, data: $0.value) }
        _ = try await service.perform(method: body.method, with: arguments)

        return try envelope.reply(body: AckBody(matterID: envelope.matterID.uuidString))
    }

    private func makeCloneReply(envelope: Matter) throws -> Matter {
        let reply = CloneReplyBody(
            identifier: identifier.uuidString,
            name: name,
            category: AstralCategory.stellar.rawValue
        )
        return try envelope.reply(body: reply)
    }
}
```

- [ ] **Step 24: Update NebulaTests.swift — add await to stellar.use() and stellar.add()**

In `echoStellar()` and `bindEchoStellar(namespace:)`, change `stellar.add(service: svc)` to `await stellar.add(service: svc)`.

In `lastRegistered_runsOutermost()`:
```swift
// Before
stellar
    .use(TrackingMiddleware(label: "A", log: log))
    .use(TrackingMiddleware(label: "B", log: log))
// After
await stellar.use(TrackingMiddleware(label: "A", log: log))
await stellar.use(TrackingMiddleware(label: "B", log: log))
```

In `shortCircuit_preventsInnerMiddleware()`:
```swift
// Before
stellar
    .use(TrackingMiddleware(label: "A", log: log))
    .use(ShortCircuitMiddleware())
// After
await stellar.use(TrackingMiddleware(label: "A", log: log))
await stellar.use(ShortCircuitMiddleware())
```

In `nonCallMatter_cloneHandledByCore()`:
```swift
// Before
stellar.use(TrackingMiddleware(label: "A", log: log))
// After
await stellar.use(TrackingMiddleware(label: "A", log: log))
```

- [ ] **Step 25: Update samples/demo/Sources/Stellar/main.swift**

```swift
// Before
let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in ... }
stellar.add(service: w2v)

// After
let w2v = Service(name: "w2v")
await w2v.add(method: "wordVector") { args in ... }
await stellar.add(service: w2v)
```

- [ ] **Step 26: Run new concurrent test**

```bash
swift test --filter "ServiceActorTests/concurrentHandleCalls"
```

Expected: PASS.

- [ ] **Step 27: Run full suite**

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 28: Build the demo**

```bash
cd samples/demo
swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 29: Confirm no @unchecked Sendable remains in Sources/**

```bash
grep -r "@unchecked Sendable" Sources/
```

Expected: No output (zero occurrences).

Also run in swift-nmtp:
```bash
cd /path/to/swift-nmtp
grep -r "@unchecked Sendable" Sources/
```

Expected: No output.

- [ ] **Step 30: Commit**

```bash
git add Sources/Nebula/Astral/Stellar/Stellar.swift \
        Tests/NebulaTests/NebulaTests.swift \
        samples/demo/Sources/Stellar/main.swift
git commit -m "[REFACTOR] ServiceStellar: open class → actor, drop @unchecked Sendable"
```

---

## Task 6: Final validation — Thread Sanitizer

- [ ] **Step 31: Run swift-nmtp with TSAN**

```bash
cd /path/to/swift-nmtp
swift test --sanitize thread
```

Expected: All tests pass, no data race reports.

- [ ] **Step 32: Run swift-nebula with TSAN**

```bash
cd /path/to/swift-nebula
swift test --sanitize thread
```

Expected: All tests pass, no data race reports.

- [ ] **Step 33: Final commit if any cleanup needed**

If TSAN reveals any issues, fix and commit. Otherwise:

```bash
# Confirm clean state
git status
```

Expected: Working tree clean across both repos.
