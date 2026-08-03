# Web UI 修复对抗性审查报告

**日期**: 2026-08-03
**审查对象**: 前一 agent 对 7 个 Web UI bug 的修复（工作区未 commit 改动 + `specs/completed/2026-07-29_*.md`）
**审查方法**: 7 路并行对抗性代码审查（每个 issue 一路）+ 主线程关键路径复核 + 修复后 E2E 验证
**原始根因分析**: [2026-07-29-web-ui-bug-analysis.md](2026-07-29-web-ui-bug-analysis.md)

---

## 结论总览

| Issue | 审查结论 | 说明 |
|-------|---------|------|
| 1 切换 session 历史丢失/导航异常 | PARTIAL → 已补修 | 主根因已修；blocking 路径漏改 + 重启后历史被覆盖洞未堵 |
| 2 模型下拉列表不更新 | PARTIAL → 已补修 | 面板跨导航保持展开时不刷新；修复引入选择被重置的回归 |
| 3 工作目录斜杠混杂 | FIXED（+1 残留已补） | 主路径已修；config 默认目录分支未规范化（已补） |
| 4 Session 自动命名回归 | FIXED（+2 残留已补） | 主路径已修；startWith 入口漏改、REST 分页上限 20（已补） |
| 5 Agent 头像加载失败 | **原修复实际无效** → 已补修 | 路由虽注册但被静态中间件的 SPA fallback 短路，E2E 实测才暴露；已补中间件豁免 + 路径穿越白名单 |
| 6 选中模型未生效 | PARTIAL → 已补修 | 创建路径已修；重启恢复路径查找键不匹配（核心缺陷） |
| 7 历史消息重复展示 | **NOT FIXED** → 已补修 | created_at 生产路径恒为 None，修复是死代码；has_more 恒 true |

**重要结论（Issue 7）**：代码层面不存在"发一次消息实际多次调用模型"的路径——`start_ws_run → run_ws_agent → agent.run_async` 每消息只调一次，成功/错误路径的 `save_session` 互斥。用户看到的重复是**纯前端分页/渲染问题**：后端历史事件从不带 `created_at`，前端去重集合与分页游标全部失效，`has_more` 恒为 true，每次滚到顶部都把同一页消息再 prepend 一遍。

---

## 逐项详述

### Issue 1：切换 session 后历史丢失 / 导航异常

**原修复**（正确）：`lib/web/handlers_ws.mbt` `run_ws_agent` 错误路径补 `save_session`，使失败运行（如 API key 错误）也持久化用户消息，避免磁盘空快照遮蔽内存历史。

**审查发现的残留**：

1. `run_ws_agent_blocking` 的同类 catch 分支漏改 → 已补（与同函数 async 版一致的三行）。
2. `WebServer::get_or_create_agent` 重建 agent 时不恢复磁盘历史，运行结束后 `save_session` 会用仅含本轮消息的 history **覆盖**磁盘快照 → 重启后旧历史永久丢失。已补：cache miss 时调用 `agent.restore_from_session(sd)`。
3. 用户报告的字面症状（Settings → 点 session → 回到新建页 + 列表消失）在 diff 中无任何前端改动直接覆盖。静态分析结论：聊天区空态提示屏（bug 1 导致历史为空时显示）最可能被误述为"新建 session 界面"；后端修复后历史正常加载，该症状应消失。E2E 验证见下文。

### Issue 2：模型下拉列表不更新

**原修复**：`view.js` toggle 打开时重置 `_modelsLoaded = false`，每次展开都重新拉取。

**审查发现**：

1. 面板跨导航保持展开时不刷新（`onPanelShow` 不重置守卫）→ 已补：`onPanelShow` 检测面板展开状态，展开则重置并重新 populate。
2. **回归**：每次重开面板都无条件把用户选择重置回 default → 已修：populate 时记住先前选择，仍存在于新列表则保留；被删除则回退 default/第一项并同步 store（同时解决失效 modelId 残留提交问题）。
3. 格式损坏（两条语句挤一行）→ 已修。

### Issue 3：工作目录斜杠混杂

**原修复**（正确）：`handlers.mbt:226` home 分支经 `dirs_fwd_slashes` 规范化。

**说明**：修复选择全平台统一正斜杠（与既有 `/api/dirs` 行为一致，正斜杠在 Windows API 全有效），是"统一风格"而非字面的"Windows 反斜杠平台风格"——spec 明示决策，可接受。

**残留**：`config.default_working_dir` 分支（`handlers.mbt:223`）未规范化，与注释声称的镜像关系不符 → 已补 `dirs_fwd_slashes(d)`。用户手输路径（POST body、PATCH working_dir）未规范化，属既有低风险瑕疵，记录在案未改。

