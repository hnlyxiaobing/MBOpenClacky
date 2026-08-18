# 配置加载对齐（BUG-0012/0022/0013/0014/0020）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0012、BUG-0022、BUG-0013、BUG-0014、BUG-0020；`reports/p5_fix_unit_clustering.md` FU-12  
> **关联历史 spec**: 无（配置簇第二份；同簇 FU-08 见 `2026-08-18_19_p5-env-overlay-config-channel.md`）  
> **来源差距**: P2 单元层（config-002/004/009/011/012/014）  
> **依赖**: 建议与 FU-08 同批连续改（同文件 loader.mbt），FU-08 先行  
> **灰度 key**: 无

## 问题描述 [必填]

配置 TOML 读写与模型切换存在五处与 Ruby 原版的已证实分歧：

1. **BUG-0012**：MB `from_toml` 从配置文件加载 `max_tokens`（loader.mbt:78-81）；Ruby 的 `CONFIG_SETTINGS_KEYS` 不含 `max_tokens`（agent_config.rb:414-421），不加载。**台账"期望行为"写"应从配置文件加载 max_tokens"，与 Ruby 原版行为（不加载）矛盾——按判定总则应删 MB 行为，但这更像原版缺陷，需显式裁决（决策 1）。**
2. **BUG-0022**：保存后加载 `max_tokens` 一致性。MB 保存（to_toml 行 208）与加载都含 max_tokens，自洽；Ruby `to_yaml`（agent_config.rb:426-445）的 settings 哈希**同样不含** max_tokens——保存端也不写。与 BUG-0012 同根因，同裁决。
3. **BUG-0013**：文件加载的模型未指定 `anthropic_format` 时，Ruby 为 `nil`（新格式 models 数组原样透传，agent_config.rb:1358-1362），MB 为 `false`（loader.mbt:175-178 缺省 false）。语义上 Ruby `anthropic_format?` 对 nil 按 false 处理（agent_config.rb:615-616），属等价；但 config_012 回归用例的闸门后断言（true）与 ruby_results 实测（null）矛盾，需修正。
4. **BUG-0014**：TOML 加载路径不自动设置 `current_model_id`；Ruby `load` 自动设为 default 模型 id（无 default 时回退第一个模型，agent_config.rb:326-338）。扩展证据 config-014：无 badge、多模型时 MB `current_model()` 返回 None。
5. **BUG-0020**：`switch_model_by_id` 失败时 Ruby 返回 false 且 `current_model` 仍返回旧模型；当前基线 MB 的失败路径行为已与之一致（Err 不改 current_model_id，单模型回退已绿），**剩余差异仅为错误消息文案**：Ruby 冻结 "model not found" vs MB "model not found with id: non-existent"。台账"MB 返回 None"的描述已过时。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB from_toml 读 max_tokens" | 读 `lib/config/loader.mbt:78-81` | `settings.get("max_tokens") → config.max_tokens` | 确认 MB 加载 |
| "MB to_toml 写 max_tokens" | 读 `lib/config/loader.mbt:208` | `settings["max_tokens"] = TomlInteger(...)` | 确认 MB 保存；MB 保存/加载自洽 |
| "Ruby CONFIG_SETTINGS_KEYS 不含 max_tokens" | 读 openclacky `agent_config.rb:414-421` + `load` 行 339-343 | KEYS 12 项无 max_tokens；load 只按 KEYS 注入构造参数 | 确认 Ruby 不加载 |
| "Ruby to_yaml 同样不写 max_tokens" | 读 openclacky `agent_config.rb:426-445` | settings 哈希 12 键无 max_tokens | 台账 BUG-0022"保存时包含 max_tokens"描述与源码不符（保存端也不含）；实测结论（回读默认 16384）不受影响 |
| "Ruby load 自动设 current_model_id" | 读 openclacky `agent_config.rb:326-338` | `default_index = find_index(type=="default") || 0`；`current_model_id: default_id` | 确认 BUG-0014 参照 |
| "MB from_toml 不自动设 current_model_id" | 读 `lib/config/loader.mbt:106-109` | 仅读显式 `current_model_id` 键 | 确认 BUG-0014 |
| "config-014 扩展证据" | 读 `test/diff/config_cli_cases_wbtest.mbt:487-512` + `lib/config/loader.mbt:360-366` | 无 badge 且 current_model_id 为 None 时仅单模型回退，多模型返回 None | 确认（BUGS.md 2026-08-14 修订已登记） |
| "Ruby switch_model_by_id 失败不动当前模型" | 读 openclacky `agent_config.rb:474-493` | `return false if index.nil?`，无赋值；current_model 经 id/badge 解析仍返回旧模型 | 确认参照 |
| "BUG-0020 当前基线剩余差异仅错误消息" | 读 `test/diff/config_cli_cases_wbtest.mbt:430-453` + `lib/config/agent.mbt:51-68` | current_model 单模型回退已绿（行 442-446）；闸门后断言冻结 Ruby 消息 "model not found"（行 452）vs MB "model not found with id: \{id}"（agent.mbt:67） | 确认；台账"MB 返回 None"已过时 |
| "Ruby 文件加载 anthropic_format 为 nil" | 读 `cases/config_cli/ruby_results.json` config-002（行 28）/config-012（行 172）均为 `null` + `agent_config.rb:1358-1362`（新格式数组原样透传，无 `\|\| false` 归一化）+ `agent_config.rb:615-616`（`anthropic_format?` 对 nil 按 false） | nil 语义 ≡ false | 确认 BUG-0013 性质为表示差异；config_012 闸门后断言 true（wbtest 行 157）与实测 null 矛盾，需修正 |
| "config-019 已改挂 BUG-0052（FU-08）" | 读 `test/diff/config_cli_cases_wbtest.mbt:341-357` + `test/diff/known_failure.mbt:69` | CLACKY_ANTHROPIC_FORMAT 未读取问题已从 BUG-0013 拆出单独立项 | 不在本 spec 范围 |

