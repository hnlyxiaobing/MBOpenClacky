# Third-Party Licenses

This file lists all third-party libraries bundled with MBOpenClacky and their licenses.

## Web UI Libraries (`web/vendor/`)

| Library | License | Directory |
|---------|---------|----------|
| highlight.js | BSD-3-Clause | `web/vendor/hljs/` |
| marked.js | MIT | `web/vendor/marked/` |
| KaTeX | MIT | `web/vendor/katex/` |
| QRCode | MIT | `web/vendor/qrcode/` |
| CodeMirror 6 | MIT | `web/vendor/codemirror/` |

## Native Dependencies

| Library | License | Notes |
|---------|---------|-------|
| OpenSSL libcrypto | Apache-2.0 | Linked on Linux/macOS (`-lcrypto`): AES-256-GCM / CSPRNG in `lib/brand`, and TLS for `@async/http` |
| Windows CNG (BCrypt) / Schannel | Proprietary | Windows system libraries, dynamically linked: AES-256-GCM / CSPRNG (BCrypt) and TLS (Schannel) |

HTTP transport is pure MoonBit (`moonbitlang/async/http`); libcurl/WinHTTP are no longer used.

## MoonBit Dependencies

See `moon.mod` for the full dependency list. All MoonBit packages are from mooncakes.io and carry their respective licenses.