### Issue 4：Session 自动命名回归

**原修复**（正确）：`createSession` 在列表为空时 `await Sessions.fetchSessions()` REST 兜底。

**残留**：

1. `Sessions.startWith` 内联了同款命名逻辑但无 REST 兜底（skills 面板入口可达）→ 已补。
2. REST 默认 `limit=20`，>20 个 session 时编号最大的可能不可见 → 已补 `?limit=50`（服务端硬上限）。
3. 注释并行格式损坏 → 已修。

### Issue 5：Agent 头像加载失败

**原修复**：`server.mbt` 注册 `/agent_avatar/:id` 路由，`Content-Type: image/png`。静态审查（含本轮第一路审查）均判定 FIXED——但 **E2E 实测证明原修复实际无效**：`GET /agent_avatar/coding` 返回 200 `text/html`（`X-SPA-Fallback: index.html`）。

**根因（第一性原理）**：crescent 的管线是先路由匹配、再执行中间件洋葱链——头像路由确实匹配成功，但静态文件中间件在洋葱链外层先执行，`StaticServer::serve` 对无扩展名路径**内部直接做 SPA fallback 返回 200 HTML**（`static_server.mbt:169-190`），而不是返回 404，于是中间件的 `if resp.status == 404 return next()` 永不触发，头像处理器根本没有机会运行。带扩展名的路径（如 `coding.png`）反而能走到路由——正好与原 bug 现象相反。教训：**"路由已注册"不等于"路由可达"，中间件短路必须用真实 HTTP 请求验证。**

**补修**：

1. `server.mbt` 静态中间件豁免列表加入 `/agent_avatar/` 前缀（与 `/api/`、`/ws` 同级）。
2. id 白名单 `[a-zA-Z0-9_-]`，防字面 `..` 与 Windows 反斜杠路径穿越。
3. E2E 实测：`/agent_avatar/coding` → 200 `image/png`；`/agent_avatar/..x`、`/agent_avatar/..%5C..%5Csecret` → 404。

### Issue 6：选中模型未生效

**原修复**：`handle_create_session` 解析 `model_id` 并经 `session_model_overlay` 查找——同次服务器运行内有效。

**审查发现的核心缺陷**：持久化存的是 `client.model`（API 模型字符串），恢复路径（`server.mbt`）却拿它按 `m.id`/`m.runtime_id` 查找；id ≠ model 时恢复静默回退全局默认，且下一条消息跑完会把错误模型**写回磁盘**，永久覆盖用户选择。
→ 已修：`session_model_overlay` 增加 `m.model` 匹配，`current_model_id` 规范化为 `Some(m.id)`（顺带排除 `runtime_id != id` 时 `current_model()` 返回 None 导致 panic 的地雷）。

### Issue 7：历史消息重复展示（NOT FIXED → 已修）

**原修复无效的证据链**：

- `Message::user/assistant/system` 构造器全部 `created_at: None`（字段不可变），`to_json` 不序列化该字段 → `message_timestamp` 恒返回 `""`，events.mbt 的"修复"在生产路径是死代码。
- `has_more = messages.length() > events.length()`：被过滤的 system/tool 消息计入分子 → 恒 true → 无限重复拉取同一页。
- `oldestCreatedAt` 恒 null → `loadMoreHistory` 用 null 游标拉到同样的最新一页 → 整页 prepend 重复。

**补修内容**：

1. 后端：消息进入 agent history 时打 `created_at`（epoch-ms 字符串，与 WS 实时回显同格式）；持久化序列化补上 `created_at`；`has_more` 改为基于遍历游标；`before` 过滤 `>=` 改 `>`（同毫秒边界重叠一条由前端去重吸收，避免丢消息）。
2. 前端：`loadMoreHistory` 无游标时停止分页（置 `hasMore=false`），防止 legacy session 无限重复。

---

## E2E 验证结果

**静态验证**：`moon check` 0 error（167 均为既有警告）；`moon test lib/web lib/agent lib/config lib/message lib/client` 1044/1044 通过（含本轮新增的 created_at 往返、has_more 边界、overlay 按模型字符串匹配等白盒测试）。

**运行验证**（WSL release 构建，端口 7076，脚本 `.test_web_compare/fix_2026-08-03_e2e.mjs`，结果 JSON 在 `.test_web_compare/fix_2026-08-03_{phase1,phase2,cleanup}.json`）：

Phase 1（新服务器）——全部 PASS：

