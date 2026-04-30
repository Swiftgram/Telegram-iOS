# syntax=docker/dockerfile:1
# Multi-stage build for tgcalls_cli Linux container
# Build: docker build -t tgcalls-test .
# Run:   docker run tgcalls-test --mode reflector --reflector 91.108.13.2:598 --duration 10

# ============================================================
# Stage 1: Build
# ============================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ cmake meson ninja-build nasm make \
    autoconf automake libtool pkg-config python3 \
    unzip curl ca-certificates patch \
    zlib1g-dev libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy source tree
COPY . .

# Always download Bazel for the container's architecture (host copy may be wrong arch)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then BAZEL_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then BAZEL_ARCH="arm64"; \
    else echo "Unsupported arch: $ARCH" && exit 1; fi && \
    curl -fL "https://github.com/bazelbuild/bazel/releases/download/8.4.2/bazel-8.4.2-linux-${BAZEL_ARCH}" \
      -o build-input/bazel-8.4.2-linux && \
    chmod +x build-input/bazel-8.4.2-linux

# Build with persistent Bazel cache
RUN --mount=type=cache,target=/root/.cache/bazel \
    ./build-input/bazel-8.4.2-linux build //tools/tgcalls_cli:tgcalls_cli \
      --strategy=Genrule=standalone --spawn_strategy=standalone && \
    cp bazel-bin/tools/tgcalls_cli/tgcalls_cli /tmp/tgcalls_cli

# ============================================================
# Stage 2: Runtime (minimal)
# ============================================================
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /tmp/tgcalls_cli /usr/local/bin/tgcalls_cli

ENTRYPOINT ["tgcalls_cli"]
CMD ["--help"]
