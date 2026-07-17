# 大赛验收反馈修复总览 · 实施路线图

> **创建日期**: 2026-07-17
> **状态**: 已完成（全部子 spec 已实施并归档）
> **关联总览**: 大赛验收反馈核对报告 (2026-07-17)
> **来源差距**: 评审反馈的 7 项问题（4 项有效 + 2 项部分有效 + 1 项已通过）
> **依赖**: 包含 5 个子 spec

## 问题描述 [必填]

大赛评审反馈指出以下问题，需要逐一修复：

1. **SQLite 持久化未实现** → 子 spec `2026-07-17_03_sqlite-persistence-decision.md`
2. **成本计算为占位逻辑** → 子 spec `2026-07-17_01_cost-tracker-wiring.md`
3. **渠道/扩展占位逻辑** → 子 spec `2026-07-17_02_channel-placeholder-fixes.md`
4. **未发布 mooncakes.io** → 操作任务（`moon publish`）
5. **C 文件/头文件缺失** → 子 spec `2026-07-17_04_c-header-files.md`
6. **README/CI 通过** → ✅ 已通过，无需处理
7. **marked/highlight 许可** → 子 spec `2026-07-17_05_third-party-licenses.md`

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 反馈项 | 验证方式 | 结果 | 状态 |
|--------|---------|------|------|
| SQLite 持久化 | `grep -rn "sqlite" lib/ cmd/` | 无实际实现 | ✅ 有效 |
| 成本计算 | `grep -n "calculate_model_cost" lib/agent/cost_tracker.mbt` | stub 返回 None | ✅ 有效 |
| 渠道占位 | `grep -n "Placeholder\|placeholder" lib/channel/` | 8 处匹配 | ✅ 有效 |
| mooncakes 发布 | 访问 mooncakes.io | 404 | ✅ 有效 |
| C 头文件 | `find lib/ -name "*.h"` | 0 结果 | ⚠️ 部分有效（C 文件已存在） |
| README/CI | `moon check` + `moon test` | 0 errors, 2769/2769 通过 | ✅ 已通过 |
| 第三方许可 | `find web/js/lib/ -name "LICENSE*"` | 0 结果 | ✅ 有效 |

### 详细分析

**当前状态**：`moon check` 0 errors / `moon test` 2769/2769 通过，项目基础稳定。

**核心差距**：
- 功能层面：成本计算未接线、渠道存在占位逻辑
- 合规层面：SQLite 描述与实现不符、缺少第三方许可文件
- 发布层面：mooncakes.io 未发布
- 代码规范：C 头文件缺失（可选改进）

## 决策 [必填 - 含为什么]

### 修复优先级（基于工作量和影响）

| 优先级 | 任务 | 工作量 | 理由 |
|--------|------|--------|------|
| P0 | mooncakes 发布 | 10 分钟 | 最快解决，无技术风险 |
| P1 | 第三方许可文件 | 0.5 天 | 文档修改，无代码风险 |
| P1 | 成本计算接线 | 0.5 天 | 定价引擎已实现，只需接线 |
| P2 | C 头文件提取 | 0.5 天 | 代码规范改进，可选 |
| P2 | SQLite 决策（方案 A：改描述） | 0.5 天 | 已确定方案 A |
| P3 | 渠道占位修复 | 3-4 天 | 比原估大：需同时接通 HTTP transport；x/crypto 无 AES 需 FFI/自实现 |

### 关键决策

1. **SQLite 方案选择**：✅ 已确定方案 A（改描述）。详见 `2026-07-17_03_sqlite-persistence-decision.md`。
2. **渠道修复分批执行**：配置加载（JSON 格式，弃用 yml）→ 接通 HTTP transport + 消息 ID 提取 → 微信 AES（FFI OpenSSL 或纯 MoonBit 实现；已确认 `moonbitlang/x/crypto` 无 AES）。
3. **成本计算直接接线**：定价引擎已完整实现，只需按字段映射（`input_tokens`→`prompt_tokens` 等）接线。

