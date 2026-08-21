# 平台 HTTP failover 域名补齐（BUG-0031）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 已完成  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0031；`reports/p5_fix_unit_clustering.md` FU-05  
> **关联历史 spec**: 无  
> **来源差距**: P2 单元层差分（cases/error_retry retry-020）  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

平台 HTTP 客户端的 failover 域名数不一致：Ruby 维护 3 个域名（primary + secondary + fallback），MB 的 `PlatformHttpConfig` 只有 2 个（primary + fallback），failover 只能在两个域名间对切。主域名故障时 MB 少一级容灾跳转。

> **B 类冻结条目提示**：BUG-0031 属 P2 单元层条目，复现证据基于 P2.5 前基线，修复前需在当前基线重新验证。本 spec 的验证记录即为当前基线（2026-08-14）的重新验证结果。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB PlatformHttpConfig 只有 2 个域名" | 读 `lib/client/platform_http.mbt:7-15` | 字段仅 `primary_host` + `fallback_host` | 确认 |
| "MB failover 在两域名间对切" | 读 `lib/client/platform_http.mbt:246-254` | `execute_failover`：current == primary → fallback，否则 → primary | 确认无第三级 |
| "Ruby 3 个域名" | 读 openclacky `lib/clacky/platform_http_client.rb:28-32` | `PRIMARY_HOST=https://www.openclacky.com`、`SECONDARY_HOST=https://api.1024code.com`、`FALLBACK_HOST=https://openclacky.up.railway.app` | 确认参照实现 |
| "Ruby hosts 数组与 override 行为" | 读 openclacky `platform_http_client.rb:55-64` | `CLACKY_LICENSE_SERVER` 设置时单 host 不 failover；否则 @[PRIMARY, SECONDARY, FALLBACK] | 确认 override 语义 |
| "PlatformHttpClient 无生产调用点" | `grep -rn "PlatformHttpClient::new\|PlatformHttpConfig::new" lib/ cmd/ --include=*.mbt`（排除 wbtest） | 仅定义点本身；唯一外部调用在 `test/diff/error_retry_cases_wbtest.mbt:356,368` | **确认**：当前为纯测试可达代码 |
| "web 发布路径不走 PlatformHttpClient" | 读 `lib/web/handlers_publish.mbt:14-23,295` | `platform_base_url()` 硬编码 `https://www.openclacky.com`（`MBOPENCLACKY_PLATFORM_URL` 可覆盖），直接拼 URL 请求，无 failover | 确认生产路径无 failover |
| "retry-020 回归用例与闸门位置" | 读 `test/diff/error_retry_cases_wbtest.mbt:361-383` | `known_failure("BUG-0031")` 闸门；green 断言冻结 mb_domains==2，闸门后期望 3 | 确认 |

### 详细分析

**Ruby 对照行为**（`platform_http_client.rb`）：

- 域名链：`www.openclacky.com`（primary）→ `api.1024code.com`（中国大陆 CDN 加速 secondary）→ `openclacky.up.railway.app`（绕过 EdgeOne 的直连 fallback）。
- 每域名 `ATTEMPTS_PER_HOST = 1`（同域不重试，BUG-0030 已标 wontfix 保留 MB 改进），失败即跳下一域名。
- `CLACKY_LICENSE_SERVER` 环境变量设置时退化为单 host（开发覆盖，不 failover）。
- `download_file` 场景仅当 URL host 命中 PRIMARY_HOST 时追加 fallback 候选 URL（:144-147）。

**MB 现状**：`PlatformHttpConfig` 结构层面只有 primary/fallback 两域；且该 client 目前**没有任何生产调用点**（web 发布路径自己拼 URL），所以 BUG-0031 的修复本质是**结构对齐 + 测试可见**，对生产行为无即时影响（见决策 2）。

**链路证据**：`cases/error_retry/test_cases.json` retry-020；`test/diff/error_retry_cases_wbtest.mbt` retry-020。

## 决策 [必填 - 含为什么]

1. **决策 1**：`PlatformHttpConfig` 增加 `secondary_host` 字段（`String`，默认 `""` 表示缺省），failover 链改为 primary → secondary → fallback 顺序遍历（空段跳过），替代当前的"两域对切"。
   - **为什么**：与 Ruby 三域链语义对齐；保留 `fallback_host` 字段名不改（公开 API 已有 wbtest/test/diff 使用，`moon info` 面最小）。hosts 数组重构虽更接近 Ruby 的 `@hosts` 形态，但会改动现有字段与构造签名，回归面更大，三域场景用三字段足够。
