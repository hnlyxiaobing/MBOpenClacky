# env overlay 配置通路补全（BUG-0041/0015/0052）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0041、BUG-0015、BUG-0052；`reports/p5_fix_unit_clustering.md` FU-08  
> **关联历史 spec**: 无（配置簇首份；同簇 FU-12 见 `2026-08-18_20_p5-config-loading-alignment.md`）  
> **来源差距**: P3 链路层（剧本 005）+ P2 单元层（config-003、config-019）  
> **依赖**: 无（批次 3 配置簇，建议与 FU-12 同批连续改，本 spec 先行）  
> **灰度 key**: 无

## 问题描述 [必填]

配置的环境变量通路存在三处与 Ruby 原版的已证实分歧：

1. **BUG-0041**：`MBOPENCLACKY_COMPRESSION_THRESHOLD` 不被 `apply_env_overlay()` 读取。该函数（`lib/config/loader.mbt:279-323`）只处理 `MBOPENCLACKY_API_KEY/BASE_URL/MODEL/ANTHROPIC_FORMAT/VERBOSE`。diff-harness 链路侧 moonbit 目标全部配置经 `MBOPENCLACKY_*` 注入（`run_scenario.py:84-87`），压缩阈值无法经此前缀生效，剧本 005 曾因 threshold 保持默认 150000 不触发压缩。当前 e2e 005 剧本改用 `CLACKY_COMPRESSION_THRESHOLD=1`（env_compat 通路）绕过，BUG 本身仍在。
2. **BUG-0015**：配置文件已有模型时，Ruby 仍会把 `CLACKY_*` 环境变量模型**追加**进 models（type 不重复时，`agent_config.rb:287-307`）；MB 的 `merge_config()` 用 env 模型**整体替换**文件模型（`env_compat.mbt:158-160`），导致 config-003 实测 MB 侧 models_count=1、current 被 env 模型夺走。
3. **BUG-0052**：`try_load_with_prefix()` 硬编码 `anthropic_format: true`（`env_compat.mbt:68`），全 lib 无任何代码读取 `CLACKY_ANTHROPIC_FORMAT`；Ruby 的 `ClackyEnv.default_anthropic_format` 读取该变量（未设置默认 true，`agent_config.rb:95-98`）。config-019（`CLACKY_ANTHROPIC_FORMAT=false`）实测分歧。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "apply_env_overlay 只处理 5 个变量，不读 COMPRESSION_THRESHOLD" | 读 `lib/config/loader.mbt:279-323` | 仅 `MBOPENCLACKY_API_KEY/BASE_URL/MODEL/ANTHROPIC_FORMAT`（行 283-297，且仅 models 为空时生效）+ `MBOPENCLACKY_VERBOSE`（行 318-320）；无 `_COMPRESSION_THRESHOLD`/`_MAX_TOKENS` | 确认 BUG-0041 |
| "env_compat 通路读 _COMPRESSION_THRESHOLD 但以 _API_KEY 存在为前提" | 读 `lib/config/env_compat.mbt:44-94` | 行 83-89 读 `<prefix>_MAX_TOKENS`/`_COMPRESSION_THRESHOLD`；行 45-47 无 `<prefix>_API_KEY` 直接返回 None | 阈值通路存在但与 API_KEY 耦合；moonbit 链路目标只设 MBOPENCLACKY_ 前缀，走不到此通路 |
| "try_load_with_prefix 硬编码 anthropic_format: true" | 读 `lib/config/env_compat.mbt:59-71`（行 68）与 `load_claude_compat`（行 119） | 两处均硬编码 true，不读 `<prefix>_ANTHROPIC_FORMAT` | 确认 BUG-0052 |
| "全 lib 无 CLACKY_ANTHROPIC_FORMAT 读取" | `grep -rn "ANTHROPIC_FORMAT" lib/` | 仅 `loader.mbt:293-297`（MBOPENCLACKY_ 前缀） | 确认 BUG-0052 无其他读取点 |
| "Ruby 配置文件有模型时仍追加 env 模型（type 不重复）" | 读 openclacky `lib/clacky/agent_config.rb:287-307` | `has_default`/`has_lite` 检查，缺则 `models << ClackyEnv.default_model_config`；行 305-307 无 default 时首模型补 `type=default` | 确认 BUG-0015 参照行为 |
| "Ruby CLACKY_ANTHROPIC_FORMAT 未设置默认 true" | 读 openclacky `agent_config.rb:54-57,95-98` | `ENV_ANTHROPIC_FORMAT="CLACKY_ANTHROPIC_FORMAT"`；`return true if nil/empty`，否则 `downcase == "true"` | 确认 BUG-0052 参照行为 |
| "MB merge_config 用 env 模型整体替换文件模型" | 读 `lib/config/env_compat.mbt:155-160` | `if !overlay.models.is_empty() { result.models = overlay.models }` | config-003 MB 侧 count=1、current=sk-env 的根因 |
| "BUG-0041 闸门在册但无对应回归用例" | `grep -rn "BUG-0041" D:/MoonBit/MBOpenClacky` | 仅 `test/diff/known_failure.mbt:57`（在册登记），无任何测试引用 | 修复需新增回归用例 |
| "e2e 005 当前经 CLACKY_ 前缀绕过 BUG-0041" | 读 `test/e2e/scenarios/005_compression_trigger.json` description | 自述"MB 侧通过 CLACKY_COMPRESSION_THRESHOLD=1 环境变量（env_compat.mbt 的 CLACKY_ 前缀路径）注入" | 修复后可将注入改回 MBOPENCLACKY_ 前缀以闭环验证 |
| "链路证据存在" | `ls D:/MoonBit/diff-harness/runs/005_compression_trigger/` | ruby/ 与 moonbit/ 产物齐全 | 确认 |

