# ============================================================
# MBOpenClacky - Multi-stage Dockerfile
# AI Agent CLI tool rewritten in MoonBit
# ============================================================

# ── Stage 1: Build ──────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies.
# libssl-dev provides libcrypto for the brand package's AES-256-GCM /
# RAND_bytes C stubs (linked via -lcrypto in cmd/moon.pkg & lib/brand/moon.pkg).
# nodejs is required because moon.mod declares
# `"--moonbit-unstable-prebuild": "build-script.js"`, a Node.js script that
# injects `-lcrypto` link config into lib/brand & lib/web at pre-build time.
# Without node in PATH, `moon build` aborts with:
#   "Running prebuild script for module hnlyxiaobing/MBOpenClacky needs `node` executable in PATH"
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    make \
    curl \
    ca-certificates \
    git \
    libssl-dev \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install MoonBit toolchain (use latest stable; pinned versions are not retained on CDN).
#
# TOOLCHAIN_CACHE_BUSTER invalidates this layer (and every layer after it) so
# the build pulls the *current* `latest` toolchain instead of reusing one
# cached by a previous build. Without it, GHA layer caching can pin a stale
# toolchain for days: the 2026-08-28 build failed because a cached older
# toolchain rejected async@0.21.1's `errdefer close(...)` (error 4174:
# "calling function with error is not allowed inside `errdefer`") even though
# the then-current toolchain compiled it fine. The workflow passes the build
# date here, so the toolchain refreshes at most once per day.
ARG TOOLCHAIN_CACHE_BUSTER
RUN echo "toolchain cache buster: ${TOOLCHAIN_CACHE_BUSTER:-unset}" \
    && curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s
ENV PATH="/root/.moon/bin:${PATH}"

# Verify MoonBit installation
RUN moon version

WORKDIR /build

# Copy full project source. moon will fetch registry dependencies from
# mooncakes.io on first build; no vendored deps are required.
COPY . .

# Resolve registry dependencies (needs network) so subsequent layers can be
# cached independently of source edits.
RUN moon update

# Build the CLI binary.
#
# NOTE: keep this step simple on purpose.
# - /bin/sh on ubuntu:22.04 is dash, which does NOT support `set -o pipefail`
#   (it exits with code 2 immediately: "Illegal option -o pipefail").
# - Piping moon's output through `tee` masks the real exit code: the pipeline
#   reports tee's status, so a failed build would look successful and only
#   surface later as a missing binary in the COPY step.
# buildx already prints the full RUN output on failure, so no log tee is
# needed. The explicit `test -f` gives a clear error if the artifact path
# ever changes with a future toolchain.
RUN cd /build \
    && moon build --target native --release cmd \
    && test -f /build/_build/native/release/build/cmd/cmd.exe \
    && echo "moon build succeeded"

# ── Stage 2: Runtime ────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Web server listens on 7071 by default (to differentiate from the
# original OpenClacky, which uses 7070). Override at runtime with -e MBOPENCLACKY_WEB_PORT=...
ENV MBOPENCLACKY_WEB_PORT=7071

# Bind to all interfaces inside the container (required for Docker port mapping).
# The security gate in cmd/main.mbt refuses to start without MBOPENCLACKY_WEB_API_KEY
# when a non-loopback host is set, so you MUST also provide an API key.
ENV MBOPENCLACKY_WEB_HOST=0.0.0.0

# Install minimal runtime dependencies.
# libssl3 ships libcrypto.so.3 required by the AES-256-GCM crypto stubs
# and by @async/tls (OpenSSL backend on POSIX).
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r mbopenclacky && useradd -r -g mbopenclacky -m mbopenclacky

WORKDIR /app

# Copy built binary from builder stage (release artifact is named cmd.exe)
COPY --from=builder /build/_build/native/release/build/cmd/cmd.exe ./mbopenclacky

# Copy static web assets
COPY --from=builder /build/assets/ ./assets/

# Create directories for runtime data
RUN mkdir -p /app/logs /app/memory \
    && chown -R mbopenclacky:mbopenclacky /app

# Switch to non-root user
USER mbopenclacky

# Expose Web UI port
EXPOSE 7071

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:7071/health || exit 1

# Default entrypoint: start the web server
ENTRYPOINT ["./mbopenclacky", "server"]
