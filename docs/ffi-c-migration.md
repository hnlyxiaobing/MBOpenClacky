# FFI C Dependency Migration

完成日期: 2026-07-25 | 最后更新: 2026-07-26

将 C stub 业务逻辑迁移到纯 MoonBit，消除对 C 编译器的业务依赖。

## Current State

剩余 C 代码: **5 files, ~610 lines**

全部是 MoonBit FFI 前端包装桩（`moonbit.h` 宏展开），无业务逻辑。

| 文件 | 行数 | 角色 |
|---|---|---|
| `lib/pty/c/_stub.c` | 236 | pty FFI + Windows fallback |
| `lib/process/c/_stub.c` | 180 | process 系统调用桩 |
| `lib/ipc/c/_stub.c` | 113 | named pipe / unix socket 桩 |
| `lib/json/c/_stub.c` | 74 | JSON number parse/print 桩 |
| `lib/filelock/c/_stub.c` | 13 | flock/lockf 桩 |

## Migration History

原始 C 代码: **6 files / 1,136 lines of C business logic** → 现在: **5 files / 610 lines** (all FFI stubs)

### Removed C Business Logic

| 移除的 C 代码 | 行数 | MoonBit 替换 |
|---|---|---|
| `lib/text/c/text_processing.c` | 452 | MoonBit string 操作 + WTF-8 |
| `lib/config/c/config_loader.c` | 276 | `lib/config/parser.mbt` + toml package |
| `lib/crescent` 子模块的 c 桩 | 156 | crescent 包内部处理 |
| `lib/tty` 子模块的 c 桩 | 162 | tty 包内部处理 |
| `lib/cryo/c/cryo_encryption.c` | 90 | MoonBit hex/base64 |

最终删除的 `lib/cryo/c/` 目录消除了最后一个剩余的 C 业务逻辑源文件，完成 FFI 依赖瘦身。

## Tech Stack Replacements

| 原 C 依赖 | MoonBit 替换 |
|---|---|
| SHA-256 (OpenSSL) | `lib/crypto/sha256.mbt` |
| HMAC (OpenSSL) | `lib/crypto/hmac.mbt` |
| Base64 encode/decode | `lib/encoding/base64.mbt` |
| Hex encode/decode | `lib/encoding/hex.mbt` |
| AES-256-GCM (OpenSSL) | `lib/crypto/aes_gcm.mbt` |
| String 处理 (WTF-8, grapheme) | `lib/text/` 模块 |
| JSON number 解析 | `lib/json/number_parse.mbt` |

## Known Gaps

1. `pty` 包在 Windows 上依赖 conpty API（Windows 10+），当前使用 fallback
2. `process` 包在 Windows 上路径处理与 Unix 不同
3. `filelock` 在 Windows 上使用 `LockFileEx` 而非 `flock`

## Related Specs

- `specs/completed/2026-07-25-ffi-c-reduce-plan.md`
- `specs/completed/2026-07-25-ffi-c-code-cleanup.md`
