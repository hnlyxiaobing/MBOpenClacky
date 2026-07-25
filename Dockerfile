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
    && rm -rf /var/lib/apt/lists/*

# Install MoonBit toolchain (use latest stable; pinned versions are not retained on CDN)
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s
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

# Build the CLI binary. We tee the build log so that if this step fails, the
# real MoonBit error is visible in the Docker build output instead of being
# swallowed by buildx.
RUN cd /build \
    && (moon build --target native --release cmd 2>&1 | tee /tmp/moon-build.log) \
    && echo "moon build succeeded" \
    && rm /tmp/moon-build.log \
    || (echo "moon build failed; see log below" && cat /tmp/moon-build.log && exit 1)

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
