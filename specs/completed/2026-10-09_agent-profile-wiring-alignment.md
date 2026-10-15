# Agent Profile 装配层对齐（B0）· 增量 Spec

> **创建日期**: 2026-10-09
> **状态**: 实施完成（2026-10-15 归档）
> **关联总览**: `diff-harness/reports/REALIGNMENT_ASSESSMENT_2026-10-09.md` §2、§4.2
> **关联历史 spec**: `2026-08-18_20_agent-profile.md`（profile 加载本体，已归档）
> **来源差距**: BUG-0058 / BUG-0059 / BUG-0060 / BUG-0064（diff-harness 台账）
> **依赖**: 无
> **灰度 key**: 无

---

## 问题描述 [必填]

MBOpenClacky 的默认运行路径上，**agent profile 从未被加载**，导致实际发给模型的 system prompt 只有 1424~1436 字符的硬编码兜底文案；对照组 openclacky(Ruby) 是 14023 字符的完整作业指令（技术合伙人身份 + Code Style + File Modification Rules + Git Safety Protocol + Error Handling + Security + Testing + Code Quality + General Behavior + Tool Usage + Response Style + Task Tracking + Long-term Memory）。

连带失效：`SOUL.md`（人格）、`USER.md`（用户档案，onboarding 的产物）、19 个内置技能的 `## Skills` 摘要段——用户走完 onboarding 填写的内容**一次也没有进入模型上下文**。

本质是「装配层断裂」：profile 加载本体（`lib/agent/profile.mbt` 单测全绿）是正确的，断在 **CLI 参数 → Agent 构造 → 加载调用** 这条线上。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `--agent` 声明后无人消费 | `grep -rn '"agent"' cmd/*.mbt` | 仅 `cmd/main.mbt:28`（声明）+ `cli_ext.mbt:300`（无关字符串） | **确认断裂**（`get_named_arg(value,"agent")` 全仓 0 命中） |
| Agent 名被硬编码 | `grep -n "Agent::new" cmd/main.mbt` | `:1026` 传字面量 `"CLI Agent"` | 确认 |
| profile 用 `self.name` 查找 | `sed -n '115,120p' lib/agent/system_prompt.mbt` | `AgentProfile::load_for_name(self.name)` | 确认（name=`"CLI Agent"` → 目录不存在） |
| 加载失败被静默吞掉 | `sed -n '117,121p' lib/agent/system_prompt.mbt` | `catch { _ => AgentProfile::default_profile() }` | 确认无日志、无告警 |
| `assets/**` 按 CWD 相对解析 | `grep -rn '"assets/' lib/ cmd/` | 19 处命中，均在 `lib/agent/profile.mbt:43,205,212,257,260`、`lib/extension/loader.mbt:47`、`lib/skill/default_skills.mbt:32`、`lib/web/{handlers_agents,handlers_profile,handlers_skills,server}.mbt` | **确认** |
| `--path` 会 chdir | `sed -n '969,971p' cmd/main.mbt` | `@utils.change_dir(p)`，`original_dir` 仅在结束时恢复 | 确认（CWD 在运行期是用户工程目录） |
| profile 名已有 session 字段但写死 | `grep -n "agent_profile" lib/agent/session_data.mbt` | `:245` 定义、`:322` 赋值 `"general"`、`:502/:635` 序列化 | **确认硬编码** |
| 恢复会话时不读 profile | `grep -rn "agent_profile" lib/agent/agent.mbt lib/agent/session_store.mbt` | 0 命中 | 确认 |
| Web 侧同样不接线 | `sed -n '313p' lib/web/handlers.mbt`、`sed -n '170p' lib/web/server.mbt` | 分别传 `name`（会话名）与字面量 `"Web Agent"` | 确认 |
| 上一轮已察觉该硬编码 | `sed -n '344,345p' lib/web/handlers.mbt` | 注释 "to_session_data hardcodes agent_profile to \"general\"; apply the requested one." | 确认（用补丁绕过而非修根因） |
| 编译产物路径深度 | `ls _build/native/debug/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe` | 存在（另有 Windows PE 变体同名混放） | 影响 assets 根推导策略 |
| `@env.args()[0]` 是程序路径 | `sed -n '423,428p' cmd/main.mbt` | 项目自身用 `all_args[1:]` 跳过 argv[0] | 确认 argv[0] 可用 |

