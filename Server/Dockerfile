# Build and run the PokerServer on Linux. Build context must be the repo root
# so the local PokerCore package is available:
#   docker build -f Server/Dockerfile -t pokerserver .
#   docker run -p 8080:8080 pokerserver

FROM swift:6.0-noble AS build
WORKDIR /workspace
COPY Packages ./Packages
COPY Server ./Server
WORKDIR /workspace/Server
RUN swift build -c release --static-swift-stdlib

FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /workspace/Server/.build/release/PokerServer ./PokerServer
ENV HOST=0.0.0.0 PORT=8080
EXPOSE 8080
ENTRYPOINT ["./PokerServer"]