## 改动范围 [必填]

### 涉及文件总览

| 模块 | 文件 | 操作 | 对应子 spec |
|------|------|------|------------|
| 成本计算 | `lib/agent/moon.pkg` | 修改 | 01 |
| 成本计算 | `lib/agent/cost_tracker.mbt` | 修改 | 01 |
| 渠道 | `lib/channel/manager.mbt` | 修改 | 02 |
| 渠道 | `lib/channel/dingtalk.mbt` | 修改 | 02 |
| 渠道 | `lib/channel/feishu.mbt` | 修改 | 02 |
| 渠道 | `lib/channel/discord_api.mbt` | 修改 | 02 |
| 渠道 | `lib/channel/weixin_api.mbt` | 修改 | 02 |
| SQLite（B 方案） | `lib/db/` | 新建 | 03 |
| SQLite（B 方案） | `lib/agent/session_store.mbt` | 修改 | 03 |
| SQLite（B 方案） | `lib/billing/billing_store.mbt` | 修改 | 03 |
| C 头文件 | `lib/client/http_native.h` | 新建 | 04 |
| C 头文件 | `lib/client/http_thread.h` | 新建 | 04 |
| C 头文件 | `lib/client/http_native.c` | 修改 | 04 |
| C 头文件 | `lib/client/http_thread.c` | 修改 | 04 |
| 许可文件 | `web/js/lib/LICENSE-highlightjs` | 新建 | 05 |
| 许可文件 | `web/js/lib/LICENSE-marked` | 新建 | 05 |
| 许可文件 | `web/js/lib/README.md` | 修改 | 05 |
| 发布 | mooncakes.io | 操作 | 直接执行 |

### 不涉及文件

- `lib/web/` - Web 服务器和路由不受影响
- `lib/tui/` - TUI 模块不受影响
- `cmd/` - 命令行入口不受影响

## 实施计划 [必填]

### 阶段 1：快速修复（预估 1 天）

#### 任务包 1.1：mooncakes 发布（10 分钟）
- 执行 `moon login`（如首次）
- 执行 `moon publish`
- 验证 `https://mooncakes.io/hnlyxiaobing/MBOpenClacky` 可访问

#### 任务包 1.2：第三方许可文件（0.5 天）
- 下载 highlight.js LICENSE（BSD-3-Clause）
- 下载 marked.js LICENSE（MIT）
- 更新 `web/js/lib/README.md`
- 可选：创建 `THIRD_PARTY_LICENSES.md`

#### 任务包 1.3：成本计算接线（0.5 天）
- `lib/agent/moon.pkg` 添加 `lib/pricing` 依赖
- 修改 `calculate_model_cost` 调用 `@pricing.calculate_cost`
- 测试验证

### 阶段 2：中等工作量（预估 1-2 天）

#### 任务包 2.1：C 头文件提取（0.5 天）
- 提取 `http_native.h` 和 `http_thread.h`
- 更新 `.c` 文件添加 `#include`
- 验证编译

#### 任务包 2.2：SQLite 决策确认（0.5 天）
- 与项目负责人确认方案 A 或 B
- 如选方案 A：修改 README 和申报材料
- 如选方案 B：进入阶段 3

### 阶段 3：高工作量（预估 2-3 天，仅方案 B 和渠道修复时执行）

#### 任务包 3.1：SQLite 实现（2-3 天，仅方案 B）
- SQLite FFI 绑定
- 会话持久化迁移
- 计费持久化迁移
- 测试验证

#### 任务包 3.2：渠道配置加载（0.5 天）
- 实现 `manager.mbt` 的 `load_config`
- JSON 配置文件解析

#### 任务包 3.3：消息 ID 提取（1 天）
- dingtalk、feishu、discord 的 HTTP 响应解析
- 替换 placeholder message_id