### 详细分析

**MB 读写路径**（`lib/config/loader.mbt`）：`from_toml`（行 63-148）逐键解析 settings + models；`to_toml`（行 200-250）全量序列化（含 max_tokens）。`current_model()`（行 347-368）解析顺序：default badge → current_model_id → 单模型回退 → None。

**Ruby 对照**（`agent_config.rb`）：`load`（行 249-348）只把 `CONFIG_SETTINGS_KEYS` 内的键注入构造参数（max_tokens 不在列）；构造时 `current_model_id` 自动锚定 default（回退第一个）模型；`switch_model_by_id`（行 474-493）失败返回 false 不动状态；`anthropic_format` 在新格式下透传（可 nil），消费端 `anthropic_format?` 按 `\|\| false` 归一。

**各条目与回归用例映射**（test/diff/config_cli_cases_wbtest.mbt）：

| BUG | 用例 | 闸门行 | 当前状态 |
|-----|------|--------|---------|
| BUG-0012 | config-002 | 行 121 | 闸门后冻结 Ruby 行为（max_tokens=16384） |
| BUG-0022 | config-011 | 行 562 | 闸门后冻结 Ruby 行为（回读 16384） |
| BUG-0013 | config-012 | 行 154 | 闸门后断言 true，与 ruby_results null 矛盾 |
| BUG-0014 | config-004（文件路径部分）/config-014 | 行 505（config-014） | config-004 env 路径已绿 |
| BUG-0020 | config-009 | 行 449 | 仅消息文案差异 |

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0012/0022 关键裁决，两个选项，最终裁决留给用户）**：
   - **选项 A（按判定总则对齐 Ruby）**：删除 `from_toml` 的 max_tokens 加载（loader.mbt:78-81）；`to_toml` 的 max_tokens 序列化（行 208）一并删除或保留均可（Ruby 保存端也不写，建议一并删除以完全对齐）。config-002/011 闸门移除、按 Ruby 行为（16384）转绿。代价：MB 用户失去从配置文件设置 max_tokens 的能力。
   - **选项 B（标"原版缺陷"，保留 MB 行为）【建议】**：Ruby 的"保存不写、加载不读"是 `CONFIG_SETTINGS_KEYS` 遗漏缺陷的强信号（max_tokens 是有一等 accessor 的常规设置项）；MB 保存/加载自洽且功能更完整。按总则"能从 openclacky 源码证明原版行为本身是 bug 时允许标记原版缺陷"——CONFIG_SETTINGS_KEYS 与 to_yaml 双双遗漏即为证据。落地动作：MB 代码零改动；config-002/011 闸门移除，断言改写为冻结 MB 行为（从文件加载 8192 / 回读 4096）；BUGS.md 两条目备注"原版缺陷"并保留 Ruby 行为描述。
   - **建议选项 B**：MB 行为自洽、无用户可感缺陷；选项 A 是删功能对齐一个疑似缺陷。
