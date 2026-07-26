# Skills 技能多行描述与 source 字段修复 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-15-skills-api-fields.md`（fix-15 已对齐 skills 列表字段）  
> **来源差距**: BUG-003（P1）、BUG-020（P3）  
> **依赖**: 无  
> **优先级**: P1（技能描述不可读，影响技能展示与选择）

## 问题描述 [必填]

`GET /api/skills` 对使用 YAML block scalar（`|` / `>`）多行语法的技能，`description` 字段返回字面量 `"|"`（块标量指示符），而非实际多行文本。影响 `browser-setup`、`channel-manager` 等使用 `description: |` 语法的技能，前端技能描述完全不可读。

同时 `source` 字段返回 `"builtin"`，原项目契约为 `"default"`。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-003 "description 为 '|'" | `curl /api/skills` | `{"name":"browser-setup","description":"|",...}` | 确认 |
| "SKILL.md 用块标量" | `grep -n "^description:" assets/skills/browser-setup/SKILL.md` | `4:description: |` | 确认：YAML block scalar 语法 |
| "loader 取字面值" | 读 `lib/skill/loader.mbt:149` | `description: fields.get("description")` 直接取 `description:` 后的剩余内容（即 `|`），未解析多行块 | 确认根因 |
| BUG-020 "source 为 builtin" | `curl /api/skills` | `"source":"builtin"` | 确认 |
| "source 字段来源" | grep `lib/web/handlers_skills.mbt` 的 source 赋值 | handler 层固定 `"builtin"` | 确认 |
| "orig 契约" | 报告对照 orig | orig description 为完整多行文本；source 为 `"default"` | 以 orig 为基准 |

### 详细分析

- **description（BUG-003）**：`lib/skill/loader.mbt` 的 frontmatter 解析器按行处理，`description:` 行剩余内容为 `|`，未实现 YAML block scalar 解析（`|` 保留换行、`>` 折叠换行）。多行技能描述（含换行的详细说明）被丢弃，只留指示符。需在 frontmatter 解析中识别 `|`/`>` 并收集后续缩进行。
- **source（BUG-020）**：handler 层把内置技能 source 标为 `"builtin"`，orig 用 `"default"`。属命名差异，前端按 source 分类可能不匹配。

## 决策 [必填 - 含为什么]

1. **description：在 skill frontmatter 解析中支持 block scalar**：识别 `description: |` / `description: >`，收集后续缩进行，`|` 保留换行、`>` 折叠为空格。保持非块标量（普通 `description: 文本`）原行为。避免引入完整 YAML 依赖（MoonBit 生态无成熟 YAML 库），手写最小块标量解析即可。
2. **source：内置技能改返回 `"default"`**：与 orig 一致。在 handler 层把 builtin 映射为 `"default"`（或源头改）。
3. **description 多行如何呈现给前端**：orig 返回完整多行文本（含 `\n`）。前端按需截断/折叠。保持原文返回。
4. **MoonBit 约束检查**：纯字符串解析，无 AOT/FFI。不引入 YAML C 库。

<!-- MoonBit 约束：无 AOT trait；无 FFI；手写块标量解析，不依赖外部 YAML 库。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/skill/loader.mbt` | 修改 | frontmatter 解析增加 block scalar（`|`/`>`）多行收集逻辑 |
| `lib/web/handlers_skills.mbt` | 修改 | 内置技能 source 字段 `"builtin"` -> `"default"` |
| `lib/skill/*_wbtest.mbt` 或 `lib/web/handlers_skills_wbtest.mbt` | 修改 | 块标量 description 解析断言；source=default 断言 |

### 不涉及文件

- SKILL.md 资产文件本身（不改内容）
- 其他 source 类型（user/uploaded）的命名

## 实施计划 [必填]

### 任务包 1：block scalar 解析（预估 0.4 天）
- loader frontmatter 解析：遇 `key: |` 或 `key: >` 时，收集后续缩进行直到非缩进行；`|` join("\n")、`>` join(" ")。
- 白盒：构造含 `description: |` + 多行的 SKILL.md，断言解析为完整文本。

### 任务包 2：source 字段对齐（预估 0.1 天）
- handler 内置 source 映射为 `"default"`。
- 白盒断言。

## 验收标准 [必填]

- [ ] `GET /api/skills` 中 `browser-setup`/`channel-manager` 的 `description` 为完整多行文本（非 `"|"`)
- [ ] 内置技能 `source` 为 `"default"`
- [ ] 非 block scalar 的普通 description 行为不变
- [ ] `moon check` 0 errors（lib/skill、lib/web）
- [ ] `moon test lib/skill lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 块标量解析误吞下一非缩进键 | 中 | 严格按缩进层级判断块结束；白盒覆盖含多键的 frontmatter |
| 多行 description 含特殊字符（引号/冒号）致前端渲染问题 | 低 | 原样返回文本，前端按 orig 方式处理 |
| source 改名影响前端按 builtin 过滤的逻辑 | 低 | orig 用 default，前端按 orig 适配；当前前端未用此字段做关键逻辑 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-003/020 起草，已 curl + 读 loader.mbt:149 与 SKILL.md 验证根因 |
| 2026-07-26 | 审核修正：无事实错误。`loader.mbt:149`（description: fields.get）经 grep 确认；source="builtin" 正确归于 `handlers_skills.mbt:58/214` 与 `default_skills.mbt:210`（非 loader.mbt），spec 改动范围已正确列出 handlers_skills.mbt | 对抗性审核 + 第一性原理校验 |
