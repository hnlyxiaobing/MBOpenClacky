# P3 契约补丁批次 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`  
> **来源差距**: I-032 ~ I-039（均 P3，八个零散契约/体验问题）  
> **依赖**: fix-06（前端验收环境）；本批次最低优先级，排最后

## 问题描述 [必填]

八个 P3 级问题，单个体量都很小，合并为一个批次处理（每项一个小节，逐一验证、逐一修复或定性）：

| ID | 问题 | 类型 |
|----|------|------|
| I-032 | 部分 404 错误体缺 `ok:false`（/api/mcp/:name/tools、/api/skills/:name/content） | 修复 |
| I-033 | /api/store/* 缺 `ok` 字段 | 修复 |
| I-034 | /api/agents 条目缺 `avatar` | 修复 |
| I-035 | /api/backup/status 缺 `config`/`dest_dir`/`is_wsl` | 修复 |
| I-036 | /api/browser/status 缺 `chrome_version` | **false positive**（字段已存在于 BrowserStatus derive(ToJson)，值为 null 与 orig 一致） |
| I-037 | i18n key `sessions.untitled` 缺失显示原始 key | 修复（前端补 key） |
| I-038 | 删除会话出现一次 DELETE net::ERR_ABORTED（疑似前端双发） | 调查 |
| I-039 | 首页 networkidle 15s 未达成（orig 2.8s vs current 16.8s） | 调查 |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-033 "store 列表响应缺 ok" | `Read lib/web/handlers_store.mbt:89-145` | `handle_store_list`/`handle_store_installed` 返回 `{extensions:[...]}` 无 `ok`；写操作（install/enable/disable/uninstall）均有 ok | 确认（读端点缺，写端点有） |
| I-034 "agents 条目来源" | `Read lib/web/handlers_agents.mbt:5-13` | 条目来自 `load_agents_from_assets()`（assets/agents/ JSON），avatar 缺失与否取决于资产文件与透传逻辑 | 确认需检查资产文件字段与白名单 |
| I-032 "404 错误体形状" | `Read lib/web/handlers_agents.mbt:44-46`（同类样本） | 404 返回 `{error:...}` 无 `ok:false`，与 I-032 描述的模式一致 | 确认模式存在；mcp/:name/tools 与 skills/:name/content 两处实施时逐点核对 |
| I-037 "上游也缺 key" | `docs/web-ui-issues.md` I-037 | 上游同样缺 `sessions.untitled`，但 current 因 I-002/I-011 修复前实际触发；`I18n.t` 返回 key 使 `\|\| "Untitled"` 兜底失效 | 确认决策方向：补 key 而非改兜底 |
| I-038/I-039 | `docs/web-ui-issues.md` | 均为运行期单次观测，未复现 | 定性为调查项 |

### 详细分析

六个修复项都是"输出补字段/补 key"级改动；两个调查项先定位再决定修复或记录。I-035 的 `is_wsl` 可复用 fix-01 引入的 `@utils.is_wsl1()`（`specs/completed/2026-07-24_web-ui-fix-01-wsl1-server-crash.md`）。I-037 注意：fix-06 前端升级会替换 `web/` 的 i18n 文件，本项必须在 fix-06 之后基于 v1.5.0 资产补 key。

## 决策 [必填 - 含为什么]

1. **404 错误体统一补 `ok:false`**：与 fix-04 确立的 `{ok, ...}` 包装约定一致；逐点修改，不抽象错误构造器（避免范围蔓延）。
2. **I-033 读端点补 `ok:true`**：与写端点及全局约定一致。
3. **I-034 avatar 按 orig 语义取值**（assets/agents 资产有则透传，无则按 orig 缺省规则给空/默认），不为 avatar 发明生成逻辑。
4. **I-037 只补 i18n key**（en/zh 两份），不改 `I18n.t` 的兜底行为——改兜底会影响所有缺失 key 的调试可见性。
5. **I-036 为 false positive**：对抗性审核发现 BrowserStatus 结构体已含 `chrome_version : String?` 字段且 derive(ToJson)，`BrowserManager::status()` 已从 `self.config.chrome_version` 填充该字段，`handle_browser_status` 返回 `status.to_json()` 包含此字段。orig Ruby `BrowserManager#status` 同样从配置读取，未配置时为 nil/null。字段存在，值为 null 与 orig 行为一致，无需修复。
6. **I-038/I-039 验收允许两种结局**：定位根因并修复，或定性为无害/外部因素并回写 `docs/web-ui-issues.md`（won't fix 或有意差异），不允许无结论关闭。
7. **MoonBit 约束检查**：全部为输出补丁与前端静态资产，无约束问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_mcp.mbt`、`lib/web/handlers_skills.mbt` | 修改 | I-032 两处 404 错误体补 ok:false |
| `lib/web/handlers_store.mbt` | 修改 | I-033 读端点补 ok |
| `lib/web/handlers_agents.mbt`（及 assets/agents/*.json 如需） | 修改 | I-034 avatar |
| `lib/web/handlers_backup.mbt` | 修改 | I-035 三字段 |
| ~~`lib/web/handlers_browser.mbt`~~ | ~~修改~~ | ~~I-036 chrome_version~~ -- **false positive，无需修改**（BrowserStatus 已含 chrome_version 且 derive(ToJson)） |
| `web/` i18n 文件（fix-06 后的 v1.5.0 资产） | 修改 | I-037 补 sessions.untitled |
| `docs/web-ui-issues.md` | 修改 | 八项状态回写（含 I-038/I-039 调查结论） |

### 不涉及文件

- 各 handler 的核心逻辑（只补输出字段）。
- I-039 若定位为后端长挂请求，修复方案另立 spec（本 spec 只到定位 + 小修）。

## 实施计划 [必填]

### 任务包 1：五个修复项（预估 1 天）
- 逐项实施 + 白盒断言；对照 api-diff.json 相应条目清零。
- I-036 已确认为 false positive，跳过。

### 任务包 2：两个调查项（预估 1 天）
- I-038：前端删除会话的调用栈走查（是否双发 DELETE）+ 复现尝试。
- I-039：首页加载抓网络瀑布，定位长挂请求；小修直接改，大修另立 spec。
- 结论回写 issues 文档。

## 验收标准 [必填]

- [ ] I-032/I-033/I-034/I-035 响应与 orig 契约一致（api-diff 相应条目清零）
- [x] I-036 确认为 false positive（BrowserStatus 已含 chrome_version 字段，值为 null 与 orig 一致）
- [ ] I-037 侧边栏不再显示原始 key（en/zh 均补）
- [ ] I-038/I-039 各有明确结论（修复或定性回写）
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| I-039 定位出需要重构的长挂请求 | 中 | 本 spec 只到定位；修复另立 spec |
| I-037 基于 v1.4.0 资产补 key 后被 fix-06 覆盖 | 低 | 明确要求 fix-06 先行 |
| 八项合并导致 review 粒度变粗 | 低 | 每项独立小节 + 独立断言，逐条验收 |

## 依赖关系 [必填]

- **前置依赖**：fix-06（前端基线，I-037 硬性依赖）。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-032~I-039 合并起草 |
| 2026-07-24 | 审核修正：对抗性审核发现 I-036 事实性错误。逐条验证：handle_store_list@handlers_store.mbt:89 确认返回 {extensions:[...]} 缺 ok（I-033 确认）；handle_store_installed 同样缺 ok 确认；handle_agents_list@handlers_agents.mbt:5-13 确认来自 load_agents_from_assets() 返回 {agents:[...]}（I-034 确认）；handle_backup_status_bridge@handlers_bridge.mbt:585-591 确认别名到 handle_backups_list@handlers_backup.mbt:469 返回 {backups,total} 缺 config/dest_dir/is_wsl（I-035 确认）。**I-036 事实性错误**：原 audit entry 声称"status 响应缺 chrome_version"不成立--BrowserStatus@browser_types.mbt:13-24 含 chrome_version:String?@:16 且 derive(ToJson)，BrowserManager::status()@browser_manager.mbt:131 设置 chrome_version:self.config.chrome_version，handle_browser_status@handlers_browser.mbt:9-15 返回 status.to_json() 包含此字段。chrome_version@:108 确实是 POST 请求体解析（非响应），但 status 响应**不缺**此字段。orig Ruby 对照：BrowserManager#status@browser_manager.rb:114-124 返回 {enabled,daemon_running,chrome_version:cfg["chrome_version"]}，同样从配置读取，未配置时为 nil/null。结论：I-036 为 false positive--字段已存在，值为 null 与 orig 行为一致（配置未设置时）。I-032/I-037/I-038/I-039 无代码验证问题。 | 对抗性审核 + 第一性原理校验 |