### 实测对照（隔离 HOME + mock LLM 抓包，同一剧本）

| 启动方式 | system prompt 长度 | 含 `AVAILABLE SKILLS` |
|---|---|---|
| `cwd=仓库根`，不带 `--path` | 21054 | ✅ |
| `cwd=仓库根`，带 `--path <临时目录>`（真实用法） | 1436 | ❌ |
| `cwd=任意临时目录` | 1424 | ❌ |

> 21054 那次的增量**几乎全部**来自把仓库自身的 `CLAUDE.md` 当成用户工程规则注入（`## Workspace Rules`），**不是** profile——即 persona 在任何启动方式下都是兜底单句。

### 详细分析

三因子叠加，缺一不可：

1. **`--agent` 未接线**：`cmd/main.mbt:28` 声明（default `coding`、help "Agent profile to use"），`:1026` 却传字面量 `"CLI Agent"`。实测 `--agent coding` / `--agent general` / 默认 三者 prompt **完全一致**。
2. **profile 名 ≠ agent 实例名**：`Agent` 结构体只有 `name` 一个身份字段，`build_system_prompt` 拿它当 profile 名用。`"CLI Agent"` 在 `~/.mbopenclacky/agents/` 与 `assets/agents/` 下均不存在 → `@errors.AgentError` → `catch` 静默 → `default_profile()`（`base_prompt/system_prompt/soul/user` 全 `None`）→ persona 为空 → 走 `system_prompt.mbt:127` 硬编码兜底。同一根因的第二受害者：`lib/agent/skill_manager.mbt:67` 按 `skill.agent_type != self.name` 过滤技能。
3. **assets 相对 CWD**：`cmd/main.mbt:971` 收到 `--path` 即 chdir；Ruby 侧对应实现是 `File.expand_path("../prompts/base.md", __FILE__)`（锚定安装位置）。因此即使修好 1、2，只要用户带 `--path`，`assets/agents/coding/system_prompt.md` 与 `assets/skills/**` 依然找不到。

资源侧本身**已忠实移植**：`assets/prompts/base.md` 2212B（上游 2288B）与 `assets/agents/coding/system_prompt.md` 3962B（上游 3895B）逐节对应，只是从未被读。

---

## 决策 [必填 - 含为什么]

1. **新增 `lib/utils/assets.mbt`，提供 `assets_root()` / `assets_path(rel)`**
   解析顺序：① 环境变量 `MBOPENCLACKY_ASSETS_DIR`（显式覆盖，供打包/测试）→ ② `@env.args()[0]`（可执行文件路径，相对时以启动 CWD 绝对化）向上逐级查找含 `assets/prompts/base.md` 的祖先目录 → ③ 启动 CWD 向上逐级查找 → ④ 回退 `"assets"`。
   **为什么向上"查找"而非固定偏移**：debug/release 产物路径深度不同（`_build/native/{debug,release}/build/<owner>/MBOpenClacky/cmd/`），固定偏移会碎。**为什么必须在 chdir 之前预热**：`--path` 会改变 CWD，首次调用时机决定解析基准，故 `cmd/main.mbt` 入口最早期调用一次。

2. **不扩展 `lib/utils/sys_native.c`**
   该文件自带硬约束注释（S-FFI-08）："this file is the project's single remaining sys-level FFI surface — do not extend it"。`@env.args()` 已提供所需信息，无需新 FFI。

