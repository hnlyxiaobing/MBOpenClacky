# Web UI 对比测试方案（MBOpenClacky vs openclacky）

> 创建日期：2026-07-24
> 目的：以原 Ruby 项目 openclacky 的 Web UI 为参考实现，跑同样的操作流，全面对比当前 MoonBit 复刻版的行为差异，产出「问题」（bug）与「差距」（缺失功能）两份记录。

## 1. 对照基线

| 项 | 原项目（参考实现） | 当前项目 |
|---|---|---|
| 路径 | `D:/MoonBit/openclacky/` | `D:/MoonBit/MBOpenClacky/` |
| 版本 | v1.5.0（`lib/clacky/version.rb:4`） | 复刻中 |
| 访问地址 | http://127.0.0.1:7070/ | http://127.0.0.1:7071/ |
| 服务端 | WEBrick 单体 `http_server.rb`（7072 行） | crescent，`lib/web/server.mbt` 内联路由（~160 端点） |
| 前端 | `lib/clacky/web/`（v1.5.0） | `web/`（上游 **v1.5.0** 托管 fork，见 `web/UPSTREAM_SYNC.md`） |
| 实时通道 | 仅 WebSocket `/ws` | 仅 WebSocket `/ws`（SSE 已删除） |
| 认证 | `CLACKY_ACCESS_KEY`，回环免认证 | `MBOPENCLACKY_WEB_API_KEY`，回环默认免认证 |

**已知有意差异（不计入问题/差距）**：web-parity-05 删除的 legacy 端点（meetings、全局 `/api/git`、`/api/backups`、`/api/settings`、`/api/models` 别名、`POST /:id/chat` SSE）；端口刻意错开；认证环境变量命名不同。当前项目独有的 `web/ext_ui/`（git、time-machine 面板）属于新增能力，不算差距。

## 2. 测试手段总览

| 手段 | 覆盖层 | 工具 | 产出 |
|---|---|---|---|
| 一、静态契约对比 | 端点/前端文件 | grep + diff（已完成） | 差距候选清单 → `web-ui-parity.md` |
| 二、API 对比测试 | HTTP 契约 | curl / Node 脚本，双 server 同请求 diff | 问题 + 差距 |
| 三、UI 流程对比 | 真实用户行为 | Playwright 1.61.1（本机已装）双开浏览器 | 问题为主 |
| 四、WS 协议对比 | 实时事件流 | Node `ws` 脚本 | 问题 + 差距 |
| 五、非功能测试 | 性能/资源/稳定/安全 | Lighthouse、autocannon、axe-core 等 | 差距为主 |

### 手段一：静态契约对比（已完成）

通过阅读两端路由注册代码与 `diff -rq web/ lib/clacky/web/` 完成端点矩阵与前端文件级对比。结论已沉淀为 `web-ui-parity.md` 的 G-001~G-003 及本文档 §6 的端点核对清单。前端 87 个上游文件全部在位，无缺文件。

### 手段二：API 对比测试

对同一组请求分别打到 7070/7071，对比状态码与响应 JSON 结构（字段存在性，不比对动态值）：

```bash
# 示例：单端点对比
for port in 7070 7071; do
  echo "== $port =="; curl -s -w "\n%{http_code}\n" http://127.0.0.1:$port/api/sessions
done
```

建议写一个 Node 脚本（`scripts/compare_api.mjs`）：内置端点清单（§6），对每个端点请求两端，归一化后（剔除 timestamp/id 等动态字段）做结构 diff，批量输出不一致项。写操作类端点（POST/PATCH/DELETE）需在两边分别构造等价前置状态后执行。

当前项目已有的进程内契约测试（`test/scenarios/web/`，`moon run cmd -- --web-eval`）可继续用于回归，但它不覆盖"与原项目是否一致"，两者互补。

### 手段三：UI 流程对比（核心手段）

用 Playwright 脚本驱动两个浏览器上下文，对两边执行**完全相同的操作流**，逐步对比：页面是否可达、操作是否成功、DOM 关键内容、console 错误、失败请求（`page.on('console')` / `page.on('requestfailed')` / `page.on('response')` 状态码 ≥400）。每步截图存档到 `logs/web-compare/`。

操作流清单（按面板分组，逐条执行并记录结果）：

**引导与新会话**
- [ ] 未配置模型时首次打开 → onboard/setup 面板出现
- [ ] 手动填 API Key/Base URL/Model → 测试连接 → 保存 → 进入主界面
- [ ] 新建会话：选 agent → 输入首条消息 → 高级区（名称/模型/工作目录）→ 创建

**会话与聊天（依赖真实 LLM，可用廉价模型或 mock key 走错误路径）**
- [ ] 发送消息 → WS 事件流渲染（assistant_message/tool_call/complete）
- [ ] 中断按钮 → agent 停止
- [ ] 编辑已发消息重发
- [ ] 切换模型 / 子模型 / reasoning effort / 工作目录
- [ ] 导出会话（JSON/zip）、fork、重命名、删除（进回收站）
- [ ] 会话列表：搜索、加载更多、置顶
- [ ] Workspace 文件树：浏览、预览、下载
- [ ] Time Machine：快照列表、diff、切换