### 详细分析

**MB 配置加载三层结构**（`lib/config/loader.mbt:25-37` `load_with_env`）：

```
AgentConfig::load(path)          # TOML 文件
  └─ apply_env_overlay()         # legacy MBOPENCLACKY_* 层（仅 models 为空时注入模型 + VERBOSE）
  └─ load_config_from_env()      # CLACKY_ > OPENCLACKY_ > CLAUDE_ 优先级层
       └─ merge_config(base, overlay)   # overlay.models 非空即整体替换
```

**Ruby 对照**（`agent_config.rb:267-307`）：`load` 解析配置文件模型后，无论 models 是否为空都会检查 `ClackyEnv.default_configured?`——models 为空则直接采用 env 模型；models 非空但无 `type=="default"` 且无 env 同 type 模型时**追加** env 模型；最后保证至少一个模型带 `type: default`（行 305-307）。即 Ruby 的语义是"按 type 去重追加"，MB 的语义是"非空即替换"。

**链路影响**：BUG-0041 使 005 类压缩剧本在 moonbit 侧无法复刻 ruby 的 `config.yml compression_threshold=1` 效果（diff-harness `run_scenario.py:120-127` 当前已改走 config.toml 文件注入注释"避免 BUG-0041 的 env overlay 缺口"）；BUG-0015 使任何"文件有模型 + env 有 key"的部署形态下 MB 静默丢弃文件模型（高严重度，fix_plan_reference 标 P1）。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0041）**：`apply_env_overlay()` 增加 `MBOPENCLACKY_COMPRESSION_THRESHOLD` 读取（`@utils.env_int` 模式，置于 VERBOSE 覆盖附近，loader.mbt:317-321 区域）。
   - **为什么**：`MBOPENCLACKY_*` 是 MB 的 legacy 前缀层，也是 diff-harness moonbit 目标的唯一注入通路（`run_scenario.py:84-87`）；阈值必须经同通路注入才能复刻 ruby `config.yml` 的 `compression_threshold: 1` 链路行为。**不**顺带加 `MBOPENCLACKY_MAX_TOKENS`——台账未登记该差异，保持最小改动。
