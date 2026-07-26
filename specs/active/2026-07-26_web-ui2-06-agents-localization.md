# Agents 本地化与第三 Agent 补全 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: 无  
> **来源差距**: BUG-006（P1）、BUG-017（P2）  
> **依赖**: 无  
> **优先级**: P1（首页 Agent 卡片仅 2 个、无中文、无头像，体验显著下降）

## 问题描述 [必填]

`GET /api/agents` 仅返回 2 个 agent（coding/general），缺少原项目的第三个 `ext-developer`；`title_zh`/`description_zh` 为空字符串，`avatar` 为 null。导致首页 Agent 选择卡片仅显示 2 个选项、无中文名称、图标退化为首字母圆形，且显示原始英文描述与"作者 openclacky"文本（BUG-017）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-006 "仅 2 agent" | `curl /api/agents` | `[{"id":"coding",...},{"id":"general",...}]` 仅 2 个 | 确认 |
| "缺 ext-developer" | `grep -r "ext-developer\|ext_developer" lib/ cmd/` | 0 命中 | 确认：第三个 agent 完全缺失 |
| "assets/agents 目录" | `ls assets/agents/` | 仅 `coding/`、`general/`（+ SOUL.md/USER.md），无 ext-developer 目录 | 确认 |
| "title_zh/description_zh 空" | `curl /api/agents` | `"title_zh":"","description_zh":""` | 确认 |
| "title_zh 硬编码" | 读 `lib/web/handlers_agents.mbt:150-160` | `"title_zh": "".to_json()`、`"description_zh": "".to_json()` 硬编码空串 | 确认根因 |
| "avatar null" | 读 handlers_agents.mbt:157 + curl | avatar 仅当 `avatar.png` 存在才非 null；两 agent 目录无 avatar.png -> null | 确认 |
| "orig 契约" | 报告对照 orig | 3 agent（general/coding/ext-developer），含 title_zh/description_zh 中文，avatar URL | 以 orig 为基准 |
| "ProfileSpec 仅 2" | 读 `lib/agent/default_profiles.mbt:23` | `get_default_profiles()` 返回 `[coding_profile(), general_profile()]` | 确认（与 assets 目录一致） |

### 详细分析

`load_agents_from_assets`（handlers_agents.mbt:116）扫描 `assets/agents/` 目录，每目录读 `config.toml`（name/display_name）与 `system_prompt.md`（首段描述）。响应字段 `title_zh`/`description_zh` 硬编码空串，avatar 依赖 `avatar.png`。`ext-developer` 既无目录也无 ProfileSpec。中文本地化字段无数据源。

## 决策 [必填 - 含为什么]

1. **新增 `ext-developer` agent 目录**：在 `assets/agents/ext-developer/` 添加 `config.toml`/`system_prompt.md`（扩展开发角色），并在 `default_profiles.mbt` 注册 `ext_developer_profile()`。与 orig 三个 agent 对齐。
2. **title_zh/description_zh 从 config.toml 读取**：扩展 `config.toml` 增加 `title_zh`/`description_zh` 键，handler 用 `agents_toml_str` 读取（已有 TOML 解析）。三个 agent 均补中文标题（"日常工作"/"编程开发"/"扩展开发"）与描述。
3. **avatar：为三个 agent 提供 avatar.png 或默认图标**：优先放 avatar.png 资源；若无则 orig 亦有降级，但为体验补齐图标。avatar URL 沿用现有 `/agent_avatar/<id>` 机制。
4. **不硬编码中文字符串在 handler**：中文来自 config.toml 数据，handler 通用化读取，便于后续扩展。
5. **MoonBit 约束检查**：纯资产文件 + handler TOML 读取，无 AOT/FFI。

<!-- MoonBit 约束：无 AOT trait；无 FFI；config.toml 已有 agents_toml_str 解析器，复用。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `assets/agents/ext-developer/config.toml` | 新建 | name=ext-developer, display_name, title_zh, description_zh |
| `assets/agents/ext-developer/system_prompt.md` | 新建 | 扩展开发角色系统提示词 |
| `assets/agents/coding/config.toml` | 修改 | 增加 title_zh/description_zh |
| `assets/agents/general/config.toml` | 修改 | 增加 title_zh/description_zh |
| `assets/agents/*/avatar.png` | 新建 | 三个 agent 头像图标（或统一默认） |
| `lib/agent/default_profiles.mbt` | 修改 | 新增 `ext_developer_profile()`，加入 `get_default_profiles()` |
| `lib/web/handlers_agents.mbt` | 修改 | `title_zh`/`description_zh` 从 config.toml 读取（复用 `agents_toml_str`） |
| `lib/web/handlers_agents_wbtest.mbt` | 修改 | 3 agent、中文非空、avatar 非空断言 |

### 不涉及文件

- Agent 运行时/工具权限逻辑（除非 ext-developer 需特定工具集）
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：ext-developer 资产与 ProfileSpec（预估 0.4 天）
- 新建 ext-developer 目录与 config.toml/system_prompt.md；注册 ProfileSpec。
- 为三 agent config.toml 补 title_zh/description_zh。

### 任务包 2：handler 本地化读取 + avatar（预估 0.3 天）
- handler 读 title_zh/description_zh；放置 avatar.png。
- 白盒：3 agent、title_zh 非空、avatar 非 null。

## 验收标准 [必填]

- [ ] `GET /api/agents` 返回 3 个 agent（含 ext-developer）
- [ ] 三 agent `title_zh`/`description_zh` 非空且为中文（"日常工作"/"编程开发"/"扩展开发"）
- [ ] 三 agent `avatar` 非 null（图标正常显示，非首字母圆形）
- [ ] 首页 Agent 卡片显示 3 个中文选项（BUG-017 修复）
- [ ] `moon check` 0 errors（lib/web、lib/agent）
- [ ] `moon test` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ext-developer 系统提示词与工具集设计不当 | 中 | 对照 orig ext-developer 角色定义；先确认 orig 该 agent 的 allowed_tools |
| avatar.png 资源版权/缺失 | 低 | 用项目既有风格图标或占位；avatar 为可选降级不影响功能 |
| config.toml TOML 解析对中文值兼容 | 低 | `agents_toml_str` 已按 `"value"` 解析，UTF-8 中文无特殊处理需求；白盒验证 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-006/017 起草，已 curl + grep + 读 handlers_agents.mbt/default_profiles.mbt 验证（ext-developer 0 命中、title_zh 硬编码空串确认） |
| 2026-07-26 | 审核修正：`load_agents_from_assets` :151 -> :116；`title_zh` :175-190 -> :150-160；`avatar` :168 -> :157；`get_default_profiles` :24 -> :23 | 对抗性审核 + 第一性原理校验 |
