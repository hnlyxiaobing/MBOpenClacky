# System Prompt 装配层对齐（B0-10）· 增量 Spec

> **创建日期**: 2026-10-09
> **状态**: 讨论中
> **关联总览**: `diff-harness/reports/B0_ACCEPTANCE_2026-10-09.md` §6
> **关联历史 spec**: `2026-10-09_agent-profile-wiring-alignment.md`（B0，装配链路已接通）
> **来源差距**: BUG-0065 / BUG-0066 / BUG-0067 / BUG-0069（diff-harness 台账）
> **依赖**: B0 已落地（`--agent` 接线、assets 根绝对化、session profile 优先级）
> **灰度 key**: 无

---

## 问题描述 [必填]

B0 把「profile → system prompt」的链路接通后，同一剧本（015）抓包对比暴露了**下一层**装配差异：模型看到的 system prompt 在**层顺序、层内容、层标题格式**三方面都与 openclacky(Ruby) 不一致。

实测（015_system_prompt_assembly，同一 mock 剧本、隔离 HOME）：

| 侧 | system prompt 长度 | 层结构 |
|----|------|--------|
| ruby | 14023 字符 | `system_prompt.md` → `base.md` → [PROJECT RULES] → `[80×=] AGENT SOUL …` → `[80×=] USER PROFILE …` → skills 块 |
| moonbit | 15113 字符 | `## Agent Identity`（内含 base.md + SOUL + USER + system_prompt.md，顺序相反）→ `## Core Behavior/## Tool Usage/## Response Style`（自创）→ `## Working Directory/## Environment/## Model`（自创）→ `## Skills` |

差异不是"少写了一段"，而是**两种不同的装配模型**：Ruby 是「扁平平铺 + `=`×80 分隔块」，MB 是「`## 标题` 嵌套」。模型对前者的解读是"这些都是我的作业指令"，对后者会把它读成"一份带章节的文档"。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| Ruby 层顺序为 6 层、`parts.join("\n\n")` | `sed -n '20,55p' openclacky/lib/clacky/agent/system_prompt_builder.rb` | `parts << @agent_profile.system_prompt` → `base` → project rules → SOUL → USER → skills | 确认 |
| Ruby 用 80 个 `=` 分隔，非 `## 标题` | 同上 `format_section` | `lines = ["", sep, title, sep, content, sep]; lines.join("\n")`，`sep = "=" * 80` | 确认 |
| MB 层顺序相反、且把 base/SOUL/USER 包进 `Agent Identity` | `lib/agent/profile.mbt:157-177` | `base_prompt → soul → user → system_prompt`，再被 `format_prompt_section("Agent Identity", …)` 包裹 | 确认 |
| MB 有 Ruby 不存在的三层 | `lib/agent/system_prompt.mbt:12,20,152,167,176` | `brand_confidentiality_notice` / `base_agent_rules` / `Working Directory`+`Environment`+`Model` | 确认 |
| Ruby SOUL/USER 有内置默认常量 | `openclacky/lib/clacky/agent_profile.rb` `DEFAULT_SOUL` / `DEFAULT_USER` | 缺失时返回常量（3 行文案 / 单行文案），MB 缺失时读 `assets/agents/SOUL.md`（长文案） | 确认 |
| Ruby 截断语义 | `system_prompt_builder.rb:truncate` | `text[0, 1000] + "\n... [truncated]"`；MB `truncate_memory` 已一致，但默认常量路径未走 | 确认 |
| Ruby 出网剥离的内部字段 | `openclacky/lib/clacky/message_history.rb:377-379` | `strip_internal_fields` = **key 黑名单** `INTERNAL_FIELDS`，其中含 `display_files` / `session_context`，**不含** `display_text` / `session_date` / `latency` | 确认 |
| MB 出网未剥离 `display_files` / `session_context` | `lib/message/message.mbt` `to_api_message` | 两者被显式保留（注释称"mirrors Ruby's hash-passthrough"，前提判断有误） | 确认 |
| Ruby Web profile 接口缺失时返回默认常量 | `openclacky/lib/clacky/server/http_server.rb:6040-6063` | `_profile_read_file` 落到 `DEFAULT_SOUL` / `DEFAULT_USER` | 确认 |
| Ruby 不依赖 `USERPROFILE` 探测 Desktop | `openclacky/lib/clacky/utils/environment_detector.rb` | WSL 走 `powershell.exe` + `wslpath`，回退 `~/Desktop`、`~/桌面` | 确认（本次不修，见「不涉及」） |

### 实测对照（015 剧本，两侧 system prompt 逐行）

ruby（`runs/015_system_prompt_assembly/ruby/requests/req_0001.json`）：

