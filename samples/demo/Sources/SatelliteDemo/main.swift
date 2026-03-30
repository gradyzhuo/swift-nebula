import Foundation
import NIO
import Nebula

// Satellite Demo — broker subscriber
//
// Subscribes to "production.orders" under subscription group "fulfillment".
// Prints each event received from Galaxy push.
// Run after Ingress and Galaxy are up, before or alongside CometDemo.
//
// Usage:
//   INGRESS_HOST=127.0.0.1 INGRESS_PORT=2240 swift run SatelliteDemo

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "2240")!

let ingressAddress = try SocketAddress.makeAddressResolvingHost(ingressHost, port: ingressPort)
let ingressClient = try await NMTClient.connect(to: ingressAddress, as: .ingress)

print("[Subscriber] Subscribing to production.orders (group: fulfillment) ...")

let subscriber = try await Subscriber(
    ingressClient: ingressClient,
    topic: "production.orders",
    subscription: "fulfillment"
)

print("[Subscriber] Subscribed. Waiting for events ...")

for await event in await subscriber.events {
    let args = event.arguments.map { "\($0.key)=\(String(data: $0.value, encoding: .utf8) ?? "?")" }
    print("[Subscriber] \(event.service).\(event.method)(\(args.joined(separator: ", ")))")
}
