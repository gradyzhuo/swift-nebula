# Nebula Repo Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `swift-nebula` into `swift-nmtp` (protocol layer), `swift-nebula` (server framework), and `swift-nebula-client` (Swift client).

**Architecture:** NMTP is the pure transport protocol — no generics, no framework semantics. Nebula server framework builds on NMTP with Astral hierarchy, service discovery, and load balancing. Swift client is one of many possible language implementations, each independently defining Astral/AstralCategory per the Nebula spec.

**Tech Stack:** Swift 6.0, swift-nio, swift-nio-extras, MessagePacker, swift-log

**Spec:** `docs/superpowers/specs/2026-04-04-repo-split-design.md`

---

## File Structure

### swift-nmtp (new repo)

```
Sources/NMTP/
├── Matter/
│   ├── Matter.swift              (Matter struct, header serialization)
│   ├── MatterType.swift          (MatterType enum)
│   ├── MatterBodies.swift        (all body codables)
│   └── Matter+Coding.swift       (MessagePack encode/decode helpers)
├── NMT/
│   ├── NMTClient.swift           (non-generic client: connect, request, send, pushes)
│   ├── NMTServer.swift           (non-generic server: bind with NMTHandler)
│   ├── NMTHandler.swift          (handler protocol)
│   ├── MatterEncoder.swift       (NIO MessageToByteEncoder)
│   ├── MatterDecoder.swift       (NIO ByteToMessageDecoder)
│   └── PendingRequests.swift     (UUID-based request/reply matching)
├── Argument.swift                (Argument struct + encoding helpers)
├── ArgumentValue.swift           (ArgumentValue enum + literal conformances)
├── NMTPError.swift               (protocol-layer errors)
└── Extensions/
    └── UUID+Bytes.swift          (UUID bytes, FixedWidthInteger bytes, UInt32 bytes)
Package.swift
Tests/NMTPTests/
    └── MatterTests.swift         (Matter serialization round-trip)
```

### swift-nebula (restructured existing repo)

```
Sources/Nebula/
├── Astral/
│   ├── Astral.swift              (Astral protocol: NMTPNode-free, AstralCategory, ServerAstral)
│   ├── Galaxy/StandardGalaxy.swift
│   ├── Amas/LoadBalanceAmas.swift
│   ├── Amas/Amas.swift
│   ├── Stellar/ServiceStellar.swift
│   ├── Stellar/Service.swift     (moved from Resource/)
│   └── Stellar/Method.swift      (moved from Resource/)
├── Broker/
│   ├── BrokerAmas.swift
│   ├── QueueStorage.swift
│   ├── QueuedMatter.swift
│   └── RetryPolicy.swift
├── Ingress/StandardIngress.swift
├── Registry/
│   ├── ServiceRegistry.swift
│   └── InMemoryServiceRegistry.swift
├── Auth/NMTMiddleware.swift
├── NMT/
│   ├── NMTServerTarget.swift     (NMTServerTarget: NMTHandler from NMTP)
│   ├── NMTServerBuilder.swift    (builder convenience)
│   └── NebulaClient.swift        (wraps NMTClient with Nebula convenience: register, find, etc.)
├── Resource/
│   └── NebulaURI.swift
├── Nebula.swift
├── NebulaError.swift             (framework-level errors: serviceNotFound, methodNotFound, etc.)
└── Logging/ColorLogHandler.swift
Package.swift                     (depends on swift-nmtp)
```

### swift-nebula-client (new repo)

```
Sources/NebulaClient/
├── Astral/
│   ├── Astral.swift              (own Astral protocol + AstralCategory, matching Nebula spec)
│   └── Planet.swift              (Planet protocol)
├── Planet/
│   ├── RoguePlanet.swift
│   ├── Moon.swift
│   ├── MethodProxy.swift
│   └── Satellite.swift
├── Comet/Comet.swift
├── Subscriber/Subscriber.swift
└── NMT/
    └── NebulaClient.swift        (client-side NMTClient convenience: find, unregister, etc.)
Package.swift                     (depends on swift-nmtp)
Tests/NebulaClientTests/
    └── ... (placeholder for Phase 2)
```

---

## Task 1: Create swift-nmtp repo and Package.swift

**Files:**
- Create: `swift-nmtp/Package.swift`

- [ ] **Step 1: Create the repo directory**

```bash
mkdir -p /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nmtp
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nmtp
git init
```

- [ ] **Step 2: Write Package.swift**

```swift
// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "swift-nmtp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NMTP", targets: ["NMTP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "NMTP",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "MessagePacker", package: "MessagePacker"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .testTarget(
            name: "NMTPTests",
            dependencies: ["NMTP"]),
    ]
)
```

- [ ] **Step 3: Create source and test directories**

```bash
mkdir -p Sources/NMTP/Matter Sources/NMTP/NMT Sources/NMTP/Extensions Tests/NMTPTests
```

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "init: swift-nmtp package skeleton"
```

---

## Task 2: Port NMTPError and UUID/Integer extensions

**Files:**
- Create: `swift-nmtp/Sources/NMTP/NMTPError.swift`
- Create: `swift-nmtp/Sources/NMTP/Extensions/UUID+Bytes.swift`

- [ ] **Step 1: Write NMTPError**

Only protocol-level errors. Framework errors (serviceNotFound, methodNotFound) stay in swift-nebula.

```swift
// NMTPError.swift
import Foundation

public enum NMTPError: Error {
    case fail(message: String)
    case invalidMatter(_ reason: String)
    case notConnected
    case connectionClosed
}
```

- [ ] **Step 2: Write UUID+Bytes extension**

```swift
// Extensions/UUID+Bytes.swift
import Foundation

