# SQLite 持久化决策 · 增量 Spec

> **创建日期**: 2026-07-17
> **状态**: 已决策（方案 A）
> **关联总览**: 大赛验收反馈 #1 - SQLite 持久化未实现
> **来源差距**: 申报承诺 SQLite 持久化，实际为 JSON 文件存储
> **依赖**: 无

## 问题描述 [必填]

大赛申报中承诺"SQLite 持久化"，但实际实现为 JSON 文件存储。评审反馈指出此差异。

当前持久化实现：
- 会话持久化：`lib/agent/session_store.mbt` → `~/.mbopenclacky/sessions/*.json`
- 计费持久化：`lib/billing/billing_store.mbt` → JSON 文件

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "项目无 SQLite 绑定代码" | `grep -rn "sqlite\|SQLite" lib/ cmd/` | 仅 1 处测试断言字符串 | 确认无 SQLite 实现 |
| "会话持久化为 JSON" | `grep -n "write_string_to_file\|read_string_from_file" lib/agent/session_store.mbt` | 使用 `@fs` 写 JSON | 确认 JSON 存储 |
| "计费持久化为 JSON" | `grep -n "write\|read" lib/billing/billing_store.mbt` | 文件读写 | 确认 JSON 存储 |
| "项目有 FFI 模式参考" | `ls lib/client/http_native.c` | 文件存在（391 行） | 可参考 FFI 模式 |

### 详细分析

**方案 A（改申报描述）**：
- 工作量：0.5 天（仅修改文档）
- 风险：无技术风险
- 适用场景：如果评审方接受"JSON 文件持久化"作为替代方案

**方案 B（实现 SQLite）**：
- 工作量：2-3 天
- 需要：新增 `lib/db/` 包，通过 MoonBit native FFI 绑定 SQLite3 C API
- 核心函数：`open/exec/query/close`
- 需要：替换 `session_store.mbt` 和 `billing_store.mbt` 的读写后端
- 需要：SQLite3 C 源文件（sqlite3.c + sqlite3.h）引入项目

## 决策 [必填 - 含为什么]

**已决策：方案 A（改申报描述）**。

理由：
- JSON 文件持久化已稳定运行，满足当前功能需求
- SQLite 实现成本高（2-3 天），且 wasm-gc 后端不支持 FFI，仅 native 可用
- 评审反馈核心是"描述与实现不符"，修正描述即可闭环
- 如后续有更高并发/查询需求，可再启动方案 B

**方案 A 执行内容**：
- README.md 中"SQLite 持久化"改为"JSON 文件持久化"
- 大赛申报材料同步修正
- 不改动任何代码

**方案 B 保留条件**：若评审方不接受方案 A，或未来有 SQL 查询/并发写入需求，重新启动方案 B。

## 改动范围 [必填]

### 方案 A 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| README.md | 修改 | 将"SQLite 持久化"描述改为"JSON 文件持久化" |
| 大赛申报材料 | 修改 | 同步修正描述 |

### 方案 A 不涉及文件

- 所有 `.mbt` 代码文件

### 方案 B 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/db/` | 新建包 | SQLite FFI 绑定 |
| `lib/db/native-stub/sqlite3.c` | 新建 | SQLite3 源文件 |
| `lib/db/native-stub/sqlite3.h` | 新建 | SQLite3 头文件 |
| `lib/db/db.mbt` | 新建 | MoonBit API：open/exec/query/close |
| `lib/db/moon.pkg` | 新建 | 包配置（native-stub + link.native） |
| `lib/agent/session_store.mbt` | 修改 | 切换到 SQLite 后端 |
| `lib/agent/moon.pkg` | 修改 | 添加 `lib/db` 依赖 |
| `lib/billing/billing_store.mbt` | 修改 | 切换到 SQLite 后端 |
| `lib/billing/moon.pkg` | 修改 | 添加 `lib/db` 依赖 |

### 方案 B 不涉及文件

- `lib/client/` - HTTP 客户端不受影响
- `lib/channel/` - 渠道模块不受影响

## 实施计划 [必填]

### 方案 A：修改申报描述（预估 0.5 天）✅ 已选
- 修改 README.md 中的持久化描述
- 修改大赛申报材料
- 提交复核并确认评审方接受

### 方案 B：实现 SQLite（预估 2-3 天）— 仅当方案 A 被拒绝时启用

#### 任务包 1：SQLite FFI 绑定（预估 1 天）
- 引入 sqlite3.c 和 sqlite3.h 到 `lib/db/native-stub/`
- 编写 MoonBit FFI 绑定：`open_database()` / `exec_sql()` / `query_sql()` / `close_database()`
- 配置 `moon.pkg`（`native-stub` + `link.native`）
- 基本功能测试

#### 任务包 2：会话持久化迁移（预估 0.5 天）
- 修改 `session_store.mbt`，将 JSON 读写替换为 SQLite 操作
- 创建 sessions 表 schema
- 数据迁移逻辑（首次启动时从 JSON 导入）

#### 任务包 3：计费持久化迁移（预估 0.5 天）
- 修改 `billing_store.mbt`，将 JSON 读写替换为 SQLite 操作
- 创建 expenses 表 schema
- 数据迁移逻辑

#### 任务包 4：测试与验证（预估 0.5 天）
- 更新所有持久化相关测试
- 验证数据完整性
- `moon check` + `moon test` 通过

## 验收标准 [必填]

### 方案 A 验收
- [ ] README.md 和申报材料中"SQLite 持久化"已改为"JSON 文件持久化"
- [ ] 评审方接受修正后的描述

### 方案 B 验收
- [ ] `lib/db/` 包可正常编译（`moon check` 0 errors）
- [ ] 会话数据通过 SQLite 持久化（非 JSON 文件）
- [ ] 计费数据通过 SQLite 持久化（非 JSON 文件）
- [ ] 首次启动时自动从旧 JSON 数据迁移
- [ ] `moon check` 0 errors
- [ ] `moon test lib/db` 通过
- [ ] `moon test lib/agent` 通过
- [ ] `moon test lib/billing` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 方案 A 评审不接受 | 高 | 预留方案 B 的实施时间 |
| SQLite3 C 源文件体积大（~250K 行） | 低 | 只编译需要的部分，不影响功能 |
| 数据迁移丢失用户数据 | 高 | 迁移前自动备份 JSON 文件 |
| Windows 平台编译问题 | 中 | 参考 `http_native.c` 的 Windows 兼容处理 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈 #1 |
| 2026-07-17 | 决策确定：方案 A | 与项目负责人确认，优先改描述 |
