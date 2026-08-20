# 配置加载深度对齐（矩阵§10）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已完成（2026-08-20 实施 + 全量回归通过，归档至 `specs/completed/`）· 此前：已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §10  
> **关联历史 spec**: 边界——P2 用例面已归两份 p5 spec：`2026-08-18_12_p5-config-loading-alignment.md`（BUG-0012/0013/0014/0020/0022：max_tokens 加载、anthropic_format nil、current_model_id 自动设置、switch 失败文案）、`2026-08-18_07_p5-env-overlay-config-channel.md`（FU-08 env overlay）；本 spec 管矩阵 §10 的**深度面**（优先级方向、解析顺序、徽章语义、模型管理 API、identity、代理策略等），重叠处以 p5 spec 为准；Providers::resolve key/localhost 回退归 B4（BUG-0073）；search.yml 归 B1（BUG-0063）；文件权限 0600 随既有 BUG-0111 条目；矩阵旧台账编号已被覆盖，一律使用 `矩阵§10/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§10 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 两份 p5 配置 spec 先行（同改 loader.mbt/env_compat.mbt）  
> **灰度 key**: 无

## 问题描述 [必填]

### 优先级与合并语义（重大分歧区）

1. **env/file 优先级反转（partial，已核实，重大）**：Ruby config file > env；MB `merge_config` 中 overlay（env）models 非空即**整体替换**文件 models（`lib/config/env_compat.mbt:155-160`）。用户 TOML 配了多模型时，只要环境里有 API key 变量，文件模型列表被全部抹掉。
2. **merge_config 整体替换语义（partial，已核实）**：同上根因——models 数组无字段级 merge（env_compat.mbt:157-160），与 Ruby overlay 四键覆盖语义相反。
3. **current_model 解析顺序相反（partial，已核实，裁决点）**：Ruby id > default 徽章 > index；MB default 徽章 > current_model_id > 单模型回退（`lib/config/loader.mbt:347-369`，注释自认"badge is the most recent explicit user choice and wins"——有意设计）。
4. **switch_model 移动全局 default 徽章（partial，已核实，裁决点）**：MB `switch_model_by_id` 每次切换同步移动徽章（`lib/config/agent.mbt:60-95`，config_wbtest.mbt:461 有"moves the default badge"断言——有意设计）；Ruby per-session 切换不动徽章。影响：TUI/斜杠命令里一次临时切换会永久改写用户 Settings 默认。
5. **set_default_model_by_id 独立操作缺失（partial，静态证实）**：Ruby 区分"会话切换"与"设置默认"两操作；MB 合并为一个。随条目 4。
6. **virtual_model_overlay 字段级 merge 缺失（partial，静态证实）**：Ruby 四键覆盖不改 @models；MB 整体替换并移徽章（config/agent.mbt:142 附近）。
7. **session_model_overlay 语义差异（partial，静态证实）**：Ruby 只钉选 model 名；MB 实现为整模型切换副本（config/agent.mbt:170 附近）。
8. **deep_copy 共享语义（partial，静态证实）**：Ruby 多会话共享 models 引用实时同步；MB 深拷贝（config/agent.mbt:195-219 矩阵引用）。裁决点：MB 隔离语义是否为有意超集。

### env 兼容层细节

9. **env base_url 默认 anthropic（partial，已核实）**：无 `_BASE_URL` 时恒 `https://api.anthropic.com`（env_compat.mbt:54-57）；对非 Anthropic provider 的 key 会静默指向错误端点。
10. **CLACKY_ANTHROPIC_FORMAT 硬编码 true（partial，已核实）**：env 链构造的 ModelConfig 恒 `anthropic_format: true`（env_compat.mbt:68,119），`_ANTHROPIC_FORMAT` 变量未消费。
11. **CLACKY_LITE_* lite 模型注入缺失（missing，静态证实）**：Ruby agent_config.rb:111-141 有 lite 模型 env 注入；MB 无。
12. **CLAUDE_* 兼容层（partial，已核实，裁决点）**：Ruby 已禁用 CLAUDE_*；MB `load_claude_compat` 活跃支持（env_compat.mbt:99-132）。移除 or 保留为 MB 超集需裁决。
13. **CLACKY_WORKSPACE_DIR 缺失（missing，静态证实）**。