extension UUID {
    public var bytes: [UInt8] {
        var uuid = self.uuid
        let ptr = UnsafeBufferPointer(start: &uuid.0, count: MemoryLayout.size(ofValue: uuid))
        return .init(ptr)
    }

    public var data: Data {
        return .init(bytes)
    }

    public init(bytes: ArraySlice<UInt8>) throws {
        try self.init(bytes: [UInt8](bytes))
    }

    public init(data: Data) throws {
        try self.init(bytes: data.map { $0 })
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count == 16 else {
            throw NMTPError.fail(message: "UUID bytes length should be 16 bytes.")
        }
        let bytesTuple = (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        self.init(uuid: bytesTuple)
    }
}

extension FixedWidthInteger {
    public func bytes() -> [UInt8] {
        return withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }
}

extension UInt32 {
    public init(bytes: [UInt8]) {
        assert(bytes.count == 4)
        self = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nmtp
swift build
```

Expected: BUILD SUCCEEDED (empty library, only extensions and error enum)

- [ ] **Step 4: Commit**

```bash
git add Sources/NMTP/NMTPError.swift Sources/NMTP/Extensions/
git commit -m "add: NMTPError and UUID/Integer byte extensions"
```

---

## Task 3: Port Matter types

**Files:**
- Create: `swift-nmtp/Sources/NMTP/Matter/Matter.swift`
- Create: `swift-nmtp/Sources/NMTP/Matter/MatterType.swift`
- Create: `swift-nmtp/Sources/NMTP/Matter/MatterBodies.swift`
- Create: `swift-nmtp/Sources/NMTP/Matter/Matter+Coding.swift`

- [ ] **Step 1: Copy Matter.swift, replace NebulaError with NMTPError**

Copy from `swift-nebula/Sources/Nebula/Matter/Matter.swift`. Replace all `NebulaError.invalidMatter` with `NMTPError.invalidMatter`.

```swift
// Matter/Matter.swift
import Foundation

public let NMTPMagic: [UInt8] = [0x4E, 0x42, 0x4C, 0x41]

public struct Matter: Sendable {
    public static let headerSize = 27

    public let version: UInt8
    public let type: MatterType
    public let flags: UInt8
    public let matterID: UUID
    public let body: Data

    public init(type: MatterType, flags: UInt8 = 0, matterID: UUID = UUID(), body: Data) {
        self.version = 1
        self.type = type
        self.flags = flags
        self.matterID = matterID
        self.body = body
    }
}

// MARK: - Serialization

extension Matter {
    public func serialized() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.headerSize + body.count)
        bytes.append(contentsOf: NMTPMagic)
        bytes.append(version)
        bytes.append(type.rawValue)
        bytes.append(flags)
        bytes.append(contentsOf: matterID.bytes)
        bytes.append(contentsOf: UInt32(body.count).bytes())
        bytes.append(contentsOf: body)
        return bytes
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= Matter.headerSize else {
            throw NMTPError.invalidMatter("Too short: \(bytes.count) bytes")
        }
        let magic = Array(bytes[0..<4])
        guard magic == NMTPMagic else {
            throw NMTPError.invalidMatter("Invalid magic bytes")
        }
        let version = bytes[4]
        guard let type = MatterType(rawValue: bytes[5]) else {
            throw NMTPError.invalidMatter("Unknown matter type: \(bytes[5])")
        }
        let flags = bytes[6]
        let matterID = try UUID(bytes: Array(bytes[7..<23]))
        let length = Int(UInt32(bytes: Array(bytes[23..<27])))
        guard bytes.count >= Matter.headerSize + length else {
            throw NMTPError.invalidMatter("Body length mismatch")
        }
        let body = Data(bytes[Matter.headerSize ..< Matter.headerSize + length])
        self.version = version
        self.type = type
        self.flags = flags
        self.matterID = matterID
        self.body = body
    }
}
```

Note: rename `NebulaMatterMagic` to `NMTPMagic` — protocol-layer naming.

- [ ] **Step 2: Copy MatterType.swift as-is**

```swift
// Matter/MatterType.swift
import Foundation

public enum MatterType: UInt8, Sendable {
    case clone       = 0x01
    case register    = 0x02
    case find        = 0x03
    case call        = 0x04
    case reply       = 0x05
    case activate    = 0x06
    case heartbeat   = 0x07
    case unregister  = 0x08
    case enqueue     = 0x09
    case ack         = 0x0a
    case subscribe   = 0x0b
    case unsubscribe = 0x0c
    case event       = 0x0d
    case findGalaxy  = 0x0e
}
```

- [ ] **Step 3: Copy MatterBodies.swift as-is**

Copy from `swift-nebula/Sources/Nebula/Matter/MatterBodies.swift`. No changes needed — all body types are plain Codable structs.

- [ ] **Step 4: Copy Matter+Coding.swift as-is**

Copy from `swift-nebula/Sources/Nebula/Matter/Matter+Coding.swift`. No changes needed — MessagePacker encode/decode helpers.

- [ ] **Step 5: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/NMTP/Matter/
git commit -m "add: Matter wire format types"
```

---

## Task 4: Port Argument and ArgumentValue

**Files:**
- Create: `swift-nmtp/Sources/NMTP/Argument.swift`
- Create: `swift-nmtp/Sources/NMTP/ArgumentValue.swift`

- [ ] **Step 1: Copy Argument.swift as-is**

Copy from `swift-nebula/Sources/Nebula/Resource/Argument.swift`. No changes needed — it depends on `MessagePacker` and `EncodedArgument` (from MatterBodies.swift), both already in swift-nmtp.

- [ ] **Step 2: Copy ArgumentValue.swift as-is**

Copy from `swift-nebula/Sources/Nebula/Resource/ArgumentValue.swift`. No changes needed.

- [ ] **Step 3: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/NMTP/Argument.swift Sources/NMTP/ArgumentValue.swift
git commit -m "add: Argument and ArgumentValue types"
```

---

## Task 5: Port NMTHandler, MatterEncoder, MatterDecoder

**Files:**
- Create: `swift-nmtp/Sources/NMTP/NMT/NMTHandler.swift`
- Create: `swift-nmtp/Sources/NMTP/NMT/MatterEncoder.swift`
- Create: `swift-nmtp/Sources/NMTP/NMT/MatterDecoder.swift`
- Create: `swift-nmtp/Sources/NMTP/NMT/PendingRequests.swift`

- [ ] **Step 1: Write NMTHandler protocol**

New file — replaces the generic `NMTServerTarget` protocol. Same signature, new name.

```swift
// NMT/NMTHandler.swift
import Foundation
import NIO

/// A handler that processes incoming Matter and optionally returns a reply.
public protocol NMTHandler: Sendable {
    func handle(matter: Matter, channel: Channel) async throws -> Matter?
}
```

- [ ] **Step 2: Copy MatterEncoder.swift, change visibility to public**

```swift
// NMT/MatterEncoder.swift
import Foundation
import NIO

public final class MatterEncoder: MessageToByteEncoder {
    public typealias OutboundIn = Matter

