# =============================================================================
# Build Stage — download and prepare binaries
# =============================================================================
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    tar \
    && rm -rf /var/lib/apt/lists/*

# --- Bento v1.4.0 binaries ---
RUN mkdir -p /opt/bento/bin && \
    curl -fSL https://github.com/boundless-xyz/boundless/releases/download/bento-v1.4.0/bento-bundle-linux-amd64.tar.gz \
    | tar -xz -C /opt/bento/bin --strip-components=1

# --- bento-bench (latest commit-hash release: main-d9fd108) ---
RUN mkdir -p /opt/bento/bin/bento-bench && \
    curl -fSL https://github.com/zerokrab/bento-bench/releases/download/main-d9fd108/bento-bench \
    -o /opt/bento/bin/bento-bench/bento-bench && \
    chmod +x /opt/bento/bin/bento-bench/bento-bench

# --- MinIO server + client ---
RUN curl -fSL https://dl.min.io/server/minio/release/linux-amd64/minio \
    -o /usr/local/bin/minio && \
    chmod +x /usr/local/bin/minio && \
    curl -fSL https://dl.min.io/client/mc/release/linux-amd64/mc \
    -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# =============================================================================
# Artifact Build Stage — optionally bake risc0 artifacts into image (5-8 GB)
# Controlled by build arg: --build-arg BAKE_ARTIFACTS=true (default) or false
# =============================================================================
FROM ubuntu:24.04 AS artifact-builder

ARG BAKE_ARTIFACTS=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    xz-utils \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$BAKE_ARTIFACTS" = "true" ]; then \
        echo "Fetching groth16 artifacts..." && \
        mkdir -p /opt/bento/artifacts/groth_16 && \
        curl -fSL "https://hancho-worker.cloudflare-y513l.workers.dev/artifacts/groth16_artifacts.tar.zst" \
        | tar --zstd -x -C /opt/bento/artifacts/groth_16 --strip-components=1;  \
    else \
        echo "Skipping groth_16 artifact download (BAKE_ARTIFACTS=false)"; \
    fi

RUN if [ "$BAKE_ARTIFACTS" = "true" ]; then \
        echo "Fetching blake3_groth16 artifacts..." && \
        mkdir -p /opt/bento/artifacts/groth_16 /opt/bento/artifacts/blake3_groth16 && \
        curl -fSL "https://staging-signal-artifacts.beboundless.xyz/v3/proving/blake3_groth16_artifacts.tar.xz" \
        | tar -xJ -C /opt/bento/artifacts/blake3_groth16 --strip-components=1; \
    else \
        echo "Skipping blake3_groth16 artifact download (BAKE_ARTIFACTS=false)"; \
    fi

# =============================================================================
# Final Stage — runtime image
# =============================================================================
FROM nvidia/cuda:12.9.1-runtime-ubuntu24.04

# Environment defaults
ENV BENTO_BIN_DIR=/opt/bento/bin \
    BENTO_ARTIFACTS_DIR=/opt/bento/artifacts \
    RISC0_HOME=/opt/bento/artifacts/groth_16 \
    BLAKE3_GROTH16_SETUP_DIR=/opt/bento/artifacts/blake3_groth16 \
    DATABASE_URL=postgresql://bento:bento@localhost:5432/taskdb \
    REDIS_URL=redis://localhost:6379 \
    S3_ENDPOINT=http://localhost:9000 \
    S3_BUCKET=workflow \
    S3_ACCESS_KEY=minioadmin \
    S3_SECRET_KEY=minioadmin \
    S3_REGION=auto \
    BENTO_API_URL=http://localhost:8081 \
    REST_API_PORT=8081 \
    REDIS_PORT=6379 \
    RUST_LOG=info \
    RUST_BACKTRACE=1 \
    PATH="/opt/bento/bin:/opt/bento/bin/bento-bench:${PATH}"

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-16 \
    redis-server \
    curl \
    ca-certificates \
    gettext-base \
    xz-utils \
    zstd \
    util-linux \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries from builder
COPY --from=builder /opt/bento/bin /opt/bento/bin
COPY --from=builder /usr/local/bin/minio /usr/local/bin/minio
COPY --from=builder /usr/local/bin/mc /usr/local/bin/mc

# Copy baked artifacts from artifact-builder (only if BAKE_ARTIFACTS=true)
COPY --from=artifact-builder /opt/bento/artifacts /opt/bento/artifacts

# Copy scripts and entrypoint
COPY scripts/ /scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
