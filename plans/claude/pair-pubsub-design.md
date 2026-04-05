# Pair（Pub/Sub）功能設計討論

這份文件整理了原本 Nebula 專案中 Pair 機制的設計現狀，供新 session 繼續討論實作方向。

---

## 背景

原本的 Nebula 專案（`/Users/gradyzhuo/Dropbox/workspace/Framework/Nebula`）中已有 Pair 的雛形，
但從未完整實作。swift-nebula 重構時整個捨棄，現在要重新設計。

---

## 原本有什麼

### Matter 層（已有定義）

**`MatterActivity`（`0xd1`）**：
```swift
case pair = 0xd1
```

**`Pair.swift`**（Matter 類型）：
```swift
public enum Pair: UInt8 {
    case reply     = 0x00
    case stellaire = 0x01   // 訂閱請求
}

public struct PairMatter {
    // 包含 service_name
}
```

**Protobuf 定義（`matter.proto`）**：
```proto
message PairBody {
    string service_name = 2;
}

message PairReplyBody {
    // 空的，尚未設計
}
```

**`MatterHandleable`**：Pair 已在 dispatch switch 中有 case，但 `handle(context:matter:PairMatter)` 預設回傳 `.unhandled`。

### Nebula facade（只有 stub，已被 comment out）
```swift
// public func pair(namespace: String) -> Planet { ... }
// public func push(event: String, data: Data) -> Planet { ... }
// public func pull(event: String) -> Planet { ... }
```

---

## 原本的設計意圖

從命名和 stub 推測原本想法：
- `pair` → 建立一條訂閱連線（client 訂閱某個 namespace/service 的 event）
- `push` → server 端推送 event 給訂閱者
- `pull` → client 主動拉取 event

這是一個基礎的 **pub/sub over NMT** 機制，讓 Nebula 不只是 request/reply RPC，也能做 event-driven 通訊。

---

## 在 swift-nebula 的現狀

swift-nebula（`/Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nebula`）目前：

- **沒有 Pair**：`MatterType` enum 沒有 `.pair` case
- **只有 request/reply**：`NMTClient` 用 UUID 匹配 reply，是一對一的同步模型
- **沒有 server push**：`NMTServer` 只被動接收，沒有主動推送機制

---

## 需要討論的設計問題

### 1. 連線模型
Pair 要用獨立長連線（一條 TCP 連線專門訂閱），還是複用現有的 NMTClient 連線？

### 2. 訂閱對象是誰？
- 訂閱 Stellar 直接推送的 event？
- 還是透過 Galaxy/Ingress 做 event routing？

### 3. 傳遞方向
- **Client → Server**：`pair`（訂閱）、`pull`（拉取）
- **Server → Client**：`push`（推送）
- Server push 在 NIO pipeline 上需要額外的 outbound handler，目前架構沒有

### 4. API 設計
希望的使用方式是什麼？例如：
```swift
// Option A：AsyncSequence
for await event in moon.on("orderUpdated") { ... }

// Option B：closure callback
moon.on("orderUpdated") { data in ... }

// Option C：actor-based
let stream = try await Nebula.subscribe(namespace: "orders", event: "updated")
```

### 5. 與現有 Moon/Satellite 的關係
Pair 是 Satellite 的一種延伸（`moon.on(...)`），還是獨立的 Astral 角色（新的 `Comet`？）？

---

## 現有架構參考

```
swift-nebula 目前的 Matter types（MatterType enum）：
- clone, register, find, call, reply, activate, heartbeat, unregister

需要新增：
- pair（訂閱請求）
- 可能需要新的 push 類型（server → client 單向）
```

關鍵檔案：
- `Sources/Nebula/Matter/Matter.swift` — MatterType enum，需加 `.pair`
- `Sources/Nebula/NMT/NMTClient.swift` — 目前只支援 request/reply
- `Sources/Nebula/NMT/NMTServer.swift` — 需要主動 push 能力
- `Sources/Nebula/Astral/Planet/Moon.swift` — 可能的 API 入口
