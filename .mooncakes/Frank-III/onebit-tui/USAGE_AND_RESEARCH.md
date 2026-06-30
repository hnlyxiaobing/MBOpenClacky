# OneBit‑TUI Usage, Linking, and Research Notes

## What app developers need to use OneBit‑TUI

### 1) Install

```bash
moon add Frank-III/onebit-tui
```

This will bring in its dependency OneBit‑Yoga (published v0.2.0) and both packages’ vendors.

### 2) Toolchain prerequisites

- Zig 0.14.x (OpenTUI vendor targets Zig 0.14; Zig 0.15 has std.Build API changes)
  - Recommended: anyzig or zigup to automatically select Zig 0.14.1 from vendor/build.zig.zon
- C/C++ toolchain (clang recommended)
- CMake (required by OneBit‑Yoga pre‑build)

### 3) Import

In your app’s `moon.pkg.json` add imports to OneBit‑TUI (and optionally its subpackages) plus OneBit‑Yoga types if you refer to enums directly:

```json
{
  "import": [
    "Frank-III/onebit-tui/widget",
    "Frank-III/onebit-tui/view",
    "Frank-III/onebit-tui/core",
    "Frank-III/onebit-tui/layout",
    "Frank-III/onebit-tui/runtime",
    { "path": "Frank-III/onebit-yoga/yoga",  "alias": "yoga" },
    { "path": "Frank-III/onebit-yoga/types", "alias": "types" }
  ]
}
```

### 4) Linking (MoonBit doesn’t propagate link flags yet)

Add a `link.native` stanza to your app’s main package. For registry installs, use `.mooncakes` paths:

```json
{
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "-L.mooncakes/Frank-III/onebit-tui/src/ffi/lib -lopentui -L.mooncakes/Frank-III/onebit-yoga/src/ffi -lyoga_wrap -L.mooncakes/Frank-III/onebit-yoga/src/ffi/yoga-install/lib -lyogacore -lc++"
    }
  }
}
```

Notes:
- On Linux, you may need `-lstdc++` instead of `-lc++`.
- The order of `-l` flags matters on some systems; keep `-lyoga_wrap -lyogacore` together as shown.

### 5) Build

`moon build --target native`

Pre‑build hooks in dependencies will run and compile Zig/C++ vendors (cached). If you’re using anyzig and it’s in PATH, the correct Zig 0.14.x will be fetched and used automatically.

### 6) Run demos (optional)

Inside OneBit‑TUI repo: `moon run --target native -C onebit-tui/src/demo main.mbt`

## How dependencies are wired to “just work”

- OneBit‑Yoga ships a trimmed vendor (`src/ffi/vendor/yoga`) and a pre‑build script that builds the Yoga static lib and our wrapper lib at build time. No network needed post‑install.
- OneBit‑TUI ships its OpenTUI Zig vendor (`src/ffi/vendor/opentui`) and a pre‑build script that builds `libopentui.a` at build time.
- Library packages (ffi) use `"link": false` so Moon doesn’t try to link executables in those packages; only the app’s main package links.
- Pre‑builds are cached and will skip when nothing changed; you can force rebuild with `ONEBIT_FORCE_ZIG_BUILD=1`.

## Publishing OneBit‑TUI (internal checklist)

- Vendor present at `src/ffi/vendor/opentui`.
- Pre‑build in `src/ffi/moon.pkg.json` points to `src/ffi/scripts/build_opentui.sh`.
- `src/ffi/moon.pkg.json` has `"link": false`.
- Strict Zig 0.14 guard in `build_opentui.sh` (for publish) to fail fast when zig 0.15 is used without anyzig.
- `moon package --list` shows a clean tarball.
- Publish with `moon publish`.

## Research: TypeScript vs MoonBit renderer behavior

### TypeScript core (packages/core)
- Uses an `OptimizedBuffer` abstraction that is backed by the Zig render lib. See `packages/core/src/buffer.ts`.
- The TS renderer (`packages/core/src/renderer.ts`) maintains two buffers per frame:
  - `nextRenderBuffer` and `currentRenderBuffer` — the Zig side performs optimized diffs between buffers so that only changed cells are flushed to the terminal.
- Rendering is demand‑driven:
  - `renderer.requestRender()` schedules a loop tick; not every frame is redrawn.
  - Many components call `requestRender` when state changes, and the renderer consolidates updates.
- Includes hit‑grid for pointer mapping (mouse events), selection overlays, console split mode, and post‑processing pipeline for effects.
- Recent upstream added text‑wrapping support (see text‑buffer files and TS commits) — we can choose to leverage the Zig side or do it at MoonBit layer.

### Current MoonBit design
- The runtime event loop renders when `needs_redraw` is set (input or timers), but the drawing path traverses the entire view tree and draws everything.
- Layout is computed via Yoga, then we draw primitives through the TUI app API.
- We are not yet delegating high‑frequency drawing to the Zig optimized buffers; thus, we don’t benefit fully from diffed buffers.

### Suggested enhancements for MoonBit runtime
- Integrate with Zig optimized buffers:
  - Maintain a persistent `OptimizedBuffer` handle and write cells through the FFI, letting Zig perform the diff.
  - Convert high‑level view drawing into buffer operations (similar to TS `OptimizedBuffer` usage).
- Drive rendering via `requestRender` algorithm:
  - Event handlers set `needs_redraw` and schedule a single render pass.
  - Track dirty regions or changed views (optional) to reduce work on the MoonBit side; let Zig handle cell‑level diffs.
- Consider a small “render tree” in MoonBit mirroring the TS approach (root renderable + children) if we want greater parity.

## Action plan (short‑term)
- Publish OneBit‑TUI with vendor included and Zig 0.14 guard.
- Update OneBit‑TUI README/DISTRIBUTION_GUIDE with:
  - anyzig usage
  - required link flags (with Linux note)
  - demo commands
- Add optional `postadd` helper to inject link flags for users (interactive prompt).

## Action plan (medium‑term)
- Shift drawing to use the Zig `OptimizedBuffer` (diff‑based rendering) for performance.
- Port OpenTUI vendor to Zig 0.15 once upstream is ready; remove 0.14 guard thereafter.
