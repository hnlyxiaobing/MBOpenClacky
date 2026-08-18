# 技能系统与系统提示词对齐（矩阵§6）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §6  
> **关联历史 spec**: 边界——`p5-session-context-alignment` 覆盖矩阵§7 的 session context 注入（与本 spec 层 "环境/模型/工作目录信息位置" 条目交叉，实施时以该 spec 为准）；invoke_skill 工具参数/注入机制归 B3 决策 12，本 spec 管技能加载与提示词侧；矩阵旧台账编号已被覆盖，一律使用 `矩阵§6/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§6 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 无硬依赖  
> **灰度 key**: 无

## 问题描述 [必填]

### 技能加载（高危：懒加载必然失败）

1. **内置技能名与磁盘目录不匹配致懒加载必然失败（partial，已核实）**：`default_skills.mbt` 硬编码元数据中 `browser_setup`/`channel_manager`/`personal_website` 为下划线，磁盘目录为 `browser-setup`/`channel-manager`/`personal-website`（连字符）——模型调用这三个内置技能时懒加载按名找目录必然落空。矩阵称 4 个，本次核实 3 个显式不匹配（第 4 个待任务包 0 全量比对）。
2. **内置技能为硬编码元数据而非磁盘 SKILL.md（partial）**：Ruby 从磁盘加载完整 SKILL.md；MB 17 条（本次 grep 见 15+ 条）硬编码且描述缩水；磁盘实际有 18 个目录（含 extend-openclacky/meeting-summarizer/skill-add 未进硬编码表）。
3. **frontmatter 手写解析不支持块列表（partial，已核实）**：`loader.mbt:54-58` 逐行 `find(":")` key:value 解析；Ruby `YAML.safe_load`——多行列表/嵌套字段的 SKILL.md 解析错乱。
4. **frontmatter 缺 name 直接丢弃（missing）**：Ruby 回退目录名；MB 丢弃整个技能。
5. **name slug 校验/warnings/invalid 标记缺失（missing）**；**描述 340 字符截断 + 首段回退缺失（missing）**。
6. **发现路径差异（partial）**：MB 多出 `.qoder/skills`、`skills/`、`.skills/`（超集裁决点）；文件名后缀匹配会误收 `myskill.md`（应为严格 `SKILL.md`）。
7. **扩展技能 / brand 加密技能来源缺失（missing）**。
8. **同名去重无仲裁记录（partial）**：MB 仅 Map 覆盖；Ruby 显式仲裁并记录错误。
9. **技能内容处理缺失（missing）**：`${ENV}` 展开/ERB/shell 输出/Supporting Files 均无（executor.mbt:12-56）。
10. **slash 命令解析与 agent 作用域校验弱（partial）**；**`disable-model-invocation` 不过滤、`agent:` 作用域语义相反（missing）**。
11. **auto_summarize 默认值相反（partial）**：Ruby true；MB false。
12. **提示词技能列表排序/LRU/30 条截断/MCP 分组缺失（missing）**；**create/toggle/delete 管理 API 仅 remove（partial——server 技能 toggle 路由断链归 B9）**。

### profile 链路

13. **profile 加载顺序与内置回退缺失（missing）**：MB 仅查用户目录，找不到静默回退空 profile；Ruby 用户目录>扩展>内置、找不到报错。
14. **profile.yml 解析未实现（missing，已核实）**：`lib/agent/profile.mbt:11` 代码内 TODO，返回空壳 ProfileConfig。
15. **SOUL.md/USER.md 路径少 `agents/` 一级、无兜底文案（partial）**；**注入无 1000 字符截断（missing）**。
16. **profile 列表 API 仅 3 条硬编码（missing）**；**CLI 硬编码 "CLI Agent" 致 profile 永远落空（partial）**。
17. **profile.yml skills 白名单消费（unclear）**：两侧均疑似死代码，任务包 0 核查。

### 系统提示词层（影响模型行为的根基层）

18. **层 1 agent 专属 prompt 缩水（missing）**：Ruby coding agent 全文 3962 字符；MB 只剩 180 字符硬编码 Role。
19. **层 2 通用行为规则 base.md 自撰缩水（partial）**：Ruby 2248 字符原文；MB 约 700 字符自撰版。
20. **层 3 项目规则格式文案不同（partial）**；**层 4/5 SOUL/USER 注入实际为空（missing，因条目 15）**。
21. **层 6 技能上下文格式完全不同（partial）**。
22. **环境/模型/工作目录信息位置（partial）**：MB 写进 system prompt 静态不刷新；Ruby 作 `[Session context]` user 消息按日刷新（与 p5-session-context-alignment 交叉，该 spec 为准）。
23. **MB 特有 brand 声明层与 Memory/Tasks 层（partial，裁决点）**：Ruby 无此两层，MB 超集是否保留。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| 内置技能名下划线 vs 磁盘连字符 | Grep `default_skills.mbt` name 字段 + 列 `assets/skills` 目录 | `browser_setup`/`channel_manager`/`personal_website` vs `browser-setup`/`channel-manager`/`personal-website` | 证实（3 个显式；矩阵称 4 个，全量比对留任务包 0） |
| 磁盘技能集与硬编码表不一致 | 列目录 | 磁盘 18 个目录含 extend-openclacky/meeting-summarizer/skill-add，硬编码表无 | 证实 |
| frontmatter 手写 key:value | 读 `lib/skill/loader.mbt:52-58` | `line.find(":")` 逐行解析 | 证实 |
| profile.yml TODO 空壳 | 读 `lib/agent/profile.mbt:8-24` | 3 处 TODO，返回默认 ProfileConfig | 证实 |
| profile 仅查用户目录 | 读 `lib/agent/profile.mbt:96-102` | 仅 `config_dir()/agents/<name>`，无扩展/内置回退 | 证实 |
| slug 校验/截断/去重仲裁/内容处理/disable-model-invocation/排序截断/profile 列表/提示词各层 | 矩阵行号引用（loader.mbt:212-215,254-257；discovery.mbt:14-17,57-60；registry.mbt:16-18,86-89；executor.mbt:12-56,60-90；system_prompt.mbt:11-16,20-39,92-98,133-147；profile.mbt:74-90,125-132；cmd/main.mbt:694） | 与矩阵声明一致 | 静态证实（任务包 0 逐函数复核） |

Ruby 参照（openclacky，只读）：`skill.rb:103-105,147-165,178-190,241-318,525-577`、`skill_loader.rb:90-132,241-321,482-501`、`skill_manager.rb:117-255`、`system_prompt_builder.rb:17,32-98`、`agent_profile.rb:60-129,180`、内置提示词资产（coding prompt/base.md）。

### 影响面

技能系统是 MB 侧"能力扩展面"的入口：条目 1 使部分内置技能实际不可调用；条目 18/19 的提示词缩水直接改变模型基础行为（P4 能力基准的第一变量）。本簇修复是 P4 基准可比性的前提之一。

## 决策 [必填 - 含为什么]

1. **决策 1（名称一致性，最高优先）**：统一技能名规范化——加载与查找两侧都做连字符/下划线归一（复用 registry 归一语义），并把 default_skills 硬编码表改为**磁盘 SKILL.md 扫描生成**（消除双源漂移）；硬编码表降级为磁盘缺失时的最小回退或直接移除。
   - **为什么**：双源（硬编码 vs 磁盘）是本次不匹配缺陷的根因；只改名不治本。
2. **决策 2（frontmatter）**：接入真正的 YAML 解析。选型与 B1/B2 的依赖调研同批：优先 mooncakes 可用 YAML 包；不可用则实现 SKILL.md 实际所需子集（标量 + 块列表 + 一级嵌套），并在 spec 内记录边界。缺 name 回退目录名；slug 校验/warnings/invalid 标记、描述 340 截断+首段回退按 Ruby 移植。
   - **为什么**：手写 key:value 对块列表结构性失效，打补丁无出路。
3. **决策 3（发现与去重）**：发现路径超集（`.qoder/skills` 等）作为 MB 扩展保留并记录；文件名匹配改严格 `SKILL.md`；同名去重加显式仲裁与错误记录（Ruby 语义）。
4. **决策 4（技能内容处理）**：`${ENV}` 展开、Supporting Files 按 Ruby 移植；ERB/shell 输出先评估安全面（shell 输出注入在 agent 上下文的风险），**裁决点**：可降级为"支持 ENV+Supporting Files，ERB/shell 记录豁免"。
5. **决策 5（调用过滤与作用域）**：`disable-model-invocation` 过滤实现；`agent:` 作用域语义对齐 Ruby；slash 命令 token 校验加强（拒绝路径形 token）。
6. **决策 6（提示词技能列表）**：排序/LRU/30 条截断/MCP 分组按 Ruby `skill_manager.rb` 移植；auto_summarize 默认值改 true。
7. **决策 7（profile 链路）**：profile.yml 解析实现（复用决策 2 的 YAML 结论）；加载链用户目录>扩展>内置、找不到报错；SOUL/USER 路径补 `agents/` 级 + 兜底文案 + 1000 字符截断；profile 列表 API 按 Ruby；CLI `--agent` 接线（与 B8 CLI spec 联调）。
   - **为什么**：TODO 空壳意味着 profile 功能整体"注册了但不存在"，与 trash_manager 桩同性质。
8. **决策 8（提示词层）**：层 1/2 恢复 Ruby 原文资产（coding prompt/base.md 从 openclacky 资产移植，作为 MB 仓库内资产文件管理而非内嵌字符串）；层 3 格式文案对齐；层 6 技能上下文格式对齐。
   - **为什么**：提示词是行为基准的第一变量；自撰缩水版无对照实验支撑，按判定总则回归原版。
9. **决策 9（裁决点组）**：brand 声明层与 Memory/Tasks 层默认保留（MB 产品形态差异，记录理由）；环境信息位置按 p5-session-context-alignment 结论执行；profile.yml skills 白名单两侧死代码则双侧记录豁免。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/skill/default_skills.mbt` | 重写/删除 | 磁盘扫描替代硬编码表 |
| `lib/skill/loader.mbt` | 修改 | YAML 解析接入、name 回退、slug 校验、描述截断 |
| `lib/skill/discovery.mbt` | 修改 | 严格 SKILL.md 匹配 |
| `lib/skill/registry.mbt` | 修改 | 名称归一、去重仲裁 |
| `lib/skill/executor.mbt` | 修改 | ENV/Supporting Files、上下文格式 |
| `lib/skill/skill.mbt`（或对应定义文件） | 修改 | disable-model-invocation、agent 作用域 |
| `lib/agent/profile.mbt` | 修改 | profile.yml 解析、加载链、SOUL/USER 路径与截断 |
| `lib/agent/system_prompt.mbt` | 修改 | 层结构对齐、资产引用 |
| 提示词资产目录（新建，如 `assets/prompts/`） | 新建 | coding prompt/base.md 原文资产 |
| `cmd/main.mbt` | 修改 | --agent profile 接线（与 B8 联调） |
| 对应 wbtest | 修改/新建 | 逐决策回归（含懒加载命中用例） |