#### 任务包 3.4：微信 AES 加密（1-2 天）
- 调研 moonbitlang/x/crypto AES 支持
- 实现或引入 AES-128-ECB
- 替换 weixin_api.mbt 占位函数

## 验收标准 [必填]

### 阶段 1 验收
- [ ] `https://mooncakes.io/hnlyxiaobing/MBOpenClacky` 可访问
- [ ] `web/js/lib/LICENSE-highlightjs` 存在
- [ ] `web/js/lib/LICENSE-marked` 存在
- [ ] `web/js/lib/README.md` 版本号正确
- [ ] `calculate_model_cost` 返回真实成本（非 None）
- [ ] `moon check` 0 errors
- [ ] `moon test lib/agent` 通过

### 阶段 2 验收
- [ ] `lib/client/http_native.h` 存在
- [ ] `lib/client/http_thread.h` 存在
- [ ] SQLite 方案已确认并执行

### 阶段 3 验收（如执行）
- [ ] SQLite 持久化正常工作（方案 B）
- [ ] 渠道配置加载正常
- [ ] 消息 ID 为真实值（非 placeholder）
- [ ] 微信 AES 加解密正常
- [ ] `moon check` 0 errors
- [ ] `moon test` 全部通过

### 最终验收
- [ ] 所有评审反馈项已处理
- [ ] `moon check` 0 errors
- [ ] `moon test` 2769/2769 通过（或更多）
- [ ] `moon build --target native --release cmd` 构建成功
- [ ] 重新提交复核申请

## 风险评估 [必填]

| 风险 | 影响 | 概率 | 缓解方案 |
|------|------|------|---------|
| 方案 A 评审不接受 | 高 | 中 | 预留方案 B 实施时间 |
| SQLite FFI 编译问题 | 中 | 低 | 参考 http_native.c 模式 |
| 微信 AES 无现成包 | 中 | 高 | FFI 调用 OpenSSL 作为备选 |
| 渠道 API 响应格式变化 | 低 | 低 | 基于实际 API 测试 |
| mooncakes 发布失败 | 低 | 低 | 检查 moon login 状态 |

## 依赖关系 [必填]

### 子 spec 依赖图

```
总览 spec
├── 01_cost-tracker-wiring (无依赖)
├── 02_channel-placeholder-fixes (无依赖)
├── 03_sqlite-persistence-decision (无依赖，需人工决策)
├── 04_c-header-files (无依赖)
└── 05_third-party-licenses (无依赖)
```

### 与现有 spec 的关系

- 与 `specs/completed/2026-07-13_09_session-zip-export-import.md` 无冲突
- 与 `specs/active/2026-07-13_16_test-coverage-expansion.md` 可能有交集（测试覆盖）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈核对报告 |
| 2026-07-17 | 对抗性审查：更新子 spec 状态 | 子 spec 03 已决策方案 A；子 spec 02 风险重估（HTTP transport 未接通，x/crypto 无 AES）；子 spec 05 补全所有库 LICENSE |

---

## 子 Spec 索引

| 子 Spec | 文件名 | 状态 | 工作量 |
|---------|--------|------|--------|
| 成本计算接线 | `2026-07-17_01_cost-tracker-wiring.md` | ✅ 已完成 | 0.5 天 |
| 渠道占位修复 | `2026-07-17_02_channel-placeholder-fixes.md` | ✅ 已完成（HTTP transport 已接通；AES-128-ECB 推迟至独立 spec） | 3-4 天 |
| SQLite 决策 | `2026-07-17_03_sqlite-persistence-decision.md` | ✅ 已完成（验证无需修改） | 0.5 天 |
| C 头文件提取 | `2026-07-17_04_c-header-files.md` | ✅ 已完成 | 0.5 天 |
| 第三方许可 | `2026-07-17_05_third-party-licenses.md` | ✅ 已完成 | 0.5 天 |