### 模型加载与管理

14. **settings 字段覆盖缺口（partial，静态证实）**：缺 `enable_idle_compression`/`message_count_threshold`/`skill_evolution`/`clacky_license_server`（loader.mbt:63-148 区间）。
15. **模型 id 语义与缺字段容忍（partial，静态证实）**：MB 把 id 当必填持久化主键、缺 id/缺 base_url/model 整条静默丢弃（loader.mbt:152-196 区间）；Ruby id 运行时注入不持久化。
16. **load 时确保至少一个 default 徽章缺失（missing，静态证实）**：Ruby agent_config.rb:303-307 归一化；MB 无。
17. **models_configured? 语义（partial，已核实）**：MB `has_model_configured` 只看任一 api_key 非空（loader.mbt:373-380）；Ruby 要求 current_model 可解析。web server 启动门（main.mbt:460）直接消费此函数，弱校验会放行"有 key 但 current_model 解析为 None"的配置。
18. **remove_model/set_model_type 等模型管理 API 缺失（missing，已核实）**：Grep 全库无 `remove_model`；Ruby agent_config.rb:1270-1311 有完整管理 API。
19. **add_model 语义差异（partial，静态证实）**：MB 同 id 去重替换；Ruby 追加+自动 id。
20. **current_model_id 持久化（partial，静态证实，随条目 3 裁决）**：Ruby 刻意不持久化；MB 写入 TOML 成"幽灵选择"（loader.mbt:106-108 区间）。与 p5-config-loading-alignment 的 BUG-0014 交叉，最终语义以本 spec 裁决为准。
21. **derive_media_model / media 三态自省缺失（missing，静态证实）**：MB 硬编码小表、无 disabled 处理。
22. **fallback_base_url 恒 None（partial，静态证实）**：无 TOML 解析无派生（llm_caller.mbt:463-476 矩阵引用；URL fallback 可达性面）。

### identity 与代理

23. **identity 存储路径疑似笔误（partial，已核实）**：MB 用 `~/.clacky/identity.json`（brand/identity.mbt:40-48）；MB 项目其余配置域用 `~/.mbopenclacky/`。裁决点：迁移路径或保持兼容。
24. **identity is_bound 语义（partial，已核实）**：MB 只判文件存在（identity.mbt:144-148）；Ruby 判 token 非空。空文件/损坏文件会被判为已绑定。
25. **identity bind!/clear! 缺失（missing，静态证实）**：Grep identity.mbt 无 bind/clear 公开操作（onboard 流程面待任务包 0 核对调用链）。
26. **代理来源策略（partial，静态证实，裁决点）**：Ruby 永不采纳 shell 代理；MB 读 HTTPS_PROXY/HTTP_PROXY（utils/proxy_config.mbt:20-47）。企业环境与复刻语义双向有理由，需裁决。
27. **代理 epoch 变更检测 / proxy_url 接线 unclear**：任务包 0 实测。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| env 整体替换文件 models | 读 `lib/config/env_compat.mbt:155-160` | overlay.models 非空即整体赋值 | 证实（优先级反转成立） |
| env base_url 默认 anthropic | 读 `lib/config/env_compat.mbt:54-57` | None => "https://api.anthropic.com" | 证实 |
| anthropic_format 硬编码 true | 读 `lib/config/env_compat.mbt:68,119` | 两条 env 链均恒 true | 证实 |
| CLAUDE_* 兼容层活跃 | 读 `lib/config/env_compat.mbt:99-132` | load_claude_compat 完整实现 | 证实 |
| current_model 解析顺序 | 读 `lib/config/loader.mbt:340-369` | badge > id > 单模型；注释自认有意设计 | 证实（裁决点） |
| has_model_configured 弱校验 | 读 `lib/config/loader.mbt:371-380` | 仅 api_key 非空 | 证实 |
| switch_model 移徽章 | 读 `lib/config/agent.mbt:60-95` + `config_wbtest.mbt:461-474` | 移徽章且有断言背书 | 证实（有意设计，裁决点） |
| remove_model 缺失 | Grep `remove_model` 全库 | 0 匹配 | 证实 |
| identity 路径 .clacky | 读 `lib/brand/identity.mbt:40-48` | `~/.clacky/identity.json` | 证实 |
| is_bound 仅判文件存在 | 读 `lib/brand/identity.mbt:142-148` | path_exists 判定 | 证实 |
| settings 缺字段/id 语义/徽章归一/lite/workspace/media 自省/fallback_url/代理/deep_copy/overlay | 矩阵行号引用（loader.mbt:63-196、config/agent.mbt:115-219、agent_config.rb 参照、utils/proxy_config.mbt） | 与矩阵声明一致 | 静态证实（任务包 0 逐条复核） |

