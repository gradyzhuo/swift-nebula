# Nebula Demo

A minimal example demonstrating the full Nebula stack: Ingress, Galaxy, Amas, Stellar, and Planet.

## Architecture

```
Server process                          Client process
┌──────────────────────────────┐        ┌──────────────────────┐
│  Ingress (:22400)            │        │  Planet              │
│    └── Galaxy "production"   │  ◄──── │    connects via URI  │
│          └── Amas "ml"       │        │    calls w2v service │
│                └── Stellar   │        └──────────────────────┘
│                     "Embedding"
│                      └── Service "w2v"
│                           └── Method "wordVector"
└──────────────────────────────┘
```

## Running

### 1. Start the server

```bash
cd samples/demo
swift run Server
```

Output:
```
Starting Nebula demo (Ctrl+C to stop)...
```

### 2. Run the client (in another terminal)

```bash
cd samples/demo
swift run Client
```

Output:
```
Result: [0.1, 0.2, 0.3]
```

## How it works

### Server (`Sources/Server/main.swift`)

1. Binds **Ingress** on `[::1]:22400`
2. Binds **Galaxy** `"production"` on a dynamic port, registers with Ingress
3. Binds **Stellar** `"Embedding"` (namespace `production.ml.embedding`) on port 7000, registers with Galaxy
4. Galaxy automatically creates a **LoadBalanceAmas** for the namespace
5. All servers run together via `ServiceGroup` with graceful shutdown on Ctrl+C

### Client (`Sources/Client/main.swift`)

1. Creates a **Planet** using the connection URI `nmtp://[::1]:22400/production/ml/embedding`
2. The URI path segments (`production/ml/embedding`) map to the namespace `production.ml.embedding`
3. Planet connects to Ingress, discovers the Stellar, then calls `w2v.wordVector` directly

### Connection URI

```
nmtp://[::1]:22400/production/ml/embedding
       └─────────┘ └────────┘ └┘ └───────┘
       Ingress      Galaxy    Amas Stellar
```
