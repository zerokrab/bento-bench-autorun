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

# --- bento-bench (latest commit-hash release: main-1401c2e) ---
# v1.0.0 has not been released yet; using the latest available build as fallback.
# Replace with v1.0.0 release URL once published:
#   https://github.com/zerokrab/bento-bench/releases/download/v1.0.0/bento-bench-linux-amd64.tar.gz
RUN mkdir -p /opt/bento/bin/bento-bench && \
    curl -fSL https://github.com/zerokrab/bento-bench/releases/download/main-1401c2e/bento-bench \
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
# COMMENTED OUT — Future Build Stage for baking in risc0 artifacts
# =============================================================================
# Uncomment when ready to bake artifacts into the image (5-8 GB).
# This avoids runtime fetching but dramatically increases image size.
#
# FROM ubuntu:24.04 AS artifact-builder
# RUN mkdir -p /opt/bento/artifacts && \
#     curl -fSL <URL_TO_RISC0_GROTH16_ARTIFACTS> | tar -xz -C /opt/bento/artifacts && \
#     curl -fSL <URL_TO_BLAKE3_GROTH16_ARTIFACTS> | tar -xz -C /opt/bento/artifacts

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
    && rm -rf /var/lib/apt/lists/*

# Copy binaries from builder
COPY --from=builder /opt/bento/bin /opt/bento/bin
COPY --from=builder /usr/local/bin/minio /usr/local/bin/minio
COPY --from=builder /usr/local/bin/mc /usr/local/bin/mc

# Copy scripts and entrypoint
COPY scripts/ /scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /scripts/*.sh

# Create artifacts directory (populated at runtime via init-artifacts.sh)
RUN mkdir -p /opt/bento/artifacts

ENTRYPOINT ["/entrypoint.sh"]