Ruby 参照（openclacky，只读）：`agent_config.rb`（303-307 徽章归一、111-141 lite、646-901 media 自省、1270-1311 管理 API）、`identity.rb`、`providers.rb`。

### 影响面

条目 1 是**配置丢失级**：环境变量存在即抹掉整个文件模型列表，多模型用户在 CI/终端环境切换时配置"消失"。条目 17 直接影响 server 启动门正确性。条目 4 使临时模型切换产生永久性副作用，与 Settings 面的用户心智冲突。条目 24 使损坏 identity 文件被误判为已绑定，阻断 onboard 修复路径。

## 决策 [必填 - 含为什么]

1. **决策 1（优先级方向对齐）**：恢复 Ruby 方向 config file > env：文件存在且 models 非空时，env 只对**同名/缺失字段**做字段级覆盖（api_key/model 等），不整体替换 models 数组；仅在无配置文件时 env 独立构造完整配置。
   - **为什么**：整体替换是多模型配置的静默销毁；env 的本意是覆盖凭据而非重置拓扑。
2. **决策 2（解析顺序与持久化裁决）**：current_model 解析顺序对齐 Ruby（id > 徽章 > index）；current_model_id 恢复 Ruby"不持久化"语义（TOML 不写回，只读兼容旧值）。
   - **为什么**：MB 现有"badge 优先 + 持久化"组合产生幽灵选择与顺序分歧双重问题；与 p5-config-loading-alignment BUG-0014 的自动设置逻辑在此裁决下统一收敛。
3. **决策 3（switch_model 语义拆分）**：`switch_model_by_id/name` 改为**不移动徽章**（会话级切换，对齐 Ruby per-session 语义）；新增独立 `set_default_model_by_id` 承担"设置默认"（移徽章+持久化）。同步修订 config_wbtest.mbt:461 断言。
   - **为什么**：临时切换改写全局默认是持久性副作用；两语义分离后 TUI/斜杠命令按需选择。
