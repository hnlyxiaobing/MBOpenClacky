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

# Install MoonBit toolchain (use latest stable; pinned versions are not retained on CDN)
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s
ENV PATH="/root/.moon/bin:${PATH}"

# Verify MoonBit installation
RUN moon version

WORKDIR /build

# Copy vendored mooncakes sources before the full project copy.
COPY .mooncakes /root/.moon/mooncakes

# Copy full project source. moon needs the package structure (moon.pkg files)
# to resolve dependencies — copying only moon.mod and pre-building is not
# possible because the `cmd` package directory must exist.
COPY . .

# Seed the registry index metadata so `moon build --frozen` can map versioned
# dependencies to the vendored .mooncakes sources without network access.
# MoonBit requires the index directory to look like a git working copy with an
# origin remote pointing to mooncakes.io and a `main` branch.
COPY .moon/registry-index/user /root/.moon/registry/index/user
RUN cd /root/.moon/registry/index \
    && git init -q \
    && git config user.email "builder@mbopenclacky.local" \
    && git config user.name "Builder" \
    && git add user \
    && git commit -q -m "seed registry index" \
    && git branch -m main \
    && git remote add origin https://mooncakes.io/git/index \
    && git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# Build using vendored .mooncakes/ (patched deps committed to repo).
# --frozen tells moon not to sync dependencies from mooncakes.io, so the
# modified dependency sources in .mooncakes/ are used exactly as committed.
# We tee the build log so that if this step fails, the real MoonBit error is
# visible in the Docker build output instead of being swallowed by buildx.
RUN cd /build \
    && (moon build --target native --release --frozen cmd 2>&1 | tee /tmp/moon-build.log) \
    && echo "moon build succeeded" \
    && rm /tmp/moon-build.log \
    || (echo "moon build failed; see log below" && cat /tmp/moon-build.log && exit 1)

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