    public init() {}

    public func encode(data: Matter, out: inout ByteBuffer) throws {
        out.writeBytes(data.serialized())
    }
}
```

- [ ] **Step 3: Copy MatterDecoder.swift, change visibility to public, replace NMTPError**

```swift
// NMT/MatterDecoder.swift
import Foundation
import NIO

public final class MatterDecoder: ByteToMessageDecoder {
    public typealias InboundOut = Matter

    public init() {}

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes >= Matter.headerSize else {
            return .needMoreData
        }
        guard let bodyLength = buffer.getInteger(
            at: buffer.readerIndex + 23,
            endianness: .big,
            as: UInt32.self
        ) else {
            return .needMoreData
        }
        let totalLength = Matter.headerSize + Int(bodyLength)
        guard buffer.readableBytes >= totalLength else {
            return .needMoreData
        }
        guard let frameBytes = buffer.readBytes(length: totalLength) else {
            return .needMoreData
        }
        let matter = try Matter(bytes: frameBytes)
        context.fireChannelRead(wrapInboundOut(matter))
        return .continue
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return .needMoreData
    }
}
```

- [ ] **Step 4: Extract PendingRequests to its own file**

```swift
// NMT/PendingRequests.swift
import Foundation

final class PendingRequests: @unchecked Sendable {
    private var waiting: [UUID: CheckedContinuation<Matter, Error>] = [:]
    private let lock = NSLock()

    func register(id: UUID, continuation: CheckedContinuation<Matter, Error>) {
        lock.lock()
        waiting[id] = continuation
        lock.unlock()
    }

    @discardableResult
    func fulfill(_ matter: Matter) -> Bool {
        lock.lock()
        let continuation = waiting.removeValue(forKey: matter.matterID)
        lock.unlock()
        continuation?.resume(returning: matter)
        return continuation != nil
    }

    func fail(id: UUID, error: Error) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    func failAll(error: Error) {
        lock.lock()
        let all = waiting
        waiting.removeAll()
        lock.unlock()
        for continuation in all.values {
            continuation.resume(throwing: error)
        }
    }
}
```

- [ ] **Step 5: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/NMTP/NMT/
git commit -m "add: NMTHandler protocol, codec handlers, PendingRequests"
```

---

## Task 6: Create non-generic NMTClient

**Files:**
- Create: `swift-nmtp/Sources/NMTP/NMT/NMTClient.swift`

- [ ] **Step 1: Write NMTClient without generics**

Remove `Target` generic parameter. Remove `target` property. Keep `targetAddress`, `pushes`, `request`, `fire`, `close`.

```swift
// NMT/NMTClient.swift
import Foundation
import NIO

public final class NMTClient: @unchecked Sendable {
    public let targetAddress: SocketAddress

    /// Server-push stream: unsolicited inbound Matter (no pending request match).
    public let pushes: AsyncStream<Matter>

    private let channel: Channel
    private let pendingRequests: PendingRequests
    private let pushContinuation: AsyncStream<Matter>.Continuation

    internal init(
        targetAddress: SocketAddress,
        channel: Channel,
        pendingRequests: PendingRequests,
        pushes: AsyncStream<Matter>,
        pushContinuation: AsyncStream<Matter>.Continuation
    ) {
        self.targetAddress = targetAddress
        self.channel = channel
        self.pendingRequests = pendingRequests
        self.pushes = pushes
        self.pushContinuation = pushContinuation
    }
}

// MARK: - Connect

extension NMTClient {
    public static func connect(
        to address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTClient {
        let elg = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let pendingRequests = PendingRequests()

        var cont: AsyncStream<Matter>.Continuation!
        let pushes = AsyncStream<Matter> { cont = $0 }

        let inboundHandler = NMTClientInboundHandler(
            pendingRequests: pendingRequests,
            pushContinuation: cont
        )

        let channel = try await ClientBootstrap(group: elg)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(MatterDecoder()),
                    MessageToByteHandler(MatterEncoder()),
                    inboundHandler,
                ])
            }
            .connect(to: address)
            .get()

        return NMTClient(
            targetAddress: address,
            channel: channel,
            pendingRequests: pendingRequests,
            pushes: pushes,
            pushContinuation: cont
        )
    }
}

// MARK: - Send

extension NMTClient {
    /// Fire-and-forget: send a Matter without waiting for a reply.
    public func fire(matter: Matter) {
        channel.writeAndFlush(matter, promise: nil)
    }

    /// Send a Matter and wait for a reply (matched by matterID).
    public func request(matter: Matter) async throws -> Matter {
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.register(id: matter.matterID, continuation: continuation)
            channel.writeAndFlush(matter, promise: nil)
        }
    }

    public func close() async throws {
        try await channel.close().get()
    }
}

// MARK: - NMTClientInboundHandler

private final class NMTClientInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Matter

    private let pendingRequests: PendingRequests
    private let pushContinuation: AsyncStream<Matter>.Continuation

    init(pendingRequests: PendingRequests, pushContinuation: AsyncStream<Matter>.Continuation) {
        self.pendingRequests = pendingRequests
        self.pushContinuation = pushContinuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let matter = unwrapInboundIn(data)
        if !pendingRequests.fulfill(matter) {
            pushContinuation.yield(matter)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        pendingRequests.failAll(error: NMTPError.connectionClosed)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        pendingRequests.failAll(error: error)
        context.close(promise: nil)
    }
}
```

