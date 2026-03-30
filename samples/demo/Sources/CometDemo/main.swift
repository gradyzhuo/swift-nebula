import Foundation
import NIO
import Nebula

// Comet Demo — async producer
//
// Sends 5 "order.placed" events into the broker namespace "production.orders".
// Run after Ingress and Galaxy are up.
//
// Usage:
//   INGRESS_HOST=127.0.0.1 INGRESS_PORT=2240 swift run CometDemo

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "2240")!

let ingressAddress = try SocketAddress.makeAddressResolvingHost(ingressHost, port: ingressPort)
let ingressClient = try await NMTClient.connect(to: ingressAddress, as: .ingress)

let comet = Comet(
    ingressClient: ingressClient,
    namespace: "production.orders"
)

print("[Comet] Sending 5 orders to production.orders ...")

for i in 1...5 {
    try await comet.enqueue(
        service: "orderService",
        method: "process",
        arguments: [
            try .wrap(key: "orderID", value: "ORD-\(1000 + i)"),
            try .wrap(key: "amount",  value: Double(i) * 9.99),
        ]
    )
    print("[Comet] Enqueued order ORD-\(1000 + i)")
}

print("[Comet] Done.")
