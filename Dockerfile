# ============================================================
# MBOpenClacky - Multi-stage Dockerfile
# AI Agent CLI tool rewritten in MoonBit
# ============================================================

# ── Stage 1: Build ──────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    make \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install MoonBit toolchain
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:${PATH}"

# Verify MoonBit installation
RUN moon version

WORKDIR /build

# Copy dependency manifest first for better layer caching
COPY moon.mod ./

# Pre-fetch dependencies
RUN moon update && moon install

# Copy full project source
COPY . .

# Build native binary (release mode for smaller size)
RUN moon build --target native

# ── Stage 2: Runtime ────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r mbopenclacky && useradd -r -g mbopenclacky -m mbopenclacky

WORKDIR /app

# Copy built binary from builder stage
COPY --from=builder /build/_build/native/debug/build/cmd/cmd ./mbopenclacky

# Copy static web assets
COPY --from=builder /build/assets/ ./assets/

# Create directories for runtime data
RUN mkdir -p /app/logs /app/memory \
    && chown -R mbopenclacky:mbopenclacky /app

# Switch to non-root user
USER mbopenclacky

# Expose Web UI port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Default entrypoint: start the web server
ENTRYPOINT ["./mbopenclacky", "server"]