3. **`Agent::new` 用可选参数而非新增位置参数**
   签名改为 `Agent::new(session_id, name, working_dir, client, config, profile? : String = "coding")`。
   **为什么**：`grep "Agent::new("` 全仓 60+ 处调用（其中绝大多数是 `_wbtest.mbt`），加位置参数会造成大面积无意义改动；可选参数零破坏，且默认值 `"coding"` 与 Ruby CLI 默认一致（`cli.rb:62`）。

4. **Agent 新增 `mut profile_name : String`，与 `name` 彻底解耦**
   对齐 Ruby：`@name` 是会话显示名、`@agent_profile.name` 是 profile 名，两者独立（`agent.rb:85-94`）。`Agent::rename` 因此不再影响 profile 解析。

5. **加载失败必须可观测**
   `build_system_prompt` 保持不抛（它返回 `String`），但失败路径记 `logger.warn`（含 profile 名与查找过的目录）；同时新增 `Agent::resolve_profile() -> Result[AgentProfile, String]` 供显式校验。CLI 在构造后主动校验一次：失败则 stderr 报错 + `exit 1`——对齐 Ruby（`AgentProfile.load` 失败即抛，不静默降级）。

6. **profile 名随 session 持久化，恢复时优先 session 值**
   修 `session_data.mbt:322` 硬编码 `"general"` → `self.profile_name`；`restore_from_session` 读取 `sd.agent_profile` 覆盖 CLI 传入值。对齐 Ruby `cli.rb:573-575`（"Prefer the agent_profile stored in the session; only fall back to the CLI --agent flag when the session predates the agent_profile field"）。