### 不涉及文件

- invoke_skill 工具参数面（B3）；技能 toggle 路由（B9）；session context（p5-session-context-alignment）。

## 实施计划 [必填]

### 任务包 0：调研与全量比对（预估 0.5 天）
1. YAML 依赖选型（与 B1/B2 regex 调研同批记录）。
2. default_skills 硬编码表 vs 磁盘目录全量比对（确认第 4 个不匹配项）。
3. 逐函数复核静态证实条目。

### 任务包 1：加载链路（预估 1.5 天）
1. YAML 解析 + name 回退 + slug 校验 + 描述截断。
2. 磁盘扫描替代硬编码表；名称归一；严格 SKILL.md；去重仲裁。
3. wbtest：三个不匹配技能的懒加载命中回归。

### 任务包 2：技能语义（预估 1 天）
1. ENV/Supporting Files；disable-model-invocation；agent 作用域；auto_summarize。
2. 技能列表排序/LRU/截断/分组。

### 任务包 3：profile + 提示词层（预估 1.5 天）
1. profile.yml 解析与加载链；SOUL/USER；profile 列表。
2. 提示词资产移植与层结构对齐。

### 任务包 4：收尾（预估 0.5 天）
1. 裁决点记录（ERB/shell、brand 层、白名单死代码）。
2. `moon check` + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] browser-setup/channel-manager/personal-website（及全量比对发现的其他项）懒加载命中
- [ ] 内置技能元数据单一来源（磁盘 SKILL.md），硬编码表不再漂移
- [ ] 块列表 frontmatter 的 SKILL.md 解析正确；缺 name 回退目录名
- [ ] `myskill.md` 类文件不被误收
- [ ] profile.yml 实际解析；找不到 profile 显式报错
- [ ] SOUL/USER 注入生效且 ≤1000 字符截断
- [ ] 提示词层 1/2 为 Ruby 原文资产（字符级对照通过）
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| YAML 依赖不可用导致自研解析范围失控 | 高 | 限定 SKILL.md 实际语法面；任务包 0 先定边界 |
| 提示词全文替换改变既有 wbtest/e2e 断言 | 中 | 提示词相关断言集中评审后同步更新 |
| 磁盘扫描替代硬编码影响启动性能 | 低 | 目录数有限；懒加载语义不变 |
| ERB/shell 输出移植引入注入面 | 高 | 裁决点默认豁免，保留需安全评审 |

## 依赖关系 [必填]

- **前置依赖**：无；YAML 选型与 B1/B2 任务包 0 合并调研。
- **后置依赖**：B8 CLI `--agent` 参数以本 spec profile 链路为前提；B9 技能 toggle 路由以本 spec 管理 API 为前提。
- **交叉**：session context 位置以 p5-session-context-alignment 为准。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§6 残留条目核实落 spec；5 项直接证实 + 12 项静态证实留任务包 0 复核）。