Key changes from original:
- Removed `Target` generic parameter
- Removed `target` property
- `connect(to:as:)` becomes `connect(to:)` (no target)
- `request(envelope:)` renamed to `request(matter:)`
- `fire(envelope:)` renamed to `fire(matter:)`
- `NebulaError` replaced with `NMTPError`

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/NMTP/NMT/NMTClient.swift
git commit -m "add: non-generic NMTClient"
```

---

## Task 7: Create non-generic NMTServer

**Files:**
- Create: `swift-nmtp/Sources/NMTP/NMT/NMTServer.swift`

- [ ] **Step 1: Write NMTServer without generics**

Replace `Target: NMTServerTarget` with `NMTHandler`. Remove `target` stored property.

```swift
// NMT/NMTServer.swift
import Foundation
import Logging
import NIO

public final class NMTServer: Sendable {
    public let address: SocketAddress
    private let channel: Channel
    private let ownedEventLoopGroup: MultiThreadedEventLoopGroup?

    internal init(
        address: SocketAddress,
        channel: Channel,
        ownedEventLoopGroup: MultiThreadedEventLoopGroup?
    ) {
        self.address = address
        self.channel = channel
        self.ownedEventLoopGroup = ownedEventLoopGroup
    }
}

// MARK: - Bind

extension NMTServer {
    public static func bind(
        on address: SocketAddress,
        handler: any NMTHandler,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        let owned = eventLoopGroup == nil ? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount) : nil
        let elg = eventLoopGroup ?? owned!
        let channel = try await ServerBootstrap(group: elg)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(MatterDecoder()),
                    MessageToByteHandler(MatterEncoder()),
                    NMTServerInboundHandler(handler: handler),
                ])
            }
            .bind(to: address)
            .get()

        let boundAddress = channel.localAddress ?? address
        return NMTServer(address: boundAddress, channel: channel, ownedEventLoopGroup: owned)
    }
}

// MARK: - Listen / Stop

extension NMTServer {
    public func listen() async throws {
        try await channel.closeFuture.get()
        try await ownedEventLoopGroup?.shutdownGracefully()
    }

    public func stop() async throws {
        try await channel.close().get()
        try await ownedEventLoopGroup?.shutdownGracefully()
    }

    public func closeNow() {
        channel.close(promise: nil)
    }
}

// MARK: - NMTServerInboundHandler

