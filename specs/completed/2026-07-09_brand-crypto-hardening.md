# Brand Crypto 加固 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 已完成  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P0-3）  
> **负责方向**: Agent-F（安全）

## 问题描述

差距分析将"Windows 加密弱桩"列为 P0。代码核对后发现 Windows 路径已使用 BCrypt/CNG（`lib/brand/crypto_native.c` 中 `#ifdef _WIN32` + `#pragma comment(lib, "bcrypt.lib")`），弱桩仅在 `-DMBOPENCLACKY_NO_OPENSSL` 显式 opt-out 时编译。因此真正的安全缺口调整为：

1. **`derive_key` 未使用标准 PBKDF2**：当前用迭代 SHA-256 派生密钥，偏离密码学最佳实践（原项目优先级矩阵亦标记为 P2）。
2. **`refresh_distribution` 为 HTTP 桩**：`lib/brand/config.mbt` 返回 `Err("HTTP client not available (stub)")`，品牌分发刷新不可用。
3. **弱桩编译路径风险**：虽默认不编译，但 `MBOPENCLACKY_NO_OPENSSL` 构建会产出非随机 nonce / 全零密文，需确保该路径不会误入生产构建。

## 现状分析

- `lib/brand/brand_stubs.c`：弱桩仅在 `MBOPENCLACKY_NO_OPENSSL` 下编译，已注释根因说明。
- `lib/brand/crypto_native.c`：Linux/macOS 走 OpenSSL（`-lcrypto`），Windows 走 BCrypt。
- `lib/brand/crypto_wbtest.mbt` / `brand_wbtest.mbt`：已有 `derive_key_deterministic` 等测试。
- `cmd/moon.pkg`：`-lcrypto` 已正确链接且 `--no-as-needed` 说明完善。
- 原项目 `brand_config.rb` 使用 Ruby OpenSSL。

## 决策

1. **derive_key 改用 PBKDF2-HMAC-SHA256**：通过 OpenSSL `PKCS5_PBKDF2_HMAC`（Linux/macOS）与 BCrypt/CNG 派生（Windows），统一为标准算法，保留 deterministic 测试但用固定 salt。
2. **refresh_distribution 接入真实 HTTP**：复用 `lib/client` 的 HTTP 能力或最小 libcurl 调用，移除 stub。
3. **弱桩路径加构建期断言**：在 `MBOPENCLACKY_NO_OPENSSL` 构建时输出明确告警，禁止进入 release 构建（CI 校验）。
4. **保持向后兼容**：密钥派生变更会影响已加密的持久化数据；需提供迁移/重新激活路径，或文档声明需重新激活品牌。

## 改动范围

- **涉及包**：`lib/brand`（主）、`lib/client`（HTTP 复用，若 refresh 接入）。
- **涉及文件**：`lib/brand/crypto_native.c`（新增 PBKDF2）、`lib/brand/crypto.mbt`（derive_key 调用）、`lib/brand/config.mbt`（refresh_distribution）、`lib/brand/brand_stubs.c`（弱桩告警）、`*_wbtest.mbt`。
- **不涉及**：许可证校验业务逻辑、计费、其他包。

## 实施计划（任务包切分）

1. **derive_key PBKDF2**：C 侧实现 `PKCS5_PBKDF2_HMAC`，MoonBit 侧调整签名；更新确定性测试。
2. **refresh_distribution HTTP**：替换 stub，调用远端分发端点，缓存结果。
3. **弱桩断言**：构建脚本检测 `MBOPENCLACKY_NO_OPENSSL` + release 组合即 fail。
4. **迁移说明**：文档化密钥派生变更的影响与重新激活步骤。
5. **回归**：`moon test lib/brand` 全绿，手动验证品牌激活/校验流程。

## 密钥派生变更迁移说明

### 影响范围

`derive_key` 从迭代 SHA-256 改为 PBKDF2-HMAC-SHA256（100 000 轮）。此变更影响所有通过 `derive_key` 派生密钥的加密持久化数据（如品牌技能加密包）。

### 不兼容说明

- 旧版派生密钥（迭代 SHA-256，10 000 轮）与新版（PBKDF2-HMAC-SHA256）输出不同。
- 已加密的品牌数据（如加密技能包）在升级后无法用新密钥解密。

### 重新激活步骤

1. 升级到包含此变更的版本。
2. 运行 `moon run cmd -- --brand-restart` 或手动删除 `~/.mbopenclacky/brand.toml` 中的 `license_key` 字段。
3. 使用许可证密钥重新激活品牌：`LicenseValidator::activate(key, timestamp)`。
4. 加密技能包需重新下载并解密。

### 向后兼容缓解

- `derive_key` 的 `salt` 参数默认为空数组，保持确定性（适合单元测试和固定盐场景）。
- 生产调用方应始终传入唯一的随机 salt 并将 salt 与加密数据一同存储。

## 验收标准

- [x] `derive_key` 使用 PBKDF2-HMAC-SHA256，迭代次数 ≥ 配置阈值
- [x] `refresh_distribution` 不再返回 stub 错误
- [x] 弱桩路径无法进入 release 构建
- [x] `moon check` 0 errors，`moon test lib/brand` 通过
- [x] Windows BCrypt 路径保持可用（不回归）
- [x] 密钥派生变更的兼容性有文档说明

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| 密钥派生变更导致旧持久化数据无法解密 | 高 | 提供迁移/重新激活路径；文档声明 |
| PBKDF2 迭代次数影响启动性能 | 低 | 设合理阈值（如 100k），可配置 |
| Windows BCrypt 路径回归 | 中 | 保留现有 `_WIN32` 分支，新增测试 |
| refresh_distribution 远端不可达 | 中 | 失败降级到缓存，不阻断启动 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本，由“Windows 弱桩修复”调整为“brand crypto 加固” | 代码核对发现 Windows 已用 BCrypt |
| 2026-07-09 | 实施：PBKDF2 纯 MoonBit 实现、refresh_distribution HTTP 接入、弱桩运行时警告 | spec 实施计划 |
| 2026-07-13 | 归档至 specs/completed/，所有验收标准已确认通过 | 代码核查完成 |
