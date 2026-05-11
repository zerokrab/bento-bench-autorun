# bento-bench-autorun

A containerized environment for running [Bento](https://github.com/boundless-xyz/boundless) benchmarks autonomously.

The container bundles PostgreSQL, Redis, MinIO, and all Bento agent processes (REST API, Aux, Exec, Prove) into a single image. On startup it initializes every service, waits for readiness, runs the benchmark, and exits with the benchmark's exit code — making it suitable for both interactive use and CI pipelines.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/dgx/nvidia-container-toolkit/index.html) (required for GPU acceleration)

> **Note:** The runtime image is based on `nvidia/cuda:12.9.1-runtime-ubuntu24.04` and requires NVIDIA GPU drivers on the host.

## Installation & Build

Build the image from the root of the repository:

```bash
docker build -t bento-bench-autorun .
```

The build uses a multi-stage `Dockerfile`:
1. **Builder stage** — downloads bento binaries (v1.4.0), bento-bench, and MinIO server/client.
2. **Final stage** — based on `nvidia/cuda:12.9.1-runtime-ubuntu24.04`, installs system packages (PostgreSQL 16, Redis), copies binaries from the builder, and sets the entrypoint.

## Running a Benchmark

You must specify the `BENCH_SUITE` environment variable — it tells the container which benchmark suite to run.

### Basic Execution

```bash
docker run --rm --gpus all \
  -e BENCH_SUITE=your-suite-name \
  bento-bench-autorun
```

### With Structured JSON Output

```bash
docker run --rm --gpus all \
  -e BENCH_SUITE=your-suite-name \
  -e BENCH_JSON=/storage/results.json \
  bento-bench-autorun
```

### With Task DB Verification

```bash
docker run --rm --gpus all \
  -e BENCH_SUITE=your-suite-name \
  -e CHECK_TASKDB=true \
  bento-bench-autorun
```

### Skipping Artifact Download

If risc0 proving artifacts are already baked into the image or present in a mounted volume, skip the startup download:

```bash
docker run --rm --gpus all \
  -e BENCH_SUITE=your-suite-name \
  -e SKIP_R0_INIT=true \
  bento-bench-autorun
```

### Persisting Results

Mount a host directory to preserve benchmark output and service data:

```bash
docker run --rm --gpus all \
  -v /path/to/results:/storage \
  -e BENCH_SUITE=your-suite-name \
  -e BENCH_JSON=/storage/results.json \
  bento-bench-autorun
```

## Configuration Options

All configuration is done via environment variables. The following tables list every tunable variable:

### Benchmark

| Variable | Description | Default | Required |
| --- | --- | --- | --- |
| `BENCH_SUITE` | Benchmark suite name or URL to run | N/A | Yes |
| `CHECK_TASKDB` | If `true`, pass `--check-taskdb` flag to bento-bench | `false` | No |
| `BENCH_JSON` | Path for structured JSON output (`--json` flag) | N/A | No |

### Service Ports

| Variable | Description | Default |
| --- | --- | --- |
| `REST_API_PORT` | Port for the bento REST API | `8081` |
| `REDIS_PORT` | Redis server port | `6379` |

### Storage

| Variable | Description | Default |
| --- | --- | --- |
| `STORAGE_ROOT` | Base directory for all persistent data | `/storage` |
| `S3_BUCKET` | MinIO bucket name | `workflow` |
| `S3_ACCESS_KEY` | MinIO root user | `minioadmin` |
| `S3_SECRET_KEY` | MinIO root password | `minioadmin` |
| `S3_ENDPOINT` | MinIO endpoint URL | `http://localhost:9000` |
| `S3_REGION` | S3 region | `auto` |

### GPU & Agents

| Variable | Description | Default |
| --- | --- | --- |
| `GPU_COUNT` | Number of GPUs (auto-detected via `nvidia-smi`) | auto |
| `SEGMENT_SIZE` | Segment `po2` value for exec agents (auto-detected by GPU model) | auto |
| `EXEC_AGENTS` | Number of exec agent processes (default: 1 per GPU) | `${GPU_COUNT}` |

### Artifacts

| Variable | Description | Default |
| --- | --- | --- |
| `SKIP_R0_INIT` | Set to `true` to skip risc0 artifact download at startup | `false` |
| `BENTO_ARTIFACTS_DIR` | Directory for risc0 proving artifacts | `/opt/bento/artifacts` |
| `GROTH16_ARTIFACTS_URL` | Override URL for groth16 artifact archive | *(built-in default)* |
| `BLAKE3_ARTIFACTS_URL` | Override URL for blake3 groth16 artifact archive | *(built-in default)* |

### Database

| Variable | Description | Default |
| --- | --- | --- |
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://bento:***@localhost:5432/taskdb` |
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379` |

### Logging

| Variable | Description | Default |
| --- | --- | --- |
| `RUST_LOG` | Rust log level for Bento binaries | `info` |
| `RUST_BACKTRACE` | Enable Rust backtraces | `1` |

## Startup Sequence

When the container starts, it runs the following steps in order:

1. **GPU detection** — queries `nvidia-smi` for GPU count and sets `SEGMENT_SIZE` based on GPU model
2. **Artifact fetch** — downloads risc0 proving artifacts (unless `SKIP_R0_INIT=true`); skipped if artifacts already present
3. **Service startup** — initializes and starts PostgreSQL, Redis, and MinIO; S3 bucket is created automatically
4. **Agent startup** — starts REST API, Aux agent, Exec agents (1 per GPU), and Prove agents (1 per GPU); waits for REST API health check
5. **Watchdog** — background loop monitoring all service PIDs; kills the container if any process crashes
6. **Readiness check** — polls the REST API `/health` endpoint until it returns 200
7. **Benchmark** — runs `bento-bench run --fetch $BENCH_SUITE` and captures exit code
8. **Cleanup** — graceful shutdown of all services and agents, container exits with benchmark exit code

## Project Structure

```
.
├── Dockerfile          # Multi-stage build (builder + nvidia/cuda runtime)
├── entrypoint.sh       # Orchestrates startup, watchdog, and cleanup
├── scripts/
│   ├── detect-gpu.sh   # Auto-detect GPU count and segment size
│   ├── init-artifacts.sh  # Fetch risc0 proving artifacts
│   ├── init-services.sh   # Start PostgreSQL, Redis, MinIO
│   ├── init-agents.sh     # Start REST API, Aux, Exec, Prove agents
│   ├── run-bench.sh        # Invoke bento-bench with configured options
│   ├── start-postgres.sh  # Initialize and start PostgreSQL cluster
│   └── wait-for-ready.sh  # Poll REST API until healthy
└── .github/workflows/
    ├── docker.yml      # Docker build and push workflow
    └── test.yml         # GPU smoke test workflow
```

## License

This project is provided as-is. See individual Bento component licenses at [boundless-xyz/boundless](https://github.com/boundless-xyz/boundless).