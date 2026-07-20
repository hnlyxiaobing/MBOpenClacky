# Web UI 对比测试报告：MBOpenClacky vs OpenClacky

- 测试日期：2026-07-20
- 被测对象：MBOpenClacky（本项目，MoonBit 重写版），`http://localhost:7071`（`cmd.exe server` 启动）
- 参照基准：OpenClacky（原项目，Ruby 版 v1.4.0），`http://127.0.0.1:7070`
- 测试工具：Playwright + Chromium（视口 1440x900）、curl（API 抽样）
- 测试产物：`.test_web_compare/`（脚本 test1~3、report1~3.json、shots/ 截图）

## 总体结论

**当前项目的 Web UI 处于不可用状态**：首页因前端 JS 语法错误整页空白，任何用户打开 `http://localhost:7071` 看到的都是纯黑页面。即使通过技术手段绕过该错误让界面渲染出来，聊天的流式回显链路仍然断裂（SSE 数据格式错误），且 LLM 调用全链路失败。与原项目相比，UI 布局、主题、输入区能力、会话管理、设置体系均存在明显差距。

---

## 一、问题 / 缺陷（当前项目存在的 bug）

### 1. 【致命】首页整页空白，SPA 无法启动

- 现象：浏览器打开 `http://localhost:7071/` 只显示纯深色空白页，页面 body 文本长度为 0，无任何按钮/输入框。Console 报 `[pageerror] Invalid regular expression flags`。
- 根因：`web/mb/main/bridge.mbt:306` 的 `extern "js" fn js_render_markdown` 函数体中存在双重转义。MoonBit 字符串里的 `\\s`、`\\w`、`\\/` 被原样 emitted 进 JS 正则字面量，其中 `\\/` 被 JS 解析为「转义的反斜杠 + 正则结束符 `/`」，导致后面的 `code<...` 被当作正则 flags，整个 `mb/index.js` ES module 解析失败，应用根本不启动。
- 证据：`shots/current-home.png`（全黑页面）、`report1.json`、`report2.json`（current_raw 探针全为 false/空）。
- 验证方式：测试中通过 Playwright 路由拦截，注入仅修复该一处正则的 `patched_index.js` 后页面即可正常渲染（`shots/current-patched-home.png`），证明这是唯一的启动阻断点。**项目源码未被修改**。

### 2. 【高】SSE 流式数据不是合法 JSON，聊天回复无法渲染

- 现象：`POST /api/sessions/{id}/chat/stream` 返回的事件数据为 MoonBit 调试格式而非 JSON，例如：
  ```
  event: status
  data: Object({ "status": String("running") })
  ```
- 根因：`lib/web/sse/sse.mbt:22` 中 `format_sse_event` 使用 `@debug.to_string(data)` 序列化 Json，应使用 `Json::stringify`。
- 影响：前端 `js_connect_sse`（bridge.mbt:317）中 `JSON.parse(data)` 必然失败走入 catch 分支，消息内容永远无法上屏。实测打补丁后的 UI 发送消息 120 秒内页面无任何回复渲染，状态停留 `IDLE`（`report3.json`，body 字符数恒为 404）。
- 证据：curl 直连 SSE 端点输出、`report3.json`。

### 3. 【高】LLM 调用全链路失败（CLI 与 Web 均失败）

- 现象：通过 Web UI / SSE 发消息，`llm_start` 事件后直接返回 `error` 事件；CLI 非交互模式 `./cmd.exe --message "..."` 同样失败。
- 排除配置因素：同一 api_key + base_url（ark.cn-beijing.volces.com，kimi-k2.7-code）用 curl 直接调 `/chat/completions` 可正常返回，说明端点和密钥可用，问题出在本项目的 LLM client 实现（请求构造或响应解析与该端点不兼容）。
- 证据：`curl` 直连端点返回正常 completion；`cmd.exe --message` 输出 `✗ Error: ...AgentError.AgentError`。

### 4. 【中】错误信息只有内部类型名，无用户可读内容

- 现象：SSE error 事件内容为 `hnlyxiaobing/MBOpenClacky/lib/errors.RetryableError.RetryableError`，CLI 输出 `...AgentError.AgentError`——错误对象被 `to_string()` 后只剩包路径 + 类型名，message 字段丢失，用户和开发者都无法据此定位问题。

### 5. 【中】Windows 下服务器日志刷大量目录错误

- 现象：服务器 stdout 反复输出 `Failed to open directory: error code 267`（Windows「目录名无效」），启动前后出现 30+ 次，疑似会话/工作目录扫描路径在 Windows 下拼接错误。

### 6. 【低】打补丁后 UI 的其它异常

- 发送消息后未收到回复期间，界面自动弹出 `Cost Information` 模态框遮挡聊天区（`shots/current-chat-done.png`）。
- 会话列表条目时间字段显示异常（`2 msgs · $0 · \u2014`，日期为空时占位符渲染不正确）。
- 页面无 favicon，无加载态/错误提示——JS 崩溃时用户看不到任何说明。

---

## 二、功能差距（原项目有、当前项目没有或不完整）

> 说明：因缺陷 #1，当前项目 UI 只能通过注入打补丁 JS 的方式测试（`report2.json` 中 current_patched 探针 + `shots/current-patched-home.png`）。

### 布局与顶栏