4. **决策 4（env 兼容层细节）**：base_url 缺失时不默认 anthropic URL，改为按 provider 推断或要求显式（裁决倾向：无 `_BASE_URL` 且无 `_PROVIDER` 时保留 anthropic 默认并记录，有 `_PROVIDER` 时按 provider 表取默认）；消费 `_ANTHROPIC_FORMAT` 变量替代硬编码；补 CLACKY_LITE_* 与 CLACKY_WORKSPACE_DIR。
5. **决策 5（CLAUDE_* 裁决）**：对齐 Ruby 禁用 CLAUDE_* 兼容层（移除 load_claude_compat 调用点）并记录；若维护者认为 MB 用户依赖该入口，则保留但在文档中标注超集。裁决倾向：移除。
6. **决策 6（模型管理面）**：移植 remove_model/set_model_type 等管理 API；add_model 对齐追加+自动 id；load 时归一化至少一个 default 徽章；settings 缺字段补齐；id 语义改运行时注入（缺 id 不再丢模型，缺 base_url/model 保留告警日志）。
7. **决策 7（models_configured 强化）**：`has_model_configured` 改为要求 `current_model()` 可解析且 api_key 非空；server 启动门随之收紧。
8. **决策 8（identity）**：is_bound 改判 device_token 非空；补 bind/clear 操作；存储路径 `~/.clacky/identity.json`——裁决保留现路径（与 skills/patches 等既有 .clacky 目录族一致，迁移成本大于收益）并记录"非笔误"结论。
9. **决策 9（裁决点组）**：代理策略——倾向保留 MB 读 shell 代理（企业环境刚需）记录为 MB 超集，但补 `CLACKY_NO_PROXY_ENV=1` 逃生门对齐 Ruby 用户预期；deep_copy 隔离语义倾向保留（多会话互不污染）并记录；media 自省与 fallback_base_url 按任务包 0 影响面分期；代理 epoch unclear 实测后处置。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/env_compat.mbt` | 修改 | 优先级方向、字段级 merge、base_url/anthropic_format、lite/workspace、CLAUDE_* 移除 |
| `lib/config/loader.mbt` | 修改 | settings 字段、id 语义、徽章归一、解析顺序、has_model_configured、current_model_id 持久化（与两份 p5 spec 同文件串行合入） |
| `lib/config/agent.mbt` | 修改 | switch_model 去徽章化、set_default_model_by_id、add_model、remove_model/set_model_type、overlay 语义 |
| `lib/brand/identity.mbt` | 修改 | is_bound、bind/clear |
| `lib/utils/proxy_config.mbt` | 修改 | 逃生门（按裁决） |
| `lib/config/config_wbtest.mbt` 等 | 修改 | 断言同步（含 :461 移徽章断言反转） |

### 不涉及文件

- max_tokens/anthropic_format nil/switch 失败文案（p5-config-loading-alignment 已覆盖）；env overlay 用例面（p5-env-overlay-config-channel）；Providers::resolve（B4）；search.yml（B1）。

## 实施计划 [必填]

### 任务包 0：复核与裁决（预估 1 天）
1. 静态证实条目逐条复核（settings 字段、id 语义、overlay、deep_copy、media 自省、代理 epoch、identity bind 调用链）。
2. 裁决点落地记录（CLAUDE_*、代理、deep_copy、identity 路径）。

### 任务包 1：优先级与合并修复（预估 1 天）
1. env/file 优先级反转修复 + 字段级 merge；base_url/anthropic_format/lite/workspace。
2. wbtest：有文件+有 env 的组合矩阵（重点：多模型文件不被抹掉）。

### 任务包 2：解析顺序与切换语义（预估 1 天）
1. current_model 顺序对齐；current_model_id 持久化移除；switch_model 拆分；徽章归一。
2. wbtest：顺序矩阵、切换不移徽章、set_default 独立路径；修订既有断言。

### 任务包 3：管理 API 与 identity（预估 1.5 天）
1. remove_model/set_model_type/add_model；has_model_configured 强化。
2. identity is_bound/bind/clear；代理逃生门。
3. `moon check` + 全量 `moon test` + test/diff 配置用例无回归。

## 验收标准 [必填]

- [x] 有 TOML 多模型配置时，设置 env API key 不再抹掉文件 models（字段级覆盖）
- [x] current_model 解析顺序为 id > 徽章 > index；current_model_id 不再写回 TOML
- [x] switch_model_by_id 不移动 default 徽章；set_default_model_by_id 独立可用
- [x] `_ANTHROPIC_FORMAT` env 变量被消费；CLACKY_LITE_*/CLACKY_WORKSPACE_DIR 生效
- [x] CLAUDE_* 兼容层按裁决处置（移除或文档化超集）
- [x] has_model_configured 要求 current_model 可解析；server 启动门联调通过
- [x] identity is_bound 在空 token 时返回 false；bind/clear 可用
- [x] `moon check` 0 errors；全量 `moon test` 无回归；test/diff config 簇全绿

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| loader.mbt 与两份 p5 spec 同改 | 高 | 串行合入：p5-config-loading → p5-env-overlay → 本 spec；每步全量回归 |
| switch_model 语义变更影响 TUI/斜杠命令三处调用方 | 中 | 任务包 2 同步核对 tui_eval_adapter/slash_commands/web_e2e_adapter 调用语义 |
| 优先级反转修复改变 CI 环境既有行为 | 中 | 发布说明显式标注；env-only 场景行为不变 |
| current_model_id 去持久化产生旧配置一次性迁移问题 | 低 | 读取时兼容旧值、保存时剥离，一次性迁移日志 |

## 依赖关系 [必填]

- **前置依赖**：两份 p5 配置 spec（同文件先行）。
- **后置依赖**：B9 的 server 启动门联调依赖决策 7。
- **交叉**：BUG-0073（Providers::resolve）归 B4；BUG-0063（search.yml）归 B1；BUG-0111（0600 权限）随既有条目。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§10 残留条目核实落 spec；10 项直接证实 + 16 项静态证实/unclear 留任务包 0；与两份 p5 配置 spec 边界已在头部声明）。
- 2026-08-20：实施完成并归档。任务包 0-3 全部落地：
  - **任务包 1**：env/file 优先级恢复 file > env + 字段级 merge（env_compat.mbt 重写 merge_config）；base_url 无 `_BASE_URL` 时保留 anthropic 默认（决策 4 裁决落地）；`_ANTHROPIC_FORMAT` 消费；CLACKY_LITE_* 注入（load_with_env 尾部，lite_env_model）；CLACKY_WORKSPACE_DIR 填充 default_working_dir；CLAUDE_* 兼容层整体移除（决策 5，load_claude_compat 删除）。
  - **任务包 2**：current_model 解析顺序 id > 徽章 > 第一个模型（loader.mbt）；current_model_id 持久化剥离（to_toml 不写、from_toml 兼容旧值）；switch_model_by_id/name 去徽章化；新增 set_default_model_by_id；TUI 三处调用点（tui_controller config 菜单 / apply_model_card_switch / slash_commands Model 分支）补 set_default_model_by_id 调用对齐 Ruby cli.rb 单会话语义；load 徽章归一（Ruby agent_config.rb:303-307）。
  - **任务包 3**：remove_model/set_model_type/add_model（追加+位置 id 注入 "model-{N}" 防碰撞）/ModelConfig.id 改 mut 运行时注入（缺 id/base_url/model 不再丢条目，保留空串+控制台告警）；settings 补 enable_idle_compression/message_count_threshold/skill_evolution/clacky_license_server 解析与写出（toml↔json 转换器）；has_model_configured 收紧为 current_model() 可解析且 api_key 非空（决策 7）；identity is_bound 判 token 非空 + bind_identity/clear_identity（决策 8，路径保持 ~/.clacky/identity.json 非笔误）；代理 CLACKY_NO_PROXY_ENV 逃生门（决策 9）。
  - **任务包 4（测试）**：config_wbtest 断言反转（switch 不移徽章）+ 新 API 用例；identity_wbtest bind/clear（HOME 重定向隔离）；proxy_config_wbtest 逃生门；test/diff config_010（期望 0→1，缺字段保留条目）/config_015（CLAUDE_* 被忽略）期望更新；lib/web handlers_config_contract drifted-config 用例改断 id-first 语义；slash_commands_wbtest roundtrip 用例改语义级断言（id 为 runtime-only，徽章选择关系存活）。
  - **实施中新发现并修复**：identity 的 derive(ToJson) 将 Int64 bound_at 序列化为 JSON 字符串，而 parse_identity 只接受 Number，导致 bind 后 is_bound 恒 false 的生产 bug--parse 兼容 Number/String 双格式修复（brand 包新增 core/string import）；slash_commands.mbt 消息字符串插值笔误（`\\{m.model}` 未插值）修复。
  - **分期搁置（记录）**：derive_media_model/media 三态自省、fallback_base_url 派生按任务包 0 影响面分期（条目 21/22，非本 spec 验收面）；deep_copy 隔离语义保留为 MB 超集并记录（决策 9）；代理 epoch 实测为 reset 已实现的死代码路径，无消费者，保留现状。
  - **回归**：moon check 0 errors；moon test 全量 3789/3789 通过（lib/config 146、lib/brand 129、lib/utils 306、lib/tui 319、lib/web 456、test/diff 145）；moon fmt/moon info 已跑（pkg.generated.mbti 更新，该文件不入库）。
  - 改动文件：lib/config/{agent,config_wbtest,env_compat,loader,model}.mbt、lib/brand/{identity,identity_wbtest}.mbt、lib/brand/moon.pkg、lib/tui/{slash_commands,slash_commands_wbtest,tui_controller}.mbt、lib/utils/{proxy_config,proxy_config_wbtest}.mbt、lib/web/handlers_config_contract_wbtest.mbt、test/diff/config_cli_cases_wbtest.mbt（15 文件，+872/-169）。