2. **决策 2（边界，不做）**：本 spec 不把 `lib/web/handlers_publish.mbt` 接入 PlatformHttpClient。
   - **为什么**：验证发现 PlatformHttpClient 当前无生产调用点，发布路径是独立实现；接入属于"生产路径 failover 能力建设"，是另一个量级的设计任务（超时/重试参数、HMAC 上传、错误语义都要过一遍），混入本 spec 会把低复杂度修复拖成中复杂度。在 BUGS.md 为"发布路径无 failover"另行登记 follow-up（或评审决定后单开 spec）。
3. **决策 3**：override 语义对齐——`secondary_host`/`fallback_host` 为空时自动跳过，天然等价 Ruby 的"override 单 host 不 failover"；不新增环境变量读取（`MBOPENCLACKY_PLATFORM_URL` 现状在 handlers_publish，与 PlatformHttpConfig 解耦，保持不动）。
   - **为什么**：Ruby 的 override 在构造期决定 hosts 数组；MB 的空段跳过在运行期等价，无需引入 env 依赖。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/platform_http.mbt` | 修改 | `PlatformHttpConfig` 加 `secondary_host : String`（默认 `""`）；failover 逻辑（`should_failover` :230-244、`execute_failover` :246-254、请求循环 :145-209）改为按 primary→secondary→fallback 顺序推进；`reset_failover`（:432-434）不变 |
| `lib/client/platform_http_wbtest.mbt` | 修改 | 新增：三域链顺序 failover；空 secondary 时 primary→fallback 直跳（兼容旧行为） |
| `test/diff/error_retry_cases_wbtest.mbt` | 修改 | retry-020：构造三域 config，移除 `known_failure("BUG-0031")` 闸门，断言 mb_domains==3 |

### 不涉及文件

- `lib/web/handlers_publish.mbt` — 发布路径接入 PlatformHttpClient 属 follow-up（决策 2）
- 同域重试次数（max_retries=2）— BUG-0030 wontfix，冻结不动
- 域名默认值常量 — MB 当前无内建默认域名（调用方传入），不新增硬编码默认值；Ruby 三域名作为参照写在 retry-020 注释

## 实施计划 [必填]

### 任务包 1：三域结构与 failover 链（预估 0.5 天）

1. `PlatformHttpConfig` 增加 `secondary_host` 字段（含 `PlatformHttpConfig::new` 的 `secondary_host?` 可选参数，默认 `""`）。
2. failover 推进逻辑改为有序链：current 为 primary → secondary（空则 fallback）→ fallback → 耗尽（AllHostsFailed）。
3. wbtest 覆盖三域顺序与空段跳过；`moon check` + `moon test lib/client` 通过。

### 任务包 2：回归用例转绿（预估 0.5 天）

1. retry-020：构造 `PlatformHttpConfig::new(primary_host=..., secondary_host=..., fallback_host=...)`，移除 BUG-0031 闸门，断言 3 域名。
2. `moon fmt` + `moon info`（pub struct 字段新增需确认 API 基线更新）。
3. 全量 `moon test` 无回归。

## 验收标准 [必填]

- [x] PlatformHttpConfig 支持 primary/secondary/fallback 三域，failover 按序推进、空段跳过（单测断言）
- [x] `test/diff` retry-020 的 BUG-0031 known-failure 闸门移除并转绿
- [x] `moon check` 0 errors（lib/client、test/diff）
- [x] `moon test lib/client`、`moon test test/diff` 全部通过
- [x] 全量 `moon test` 无回归（3831/3831 通过）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| pub struct 加字段破坏 API 基线（`moon info`） | 低 | 按 `moon info` 提示更新 .mbti；字段带默认值，构造方源码兼容 |
| failover 顺序改动影响既有 wbtest（两域对切语义） | 低 | 空 secondary 时保持 primary↔fallback 行为，旧用例不改 |
| 三域结构上线但无生产调用方，修复"不可见" | 中 | 本 spec 定位即结构对齐（retry-020 闸门）；生产接入 follow-up 已在决策 2 登记，避免"修了个寂寞"的隐性预期 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（"发布路径接入 PlatformHttpClient"的潜在 follow-up 依赖本 spec 的三域结构，但尚未立项）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-05（BUG-0031） |
| 2026-08-21 | 开发完成：`PlatformHttpConfig` 补 `secondary_host` 字段（默认 `""`），failover 改为 primary→secondary→fallback 链式推进、空段跳过、链尾回卷；wbtest 新增三域顺序/空段跳过/secondary-only 用例；retry-020 移除 BUG-0031 闸门断言三域转绿；BUG-0031 移出 known_failure 注册表。`moon check` 0 errors，全量 `moon test` 3831/3831 通过 | P5 修复实施 |
