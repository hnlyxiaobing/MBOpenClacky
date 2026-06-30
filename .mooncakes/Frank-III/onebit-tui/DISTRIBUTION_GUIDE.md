# onebit-tui: Packaging, Install, and Usage

This package builds the OpenTUI Zig core at user build time using MoonBit `pre-build`.
There is no fallback: if Zig isn’t available or incompatible, builds fail with a clear error.

## Prerequisites

- Zig: currently OpenTUI’s `build.zig` in this repo expects Zig 0.14.x
  - We will update to 0.15.x+ once upstream supports it
- Native toolchain: `clang` (or `cc`) available in PATH

## What happens on build

- The `pre-build` step runs `src/ffi/scripts/build_opentui.sh`
  - Builds vendored Zig sources under `src/ffi/vendor/opentui`
  - Produces a static library `src/ffi/lib/libopentui.a`
- The C FFI wrapper is compiled via `native-stub` (opentui_wrap.c)
- Link flags are set to use `-Lsrc/ffi/lib -lopentui -lc++`

## Syncing vendored Zig

- Vendored code path: `src/ffi/vendor/opentui`
- Scripts:
  - `scripts/vendor.lock` – fork repo and pinned ref
  - `scripts/vendor_fetch.sh` – populate vendor from lock (used by postadd)
  - `scripts/update_vendor.sh` – bump pinned ref and update checkout
  - `scripts/postadd.sh` – fetch vendor after `moon add` when missing

We recommend publishing with vendored sources included to avoid network on install.

## Notes

- Until OpenTUI supports Zig 0.15.x, builds will fail on newer Zig; please install 0.14.x.
- No fallback renderer is provided; failure is explicit by design.

