import Foundation
import NIO
import NebulaClient

// Satellite Demo — broker subscriber
//
// Subscribes to "production.orders" under subscription group "fulfillment".
// Prints each event received from Galaxy push.
// Run after Ingress and Galaxy are up, before or alongside CometDemo.
//
// Usage:
//   INGRESS_HOST=127.0.0.1 INGRESS_PORT=6224 swift run SatelliteDemo

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "6224")!

let ingressAddress = try SocketAddress.makeAddressResolvingHost(ingressHost, port: ingressPort)
let ingressClient = try await IngressClient.connect(to: ingressAddress)

print("[Subscriber] Connecting to Ingress ...")
print("[Subscriber] Finding Galaxy for production.orders ...")

let subscriber = try await Subscriber(
    ingressClient: ingressClient,
    topic: "production.orders",
    subscription: "fulfillment"
)

print("[Subscriber] Subscribed. Waiting for events ...")

for await event in await subscriber.events {
    let dict = event.arguments.toArguments().toDictionary()
    let args = dict.map { "\($0.key)=\($0.value.map { "\($0)" } ?? "nil")" }.sorted()
    print("[Subscriber] \(event.service).\(event.method)(\(args.joined(separator: ", ")))")
}