- 原项目有完整顶部 header：侧边栏开关、品牌 logo（可点击回首页）、居中会话搜索栏（Ctrl+K 命令面板）、分享、任务完成提示音、亮/暗主题切换。
- 当前项目**没有 header**（`hasHeader: false`），所有功能入口（Settings/Stats/MCP/Channels/Schedules/Backups/Billing/Browser/Git/Trash/Brand/Profile/Share/Models/Workspace/Creator/Version/Onboard/Tasks/Media/Marketplace/Meeting 共 20+ 个）全部堆在左侧栏底部，无分组、无顶栏；无 logo，仅文字 "MBOpenClacky"。

### 主题与外观

- 原项目：亮/暗双主题 + 跟随系统，6 种主题色（Indigo/Aurora Blue/Forest Green/Sunrise Orange/Rose Violet/Coral Red），字号 Small/Medium/Large。
- 当前项目：仅深色一套配色；Profile 里有 Dark/Light/System 下拉但未见实际生效证据。

### 国际化

- 原项目：完整 data-i18n 体系，中/英文切换，界面已中文化。
- 当前项目：界面文案全英文硬编码；Profile 有 English/中文/日本語 下拉但未见生效证据。

### 新会话流程

- 原项目：新建会话时可选择 agent 类型（General / Coding / Extension Developer 卡片）、命名、选择工作目录（Browse folders）、选择模型、可选初始化项目。
- 当前项目：仅有「名称 + Create」对话框，无 agent 类型/目录/模型选择。

### 输入区能力

- 原项目：附件上传（image/pdf/docx/md/tar.gz，支持拖拽和 Ctrl+V）、斜杠技能命令插入、AI 运行中可继续追加消息、显式 Stop 按钮、底部状态栏（running 状态 / 会话 id / 工作目录 / 模型 / task 数）。
- 当前项目：仅纯文本输入框 + 发送按钮，无附件、无斜杠命令、无运行状态栏；停止按钮测试期间未出现。

### 会话管理

- 原项目：会话搜索支持类型过滤（Default/Scheduled/Channel/Setup/Coding）和日期过滤；每个会话有 Actions 菜单（重命名/删除等）；列表分页（Load more）；会话条目带类型徽标（CODING 等）和任务数。
- 当前项目：仅一个简单搜索框 + 列表 + 单条删除按钮。

### 设置体系

- 原项目：设置分 Models / UI / General / Data Management / About 五个分区，含模型增删（base_url/api_key/默认模型）、字号、语言、货币汇率、代理、许可证绑定/解绑、浏览器配置、备份自动开关、重跑 Onboard。
- 当前项目：设置入口存在但功能面明显更窄；另有 License/Brand 页面部分重复。

### 其它页面

- 原项目独有能力：Assistant Memory（Soul/User/Memories 三区，可让助手维护）、File Recall、Usage 用量页、Extension & Creation 工作区（OWNER 入口）、技能从 ZIP/GitHub URL 导入、完整 Onboard 引导（含模型测试向导）。
- 当前项目对应按钮（MCP/Marketplace/Creator/Media/Meeting/Tasks 等）在侧边栏可见，但受缺陷 #1/#2 影响未逐项深入验证，完成度待缺陷修复后回归。

### API 契约差异

- 抽样对比（current vs orig HTTP 状态）：`/api/profile`、`/api/skills`、`/api/channels` 两边均 200；`/api/models`、`/api/settings`、`/api/schedules` 当前项目 200 而原项目 404（原项目走 `/api/config/models` 等路径）。若目标是对齐原项目前端/第三方集成，API 路径不一致需要关注。
- 当前项目 SSE 事件格式与原项目不兼容（见缺陷 #2），且事件里出现尾随逗号的非法 JSON（`"total_cost_usd": Number(0),`）。

---

## 三、复现与测试方法

1. 构建并启动当前项目：`moon build --target native --release cmd`，`./_build/native/release/build/cmd/cmd.exe server`（端口 7071）。
2. Playwright 脚本（`.test_web_compare/`）：
   - `test1_load.js`：首屏加载、console 错误、DOM 结构探针 → `report1.json`
   - `test2_structure.js`：原始/打补丁两种模式下的 UI 结构探针（按钮/输入框/下拉/导航清单）→ `report2.json`
   - `test3_chat.js`：两边各发送 "Reply with just: OK"，采样流式渲染过程 → `report3.json`
   - `make_patched.js`：生成仅修复 bridge.mbt:306 正则的诊断用 patched_index.js（通过路由拦截注入，未改源码）
3. curl 抽样：`/api/sessions`、`/api/config/models`、SSE 端点直连、LLM 端点直连。
4. 截图：`shots/`（orig-home、current-home、current-patched-home、current-new-session、current-chat-done、orig-chat-done）。

### 测试限制

- 受缺陷 #1 影响，当前项目 UI 的交互测试均在「注入打补丁 JS」前提下进行，补丁未进入源码；缺陷 #1 修复后需完整回归。
- 受缺陷 #3 影响，无法验证当前项目的 markdown 渲染、代码高亮、工具调用展示等依赖真实 LLM 回复的功能。
- 设置/市场/会议等二级页面只做了存在性探针，未做逐项功能操作。

## 四、修复优先级建议

1. 修复 `web/mb/main/bridge.mbt:306` 双重转义（并全量排查其它 `extern "js"` 函数体的同类问题），重新构建 `web/mb/index.js` —— 恢复首页可用。
2. 修复 `lib/web/sse/sse.mbt:22` 的 `@debug.to_string` → `Json::stringify` —— 恢复流式聊天。
3. 修复 LLM client 与 ark/volces 端点的兼容性问题，并让错误类型透出可读 message。
4. 排查 Windows 下 `error code 267` 目录扫描路径问题。
5. 以上完成后，按本报告第二节逐项回归功能差距。
