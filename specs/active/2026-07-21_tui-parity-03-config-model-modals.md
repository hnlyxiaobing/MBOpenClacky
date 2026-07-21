# TUI 对齐批次 3：/config 配置菜单与 /model 选择器 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 讨论中（draft，待对抗性审核）  
> **关联总览**: `docs/tui_feature_parity_plan.md`（功能差距矩阵）  
> **关联历史 spec**: `specs/active/2026-07-21_tui-parity-01-command-usability.md`（批次 1，controller 拦截模式）  
> **来源差距**: C02 / C03 / C04 / K04（差距矩阵批次 3，P1——最大功能缺口）  
> **依赖**: 建议批次 1 先落地（/exit、controller 拦截模式）；ConfigMenuDialog/FormDialog 组件已存在  
> **灰度 key**: 无

## 问题描述 [必填]

原版的 `/config` 是完整的交互式配置管理（模型列表 + 掩码 API key + Add/Edit/Delete + 带连接测试的编辑表单），`/model` 是两级抽屉选择器（模型卡片 → 子模型）。MBOpenClacky 现状：

| # | 缺口 | 来源 ID |
|---|------|---------|
| 1 | `/config` 仅支持 `/config <key> <value>` 赋值且只有 `max_tokens`/`verbose`/`fallback_model` 三个 key 真写，无交互菜单 | C02 |
| 2 | 无模型编辑表单（Provider 选择、掩码 key、连接测试 validator） | C03 |
| 3 | `/model` 只能 `/model <name>` 盲打模型名，无列表选择器 | C04 |
| 4 | ConfigMenuDialog/FormDialog 组件渲染与状态逻辑完备但**无触发入口**；缺 jk 导航/掩码字段/validator 钩子 | K04 |
| 5 | 配置变更不持久化（重启丢失） | C02 |

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| ConfigMenuDialog/FormDialog 无生产调用点 | `grep -rn "ConfigMenuDialog::new\|FormDialog::new" lib/ --include="*.mbt"` | 仅 `dialog_config_menu.mbt:84`、`dialog_form.mbt:59` 定义行（wbtest 除外） | 确认：组件是死代码，本 spec 激活 |
| /config 仅 3 key 真写 | `lib/tui/slash_commands.mbt:209-221` | max_tokens/verbose/fallback_model 写 agent.config；其余回显 | 确认 |
| /model 直切实现 | `slash_commands.mbt:227-240` | 重建 `@client.Client` 替换 `agent.client`，保留 api_key/base_url/api_type | 确认：直切逻辑可复用为选择器的"确认"动作 |
| 配置持久化路径已存在 | `grep -n "pub fn AgentConfig::save" lib/config/loader.mbt` | `loader.mbt:42 AgentConfig::save(path)` | 确认：持久化只需调用，不需新建 |
| 多模型配置的数据结构 | `grep "models\|current_model_id\|switch_model" lib/config/agent.mbt` | `agent.mbt:9` `mut models : Array[ModelConfig]`、`:10` `mut current_model_id : String?`、`:43` `switch_model_by_id`、`:65` `switch_model_by_name`；ModelConfig（`lib/config/model.mbt:3`）已含 `type_`/`api_key`/`base_url`/`model` 字段 | 确认：结构已存在，菜单/选择器/表单均有数据源，无需新增结构（原"待实施时验证"已消除） |
| 连接测试能力 | `lib/client/http_async.mbt` | `http_post_async` 存在；可用一个最小 chat 请求或 models 列表请求做 validator | 确认可行；validator 需 async，FormDialog 当前为同步状态机（见决策 3） |
| ApprovalDialog 的 modal 先例 | `tui_controller.mbt` 确认对话框分支 + `modal_lifecycle.mbt` | 已有"对话框拦截键位 → resolve → 恢复"完整模式 | 确认：/config、/model 菜单复用同一 modal 生命周期 |
| 掩码 key 展示 | 外部参照（原版 `ui_controller.rb:1529`，当前仓库无 `.repos/`，未验证） | `sk-...XXXX`（前 3 后 4） | 原版行号待复核；掩码规则可直接复刻 |

