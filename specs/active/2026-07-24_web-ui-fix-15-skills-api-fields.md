# 技能列表 API 字段对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-07_skills-web-api.md`  
> **来源差距**: I-021 / I-025（均 P2）  
> **依赖**: fix-06（前端验收环境）；被 fix-17 依赖

## 问题描述 [必填]

- **I-021**：`GET /api/skills` 条目缺 `name_zh`/`description_zh`/`always_show`/`warnings` 等 9 个展示字段，中文界面下技能列表缺名称与描述。
- **I-025**：`GET /api/sessions/:id/skills` 返回空数组，orig 同位置有 53 个技能；需确认是数据差异还是加载未实现。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-021 "skills 条目仅四键" | `Read lib/web/handlers_skills.mbt:74-100` | `scan_skills` 条目仅 `name/description/source/enabled`，description 取自 SKILL.md 正文提取（`skill_description_of`），无 name_zh/description_zh/always_show/warnings | 确认 |
| I-025 "sessions/:id/skills 是 stub" | `Read lib/web/handlers_session_ext.mbt:652-670` | `handle_session_skills` 固定返回 `{session_id, skills: []}`，注释自承 TODO(P3) 未接 skill registry | 确认属"加载未实现"而非数据差异 |
| "技能扫描数据源" | `Read lib/web/handlers_skills.mbt:169-188` | 合并 `assets/skills`（builtin）与 `.mbopenclacky/skills`（user）两目录 | 确认 sessions 端点可复用同一扫描 |
| "orig 9 字段清单" | `docs/web-ui-issues.md` I-021 | name_zh/description_zh/always_show/warnings 等（需读 orig Ruby skills handler 逐键确认完整清单与语义） | 待实施时对照 |

### 详细分析

两个 issue 同源：技能元数据提取层（`scan_skills`/`skill_description_of`）只解析了 frontmatter 的冰山一角。orig 的 9 个展示字段大概率来自 SKILL.md frontmatter 扩展键（中文名/描述、always_show、warnings 等），修复方向是增强 frontmatter 解析并按 orig 形状输出；`sessions/:id/skills` 则把 stub 替换为复用同一扫描逻辑的真实列表（session 作用域与全局的差异以 orig 语义为准）。

## 决策 [必填 - 含为什么]

1. **增强 `scan_skills` 的 frontmatter 解析，单点修复两处受益**：/api/skills 与 sessions/:id/skills 共用扫描，字段提取改一处即可。
2. **sessions/:id/skills 复用全局扫描**：orig 同位置返回 53 个技能与全局列表量级一致，无证据表明 orig 做了 session 级过滤；若 orig 确实有过滤语义，按其实现，否则按全局列表返回。
3. **未识别的 frontmatter 键按原样透传而非丢弃**：warnings 等数组/对象字段直接透传 JSON，避免逐键发明解析逻辑。
4. **scope 上限**：只到"返回与 orig 同形状的真实列表"，不碰技能执行/加载进 agent 的逻辑（fix-17 发布功能另行依赖本数据通路）。
5. **MoonBit 约束检查**：纯解析与 JSON 输出改动，无约束问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_skills.mbt` | 修改 | scan_skills/skill_description_of 增强 frontmatter 解析，条目补 9 字段 |
| `lib/web/handlers_session_ext.mbt` | 修改 | handle_session_skills 接真实扫描 |
| `lib/web/handlers_skills_wbtest.mbt` | 修改 | 契约断言更新 |

### 不涉及文件

- 技能执行/agent 加载链路。
- `/api/creator/skills`（fix-16）、`/api/my-skills/:name/publish`（fix-17）、`/api/skills/:name/content` 的 404 错误体（fix-20 I-032）。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：orig 字段对照（预估 0.5 天）
- 读 orig Ruby skills handler 与 SKILL.md frontmatter 样例，确定 9 字段逐键来源。
- 检查 `assets/skills/` 本地技能文件的 frontmatter 实际含哪些键。

### 任务包 2：解析增强与两端点接线（预估 1 天）
- scan_skills 输出对齐；handle_session_skills 去 stub。
- 白盒测试 + Playwright 技能面板（中英文）走查。

## 验收标准 [必填]

- [ ] GET /api/skills 条目含 orig 9 字段（无数据的键按 orig 缺省规则输出）
- [ ] GET /api/sessions/:id/skills 返回真实技能列表（非空，形状同 orig）
- [ ] 中文界面技能名称/描述正常显示
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 本地 SKILL.md frontmatter 不含 zh 字段（数据缺失而非解析缺失） | 中 | 任务包 1 先盘数据；若键缺失则对齐解析后字段为空属预期，记录结论 |
| orig sessions skills 有过滤语义被忽略 | 低 | 任务包 1 读 orig 代码确认；有则照抄 |
| 9 字段清单与 issues 描述不完全一致 | 低 | 以 orig 代码逐键为准，偏差写验证记录 |

## 依赖关系 [必填]

- **前置依赖**：fix-06。
- **后置依赖**：fix-17（发布功能依赖技能数据通路正确）。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-021/I-025 合并起草；验证确认 I-025 为 stub 未实现 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：scan_skills@handlers_skills.mbt:74-100 确认仅输出 {name,description,source,enabled} 四字段，无 name_zh/description_zh/always_show/warnings；handle_session_skills@handlers_session_ext.mbt:652-670 确认返回 {session_id,skills:[]} 空数组 stub（注释自承 TODO(P3) 未接 skill registry）；handle_skills_list@:169-188 确认合并 BUILTIN_SKILLS_DIR+user_skills_dir() 两目录扫描。交叉引用 skills-web-api.md@completed/ 存在确认。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