```
  0| You are an AI coding assistant and technical co-founder, …   ← system_prompt.md（CRLF）
 18| ## Code Style
 89| ## Task Tracking
100| Topical knowledge lives in `~/.clacky/memories/`.             ← base.md 尾部
106| <<SEP80>>
107| AGENT SOUL (from ~/.clacky/agents/SOUL.md)
109| You are calm, precise, and helpful. …                         ← DEFAULT_SOUL
115| <<SEP80>>
116| USER PROFILE (from ~/.clacky/agents/USER.md)
118| (No user profile configured yet. …)                           ← DEFAULT_USER
123| <<SEP80>>
124| AVAILABLE SKILLS:
```

moonbit（`runs/015_system_prompt_assembly/moonbit/requests/req_0001.json`）：

```
  0| ## Agent Identity                                              ← 自创外层标题
  6| ## General Behavior …（base.md 内容被嵌进 persona 内层）
 11| # Agent Soul / ## Core Values …（assets/agents/SOUL.md 长文案）
 31| # User Guide …
 90| ## Code Style（其实来自 system_prompt.md，被排在最后一层）
149| ## Core Behavior / ## Tool Usage / ## Response Style           ← 自创
168| ## Working Directory
171| ## Environment
175| ## Model
178| ## Skills
```

关键点：MB 的 `Agent Identity` 把 4 个来源缝成一段，模型无法分辨"哪一段是我的角色定义、哪一段是通用规则"。Ruby 的 `=`×80 分隔是**刻意的**：每个块都是独立作业指令。

### 详细分析

1. **层顺序（BUG-0065）**：Ruby 是 `角色 → 通用规则 → 项目规则 → 人格 → 用户档案 → 技能`；MB 是 `通用规则 → 人格 → 用户档案 → 角色`。顺序影响模型对指令优先级的判断（角色定义在前、通用规则紧随），不是纯格式问题。
2. **自创内容（BUG-0066）**：`brand_confidentiality_notice` 是 MB 发明的"品牌技能保密声明"，Ruby 的对应机制是 `[CONFIDENTIAL SKILL START/END]` 包裹单个技能正文（`skill_manager.rb:363-368`），**不进 system prompt**；`base_agent_rules` 是 MB 硬编码的"## Core Behavior"，与 `base.md` 职责重叠且内容冲突（base.md 已规定 Tool Usage / Response Style）；`Working Directory/Environment/Model` 三层 Ruby 从未有——这些信息 Ruby 放在**第一条 user 消息的 session context** 里。
3. **SOUL/USER 默认文案（BUG-0067）**：MB 兜底读 `assets/agents/SOUL.md`（一份 ~2KB 的完整人格文档），Ruby 兜底是 3 行常量。这导致**没做过 onboarding 的用户**，MB 会塞给对方一份它没写过的人格设定。
4. **出网字段（BUG-0069）**：MB 的 `to_api_message` 保留了 `display_files` 与 `session_context`，理由是"对齐 Ruby 的 hash 直通"。实测 Ruby 用 `INTERNAL_FIELDS` 黑名单剥离这两个键——MB 的推断前提不成立，属实现缺陷（同 spec `2026-08-18_23` 的 decision 需修正）。

---

## 决策 [必填 - 含为什么]

**D1. 完全复刻 Ruby 的 six-part 装配，不再保留 MB 自创层。**

理由：差分测试的判定总则是"以 Ruby 为准"。MB 自创的三层不是功能增强而是**干扰项**——`brand_confidentiality_notice` 对无品牌技能的用户是纯噪声；`base_agent_rules` 与 `base.md` 重复；`Working Directory/Environment/Model` 泄漏到 system prompt 会与 session context 里的同类信息构成**双份事实**，一旦两者不一致（如 cwd 变更）模型会无所适从。

**D2. 分隔块用 Ruby 的 `=`×80，标题串沿用 Ruby 原文（含 `~/.clacky/...` 路径）。**

理由：MB 的资产（`base.md` 等）本就是照抄 Ruby 的，`base.md` 内部同样写着 `~/.clacky/memories/`，说明"品牌路径"不是 MB 的有意设计而是忠实复刻的一部分。差分对齐优先——任何字面改动都会在抓包 diff 里变成噪声，掩盖真 bug。若将来要品牌化路径，应作为**独立批次**统一处理（含 `base.md` 内部、技能正文、CLI 帮助文案）。

**D3. SOUL/USER 兜底改为内置常量，`assets/agents/SOUL.md` / `USER.md` 不再作为 system prompt 兜底。**

