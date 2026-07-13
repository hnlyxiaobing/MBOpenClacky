# Extension CLI 命令实现 · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G8（P1 重要功能差距）
> **关联历史**: `specs/completed/2026-07-09_extension-framework-mvp.md`（MVP 已完成）
> **来源差距**: G8 - Extension CLI 命令（ext list/install/create/enable/disable/uninstall）
> **依赖**: 无（CLI 命令调用已有 `lib/extension/marketplace.mbt` API，不依赖 G2 API 路由 DSL）

## 问题描述

原项目 `ext_cli.rb`（226 行）提供了完整的命令行扩展管理接口，当前 CLI（`cmd/`）中无对应 `ext` 子命令。用户无法通过 CLI 管理扩展，只能通过 Web 面板操作。

## 现状分析（经代码验证）

### `cmd/` 目录结构
- `cmd/main.mbt`：CLI 入口，子命令通过参数匹配路由
- `cmd/patch_loader.mbt`：启动时 patch 加载（独立于本 spec）
- `cmd/api_extension_loader.mbt`（71 行）：已有 CLI 侧扩展加载和验证（`load_extensions()` + `register_extensions()`），但无交互式管理命令
- `cmd/hook_loader.mbt`、`cmd/channel_scaffold.mbt`、`cmd/ndjson_logger.mbt`：其他 CLI 模块
- **不存在 `cmd/cli_*.mbt` 命名模式**（原 spec 引用有误）

### `lib/extension/marketplace.mbt`（428 行）已有 API
- `list_marketplace_extensions() -> Array[RegistryEntry]`：列出市场扩展
- `list_installed_extensions() -> Array[Extension]`：列出已安装扩展
- `list_local_extensions() -> Array[Extension]`：列出本地扩展
- `enable_extension(ext_id) -> Result[Extension, String]`：启用扩展（当前为 stub，仅 println，不持久化状态）
- `disable_extension(ext_id) -> Result[Extension, String]`：禁用扩展（当前为 stub，仅 println，不持久化状态）
- `install_extension_from_path(ext_path) -> Result[Extension, String]`：从路径安装扩展

### `lib/extension/scaffold.mbt` 已有
- `create_extension_scaffold()`：扩展骨架创建

### 关键差距
1. **无 `ext` CLI 子命令**：`cmd/main.mbt` 中无 `ext` 路由分支
2. **`enable_extension`/`disable_extension` 为 stub**：不持久化启用/禁用状态到磁盘
3. **无 `uninstall_extension` API**：marketplace.mbt 中无卸载方法
4. **`install_extension_from_path` 无 CLI 封装**：API 存在但无命令行入口

## 关键决策（含为什么）

1. **新增 `cmd/cli_ext.mbt`**：按现有 cmd 模块命名（如 `cmd/patch_loader.mbt`、`cmd/api_extension_loader.mbt`），实现 6 个扩展管理命令。
2. **`ext enable/disable` 需修复 stub**：`enable_extension`/`disable_extension` 当前不持久化状态。需在 `lib/extension/marketplace.mbt` 中增加状态持久化（写入 `~/.clacky/extensions/enabled_state.json`）。
3. **`ext install` 支持本地路径**：先支持本地 `.clackyext` 文件或目录安装（调用已有 `install_extension_from_path`），远程市场安装后续对接。
4. **`ext uninstall` 需新增 API**：在 `lib/extension/marketplace.mbt` 中增加 `uninstall_extension(ext_id)` 方法，删除扩展目录。
5. **`ext create` 复用 scaffold**：调用已有 `create_extension_scaffold()`。
6. **输出格式**：列表用对齐文本（非表格库），安装/卸载用状态消息。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `cmd/cli_ext.mbt` | 新建 | 6 个扩展命令实现 |
| `cmd/main.mbt` | 修改 | 路由 `ext` 子命令到 `cli_ext.mbt` |
| `lib/extension/marketplace.mbt` | 修改 | 修复 `enable_extension`/`disable_extension` 持久化；新增 `uninstall_extension` |
| 对应 `*_wbtest.mbt` | 新增 | 覆盖 enable/disable 持久化、uninstall |

### 不涉及文件

- `lib/web`（Web 端点不受影响）
- `lib/extension/loader.mbt`（加载逻辑不变）
- `lib/extension/scaffold.mbt`（已有 create 能力，直接复用）

## 实施计划（任务包切分）

### 任务包 1：enable/disable 持久化修复（0.5 天）
- 在 `lib/extension/marketplace.mbt` 中增加 `enabled_state.json` 读写
- `enable_extension` 写入 `{ext_id: true}`
- `disable_extension` 写入 `{ext_id: false}`
- loader 加载时合并 `enabled_state.json` 与 `enabled_by_default`

### 任务包 2：uninstall API（0.5 天）
- 在 `lib/extension/marketplace.mbt` 中增加 `uninstall_extension(ext_id) -> Result[Unit, String]`
- 删除 `~/.clacky/extensions/<ext_id>/` 目录
- 从 registry 中移除记录

### 任务包 3：CLI 命令实现（1 天）
- `ext list`：调用 `list_installed_extensions()` + `list_local_extensions()`，格式化输出
- `ext install <path>`：调用 `install_extension_from_path()`
- `ext uninstall <name>`：调用新增的 `uninstall_extension()`
- `ext create <name>`：调用 `create_extension_scaffold()`，交互式输入
- `ext enable <name>`：调用修复后的 `enable_extension()`
- `ext disable <name>`：调用修复后的 `disable_extension()`

### 任务包 4：集成测试（0.5 天）
- `moon run cmd -- ext list` 正常输出
- `moon run cmd -- ext install <path>` 成功安装
- `moon run cmd -- ext enable/disable <name>` 状态持久化

## 验收标准

- [ ] 6 个 CLI 命令均可正常执行
- [ ] `ext list` 输出格式清晰（名称、版本、状态、来源）
- [ ] `ext install` 可安装本地 `.clackyext` 文件或目录
- [ ] `ext uninstall` 可删除扩展并清理文件
- [ ] `ext create` 生成合规扩展骨架
- [ ] `ext enable/disable` 正确切换扩展状态并持久化到 `enabled_state.json`
- [ ] `moon check` 0 errors（`cmd` + `lib/extension`）
- [ ] `moon run cmd -- ext list` 正常输出
- [ ] `moon test lib/extension --filter "enable*|disable*|uninstall*"` 通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `ext uninstall` 误删文件 | 高 | 卸载前确认提示；仅删除 `~/.clacky/extensions/<id>/` 目录，不递归删除父目录 |
| `enable/disable` 状态文件竞争 | 低 | 单用户 CLI 环境，无并发问题 |
| `ext install` 远程市场未就绪 | 中 | 先支持本地文件安装，远程市场后续对接 |
| `enabled_state.json` 与 loader 的 `enabled_by_default` 冲突 | 中 | loader 优先读取 `enabled_state.json`，fallback 到 `enabled_by_default` |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G8，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"参考 `cmd/cli_*.mbt`"（该命名模式不存在）；修正 G2 依赖为无依赖（CLI 调用已有 marketplace API）；补充 `enable_extension`/`disable_extension` 为 stub 的现状；补充 `uninstall_extension` API 缺失；补充 `cmd/api_extension_loader.mbt` 已存在的现状；补充 enable/disable 持久化修复任务 | 对抗性审核 + 第一性原理校验 |
