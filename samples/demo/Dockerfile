# Build stage
FROM swift:6.0 AS builder
WORKDIR /swift-nebula
COPY . .
WORKDIR /swift-nebula/samples/demo
RUN swift build -c release

# Runtime stage
FROM swift:6.0-slim
COPY --from=builder /swift-nebula/samples/demo/.build/release/Ingress /usr/local/bin/
COPY --from=builder /swift-nebula/samples/demo/.build/release/Galaxy /usr/local/bin/
COPY --from=builder /swift-nebula/samples/demo/.build/release/Stellar /usr/local/bin/
COPY --from=builder /swift-nebula/samples/demo/.build/release/Client /usr/local/bin/