理由：对齐 Ruby `DEFAULT_SOUL` / `DEFAULT_USER`。两个 assets 文件保留（onboard 流程仍需展示模板），但 profile 装配路径不再读它们。截断（1000 字符 + `\n... [truncated]`）对**所有**来源生效（Ruby 的 `truncate` 在 `soul` 取值后无条件调用）。

**D4. `to_api_message` 改为按 `INTERNAL_FIELDS` 语义剥离，`ToJson` 对 User 消息仅在 `display_files` 为 `Some` 时写该键。**

理由：`display_text` 在 Ruby 中确实出网（015 抓包 msg[2] 有 `display_text: null`），`session_date` 同理；只有 `display_files`、`session_context` 被剥离。`to_persist_message` 保留全部字段，故 session.json 持久化不受影响。同步修正 spec `2026-08-18_23` 的错误前提（在其变更记录中追加说明，不删旧版）。

**D5. 行尾不统一（Ruby 资产为 CRLF，MB 为 LF）。**

理由：内容逐字节一致才是目标，行尾差异不影响模型解读，但强行改成 CRLF 会在 `git`（Windows/WSL 混合环境，`core.autocrlf` 不确定）下反复翻转，收益为负。记入 diff-harness 台账为"无害差异"，在比对脚本中归一化。

**D6. `assets/prompts/base.md` 的一行措辞同步到 Ruby 最新版，其余不动。**

理由：MB 落后于 Ruby 2026-09-08 的更新（`file://~/path/to/file` + "Use the raw file path as-is" → `file:///absolute/path/to/file` + "Use the exact absolute path the write tool returned"）。这行直接指导模型如何输出用户可点击的下载链接，是**用户可见行为**。

**D7. BUG-0068（WSL Desktop 探测）本次不修。**

理由：Ruby 用 `powershell.exe` + `wslpath` 探测 Windows 桌面路径；MB 侧只有 `moonbitlang/async/process`（async API），而 `build_system_prompt` 是同步函数，改造会波及 `react.mbt` / `session_data.mbt` 的调用链。属独立批次（B1），本条保持 `open`。当前 MB 在 WSL 下 `Desktop:` 段永久缺失，该差异需在 015 diff 中显式豁免。

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 改动性质 | 预估行数 |
|------|---------|---------|
| `lib/agent/system_prompt.mbt` | 重写 `build_system_prompt`（6 层 + `parts` join）；删 `brand_confidentiality_notice` / `base_agent_rules`；`format_prompt_section` → `format_section`（`=`×80） | ~120 |
| `lib/agent/profile.mbt` | 新增 `DEFAULT_SOUL` / `DEFAULT_USER` 常量；`load_shared_agent_file` 改为「用户目录 → 常量」；`build_system_prompt_section` 改为按 Ruby 顺序返回 4 段 | ~60 |
| `lib/message/message.mbt` | `to_api_message` 剥离 `display_files` / `session_context`；`ToJson` 的 User 分支按 `Some` 条件写 `display_files` | ~20 |
| `lib/web/handlers_profile.mbt` | 默认文案来源改为常量（2 处 `assets_path` 调用） | ~10 |
| `assets/prompts/base.md` | 同步 Ruby 2026-09-08 那一行措辞 | 1 |

### 不涉及文件

- `lib/utils/sys_native.c` —— 明确不扩展（BUG-0068 归 B1）。
- `assets/agents/SOUL.md` / `USER.md` —— 文件保留，仅不再作 prompt 兜底。
- `assets/agents/*/system_prompt.md` —— `coding` / `general` 与 Ruby 逐字一致（忽略行尾），`ext-developer` 内容差异大，另立条目，不在本批。
- `lib/skill/*` —— 技能段格式已对齐，**内容/排序/描述取值**差异属 BUG-0070，不在本批。

---

## 实施计划 [必填]

### 任务包 1：`system_prompt.mbt` 六层重排（0.5 天）

- `build_system_prompt` 改为：`profile.system_prompt` → `profile.base_prompt`（非空才加）→ project rules（`format_section` + footer）→ `format_section("AGENT SOUL (from ~/.clacky/agents/SOUL.md)", soul)` → `format_section("USER PROFILE (from ~/.clacky/agents/USER.md)", user)` → `available_skills_summary()`，最后 `parts.join("\n\n")`。
- 新增 `format_section(title, content, footer~)`：`["", SEP, title, SEP, content, SEP]` join `\n`，有 footer 时再追加 footer + SEP。
- profile 加载失败时保留 `write_diagnostic`，但**不再**注入 `Role` 兜底文案（Ruby 会 raise；MB 选择降级为不含 persona 的 5 层，并保留诊断）。
- `Memory` / `Tasks` 两段：本批**移除**（Ruby 无此层，且其内容为空时不输出，删除对默认路径零影响；非空时属另一处行为差异，另立条目）。

