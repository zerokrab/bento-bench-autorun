# bento-bench-autorun

Automated environment for running `bento-bench` benchmarks. This repository provides a Dockerized setup that orchestrates all necessary services and agents required to execute the benchmark suite.

## Prerequisites

- **Docker**: Installed and running.
- **NVIDIA Driver & Container Toolkit**: Required for GPU acceleration.
- **Supported Hardware**: NVIDIA GPU.

## Build

Build the Docker image using the provided Dockerfile:

```bash
docker build -t bento-bench-autorun .
```

The build uses a multi-stage `Dockerfile`:
1. **Builder stage** — downloads bento binaries (v1.4.0), bento-bench, and MinIO server/client.
2. **Final stage** — based on `nvidia/cuda:12.9.1-runtime-ubuntu24.04`, installs system packages (PostgreSQL 16, Redis), copies binaries from the builder, and sets the entrypoint.

## Run

To run a benchmark suite, use the following command:

```bash
docker run --rm --gpus all \
  -e BENCH_SUITE=<suite-url> \
  bento-bench-autorun
```

Replace `<suite-url>` with the URL of the benchmark suite tarball (e.g. `https://boundless-benchmarks.example.com/suites/suite-og-4-1m-10m.tar.zst`).

### Execution Flow

When the container starts, it performs the following steps automatically:

1. **System Specs Logging** (`log-specs.sh`) — Logs CPU, memory, OS, disk, and GPU specifications to stdout for benchmark reproducibility and environment comparison.
2. **GPU Detection** (`detect-gpu.sh`) — Verifies NVIDIA GPU availability and sets `GPU_COUNT` and `SEGMENT_SIZE` based on the detected hardware.
3. **Artifact Initialization** (`init-artifacts.sh`) — Fetches risc0 proving artifacts (groth16 and blake3_groth16) if not already present. Detects baked-in artifacts by checking for `settings.toml` and `verify_for_guest_final.zkey` sentinel files. Skipped when `SKIP_R0_INIT=true`.
4. **Service Setup** (`init-services.sh`) — Starts PostgreSQL, Redis, and MinIO. The S3 bucket is created automatically if it does not exist.
5. **Agent Startup** (`init-agents.sh`) — Launches the REST API, aux agent, exec agents (1 per GPU), and prove agents (1 per GPU). Waits for the REST API to become healthy before proceeding.
6. **Benchmark Execution** (`run-bench.sh`) — Runs the specified `BENCH_SUITE` via `bento-bench`. The container exits with the benchmark's exit code.
7. **Cleanup** — On exit or signal, the entrypoint shuts down all services and agents gracefully.

A background watchdog monitors all service PIDs and terminates the container if any service crashes.

## Configuration

Configure the environment using the following variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `BENCH_SUITE` | URL of the benchmark suite tarball to run | N/A | Yes |
| `CHECK_TASKDB` | Enable database check if set to `true` | `false` | No |
| `BENCH_JSON` | Path for structured JSON output | N/A | No |
| `S3_BUCKET` | Name of the S3 bucket | `workflow` | No |
| `S3_ACCESS_KEY` | MinIO access key | `minioadmin` | No |
| `S3_SECRET_KEY` | MinIO secret key | `minioadmin` | No |
| `S3_ENDPOINT` | MinIO endpoint URL | `http://localhost:9000` | No |
| `S3_REGION` | S3 region | `auto` | No |
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://bento:bento@localhost:5432/taskdb` | No |
| `REDIS_URL` | Redis connection string | `redis://localhost:6379` | No |
| `REDIS_PORT` | Redis port | `6379` | No |
| `SKIP_R0_INIT` | Skip fetching risc0 artifacts if `true` | `false` | No |
| `REST_API_PORT` | Port for the bento REST API | `8081` | No |
| `SEGMENT_SIZE` | segment-po2 value for exec agents (auto-detected by GPU model if unset) | auto | No |
| `EXEC_AGENTS` | Number of exec agents to start (defaults to 1 per GPU) | `GPU_COUNT` | No |
| `STORAGE_ROOT` | Base storage directory | `/storage` | No |