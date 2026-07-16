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
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    make \
    curl \
    ca-certificates \
    git \
    libssl-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install MoonBit toolchain
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:${PATH}"

# Verify MoonBit installation
RUN moon version

WORKDIR /build

# Copy full project source. moon needs the package structure (moon.pkg files)
# to resolve dependencies — copying only moon.mod and pre-building is not
# possible because the `cmd` package directory must exist.
COPY . .

# Build using vendored .mooncakes/ (patched deps committed to repo).
# We build the `cmd` package explicitly: a plain `moon build` would also try to
# link the non-main `lib/brand` package as a standalone executable (moon issue
# #1488) and fail with "undefined reference to main". Targeting `cmd` builds
# only the real entrypoint and produces _build/native/release/build/cmd/cmd.exe.
RUN moon build --target native --release cmd

# ── Stage 2: Runtime ────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Web server listens on 7071 by default (to differentiate from the
# original OpenClacky, which uses 7070). Override at runtime with -e MBOPENCLACKY_WEB_PORT=...
ENV MBOPENCLACKY_WEB_PORT=7071

# Install minimal runtime dependencies.
# libssl3 ships libcrypto.so.3 required by the AES-256-GCM crypto stubs.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libssl3 \
    libcurl4 \
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