2. **决策 2（BUG-0015）**：`merge_config()` 的 models 合并从"整体替换"改为"按 type 去重追加"：overlay 模型（env 层，type 缺省为 `"default"`）仅当 base 中不存在同 type 模型时才追加；合并后若仍无 `type=="default"` 模型，给首模型补 `type_ = Some("default")`（对齐 `agent_config.rb:305-307`）。
   - **为什么**：与 Ruby `agent_config.rb:287-307` 语义一致；`merge_config` 是 `load_with_env` 的唯一汇合点，改这里单点生效。`apply_env_overlay`（MBOPENCLACKY_ legacy 层）维持"models 为空才注入"的现状——Ruby 无对应物，此前缀本身是 wontfix 扩展（BUG-0016），不在本 spec 对齐范围。
   - **影响面核查**：config-004/005/006/015 等绿用例的 base 均无文件模型（追加 ≡ 替换），不受影响；config-003 从红转绿。
3. **决策 3（BUG-0052）**：`try_load_with_prefix()` 读取 `<prefix>_ANTHROPIC_FORMAT`：未设置或空串 → true（保持现默认）；否则 `to_lower() == "true"`。
   - **为什么**：逐字对齐 `ClackyEnv.default_anthropic_format`（agent_config.rb:95-98）；CLACKY_ 与 OPENCLACKY_ 共用此函数，一处修复两前缀生效。`load_claude_compat` 不动（Ruby 侧 ClaudeCode 支持已禁用，MB 的 CLAUDE_ 层属 BUG-0018 wontfix 扩展）。
