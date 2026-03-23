import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

// MARK: - Ingress

let ingressAddress = try SocketAddress(ipAddress: "::1", port: 22400)
let ingress = StandardIngress(name: "ingress")
let ingressServer = try await Nebula.server(with: ingress).bind(on: ingressAddress)

// MARK: - Galaxy

let galaxy = StandardGalaxy(name: "production")
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: "::1", port: 0))  // dynamic port

// Register Galaxy with Ingress
let ingressClient = try await NMTClient.connect(to: ingressAddress, as: .ingress)
try await ingressClient.registerGalaxy(
    name: "production",
    address: galaxyServer.address,
    identifier: galaxy.identifier
)

// MARK: - Stellar

let stellar = makeStellar()  // defined in StellarSetup.swift
let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let stellarServer = try await Nebula.server(with: stellar).bind(on: stellarAddress)

// Register with Galaxy — LoadBalanceAmas is created automatically
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

// MARK: - Run all services

let logger = Logger(label: "nebula-demo")

let serviceGroup = ServiceGroup(
    services: [
        ingressServer,
        galaxyServer,
        stellarServer,
    ],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Starting Nebula demo (Ctrl+C to stop)...")
try await serviceGroup.run()