## 决策 [必填 - 含为什么]

1. **/config 采用 controller 拦截打开 ConfigMenuDialog（沿用批次 1 的 /todo、/theme 拦截模式），同时保留 `/config <key> <value>` 快捷赋值路径**。理由：带参数时是明确意图，无参数时进菜单；两形态不冲突，也与批次 3 后 `/model` 双形态决策一致。
2. **菜单分两级**：L1 模型列表（当前模型高亮、掩码 key、type 徽标；操作：Enter 切换 / a Add / e Edit / d Delete / Esc 关闭）；L2 编辑表单（FormDialog：Provider 下拉预设 + api_key 掩码字段 + model + base_url）。理由：与原版信息架构一致，且 ConfigMenuDialog 的单选/多选与 FormDialog 的多字段模型已覆盖所需交互，只需补 jk 导航与掩码显示。
3. **连接测试 validator 本批降级为"保存后异步验证 + 失败警告"**：表单保存先落盘，随后发起一次轻量请求，失败在消息区输出 [warning]，不在表单内阻塞循环。理由：FormDialog 是纯同步状态机，表单内嵌 async validator 需要引入"表单等待态"渲染与取消语义，复杂度超本批预算；原版体验（⏳ Testing connection）列为后续优化，差异显式记录。
4. **/model 双形态**：`/model`（无参数）打开选择器（当前配置内的可用模型列表；若配置只有单模型则直接提示无可切换项）；`/model <name>` 保留直切。理由：MBOpenClacky 的配置模型若只有单一 active model，两级抽屉无数据源——选择器的数据边界就是"配置中已知的模型集合"，不臆造 provider 目录（见风险 1）。
5. **持久化统一走 `AgentConfig::save`**：菜单内一切变更（切换/增/删/改）立即落盘 + 热切换 agent.client。理由：原版同语义；save 已存在。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及运行时动态加载 trait；Provider 预设列表为静态数据。
- crescent 路由：不涉及。
- FFI：不涉及（连接测试复用 http_post_async）。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller.mbt` | 修改 | /config、/model 拦截分支；modal 状态接入主循环键位分发；菜单动作 → client 热切换 + AgentConfig::save |
| `lib/tui/slash_commands.mbt` | 修改 | Config 无参数时返回特殊标记或直接由 parser 分流（与 controller 约定拦截点） |
| `lib/tui/dialog_config_menu.mbt` | 修改 | 补 jk 导航、type 徽标列、当前模型高亮、disabled 分隔项 |
| `lib/tui/dialog_form.mbt` | 修改 | 补掩码字段类型（api_key 显示为 `sk-...XXXX`）、Provider 下拉字段 |
| `lib/tui/modal_lifecycle.mbt` | 修改 | 扩展状态机支持多步 modal（菜单→表单→返回） |
| `lib/tui/state.mbt` | 修改 | TuiState 增加 config_menu/form 活动状态 |
| `lib/config/agent.mbt`、`lib/config/model.mbt`（只读调用） | 不修改 | AgentConfig 已有 `models`/`current_model_id`/`switch_model_*`，ModelConfig 已含所需字段，菜单直接调用，无需改结构 |
| `lib/tui/dialog_config_menu_wbtest.mbt`、`dialog_form_wbtest.mbt` | 修改 | 补 jk/掩码/高亮单测 |
| `test/scenarios/tui/config_menu_open.json`、`config_menu_switch.json`、`model_selector.json` | 新建 | eval 场景 |

### 不涉及文件

- `lib/client/http_async.mbt`（连接测试只调用）
- `lib/agent/react.mbt`、`llm_caller.mbt`（热切换只换 client 字段，不动调用链）
- `lib/tui/dialog_approval.mbt`（审批对话框独立）

## 实施计划 [必填]

1. **结构确认（已完成，0 天）**：AgentConfig 已有 `models: Array[ModelConfig]` + `current_model_id` + `switch_model_by_id`/`switch_model_by_name`，ModelConfig 已含 `type_`/`api_key`/`base_url`/`model`，无需新增结构或迁移。
2. ConfigMenuDialog 激活：/config 拦截 → 模型列表渲染（掩码/徽标/高亮）→ Enter 切换 + save（1.5 天）。
3. FormDialog 编辑：Add/Edit 表单（Provider 预设 + 掩码 + 三字段）→ 保存落盘（1.5 天）。
4. Delete 流程（确认后删除 + save + 当前模型被删时回退策略）（0.5 天）。
5. /model 选择器（复用 ConfigMenuDialog 的列表渲染，单级）（1 天）。
6. 保存后异步连接验证 + [warning]（0.5 天）。
7. eval 场景 + 全量验证 + 人工 TTY 走查 Add/Edit/Delete/切换（1 天）。

## 验收标准 [必填]

- [ ] `/config` 打开模型列表菜单：掩码 key、当前模型高亮、jk/↑↓ 导航、Esc 关闭
- [ ] 菜单内 Enter 切换模型立即生效（状态栏模型名变化）且重启后保持（持久化）
- [ ] Add 表单可新增模型（Provider 预设 + key 掩码输入 + model + base_url），保存后出现在列表
- [ ] Edit/Delete 流程可用；删除当前模型时有明确回退行为
- [ ] `/model` 打开选择器；`/model <name>` 直切保留
- [ ] 连接验证失败时消息区出现 [warning] 但配置已保存（降级语义）
- [ ] `moon check` 0 errors；`moon test lib/tui`、`lib/config` 通过
- [ ] `--tui-eval` 全量 PASS（含新增 3 场景）
- [ ] 人工 TTY 完整走查 Add → Edit → 切换 → Delete

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~AgentConfig 无多模型列表结构~~（审核已确认存在 `models: Array[ModelConfig]` + `current_model_id` + `switch_model_by_id`/`switch_model_by_name`） | ~~高~~→已消除 | 无需新增结构；切换/增删改直接操作 `models` 数组；旧配置兼容由现有 load/save 处理 |
| modal 多步（菜单→表单）状态复杂化 | 中 | modal_lifecycle 扩展为先导单测（纯状态机可脱离终端测）；键位分发集中在 controller 单点 |
| 热切换 client 后进行中的 agent 运行引用旧 client | 中 | 菜单操作期间若 agent_running 则禁用切换（提示 "agent is running"） |
| 掩码字段误将明文写入持久化 | 高 | 掩码仅用于显示；表单输入态保存明文但渲染掩码；单测覆盖 |
| 旧配置文件格式变更破坏兼容 | 中 | loader 保留旧字段读取路径；save 写新格式；补迁移单测 |

## 依赖关系 [必填]

- **前置依赖**：建议批次 1（controller 拦截模式、/exit 落地）；ConfigMenuDialog/FormDialog/modal_lifecycle 已存在
- **后置依赖**：批次 4 的 token 统计/状态展示默认模型切换已可用；批次 5 的 Shift+Tab 权限切换复用 modal 键位分发

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：8 项声称经 grep 验证（两对话框无生产调用点、AgentConfig::save 存在、/model 直切可复用）；validator 降级、双形态、多模型结构前置验证三处显式决策 | 差距矩阵批次 3（P1）落实 |
| 2026-07-21 | 审核修正：多模型结构声称"待实施时验证"纠正为"已确认存在"（AgentConfig `models: Array[ModelConfig]` + `current_model_id` + `switch_model_by_id`/`by_name`，ModelConfig 已含 type_/api_key/base_url/model）；风险 1 高估降级为已消除；实施计划任务 1 由"前置验证"改为"已完成"；原版 `ui_controller.rb:1529` 标注未验证外部参照；交叉引用 parity-01 draft->active | 对抗性审核 + 第一性原理校验 |
