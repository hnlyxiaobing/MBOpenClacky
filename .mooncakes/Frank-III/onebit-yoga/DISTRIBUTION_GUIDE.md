# onebit-yoga: Packaging, Install, and Usage

This package builds the Yoga (C++) static library at user build time using MoonBit `pre-build`.
There is no fallback: if required tools are missing, builds fail with a clear error.

## Prerequisites

- Native toolchain: `clang` (or `cc`) available in PATH
- Build tools: `cmake`, `make`

## What happens on build

- The `pre-build` step runs `src/ffi/scripts/build_yoga.sh`
  - Finds Yoga sources under `src/ffi/vendor/yoga`, or uses the dev fallback `build/yoga`
  - Builds and installs static library into `src/ffi/yoga-install/lib/libyogacore.a`
  - Builds our C wrapper static lib `src/ffi/libyoga_wrap.a`
- Library packages themselves do not link executables (no `link` in library packages)

## Using from your project

Add dependency in your module:

```
{
  "deps": {
    "Frank-III/onebit-yoga": "latest"
  }
}
```

Import in your main package and add link flags (MoonBit currently does not propagate link flags):

```
// moon.pkg.json of your main package
{
  "import": [
    { "path": "Frank-III/onebit-yoga/yoga", "alias": "yoga" },
    { "path": "Frank-III/onebit-yoga/types", "alias": "ytypes" }
  ],
  "is-main": true,
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "-L<path-to-onebit-yoga>/src/ffi -lyoga_wrap -L<path-to-onebit-yoga>/src/ffi/yoga-install/lib -lyogacore -lc++"
    }
  }
}
```

Notes:
- When installed from the registry, `src/ffi/...` paths are inside the dependency directory that Moon resolves.
- For local path development (this repo checked out side-by-side), you can use a relative path as shown in `tmp-consumer/moon.pkg.json` in this repo.

## Maintainers: vendoring & sync

- Vendored Yoga source should live under `src/ffi/vendor/yoga`
- The repo includes:
  - `scripts/vendor.lock` – repo + pinned ref
  - `scripts/vendor_fetch.sh` – populate vendor from lock
  - `scripts/update_vendor.sh` – bump pinned ref and update checkout
  - `scripts/postadd.sh` – fetch vendor after `moon add` when missing

We recommend publishing with vendored sources included to avoid network on install.

---

## Local smoke test (already performed here)

- Built Yoga and wrapper via `moon build --target native` in `onebit-yoga`.
- Created a local consumer (`tmp-consumer`) with a path dep to `../onebit-yoga`.
- Ran `moon run --target native main.mbt` successfully, linking against Yoga + wrapper.