7. **Web 侧三处接线**
   `handlers.mbt:313` 传请求里的 `agent_profile`（而非会话名）；`server.mbt:170` 改为从 session data 恢复（缺省 `"coding"`）；`handlers_onboard.mbt:315` 同理。删除 `handlers.mbt:344-345` 的补丁式绕过。

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/utils/assets.mbt` | 新建 | `assets_root()` / `assets_path(rel)` / `prewarm_assets_root()`，带进程级缓存 |
| `lib/utils/assets_wbtest.mbt` | 新建 | 环境变量覆盖、向上查找、缓存命中 |
| `lib/agent/agent.mbt` | 修改 | 新增 `mut profile_name`；`Agent::new` 增加可选 `profile` 参数；新增 `resolve_profile()` / `set_profile()` |
| `lib/agent/system_prompt.mbt` | 修改 | 用 `self.profile_name` 加载；失败记 warning |
| `lib/agent/profile.mbt` | 修改 | 5 处 `assets/**` 改用 `@utils.assets_path()` |
| `lib/agent/session_data.mbt` | 修改 | `agent_profile: "general"` → `self.profile_name` |
| `lib/agent/session_store.mbt` | 修改 | 恢复路径应用 `sd.agent_profile` |
| `cmd/main.mbt` | 修改 | 入口预热 assets 根；消费 `--agent`；构造后校验 profile 并报错退出 |
| `lib/skill/default_skills.mbt` | 修改 | `DEFAULT_SKILLS_DIR` 常量改为 `assets_path("skills")` 求值 |
| `lib/extension/loader.mbt` | 修改 | `assets/extensions` 绝对化 |
| `lib/web/handlers.mbt` | 修改 | 传 profile 给 `Agent::new`；删除 `:344-345` 绕过 |
| `lib/web/server.mbt` | 修改 | `"Web Agent"` → 从 session data 恢复 profile；头像路径绝对化 |
| `lib/web/handlers_onboard.mbt` | 修改 | profile 显式化 |
| `lib/web/handlers_agents.mbt` | 修改 | `assets/skills`、`assets/agents` 绝对化 |
| `lib/web/handlers_profile.mbt` | 修改 | `assets/agents/{USER,SOUL}.md` 绝对化 |
| `lib/web/handlers_skills.mbt` | 修改 | `BUILTIN_SKILLS_DIR` 绝对化 |

### 不涉及文件

- `lib/utils/sys_native.c`（FFI 冻结）
- `lib/agent/default_profiles.mbt`（静态元数据表，不参与运行时装配；其 `system_prompt_path` 字段仍为展示用途）
- `openclacky/`（只读参考）
- 工具 schema / `ask_user` / `api_format` / hook 触发点（属 B1~B3 批次）
- `--file` / `--image` 附件注入（BUG-0060，归 B1；本批次不动）

---

## 实施计划 [必填]

### 任务包 1：assets 根绝对化（预估 0.5 天）
- 新建 `lib/utils/assets.mbt`：四级解析 + 缓存 + `prewarm_assets_root()`
- `cmd/main.mbt` 与 Web 服务器启动处预热
- 替换 19 处字面路径（含 3 处 `const`，改为函数求值）
- 单测：env 覆盖优先、exe 路径推导、CWD 回退、缓存一致性

### 任务包 2：profile 名与实例名解耦 + 可观测（预估 0.5 天）
- `Agent` 加字段、`Agent::new` 加可选参数、`rename` 语义澄清
- `build_system_prompt` 改用 `profile_name` + 失败告警
- `resolve_profile()` 暴露为 `Result`

### 任务包 3：CLI 与 session 接线（预估 0.5 天）
- `cmd/main.mbt` 消费 `--agent`
- 构造后校验 profile，失败 stderr + exit 1
- `session_data.mbt` / `session_store.mbt` 读写 profile 名，恢复优先 session 值

### 任务包 4：Web 接线（预估 0.5 天）
- 三处 `Agent::new` + 删除绕过补丁
- 头像路径绝对化

### 任务包 5：验证与回归资产（预估 0.5 天）
- `moon check` + `moon test lib cmd` 全绿
- diff-harness 新增剧本 `003_system_prompt_assembly.json`
- 两侧抓包对比，回写 BUG-0058/0059/0064

---

## 验收标准 [必填]

- [ ] 隔离 HOME + mock 抓包：system prompt ≥ 6000 字符，含 `technical co-founder`、`## File Modification Rules`、`## Git Safety Protocol`
- [ ] 同一条件下 system prompt 含 `## Skills` 段，且含 ≥ 15 个内置技能名
- [ ] `--agent coding` / `--agent general` / `--agent ext-developer` 三者 prompt **互不相同**
- [ ] `--agent nonexistent` 退出码非 0 且 stderr 有明确报错（不再静默降级）
- [ ] 隔离 HOME 写入自定义 `SOUL.md` / `USER.md` 后，prompt 含其内容
- [ ] `cwd` 为任意目录、且带 `--path <临时工程目录>` 时，上述断言依然成立（CWD 无关）
- [ ] 会话恢复：`--agent coding` 建会话 → 用 `--agent general` continue 时，仍使用 session 中记录的 `coding`
- [ ] `moon check` 0 errors（`lib cmd`）
- [ ] `moon test lib cmd` 全绿
- [ ] diff-harness `003_system_prompt_assembly.json` 两侧跑通并断言通过

---

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `@env.args()[0]` 在不同调用方式下为相对路径或空 | 中 | 相对时以启动 CWD 绝对化；空/失败时回退 CWD 向上查找；env 变量兜底 |
| 预热时机晚于 chdir | 高 | `cmd/main.mbt` 在参数解析前调用 `prewarm_assets_root()`；Web 侧在 `run_server` 入口预热 |
| 缓存导致测试间污染 | 中 | 提供 `reset_assets_root_cache_for_test()`，单测用 |
| 替换 19 处路径引入漏改 | 中 | 验收以"从任意 CWD 的抓包断言"兜底，而非依赖逐处 review |
| 默认 profile 名 `coding` 与既有 session 的 `"general"` 记录冲突 | 低 | 恢复时优先 session 值；旧 session 无 profile 字段时回退 CLI 值（对齐 Ruby） |

---

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：B1（工具面 `ask_user` 转正）复用本 spec 的 `resolve_profile()`；B4（上游增量追平）依赖 profile 名已正确持久化

---

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-10-09 | 初始版本 | diff-harness 重新对齐评估 §2/§4.2 发现装配层断裂 |