2. **决策 2（BUG-0014）**：`from_toml` 末尾自动设置 `current_model_id`：优先 `type_ == Some("default")` 的模型 id，否则第一个模型 id（对齐 agent_config.rb:326-338）。
   - **为什么**：单点修复同时覆盖 config-004 文件路径与 config-014；无需动 `current_model()` 的单模型回退限制（loader.mbt:360-366）——current_model_id 一旦设置，多模型场景即可定位，最小侵入。
3. **决策 3（BUG-0013）**：认定为表示差异、语义等价，关闭为 wontfix 类处置：MB `Bool` 无需也无法表达 nil，消费端语义与 Ruby `anthropic_format?` 的 `\|\| false` 一致。落地动作：config_012 移除闸门，闸门后断言从 `assert_true` 修正为 `assert_false`（当前断言 true 与 ruby_results 实测 null 矛盾，属迁移期错误冻结）；BUGS.md 回写"语义等价，冻结 MB false"。`CLACKY_ANTHROPIC_FORMAT` env 读取属 BUG-0052/FU-08，不在本 spec。
4. **决策 4（BUG-0020）**：`switch_model_by_id` 的 Err 消息改为 `"model not found"`（agent.mbt:67），与 Ruby 冻结文案对齐；`switch_model_by_name` 同理评估（config-008 已绿则不动）。
   - **为什么**：行为语义两侧已一致，仅对外消息文案残留差异；改消息是最小对齐。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/loader.mbt` | 修改 | `from_toml`（行 63-148）末尾自动设置 current_model_id（决策 2）；max_tokens 加载/序列化按决策 1 裁决（选项 A：删行 78-81 与 208；选项 B：不动） |
| `lib/config/agent.mbt` | 修改 | `switch_model_by_id`（行 67）Err 消息改 "model not found" |
| `test/diff/config_cli_cases_wbtest.mbt` | 修改 | config-002（行 121）/config-011（行 562）按决策 1 裁决移除闸门并修正断言；config-012（行 154）移除闸门、断言改 false；config-014（行 505）移除闸门转绿；config-009（行 449）移除闸门转绿 |
| `test/diff/known_failure.mbt` | 修改 | 在册数组移除 BUG-0012、BUG-0022、BUG-0013、BUG-0014、BUG-0020 |
| `reports/BUGS.md`（diff-harness 侧） | 修改 | 各条目修复/关闭记录回写；BUG-0012/0022 按裁决标"原版缺陷"（选项 B 时） |

### 不涉及文件

- `lib/config/env_compat.mbt` — env 通路与 merge_config 属 FU-08
- `apply_env_overlay` — 属 FU-08（BUG-0041）
- `current_model()` 的 badge-first 解析逻辑（loader.mbt:347-368）— 决策 2 已论证无需改动
- BUG-0016~0019、0021（wontfix 扩展/表示差异）— 不动

## 实施计划 [必填]

### 任务包 1：BUG-0012/0022 裁决确认（预估 0.5 天）

1. 向用户呈交决策 1 两个选项与建议（选项 B）；裁决落地前不动 max_tokens 相关代码。
2. 裁决后：选项 A 删加载/序列化并转绿 Ruby 冻结断言；选项 B 改写 config-002/011 断言冻结 MB 行为并回写 BUGS.md"原版缺陷"备注。

### 任务包 2：BUG-0014 + BUG-0020（预估 0.5 天）

1. from_toml 自动设置 current_model_id（default badge 优先，回退第一个）。
2. switch_model_by_id 错误消息对齐。
3. config-004/014/009 移除闸门转绿；同包白盒补 from_toml 自动锚定用例。

### 任务包 3：BUG-0013 关闭 + 全量回归（预估 0.5 天）

1. config_012 断言修正为 false、移除闸门；BUGS.md 回写"语义等价"。
2. known_failure.mbt 移除五编号。
3. `moon check` 0 errors；`moon test lib/config`、`moon test test/diff`；全量 `moon test` 无回归；diff-harness 复跑 config_cli 用例集比对。

## 验收标准 [必填]

- [ ] BUG-0012/0022 裁决落地：选项 A 则 max_tokens 不加载且 config-002/011 按 16384 转绿；选项 B 则 config-002/011 按 MB 行为（8192/4096）转绿且 BUGS.md 标"原版缺陷"
- [ ] config-014：无 default badge 多模型时 current_model 返回第一个模型（BUG-0014 闸门移除转绿）；config-004 文件路径同步验证
- [ ] config-009：错误消息 "model not found"（BUG-0020 闸门移除转绿）
- [ ] config-012：断言修正为 false 并转绿，BUG-0013 关闭为语义等价（BUGS.md 回写）
- [ ] `test/diff/known_failure.mbt` 在册数组移除 BUG-0012、0013、0014、0020、0022
- [ ] `moon check` 0 errors（lib/config、test/diff）
- [ ] `moon test lib/config`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 决策 1 裁决与总则解读分歧 | 中 | 显式双选项 + 证据（CONFIG_SETTINGS_KEYS 与 to_yaml 双双遗漏）呈交用户；未裁决前不动代码 |
| from_toml 自动设 current_model_id 改变现有绿用例（如 config-016 deep_copy 断言 current_model_id==None） | 中 | config-016（wbtest 行 571-587）断言 `config.current_model_id == None`——自动锚定后该断言变红，需同步修订为断言锚定后的 id；任务包 2 全量扫 current_model_id 相关断言 |
| 错误消息改动影响其他消费方（TUI/server 展示） | 低 | grep "model not found" 全部引用点后改；消息仅用于展示 |
| config_012 断言修正被质疑"改测试通过" | 低 | 修正依据为 ruby_results.json 实测 null（验证记录），注释保留原冻结值与修订原因 |
| 选项 B 下与 ruby 的持久化格式差异长期存在 | 低 | BUGS.md 备注 + FEATURE_MATRIX 标注"原版缺陷，MB 保留"；后续 ruby 若修复可再对齐 |

## 依赖关系 [必填]

- **前置依赖**：无（建议 FU-08 先行仅因同文件减少冲突，非硬依赖）
- **后置依赖**：无；BUG-0052（CLACKY_ANTHROPIC_FORMAT）属 FU-08，与本 spec 的 BUG-0013 关闭无耦合

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-12 |
| 2026-08-14 | BUG-0012/0022 显式双选项裁决（建议选项 B 标原版缺陷）；BUG-0020 范围修正为消息文案；config-019 划归 BUG-0052/FU-08 | 当前基线代码验证结论 |
