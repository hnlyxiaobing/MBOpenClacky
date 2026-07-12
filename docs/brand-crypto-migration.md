# Brand Crypto 密钥派生变更 · 迁移说明

> 关联规格：`specs/active/2026-07-09_brand-crypto-hardening.md`
> 适用版本：包含 "Brand Crypto 加固" 变更的发布

## 变更摘要

`derive_key` 从**迭代 SHA-256**（10 000 轮）改为标准 **PBKDF2-HMAC-SHA256**（100 000 轮，OWASP 2023 建议阈值）。所有通过 `derive_key` 派生密钥的加密持久化数据都会受到影响。

## 影响范围

- 受影响：通过 `derive_key` 派生的密钥所加密的持久化数据（例如品牌技能加密包）。
- 不受影响：AES-256-GCM、HMAC-SHA256、SHA-256 等对称/哈希原语本身（仍走 OpenSSL / Windows CNG）。

## 不兼容说明

- 旧版派生密钥（迭代 SHA-256，10 000 轮）与新版（PBKDF2-HMAC-SHA256，100 000 轮）输出不同。
- 已加密的品牌数据（如加密技能包）在升级后无法用新密钥解密。

## 重新激活步骤

升级到包含此变更的版本后，请按以下任一方式重新建立品牌状态：

1. **手动清除**（推荐，最稳妥）：
   - 删除 `~/.mbopenclacky/brand.toml` 中的 `license_key` 字段；或
   - 直接删除 `~/.mbopenclacky/brand.toml` 后重新激活。
2. **命令行快捷方式**（如当前构建提供）：
   - 运行 `moon run cmd -- --brand-restart`（若 CLI 未暴露该旗标，请使用手动方式）。
3. 使用许可证密钥重新激活品牌：
   - 调用 `LicenseValidator::activate(key, timestamp)`。
4. 加密技能包需重新下载并解密。

## 向后兼容缓解

- `derive_key` 的 `salt` 参数默认为空数组，保持确定性——适合单元测试与固定盐场景。
- 生产调用方应始终传入**唯一的随机 salt**，并将 salt 与加密数据一同持久化存储。

## 弱桩路径（MBOPENCLACKY_NO_OPENSSL）安全约束

该构建选项会编入 `lib/brand/brand_stubs.c` 中的**不安全占位实现**（非随机 nonce、全零密文），**严禁进入 release / 生产构建**。两道独立卡点保障：

1. **编译期**：`brand_stubs.c` 在未同时定义 `MBOPENCLACKY_INSECURE_DEBUG_BUILD` 时直接 `#error`，使不安全桩代码根本无法被编译。仅调试/极简构建在显式确认后方可编入。
2. **CI / 构建脚本**：`scripts/check-crypto-build.{sh,ps1}` 在 `MBOPENCLACKY_NO_OPENSSL` 与 release 组合下返回非零退出码，CI 步骤 `Guard insecure crypto build` 会因此失败。

## 验收对照

| 验收项 | 状态 |
|---|---|
| `derive_key` 使用 PBKDF2-HMAC-SHA256，迭代 ≥ 阈值 | ✅ 100 000 轮 |
| `refresh_distribution` 不再返回 stub 错误 | ✅ 已接入真实 HTTP |
| 弱桩路径无法进入 release 构建 | ✅ 编译期 `#error` + CI 守护 |
| `moon check` 0 errors / `moon test lib/brand` 通过 | 见 CI |
| Windows BCrypt 路径保持可用 | ✅ 未改动 `_WIN32` 分支 |
| 密钥派生变更的兼容性有文档说明 | ✅ 本文档 |