### 任务包 2：`profile.mbt` 默认常量 + 截断（0.5 天）

- 常量逐字对齐 Ruby：`DEFAULT_SOUL`（3 行）、`DEFAULT_USER`（单行）。
- `load_shared_agent_file(filename)` 拆为「只在 `~/.mbopenclacky/agents/<file>` 找用户覆盖 → 缺失返回常量」；不存在的 filename 返回 None。
- `build_system_prompt_section` 的返回语义调整：改为暴露单一 `soul` / `user_profile` 取值器（含默认常量 + 截断），由 `system_prompt.mbt` 负责分段与标题。

### 任务包 3：`message.mbt` 出网字段（0.3 天）

- `to_api_message`：`display_files: None`、`session_context: None`。
- `impl ToJson for Message` 的 User 分支：`display_files` 仅 `Some` 时写。
- 补 `lib/message/message_wbtest.mbt` 用例：带 `display_files` 的 user 消息经 `to_api_message` 后 JSON 不含该键；`to_persist_message` 后仍含。

### 任务包 4：Web 默认文案同步（0.2 天）

- `handlers_profile.mbt` 的两处默认文案改为读常量，保证 Web 展示与模型实际看到的一致。

### 任务包 5：验证（0.5 天）

- `moon check` / `moon test lib cmd` / `moon test lib/utils` 全绿。
- 重跑剧本 015（coding/general/ext-developer 三个变体）与 016，抓包对比：层标题序列完全一致、自创标题归零、SOUL/USER 文案一致。
- 新写比对脚本（存 `diff-harness/scripts/`）：把 skills 段替换为占位符后逐行 diff，归零则视为装配层对齐。

---

## 验收标准 [必填]

1. 015 抓包的 system prompt 中，`=`×80 分隔块的数量与顺序与 ruby 完全一致（SOUL → USER → AVAILABLE SKILLS）。
2. 015 抓包中不再出现 `## Agent Identity` / `## Core Behavior` / `## Tool Usage` / `## Response Style` / `## Working Directory` / `## Environment` / `## Model` / `## Skills` / `## Regular Behavior` 等 MB 自创标题。
3. SOUL 段文案为 `You are calm, precise, and helpful. …`（3 行），USER 段文案为 `(No user profile configured yet. …)`（单行）；隔离 HOME 写入自定义 SOUL/USER 后（剧本 016）两侧仍一致。
4. 超过 1000 字符的 SOUL/USER 截断标记为 `\n... [truncated]`，且截断后长度 == 1000 + 19。
5. user 消息出网 JSON 不含 `display_files` / `session_context` 键；session.json 中仍保留。
6. `assets/prompts/base.md` 的下载链接指引与 Ruby 逐字一致（忽略行尾）。
7. `moon check` 0 error；`moon test lib cmd` 与 `moon test lib/utils` 全绿。
8. 比对脚本在「skills 段占位、行尾归一」的前提下，两侧 system prompt 逐行 diff 为空。

---

## 风险评估 [必填]

| 风险 | 影响 | 缓解 |
|------|------|------|
| 移除 `brand_confidentiality_notice` 后品牌技能保密性下降 | 中 | Ruby 用 `[CONFIDENTIAL SKILL START/END]` 包裹技能正文，本批不动技能注入路径；保密声明移除是对齐 Ruby 的有意选择，在报告中记录 |
| 移除 `Memory` / `Tasks` 层导致长期记忆/待办对模型不可见 | 中 | 两段默认空（015 实测不输出）；非空场景另立条目评估 |
| `display_files` 条件写破坏既有持久化 | 低 | `to_persist_message` 不改；补单测覆盖两条路径 |
| profile 加载失败时不再注入 `Role` 兜底 | 低 | 保留 `write_diagnostic`，且 `--agent nonexistent` 已在 CLI 层报错退出（B0 验收标准 4） |
| CRLF 差异被误判为新 bug | 低 | 比对脚本归一化；台账记为无害差异 |

---

## 依赖关系 [必填]

- 前置：B0 已完成（`--agent` 接线、assets 根绝对化、session profile 优先级、`load_for_name` 报错）。
- 后端：BUG-0070（技能集合/描述取值/排序）、BUG-0068（WSL Desktop 探测）为后续批次。
- 对 diff-harness 的影响：新增「system prompt 装配层」比对脚本，作为 015 剧本的常驻断言。

---

## 变更记录 [必填]

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-10-09 | 创建 | 依据 B0 验收报告遗留的 5 项装配差异（BUG-0065~0069）立稿 |
