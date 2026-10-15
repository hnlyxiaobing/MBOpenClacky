# Vendored: DzmingLi/clap

This package is a vendored copy of the `DzmingLi/clap` command-line argument
parser (upstream version 0.2.8, MIT license).

## Why vendored

Upstream `DzmingLi/clap@0.2.8` is the latest published release and still ships
the legacy `moon.pkg.json` package manifest, which current MoonBit toolchains
reject. Because `moon publish` re-downloads dependencies from the registry and
runs a clean `moon check`, that legacy manifest blocked publishing this module.
clap has no dependencies outside `moonbitlang/core`, so the implementation is
vendored directly into this module (new-format `moon.pkg`) to keep the published
package self-contained and buildable.

## Provenance

- Upstream: https://github.com/DzmingLi/clap.mbt
- License: MIT (see `LICENSE`)
- Upstream README: `README.upstream.md`
- Vendored files: `arg.mbt`, `gen_help.mbt`, `parser.mbt`, `subcmd.mbt`,
  `value.mbt` (upstream test files intentionally omitted)

Consumers import this package as `@clap`
(`hnlyxiaobing/MBOpenClacky/third_party/clap`), preserving the same alias the
external dependency used.