private final class NMTServerInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Matter
    typealias OutboundOut = Matter

    private let handler: any NMTHandler
    private let logger = Logger(label: "nmtp.server")

    init(handler: any NMTHandler) {
        self.handler = handler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let matter = unwrapInboundIn(data)
        let channel = context.channel

        Task {
            do {
                if let reply = try await handler.handle(matter: matter, channel: channel) {
                    channel.writeAndFlush(reply, promise: nil)
                }
            } catch {
                logger.error("handler error: \(error)")
                channel.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

Key changes from original:
- Removed `Target` generic parameter
- `bind(on:target:)` becomes `bind(on:handler:)` accepting `any NMTHandler`
- `NMTServerTarget` replaced with `NMTHandler`
- Removed `target` stored property from `NMTServer`
- Logger label changed to `nmtp.server`

- [ ] **Step 2: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/NMTP/NMT/NMTServer.swift
git commit -m "add: non-generic NMTServer with NMTHandler"
```

---

## Task 8: Add Matter round-trip test

**Files:**
- Create: `swift-nmtp/Tests/NMTPTests/MatterTests.swift`

- [ ] **Step 1: Write test**

```swift
// Tests/NMTPTests/MatterTests.swift
import Testing
import Foundation
@testable import NMTP

@Test func matterSerializationRoundTrip() throws {
    let original = Matter(
        type: .call,
        flags: 0,
        matterID: UUID(),
        body: Data("hello".utf8)
    )
    let bytes = original.serialized()
    let decoded = try Matter(bytes: bytes)

    #expect(decoded.version == original.version)
    #expect(decoded.type == original.type)
    #expect(decoded.flags == original.flags)
    #expect(decoded.matterID == original.matterID)
    #expect(decoded.body == original.body)
}

@Test func matterTooShortThrows() {
    #expect(throws: NMTPError.self) {
        _ = try Matter(bytes: [0x00, 0x01])
    }
}

@Test func matterInvalidMagicThrows() {
    var bytes = [UInt8](repeating: 0, count: Matter.headerSize)
    bytes[0] = 0xFF  // wrong magic
    #expect(throws: NMTPError.self) {
        _ = try Matter(bytes: bytes)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test
```

Expected: All 3 tests pass

- [ ] **Step 3: Commit**

```bash
git add Tests/
git commit -m "test: Matter serialization round-trip"
```

---

## Task 9: Update swift-nebula Package.swift to depend on swift-nmtp

**Files:**
- Modify: `swift-nebula/Package.swift`

- [ ] **Step 1: Add swift-nmtp as local dependency, remove duplicated deps**

```swift
// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "swift-nebula",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Nebula", targets: ["Nebula"]),
    ],
    dependencies: [
        .package(path: "../swift-nmtp"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [
                .product(name: "NMTP", package: "swift-nmtp"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .testTarget(
            name: "NebulaTests",
            dependencies: ["Nebula"]),
    ]
)
```

Note: swift-nio, swift-nio-extras, MessagePacker are transitive deps via NMTP. swift-log is kept because server code uses it directly (ColorLogHandler, logger in handlers). NebulaServiceLifecycle target removed per spec.

- [ ] **Step 2: Do NOT build yet** — source files still reference old types. Build verification happens after Task 11.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "refactor: depend on swift-nmtp, remove duplicated deps"
```

---

## Task 10: Remove extracted files from swift-nebula

**Files:**
- Delete: `Sources/Nebula/Matter/` (all 4 files — now in swift-nmtp)
- Delete: `Sources/Nebula/NMT/MatterEncoder.swift`
- Delete: `Sources/Nebula/NMT/MatterDecoder.swift`
- Delete: `Sources/Nebula/NMT/NMTClient.swift`
- Delete: `Sources/Nebula/NMT/NMTClient+Astral.swift`
- Delete: `Sources/Nebula/NMT/Target/NMTClientTarget.swift`
- Delete: `Sources/Nebula/Resource/Argument.swift`
- Delete: `Sources/Nebula/Resource/ArgumentValue.swift`
- Move: `Sources/Nebula/Resource/Service.swift` → `Sources/Nebula/Astral/Stellar/Service.swift`
- Move: `Sources/Nebula/Resource/Method.swift` → `Sources/Nebula/Astral/Stellar/Method.swift`

- [ ] **Step 1: Delete extracted files**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula
rm -rf Sources/Nebula/Matter/
rm Sources/Nebula/NMT/MatterEncoder.swift
rm Sources/Nebula/NMT/MatterDecoder.swift
rm Sources/Nebula/NMT/NMTClient.swift
rm Sources/Nebula/NMT/NMTClient+Astral.swift
rm Sources/Nebula/NMT/Target/NMTClientTarget.swift
rm Sources/Nebula/Resource/Argument.swift
rm Sources/Nebula/Resource/ArgumentValue.swift
```

- [ ] **Step 2: Move Service and Method to Stellar/**

```bash
mv Sources/Nebula/Resource/Service.swift Sources/Nebula/Astral/Stellar/Service.swift
mv Sources/Nebula/Resource/Method.swift Sources/Nebula/Astral/Stellar/Method.swift
```

- [ ] **Step 3: Split UUID+extension.swift — keep UUID/Integer helpers, extract NebulaError**

The current `UUID+extension.swift` contains both `NebulaError` and UUID helpers. UUID helpers are now in swift-nmtp. Extract `NebulaError` to its own file (framework-level errors only), delete the original.

Create `Sources/Nebula/NebulaError.swift`:

```swift
// NebulaError.swift
import Foundation

public enum NebulaError: Error {
    case invalidURI(_ reason: String)
    case discoveryFailed(name: String)
    case serviceNotFound(namespace: String)
    case methodNotFound(service: String, method: String)
}
```

Note: `fail(message:)`, `invalidMatter`, `notConnected`, `connectionClosed` are now in `NMTPError` (swift-nmtp). Only framework-specific errors remain here.

```bash
rm Sources/Nebula/Resource/UUID+extension.swift
```

- [ ] **Step 4: Do NOT build yet** — imports and references still need updating. Proceed to Task 11.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove files extracted to swift-nmtp, move Service/Method to Stellar"
```

---

## Task 11: Add re-exports and update NMTServerTarget

**Files:**
- Modify: `Sources/Nebula/NMT/Target/NMTServerTarget.swift`
- Modify: `Sources/Nebula/NMT/NMTServer.swift`
- Create: `Sources/Nebula/NMT/NebulaClient.swift` (Nebula convenience wrapper over NMTClient)

- [ ] **Step 1: Update NMTServerTarget to extend NMTHandler**

```swift
// NMT/Target/NMTServerTarget.swift
import Foundation
import NIO
import NMTP

/// A Nebula server target that handles incoming Matter.
/// Bridges the NMTP protocol layer's NMTHandler to the Nebula framework.
public protocol NMTServerTarget: NMTHandler {}
```

This means all existing conformers (StandardGalaxy, ServiceStellar, StandardIngress) now conform to `NMTHandler` through `NMTServerTarget`. Their `handle(envelope:channel:)` method needs renaming to `handle(matter:channel:)`.

- [ ] **Step 2: Update NMTServer.swift to use NMTP's NMTServer**

Replace the generic `NMTServer<Target>` with a thin wrapper or re-export. Since `NMTP.NMTServer` already takes `any NMTHandler`, and `NMTServerTarget: NMTHandler`, existing targets work directly.

```swift
// NMT/NMTServer.swift
//
// NMTServer is now provided by NMTP.
// This file re-exports it and provides the NMTServerBuilder convenience.

@_exported import NMTP

// NMTServerBuilder provides the Nebula.server(with:) convenience.
public struct NMTServerBuilder: Sendable {
    public let target: any NMTServerTarget

    public func bind(
        on address: SocketAddress,
        eventLoopGroup: MultiThreadedEventLoopGroup? = nil
    ) async throws -> NMTServer {
        try await NMTServer.bind(on: address, handler: target, eventLoopGroup: eventLoopGroup)
    }
}
```

- [ ] **Step 3: Create NebulaClient.swift — Nebula convenience methods over NMTClient**

This replaces the old `NMTClient+Astral.swift` and `NMTClient<Target>` extensions. Instead of generic extensions, it wraps `NMTClient` (from NMTP) with Nebula-specific operations.

```swift
// NMT/NebulaClient.swift
import Foundation
import NIO
import NMTP

// MARK: - Result Types

public struct FindResult: Sendable {
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    public let nextAddress: SocketAddress?
}

// MARK: - Nebula Convenience on NMTClient

extension NMTClient {

    // MARK: Ingress Operations

    public func find(namespace: String) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let stellarAddress: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: stellarAddress)
    }

    public func registerGalaxy(name: String, address: SocketAddress, identifier: UUID) async throws {
        let body = RegisterBody(
            namespace: name,
            host: address.ipAddress ?? "0.0.0.0",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register Galaxy failed: \(replyBody.status)")
        }
    }

    public func register(namespace: String, address: SocketAddress, identifier: UUID) async throws {
        let body = RegisterBody(
            namespace: namespace,
            host: address.ipAddress ?? "::1",
            port: address.port ?? 0,
            identifier: identifier.uuidString
        )
        let matter = try Matter.make(type: .register, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "ok" else {
            throw NebulaError.fail(message: "Register failed: \(replyBody.status)")
        }
    }

    public func unregister(namespace: String, host: String, port: Int) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let nextAddress: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: nextAddress)
    }

    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = []
    ) async throws {
        let body = EnqueueBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let matter = try Matter.make(type: .enqueue, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "queued" else {
            throw NebulaError.fail(message: "Enqueue failed: \(replyBody.status)")
        }
    }

    public func findGalaxy(topic: String) async throws -> SocketAddress? {
        let body = FindGalaxyBody(topic: topic)
        let matter = try Matter.make(type: .findGalaxy, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(FindGalaxyReplyBody.self)
        guard let host = replyBody.galaxyHost, let port = replyBody.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }

    public func clone() async throws -> CloneReplyBody {
        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await request(matter: matter)
        return try reply.decodeBody(CloneReplyBody.self)
    }
}
```

Note: No more generic Target constraints. All methods available on every `NMTClient`. The Target-based restriction was a framework concept; at the Nebula convenience layer, trust the caller.

- [ ] **Step 4: Do NOT build yet** — entity files (StandardGalaxy, etc.) still need updating. Proceed to Task 12.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: NMTServerTarget extends NMTHandler, add NebulaClient convenience"
```

---

## Task 12: Update all server entities to use NMTP types

**Files:**
- Modify: `Sources/Nebula/Astral/Astral.swift`
- Modify: `Sources/Nebula/Astral/Galaxy/StandardGalaxy.swift`
- Modify: `Sources/Nebula/Astral/Stellar/Stellar.swift`
- Modify: `Sources/Nebula/Ingress/StandardIngress.swift`
- Modify: `Sources/Nebula/Astral/Amas/LoadBalanceAmas.swift`
- Modify: `Sources/Nebula/Astral/Amas/Amas.swift`
- Modify: `Sources/Nebula/Broker/BrokerAmas.swift`
- Modify: `Sources/Nebula/Auth/NMTMiddleware.swift`
- Modify: `Sources/Nebula/Nebula.swift`
- Modify: `Sources/Nebula/Resource/NebulaURI.swift`

This is the largest task. Changes needed across all files:

1. Add `import NMTP` to every file that uses Matter, MatterType, NMTClient, NMTServer, Argument, etc.
2. Rename `handle(envelope:channel:)` to `handle(matter:channel:)` in all NMTServerTarget conformers
3. Replace `NMTClient<GalaxyTarget>` / `NMTClient<IngressTarget>` / `NMTClient<StellarTarget>` with plain `NMTClient`
4. Replace `NMTClient.connect(to:as:)` with `NMTClient.connect(to:)`
5. Replace `request(envelope:)` with `request(matter:)`
6. Replace `fire(envelope:)` with `fire(matter:)`
7. Remove `NebulaError.fail(message:)`, `NebulaError.invalidMatter`, `NebulaError.notConnected`, `NebulaError.connectionClosed` usages — use `NMTPError` equivalents or adjust as needed
8. Remove old `NMTServerBuilder<Target>` generic — it is now non-generic in Task 11

- [ ] **Step 1: Update Astral.swift**

Add `import NMTP`. Remove `ServerAstral` requirement for `NMTServerTarget` (it now requires `NMTHandler` from NMTP, bridged via `NMTServerTarget` from Task 11).

- [ ] **Step 2: Update StandardGalaxy.swift**

Add `import NMTP`. Rename `handle(envelope:channel:)` to `handle(matter:channel:)`. Replace all internal `envelope` variable names with `matter`. Replace `NMTClient<GalaxyTarget>` with `NMTClient`.

- [ ] **Step 3: Update ServiceStellar.swift**

Add `import NMTP`. Same rename pattern. Replace `NMTClient<StellarTarget>` with `NMTClient`.

- [ ] **Step 4: Update StandardIngress.swift**

Add `import NMTP`. Same rename pattern. Replace `NMTClient<GalaxyTarget>` with `NMTClient`. Update `galaxyClient` method to use `NMTClient.connect(to:)`.

- [ ] **Step 5: Update LoadBalanceAmas.swift, Amas.swift, BrokerAmas.swift**

Add `import NMTP`. Rename envelope references if present.

- [ ] **Step 6: Update NMTMiddleware.swift**

Add `import NMTP`. Update `NMTMiddlewareNext` typealias if it uses `Matter`.

- [ ] **Step 7: Update Nebula.swift**

Add `import NMTP`. Update `Nebula.server(with:)` to return `NMTServerBuilder` (non-generic from Task 11). Update `Nebula.planet(connecting:service:)` and `Nebula.moon(connecting:service:)` to use `NMTClient.connect(to:)` (no `as:` parameter).

- [ ] **Step 8: Update NebulaURI.swift**

Add `import NMTP` if it references `NebulaError.invalidURI` — this stays in NebulaError.

- [ ] **Step 9: Update NebulaError.swift to keep only framework errors and add a bridge case**

```swift
public enum NebulaError: Error {
    case fail(message: String)
    case invalidURI(_ reason: String)
    case discoveryFailed(name: String)
    case serviceNotFound(namespace: String)
    case methodNotFound(service: String, method: String)
}
```

Keep `fail(message:)` for framework-level failures that aren't protocol errors.

- [ ] **Step 10: Verify build**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula
swift build
```

Expected: BUILD SUCCEEDED. This is the critical verification — if this passes, the server-side split is complete.

- [ ] **Step 11: Run existing tests**

```bash
swift test
```

Expected: All existing tests pass (they may need `import NMTP` added and envelope→matter renames).

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor: migrate all server entities to use NMTP types"
```

---

## Task 13: Create swift-nebula-client repo

**Files:**
- Create: `swift-nebula-client/Package.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Astral/Astral.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Astral/Planet.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Planet/RoguePlanet.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Planet/Moon.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Planet/MethodProxy.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Planet/Satellite.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Comet/Comet.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/Subscriber/Subscriber.swift`
- Create: `swift-nebula-client/Sources/NebulaClient/NMT/NebulaClient.swift`

- [ ] **Step 1: Create repo and Package.swift**

```bash
mkdir -p /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula-client
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula-client
git init
```

```swift
// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "swift-nebula-client",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NebulaClient", targets: ["NebulaClient"]),
    ],
    dependencies: [
        .package(path: "../swift-nmtp"),
    ],
    targets: [
        .target(
            name: "NebulaClient",
            dependencies: [
                .product(name: "NMTP", package: "swift-nmtp"),
            ]),
        .testTarget(
            name: "NebulaClientTests",
            dependencies: ["NebulaClient"]),
    ]
)
```

```bash
mkdir -p Sources/NebulaClient/Astral Sources/NebulaClient/Planet Sources/NebulaClient/Comet Sources/NebulaClient/Subscriber Sources/NebulaClient/NMT Tests/NebulaClientTests
```

- [ ] **Step 2: Define client-side Astral protocol and AstralCategory**

```swift
// Sources/NebulaClient/Astral/Astral.swift
import Foundation

public enum AstralCategory: UInt8, Sendable {
    case planet    = 1
    case stellar   = 2
    case galaxy    = 8
    case comet     = 3
    case satellite = 4
}

public protocol Astral: Sendable {
    static var category: AstralCategory { get }
    var identifier: UUID { get }
    var name: String { get }
    var namespace: String { get }
}

extension Astral {
    public var namespace: String { name }
}
```

This is the client's own copy, matching the Nebula spec.

- [ ] **Step 3: Define Planet protocol**

```swift
// Sources/NebulaClient/Astral/Planet.swift
import Foundation

public protocol Planet: Astral {}

extension Planet {
    public static var category: AstralCategory { .planet }
}
```

- [ ] **Step 4: Port RoguePlanet**

Copy from `swift-nebula/Sources/Nebula/Astral/Planet/Planet.swift` (the `RoguePlanet` actor). Changes needed:
- Add `import NMTP`
- Replace `NMTClient<IngressTarget>` with `NMTClient`
- Replace `NMTClient<StellarTarget>` with `NMTClient`
- Replace `NMTClient.connect(to:as:)` with `NMTClient.connect(to:)`
- Replace `request(envelope:)` with `request(matter:)`
- Replace `NebulaError` with `NMTPError` for protocol errors, or define a local `NebulaClientError`

- [ ] **Step 5: Port Moon, MethodProxy, Satellite**

Copy from originals. Add `import NMTP`. Minimal changes — these types mostly delegate to `RoguePlanet`.

- [ ] **Step 6: Port Comet**

Copy from `swift-nebula/Sources/Nebula/Astral/Comet/Comet.swift`. Changes:
- Add `import NMTP`
- Replace `NMTClient<IngressTarget>` with `NMTClient`

- [ ] **Step 7: Port Subscriber**

Copy from `swift-nebula/Sources/Nebula/Astral/Subscriber/Subscriber.swift`. Same pattern of changes.

- [ ] **Step 8: Create client-side NMT convenience**

```swift
// Sources/NebulaClient/NMT/NebulaClient.swift
import Foundation
import NIO
import NMTP

// Client-side Nebula convenience on NMTClient.
// Duplicates the subset of operations that client entities need.

public struct FindResult: Sendable {
    public let stellarAddress: SocketAddress?
}

public struct UnregisterResult: Sendable {
    public let nextAddress: SocketAddress?
}

extension NMTClient {

    public func find(namespace: String) async throws -> FindResult {
        let body = FindBody(namespace: namespace)
        let matter = try Matter.make(type: .find, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(FindReplyBody.self)
        let addr: SocketAddress? = try {
            guard let host = replyBody.stellarHost, let port = replyBody.stellarPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return FindResult(stellarAddress: addr)
    }

    public func unregister(namespace: String, host: String, port: Int) async throws -> UnregisterResult {
        let body = UnregisterBody(namespace: namespace, host: host, port: port)
        let matter = try Matter.make(type: .unregister, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(UnregisterReplyBody.self)
        let addr: SocketAddress? = try {
            guard let host = replyBody.nextHost, let port = replyBody.nextPort else { return nil }
            return try SocketAddress.makeAddressResolvingHost(host, port: port)
        }()
        return UnregisterResult(nextAddress: addr)
    }

    public func enqueue(
        namespace: String,
        service: String,
        method: String,
        arguments: [Argument] = []
    ) async throws {
        let body = EnqueueBody(
            namespace: namespace,
            service: service,
            method: method,
            arguments: arguments.toEncoded()
        )
        let matter = try Matter.make(type: .enqueue, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(RegisterReplyBody.self)
        guard replyBody.status == "queued" else {
            throw NMTPError.fail(message: "Enqueue failed: \(replyBody.status)")
        }
    }

    public func findGalaxy(topic: String) async throws -> SocketAddress? {
        let body = FindGalaxyBody(topic: topic)
        let matter = try Matter.make(type: .findGalaxy, body: body)
        let reply = try await request(matter: matter)
        let replyBody = try reply.decodeBody(FindGalaxyReplyBody.self)
        guard let host = replyBody.galaxyHost, let port = replyBody.galaxyPort else { return nil }
        return try SocketAddress.makeAddressResolvingHost(host, port: port)
    }
}
```

- [ ] **Step 9: Verify build**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula-client
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "init: swift-nebula-client with Planet, Comet, Subscriber"
```

---

## Task 14: Remove client entities from swift-nebula

**Files:**
- Delete: `swift-nebula/Sources/Nebula/Astral/Planet/` (entire directory)
- Delete: `swift-nebula/Sources/Nebula/Astral/Comet/`
- Delete: `swift-nebula/Sources/Nebula/Astral/Subscriber/`
- Modify: `swift-nebula/Sources/Nebula/Nebula.swift` (remove planet/moon factory methods)

- [ ] **Step 1: Delete client entity directories**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula
rm -rf Sources/Nebula/Astral/Planet/
rm -rf Sources/Nebula/Astral/Comet/
rm -rf Sources/Nebula/Astral/Subscriber/
```

- [ ] **Step 2: Remove client factory methods from Nebula.swift**

Remove `Nebula.planet(connecting:service:)` and `Nebula.moon(connecting:service:)`. Keep `Nebula.server(with:)`.

- [ ] **Step 3: Verify build**

```bash
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run tests**

```bash
swift test
```

Expected: Tests pass (any client-specific tests will have been removed or will fail — remove them).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove client entities (now in swift-nebula-client)"
```

---

## Task 15: Update demo to use split packages

**Files:**
- Modify: `swift-nebula/samples/demo/Package.swift`
- Modify: `swift-nebula/samples/demo/Sources/Client/main.swift`
- Modify: `swift-nebula/samples/demo/Sources/CometDemo/main.swift`
- Modify: `swift-nebula/samples/demo/Sources/SatelliteDemo/main.swift`

- [ ] **Step 1: Update demo Package.swift**

Add `swift-nebula-client` as a dependency. Client targets depend on `NebulaClient` instead of `Nebula`.

- [ ] **Step 2: Update Client/main.swift**

Replace `import Nebula` with `import NebulaClient` and `import NMTP`. Update API calls to match non-generic NMTClient.

- [ ] **Step 3: Update CometDemo/main.swift**

Replace `import Nebula` with `import NebulaClient` and `import NMTP`. Replace `NMTClient.connect(to:as:)` with `NMTClient.connect(to:)`.

- [ ] **Step 4: Update SatelliteDemo/main.swift**

Same pattern as CometDemo.

- [ ] **Step 5: Update server demos (Ingress, Galaxy, Stellar)**

Add `import NMTP` where needed. Update `handle(envelope:channel:)` references to `handle(matter:channel:)`.

- [ ] **Step 6: Verify demo builds**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula/samples/demo
swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
cd /Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula
git add samples/demo/
git commit -m "refactor: update demo to use split packages"
```

---

## Summary

| Task | Repo | Description |
|------|------|-------------|
| 1 | swift-nmtp | Package skeleton |
| 2 | swift-nmtp | NMTPError + UUID extensions |
| 3 | swift-nmtp | Matter types |
| 4 | swift-nmtp | Argument / ArgumentValue |
| 5 | swift-nmtp | NMTHandler + codec + PendingRequests |
| 6 | swift-nmtp | Non-generic NMTClient |
| 7 | swift-nmtp | Non-generic NMTServer |
| 8 | swift-nmtp | Tests |
| 9 | swift-nebula | Update Package.swift |
| 10 | swift-nebula | Remove extracted files |
| 11 | swift-nebula | NMTServerTarget + NebulaClient convenience |
| 12 | swift-nebula | Update all entities |
| 13 | swift-nebula-client | Full client package |
| 14 | swift-nebula | Remove client entities |
| 15 | swift-nebula | Update demo |
