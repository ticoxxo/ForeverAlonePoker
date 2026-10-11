# Build and run the PokerServer on Linux. Build context must be the repo root
# so the local PokerCore and SkinKit packages are available:
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
# Development skin catalog (tdr/0012). In production mount the published
# skins over it, or point the manifest's assetBaseURL at a CDN, and pass
# CATALOG_SIGNING_KEY as a secret.
COPY Server/SkinAssets ./SkinAssets
ENV HOST=0.0.0.0 PORT=8080 SKINS_DIR=/app/SkinAssets
EXPOSE 8080
ENTRYPOINT ["./PokerServer"]