- `GET /agent_avatar/coding` → 200 `image/png`；`..x` / 编码穿越 → 404（Issue 5）
- 3 个模型 id ≠ model 字符串；以非默认模型 `model_id` 创建 session → 响应 `session.model` 即为所选模型（Issue 6 创建路径）
- 默认 `working_dir=/root/clacky_workspace` 无混合分隔符（Issue 3；Windows 原生混杂场景由 `dirs_fwd_slashes` 单测逻辑覆盖，WSL 下本为纯正斜杠）
- `GET /api/sessions?limit=50` 正常（Issue 4 配套）
- WS 发送消息跑通一轮真实对话；历史事件 3/3 带 `created_at`，`has_more=false` 正确（Issue 7）

Phase 2（**重启服务器后**，验证恢复路径）——全部 PASS：

- session 模型仍为所选模型（未回退全局默认）（Issue 6 恢复路径——原修复的断环）
- 重启后发新消息，历史从 3 条增长到 6 条而非被覆盖（Issue 1 的 `get_or_create_agent` 恢复修复）
- 运行后模型未被写回翻转为默认模型（Issue 6 自我强化覆盖已根除）
- 页内事件零重复（Issue 7）

测试 session 已通过 `DELETE /api/sessions/:id` 清理。

**未覆盖项（需人工浏览器复测）**：Issue 2 下拉刷新/选择保留、Issue 4 命名兜底为纯前端改动（已过 `node --check` 与静态核对）；Issue 1 的字面导航症状（回到新建页+列表消失）未能在 API 层复现，静态分析判断其为历史空态屏的误述，建议按原操作序列人工确认一次。

## 遗留问题（记录在案）

> **2026-08-03 更新（两轮）**：以下问题除换行符 churn（仓库卫生项）外已全部闭环。
> 第一轮按 Harness v2 立项归档：`specs/completed/2026-08-03_windows-native-build-cli-args.md`、`2026-08-03_model-identity-unification.md`（含 model_fallback 警告）、`2026-08-03_working-dir-input-normalization.md`、`2026-08-03_history-index-pagination.md`。
> 第二轮（同日晚间手工复测发现）直接修复，见下节。

## 第二轮修复（2026-08-03 晚间手工复测）

复测发现 4 个新问题，全部定位根因并修复（`moon test` 3256/3256，E2E 8/8 + 回归 11/11）：

1. **斜杠混用复发**：真正根因是 MoonBit `String::replace` **只替换首个匹配**——`dirs_fwd_slashes` 对多反斜杠路径只规范了第一个。修为 `replace_all`（另含 `file_reader.mbt`、`pty.mbt` 两处同类），补多反斜杠回归测试。
2. **快速新建用错模型**：Settings `[default]` 徽标（`type_`）与 `current_model_id` 两套"默认"概念漂移（Settings 打徽标从不同步 id）。已统一为单一概念：**徽标权威**——`current_model()` 徽标优先；Settings POST/PATCH 打徽标同步 id；`switch_model_by_id/name` 同步移徽标；`session/virtual_model_overlay` 深拷贝+移徽标（session 级选模型不被全局徽标劫持）。
3. **目录切换弹窗/校验**：PATCH 在未配置 `default_working_dir` 时一刀切拒绝全部绝对路径（与 POST 不对称），已放宽为沙盒 opt-in；输入统一规范化+去尾斜杠；目录选择器在会话目录不存在时回退真实文件系统浏览（祖先目录兜底），不再卡死"空目录"。
4. **会话名语义化生成**：占位名（`Session N`）在首条真实用户消息后按内容自动重命名（折叠空白、≤30 字+…），持久化 + WS 广播 `session_renamed`；用户命名过的会话不受影响。

历史遗留（原记录，均已闭环）：

- ~~Windows 原生构建 LNK2019~~ → 已由 `2026-08-03_windows-native-build-cli-args.md` 修复（`@sys.get_cli_args()` → core `@env.args()`），双端构建验证通过。
- ~~`SessionSummary.model_id` 填模型字符串~~ → 已由 `2026-08-03_model-identity-unification.md` 修复（改填 `model_config_id`）。
- ~~model_id 查找失败静默回退~~ → 同 spec 修复（响应顶层 `model_fallback: true` + 前端 toast）。
- ~~POST/PATCH working_dir 用户输入未规范化~~ → 第一轮已修，第二轮补齐 `replace_all` 后真正生效，并放宽绝对路径误拒。
- `git diff` 中 `lib/tui/`、`lib/agent/compressor*`、`lib/client/format_openai.mbt` 等大量改动为换行符 churn，与本次 7 个 issue 无关，建议单独处理，不要混入功能 commit。
