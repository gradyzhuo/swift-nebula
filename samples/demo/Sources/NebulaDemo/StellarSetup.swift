//
//  StellarSetup.swift
//
//  Stellar and Service setup is isolated in this file so that
//  `Service` (Nebula) does not conflict with `Service` (ServiceLifecycle).
//

import Nebula
import MessagePacker

func makeStellar() -> ServiceStellar {
    let stellar = ServiceStellar(name: "Embedding", namespace: "embedding.ml.production")

    let w2v = Service(name: "w2v")
    w2v.add(method: "wordVector") { args in
        print("[Stellar] wordVector called with:", args.toDictionary())
        let result = ["vector": [0.1, 0.2, 0.3]]
        return try MessagePackEncoder().encode(result)
    }
    stellar.add(service: w2v)

    return stellar
}