**配置区面板**
- [ ] Tasks：创建 cron 任务 → 启停 → 手动触发 → 查看历史
- [ ] Skills：列表、启停、查看/编辑内容、删除；Brand Skills tab
- [ ] Channels：平台配置保存/测试/启停/删除
- [ ] MCP：新增 server → probe → 查看工具 → 启停 → 删除
- [ ] Extensions：市场浏览、详情、安装/启停/卸载（当前项目前端为只读展示，预期差异）

**My Data 面板**
- [ ] Profile & Soul：三个 tab 读写、Memories CRUD
- [ ] Trash：文件/会话两 tab，还原、彻底删除
- [ ] Billing：汇总/按日/按会话/明细切换、清空

**Settings（5 个 tab）**
- [ ] Models：增删改模型、设默认、测试连接；Secondary Models + OCR 配置
- [ ] UI：语言切换、字号、背景主题、强调色
- [ ] General：币种切换、Browser MCP 配置、Brand & License 状态
- [ ] Data：自动备份开关、手动备份下载/恢复
- [ ] About：版本检查、升级流程

**全局**
- [ ] Cmd-K 命令面板搜索会话
- [ ] 主题切换、分享成绩卡
- [ ] 认证流程：设 key 后 401 → 弹窗输入 → 通过（两端分别设 `CLACKY_ACCESS_KEY` / `MBOPENCLACKY_WEB_API_KEY`）

### 手段四：WebSocket 协议对比

Node 脚本用 `ws` 库分别连两端 `/ws`，发送相同帧序列（`subscribe` → `message` → `interrupt` → `ping`），记录两端事件流的类型序列与关键字段，对比：事件类型是否齐全（参考原项目 ws-dispatcher.js 的 ~25 种事件）、字段命名、错误路径行为（订阅不存在 session、非法 JSON 帧）。

### 手段五：非功能性测试（推荐方法）

| 维度 | 方法 | 工具与命令 |
|---|---|---|
| 首屏性能 | Lighthouse（性能/FCP/LCP/TBT）+ Network waterfall 对比资源体积与请求数 | `npx lighthouse http://127.0.0.1:7071 --output=json`（两端各跑一次） |
| API 时延 | 同端点各请求 50 次取 p50/p95 对比 | `curl -w "%{time_total}"` 循环，或 `npx autocannon -c 10 -d 10 http://127.0.0.1:707x/api/sessions` |
| 吞吐量 | 静态资源 + JSON 端点压测（WS 服务慎用高压） | autocannon / `hey` |
| 内存占用 | 空闲与负载下进程 RSS 对比（Ruby 是 master+worker，MoonBit 单进程，口径注明） | `tasklist` / PowerShell `Get-Process` 定时采样 |
| 稳定性 | 长跑 1h+，期间 WS 客户端反复断线重连，观察内存增长与事件丢失 | Playwright 脚本 + 采样 |
| 并发 | 多浏览器上下文同时操作不同会话 | Playwright `browser.newContext()` × N |
| 可访问性 | 自动化 a11y 扫描（两端前端同源，主要验证 fork 改动未破坏） | `axe-core` 注入或 Lighthouse a11y 项 |
| 浏览器兼容 | 同一 Playwright 脚本跑 chromium/firefox/webkit | `playwright` 三内核 |
| 安全 | 认证绕过（伪造 `X-Forwarded-For` 试 loopback 绕过——当前项目已知弱点，见 G-003）、路径遍历（`/api/files/read`、`/api/local-image`、`/api/backup/download`）、模板注入（`{{BRAND_NAME}}` XSS） | curl + 手工用例 |

## 3. 问题 vs 差距判定规则

- **问题（bug）** → `docs/web-ui-parity.md`：当前项目**已有该功能**，但流程跑不通或行为错误（报错、无响应、渲染错误、与原项目行为矛盾）。
- **差距（gap）** → `docs/web-ui-parity.md`：当前项目**尚未实现**原项目已有的功能/端点/事件/非功能能力。
- 同一事项优先记为问题，不重复记入差距。有意差异（§1）两者都不记。

## 4. 记录字段模板

每条记录包含：ID、标题、严重度（P0 阻断核心流程 / P1 功能受损有绕行 / P2 体验问题 / P3 轻微）、所在面板或端点、复现步骤（UI 流程或 curl/脚本）、**期望行为（原项目实际表现）**、**实际行为（当前项目表现）**、证据（截图/响应体/日志路径）、状态（Open / Fixed / Won't fix）。

## 5. 执行约定

- 两端对比时保持等价初始状态（空会话列表、默认配置），必要时先清空两端数据目录。
- 截图与原始响应存 `logs/web-compare/<日期>/`，文档中只引用路径。
- 每修复一条记录，回归对应操作流，并将状态改为 Fixed（注明修复 commit）。