4. **决策 4（验证闭环）**：修复后将 e2e 005 剧本的 MB 侧注入从 `CLACKY_COMPRESSION_THRESHOLD` 改回 `MBOPENCLACKY_COMPRESSION_THRESHOLD`，证明 BUG-0041 通路真实可用；同时在 test/diff 新增 BUG-0041 单元回归（当前只有闸门登记无用例）。
   - **为什么**：005 description 自述的 CLACKY_ 注入是绕过手段；不改回则 BUG-0041 无链路级证据闭环。若改回引入其他剧本断言变动，则退回"保留 CLACKY_ 注入 + 单元回归兜底"方案并在实施记录中说明。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖（`@utils.env_int` 已在 env_compat.mbt 使用）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/loader.mbt` | 修改 | `apply_env_overlay()`（行 279-323）增加 `MBOPENCLACKY_COMPRESSION_THRESHOLD` 读取 |
| `lib/config/env_compat.mbt` | 修改 | ①`try_load_with_prefix()`（行 59-71）anthropic_format 改读 `<prefix>_ANTHROPIC_FORMAT`；②`merge_config()`（行 155-160）models 合并改按 type 去重追加 + 首模型补 default |
| `lib/config/loader_wbtest.mbt` 或 `env_compat` 同包白盒 | 修改 | 新增：MBOPENCLACKY_COMPRESSION_THRESHOLD 注入（BUG-0041）；merge_config 追加语义（BUG-0015）；`<prefix>_ANTHROPIC_FORMAT=false`（BUG-0052） |
| `test/diff/config_cli_cases_wbtest.mbt` | 修改 | config-003 移除 `known_failure("BUG-0015")`（行 220）；config-019 移除 `known_failure("BUG-0052")`（行 354） |
| `test/diff/known_failure.mbt` | 修改 | 从在册数组移除 BUG-0015、BUG-0052（BUG-0041 视新用例是否仍需闸门而定，目标同步移除） |
| `test/e2e/scenarios/005_compression_trigger.json` | 修改 | MB 侧阈值注入改回 MBOPENCLACKY_ 前缀并更新 description（若验证不可行则保留现状并记录原因） |

### 不涉及文件

- `lib/config/agent.mbt` — AgentConfig 结构与本 spec 无关（属 FU-12）
- `from_toml` / `to_toml` — 文件读写路径（属 FU-12：BUG-0012/0022/0014）
- `load_claude_compat` — CLAUDE_ 兼容层为 wontfix 扩展（BUG-0018）
- `lib/agent/compressor.mbt` — 压缩判定语义属 FU-07

## 实施计划 [必填]

### 任务包 1：BUG-0052 + BUG-0041（env 变量读取补全，预估 0.5 天）

1. `try_load_with_prefix()` 增加 `<prefix>_ANTHROPIC_FORMAT` 解析（未设/空→true，否则 lower=="true"）。
2. `apply_env_overlay()` 增加 `MBOPENCLACKY_COMPRESSION_THRESHOLD` 读取。
3. 白盒单测：CLACKY_ANTHROPIC_FORMAT=false → anthropic_format=false；未设置 → true；MBOPENCLACKY_COMPRESSION_THRESHOLD=1 → config.compression_threshold==1。
4. config-019 移除 BUG-0052 闸门转绿。

### 任务包 2：BUG-0015（merge_config 追加语义，预估 0.5 天）

1. `merge_config()` models 合并改按 type 去重追加 + 无 default 补首模型。
2. config-003 移除 BUG-0015 闸门转绿（models_count=2、current 保持 sk-file）。
3. 跑 config-004/005/006/013/016/020 确认无回归。

### 任务包 3：链路闭环与全量回归（预估 0.5 天）

1. e2e 005 改回 MBOPENCLACKY_COMPRESSION_THRESHOLD 注入并跑通（或记录保留 CLACKY_ 的原因）。
2. known_failure.mbt 移除 BUG-0015/0052（0041 视用例落地情况）。
3. `moon check` 0 errors；全量 `moon test` 无回归；diff-harness 复跑剧本 005 两侧对比。

## 验收标准 [必填]

- [ ] `MBOPENCLACKY_COMPRESSION_THRESHOLD` 经 apply_env_overlay 生效（新增单测 + e2e 005 BUG-0041 部分闭环）
- [ ] config-003：文件模型 + CLACKY_* env 时 models_count=2、current 保持文件模型（BUG-0015 闸门移除转绿）
- [ ] config-019：CLACKY_ANTHROPIC_FORMAT=false 生效（BUG-0052 闸门移除转绿）
- [ ] `test/diff/known_failure.mbt` 在册数组移除 BUG-0015、BUG-0052（及 BUG-0041，如用例落地）
- [ ] `moon check` 0 errors（lib/config、test/diff、test/e2e）
- [ ] `moon test lib/config`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| merge_config 追加语义改变现有绿用例行为 | 中 | 任务包 2 逐一跑 config-004~020；base 无模型场景追加≡替换，理论无影响，实测确认 |
| env 模型追加后 current_model 解析变化（badge 语义） | 中 | current_model 是 badge-first（loader.mbt:347-368）；追加的 env 模型带 type=default 仅当 base 无 default——与 ruby 的"首个/default badge"语义一致；用 config-003/013 覆盖 |
| e2e 005 改注入方式触发其他断言变动 | 低 | 剧本 golden 对比以请求序列为准；阈值值不变（=1）仅注入通路变化；失败则退回单元级闭环并记录 |
| ANTHROPIC_FORMAT 解析与 ruby 边界差异（如 "TRUE"/"1"） | 低 | 逐字对齐 `downcase == "true"`；单测覆盖大小写 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：FU-12（同文件 loader.mbt，建议同批随后实施）；FU-07 压缩簇的链路验证依赖本 spec 的阈值通路

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本（BUG-0041+0015） | P5 归并分析 FU-08 |
| 2026-08-14 | 并入 BUG-0052（CLACKY_ANTHROPIC_FORMAT 未读取） | P5 新登记条目，同根因族（env 变量读取缺口） |
