# MBOpenClacky Web UI 专项开发计划

> **文档版本**: 1.0
> **创建日期**: 2026-06-25
> **上游参考**: OpenClacky (Ruby) v1.3.2
> **目标**: 修复 Web UI 阻塞缺陷，补齐前端管理面板，实现功能完整、可直接使用的 Web 界面

---

## 目录

1. [评审结论：当前 Web UI 状态](#1-评审结论当前-web-ui-状态)
2. [差距分析](#2-差距分析)
3. [开发任务清单](#3-开发任务清单)
4. [依赖拓扑](#4-依赖拓扑)
5. [里程碑计划](#5-里程碑计划)
6. [技术方案详解](#6-技术方案详解)
7. [验证标准](#7-验证标准)
8. [风险评估](#8-风险评估)

---

## 1. 评审结论：当前 Web UI 状态

### 1.1 总体评估：**代码就绪但不可运行**

MBOpenClacky 的 Web 界面在代码层面已有大量投入（后端 68+ REST API 端点、前端 ~2,900 行 HTML/CSS/JS），但由于两个关键缺陷，**Web UI 实际无法在浏览器中使用**。

### 1.2 已完成部分（坚实基础）

| 模块 | 文件数 | 代码行数 | 实际状态 |
|------|--------|---------|---------|
| **后端 REST API** | 14 个 `.mbt` | ~1,800 行 | ✅ **完整可用**（68+ 端点全部实现） |
| **WebSocket 端点** | `handlers.mbt` 内 | ~70 行 | ✅ **完整可用** |
| **SSE 流式端点** | `sse/sse.mbt` | 91 行 | ✅ **完整可用** |
| **中间件系统** | 2 个 `.mbt` | 42 行 | ✅ **完整可用**（认证/日志/CORS） |
| **DTO 类型定义** | `types.mbt` | 257 行 | ✅ **完整可用**（15 个类型 + JSON 序列化） |
| **前端 HTML** | `index.html` | 128 行 | ✅ 代码完成（6 个视图容器） |
| **前端 CSS** | `style.css` | 1,066 行 | ✅ 代码完成（暗色主题 + 响应式） |
| **前端 JS** | 6 个 `.js` | ~1,660 行 | ✅ 代码完成（Chat/Sessions/Settings/Skills/WebSocket/App） |
| **后端测试** | `web_handlers_wbtest.mbt` | 350 行 | ✅ 78 个测试全部通过 |

### 1.3 阻塞缺陷（P0 — 必须立即修复）

| # | 缺陷 | 位置 | 影响 |
|---|------|------|------|
| **D-1** | `static_server.mbt` 是空壳实现 — 不读取真实文件，返回占位符字符串 | `lib/web/static_server.mbt` 第 63-65 行 | 🔴 **前端 HTML/CSS/JS 完全无法送达浏览器** |
| **D-2** | `server.mbt` 未注册静态文件 catch-all 路由 — crescent 框架只响应 API 路径 | `lib/web/server.mbt` `start()` 方法 | 🔴 **浏览器访问任何非 API 路径均返回 404** |

**证据**：

```moonbit
// static_server.mbt L63-65 — TODO 注释确认占位符实现
// TODO: Actually read file from filesystem
// In MoonBit/WASM environment, file I/O would use platform-specific FFI
// For now, return placeholder responses based on path
```

```moonbit
// static_server.mbt L73-76 — 返回占位符而非实际文件内容
HttpResponse::{
  status: 200,
  body: "/* static content for: \{clean_path} */",  // ← 占位符
  content_type: mime,
  ...
}
```

```moonbit
// static_server.mbt L100-102 — SPA fallback 使用硬编码 HTML，非 assets/web/index.html
fn spa_fallback(server : StaticServer) -> HttpResponse {
  // TODO: Read actual index.html from root_dir
  let fallback_body = "<!DOCTYPE html><html><body>..." // ← 硬编码
```

**`server.mbt` 中无静态文件路由**：`start()` 方法注册了所有 API 路由和 WebSocket 路由，但**没有注册任何静态文件 catch-all 路由**。

### 1.4 已实现但因缺陷无法使用的功能

由于 D-1 和 D-2，以下前端功能虽然在 JS 代码中完整实现，但浏览器无法加载：

- ❌ 会话列表浏览与搜索（[sessions.js](file:///d:/MoonBit/MBOpenClacky/assets/web/js/sessions.js)）
- ❌ AI 对话界面（[chat.js](file:///d:/MoonBit/MBOpenClacky/assets/web/js/chat.js)，554 行）
- ❌ SSE 流式实时响应（[websocket.js](file:///d:/MoonBit/MBOpenClacky/assets/web/js/websocket.js)）
- ❌ 设置面板 — 模型切换/权限模式/Token 限制（[settings.js](file:///d:/MoonBit/MBOpenClacky/assets/web/js/settings.js)）
- ❌ 技能/工具网格展示（[skills.js](file:///d:/MoonBit/MBOpenClacky/assets/web/js/skills.js)）
- ❌ 统计仪表盘、通知系统、键盘快捷键、移动端响应式

---

## 2. 差距分析

### 2.1 对比 Ruby 源项目：前端功能覆盖

| 功能 | Ruby openclacky | MBOpenClacky 当前 | 差距 |
|------|-----------------|-------------------|------|
| **静态文件服务** | WEBrick 直接服务文件系统 | 空壳占位符 | 🔴 **阻塞** |
| **Chat 对话界面** | 完整 SSE 流式 | JS 已实现，无法送达 | 🔴 **阻塞** |
| **Session 管理** | 侧边栏列表 + 搜索 | JS 已实现，无法送达 | 🔴 **阻塞** |
| **Settings 面板** | 模型/权限/Token 配置 | JS 已实现，无法送达 | 🔴 **阻塞** |
| **Skills 面板** | 技能列表/调用 | JS 已实现，无法送达 | 🔴 **阻塞** |
| **Stats 仪表盘** | 统计卡片 | JS 已实现，无法送达 | 🔴 **阻塞** |
| **MCP 管理面板** | ❌ 源项目无此功能 | 后端 API 有，前端缺失 | 🟡 MBOpenClacky 增强功能 |
| **Channels 管理面板** | Channel UI 配置面板 | 后端 API 有，前端缺失 | 🟡 |
| **Schedules 管理面板** | Cron 管理前端 | 后端 API 有，前端缺失 | 🟡 |
| **Backups 管理面板** | 备份管理前端 | 后端 API 有，前端缺失 | 🟡 |
| **Billing 面板** | 计费信息 UI | 后端 API 有，前端缺失 | 🟡 |
| **Browser 控制面板** | 浏览器启停/截图 | 后端 API 有，前端缺失 | 🟡 |
| **Git Panel** | Git 状态/差异查看 | 后端 API 有，前端缺失 | 🟡 |
| **Trash 回收站** | 回收站 UI | 后端 API 有，前端缺失 | 🟡 |
| **多主题支持** | UI2 3 个主题 | 仅 1 个暗色主题 | 🟢 可选 |
| **文件上传/附件** | 拖拽上传 | 无此功能 | 🟢 可选 |

### 2.2 当前前端视图 vs 后端 API 模块覆盖率

**5 个已有的前端视图**（Chat / Settings / Skills / Stats / Modal）覆盖了 4 个后端 API 模块组（共 12 个），覆盖率 **33%**。

| 后端 API 模块组 | 端点数 | 前端视图 | 状态 |
|---------------|--------|---------|------|
| Sessions 会话管理 | 11 | ✅ Chat View | JS 已实现 |
| Chat 对话 | 2 | ✅ Chat View | JS 已实现 |
| Config 配置 | 4 | ✅ Settings View | JS 已实现 |
| Stats 统计 | 2 | ✅ Stats View | JS 已实现 |
| Skills 技能 | 6 | ✅ Skills View | JS 已实现 |
| MCP 协议 | 5 | ❌ | **需新建** |
| Channels 渠道 | 6 | ❌ | **需新建** |
| Schedules 调度 | 6 | ❌ | **需新建** |
| Backups 备份 | 4 | ❌ | **需新建** |
| Billing 计费 | 3 | ❌ | **需新建** |
| Browser 浏览器 | 5 | ❌ | **需新建** |
| Trash 回收站 | 4 | ❌ | **需新建** |
| Webhooks | 1 | ❌ | **需新建**（含在 Channels 面板中） |

### 2.3 项目文档中的误导信息

开发计划文档 `development-plan-0623.md` 第 88 行标记 **Phase 14（Web 前端 SPA）为 ✅ 已完成**，第 125 行评估 **"Web 服务器：基本对齐"（P3 优先级）**。

**实际情况**：Phase 14 的后端 API 部分确实已完成，但前端 SPA 因静态文件服务缺陷而"不可用"。文档未反映这一关键问题，造成项目完成度的高估。本次计划旨在纠正这一偏差。

---

## 3. 开发任务清单

### 优先级说明
- **P0（阻塞）**: 不修复则 Web UI 完全不可用，必须最先完成
- **P1（重要）**: 修复后 Web UI 基本可用，用户体验完整
- **P2（增强）**: 补齐缺失的前端管理面板，覆盖全部后端 API
- **P3（优化）**: 可选增强，提升用户体验

---

### 🔴 P0 — 阻塞缺陷修复（预估 1-1.5 天）

| # | 任务 | 文件 | 预估工时 | 前置依赖 |
|---|------|------|---------|---------|
| **P0-1** | **修复 static_server.mbt 实现真实文件读取** | `lib/web/static_server.mbt` | 4-6h | 无 |
| **P0-2** | **在 server.mbt 中注册静态文件 catch-all 路由** | `lib/web/server.mbt` | 1-2h | P0-1 |
| **P0-3** | **端到端验证：浏览器访问 Web UI** | — | 1h | P0-2 |
| **P0-4** | **更新 static_server_wbtest 测试** | `lib/web/` (新建测试) | 2h | P0-1 |

#### 技术细节

**P0-1 详细任务**：重写 `StaticServer::serve()` 方法，实现以下逻辑：

1. **路径规范化**（已有）：去除前导 `/`，防止 `..` 目录遍历
2. **文件读取**（需新增）：使用 MoonBit native FFI 或 `@fs` 包读取 `assets/web/` 下的真实文件
3. **MIME 类型映射**（已有）：根据文件扩展名设置 `Content-Type`
4. **SPA fallback**（需修复）：非静态资源路径（无文件扩展名）返回真实的 `index.html`
5. **缓存头**：静态资源设置 `Cache-Control: public, max-age=3600`；SPA fallback 设置 `no-cache`

```moonbit
// 核心实现伪代码
pub fn StaticServer::serve(self : StaticServer, path : String) -> HttpResponse {
  let clean_path = normalize_path(path, self.index_file)
  if clean_path.contains("..") {
    return HttpResponse::bad_request("Invalid path")
  }
  let full_path = self.root_dir + "/" + clean_path
  let mime = get_mime_type(full_path)
  
  // 尝试读取真实文件（使用 native FFI）
  let content = @fs.read_file(full_path)  // ← 关键修改
  match content {
    Ok(data) => HttpResponse::ok(data)
      .header("Content-Type", mime)
      .header("Cache-Control", "public, max-age=3600")
    Err(_) => {
      if is_static_asset(clean_path) {
        HttpResponse::not_found("File not found")
      } else {
        spa_fallback(self)  // ← 读取真实 index.html
      }
    }
  }
}
```

**P0-2 详细任务**：在 `server.mbt` 的 `start()` 方法中，WebSocket 路由之后添加：

```moonbit
// ── Static Files (SPA) ──────────────────────────────────────
let static_server = @static.StaticServer::new("assets/web")
app.get_raw("/*path", (event : @crescent.Event) => {
  let path = event.req.path()
  if path.starts_with("/api/") || path.starts_with("/ws/") || path == "/health" {
    // API/WS 路径不应走到这里，返回 404
    "{\"error\":\"Not found\"}"
  } else {
    let response = static_server.serve(path)
    response.body
  }
})
```

> **重要**：crescent 框架的 catch-all 路由语法和静态文件服务方式需要在实际编码时通过 `moon ide doc` 或 `moonbit-orientation` skill 确认准确 API。crescent 可能使用 `app.get("/*", ...)` 而非 `app.get_raw`，也可能需要在 group 中配置。

**P0-3 验证清单**：
1. `moon run cmd -- --server` 启动后，浏览器访问 `http://localhost:4000`
2. 确认加载完整 `index.html`（非占位符）
3. 确认 CSS 样式正常渲染（暗色主题）
4. 确认 JS 脚本正常加载（F12 无 404/脚本错误）
5. 确认侧边栏会话列表正常显示
6. 确认 API 调用正常（创建会话/发送消息）

**P0-4 测试任务**：为 `StaticServer::serve()` 方法编写白盒测试，至少覆盖：
- 根路径返回 `index.html`
- CSS 文件返回正确 MIME 类型 `text/css`
- JS 文件返回正确 MIME 类型 `application/javascript`
- SPA fallback 对非静态资源路径返回 `index.html`
- 目录遍历攻击防护（`../` 路径返回 400）
- 不存在的静态资源返回 404

---

### 🟡 P1 — 前端基础功能补齐（预估 2-3 天）

| # | 任务 | 文件 | 预估工时 | 前置依赖 |
|---|------|------|---------|---------|
| **P1-1** | **侧边栏导航重构 — 添加管理面板入口** | `index.html` + `app.js` | 2-3h | P0-3 |
| **P1-2** | **完善错误处理与加载状态** | `chat.js` + `sessions.js` | 2h | P0-3 |
| **P1-3** | **前端 API 适配层重构** | `websocket.js` | 2h | P0-3 |
| **P1-4** | **Web UI 冒烟测试脚本** | `assets/web/` (新建测试) | 2h | P0-3 |

#### 技术细节

**P1-1 侧边栏导航重构**：

当前侧边栏只有 Settings 和 Stats 两个入口，需扩展为：

```
侧边栏 Footer:
├── [⚙ Settings]  [📊 Stats]
├── [🔧 MCP]      [📡 Channels]
├── [⏰ Schedules] [💾 Backups]
└── [💰 Billing]   [🗑 Trash]
```

实现方式：
- 在 `index.html` 的 `sidebar-footer` 中添加导航按钮组
- 在 `app.js` 中添加对应的视图切换逻辑
- 新增 `view-mcp`, `view-channels`, `view-schedules`, `view-backups`, `view-billing`, `view-browser`, `view-git`, `view-trash` 视图容器

**P1-2 错误处理增强**：
- 网络错误时显示重试按钮（而非仅 toast 通知）
- API 返回 401/403 时引导配置 API Key
- 长时间无响应时显示超时提示
- SSE 断连时自动重连（已有基础，需增强）

**P1-3 前端 API 适配层**：
- 抽取通用 fetch 封装（统一错误处理、超时、重试）
- 类型安全的 API 响应解析

**P1-4 冒烟测试**：
- 页面加载测试（HTML/CSS/JS 正常加载）
- 会话 CRUD 流程测试
- SSE 流式聊天端到端测试
- 设置保存/读取测试

---

### 🟠 P2 — 补齐管理面板前端（预估 4-6 天）

每个管理面板遵循统一的设计模式：
1. 在 `index.html` 中添加 `view-{name}` 视图容器
2. 创建 `assets/web/js/{name}.js` 模块文件
3. 在 `app.js` 中注册路由和初始化
4. 在 `index.html` 中引入脚本

| # | 任务 | 文件 | REST API 端点 | 预估工时 |
|---|------|------|--------------|---------|
| **P2-1** | **MCP 服务器管理面板** | `js/mcp.js` (~200行) | GET/POST/DELETE `/api/mcp/servers`, GET `/api/mcp/tools`, POST `/api/mcp/tools/:name/execute` | 4-5h |
| **P2-2** | **IM 渠道配置面板** | `js/channels.js` (~250行) | GET/POST/PUT/DELETE `/api/channels`, POST `/api/channels/:id/test`, GET `/api/channels/:id/status` | 5-6h |
| **P2-3** | **Cron 调度管理面板** | `js/schedules.js` (~220行) | GET/POST/PUT/DELETE `/api/schedules`, POST `/api/schedules/:id/trigger`, GET `/api/schedules/:id/history` | 4-5h |
| **P2-4** | **备份管理面板** | `js/backups.js` (~150行) | GET/POST/DELETE `/api/backups`, POST `/api/backups/:id/restore` | 3-4h |
| **P2-5** | **计费面板** | `js/billing.js` (~180行) | GET `/api/billing/status`, POST `/api/billing/activate`, GET `/api/billing/usage` | 3-4h |
| **P2-6** | **Browser 控制面板** | `js/browser.js` (~180行) | GET `/api/browser/status`, POST `/api/browser/start|stop|navigate`, GET `/api/browser/screenshot` | 3-4h |
| **P2-7** | **回收站面板** | `js/trash.js` (~120行) | GET/DELETE `/api/trash`, POST `/api/trash/:id/restore` | 2-3h |
| **P2-8** | **Git 面板** | `js/git_panel.js` (~250行) | 需后端新增 REST API | 5-6h |

#### 面板功能规格

**P2-1 MCP 管理面板**：
- 服务器列表（名称/传输类型/状态指示）
- 添加服务器表单（Stdio 命令 + 参数 / HTTP URL）
- 删除服务器（确认对话框）
- 工具浏览器（从选中服务器加载工具列表）
- 工具手动执行（输入参数 JSON → 查看结果）

**P2-2 Channels 管理面板**：
- 渠道列表（平台图标/名称/状态开关）
- 渠道配置表单（平台选择 / Webhook URL / API Key / Secret）
- 测试按钮（发送测试消息）
- 状态监控（连接状态 / 最后活动时间）

**P2-3 Schedules 管理面板**：
- 定时任务列表（名称/Cron 表达式/下次执行时间/状态）
- 创建/编辑任务表单（名称/消息/Cron 表达式/启用状态）
- 手动触发按钮
- 执行历史日志（时间/状态/输出）

**P2-4 Backups 管理面板**：
- 备份列表（创建时间/大小/标签）
- 创建备份按钮
- 恢复备份（确认对话框）
- 删除备份

**P2-5 Billing 面板**：
- 计费状态概览（激活状态/计划/到期时间）
- 用量统计图（按日/周的 Token 消耗）
- 费用明细表（按模型/会话分类）

**P2-6 Browser 面板**：
- 浏览器状态指示（运行中/已停止）
- 启动/停止按钮
- URL 导航输入框
- 截图预览区（Base64 图片渲染）

**P2-7 Trash 面板**：
- 回收站文件列表（原路径/删除时间/大小）
- 恢复/永久删除按钮
- 清空回收站按钮

**P2-8 Git 面板**：
- 当前分支/状态显示
- 变更文件列表（staged/unstaged）
- Diff 查看器（语法高亮，使用简单颜色标记）
- Commit 快捷操作（暂不实现完整 Git 交互）

---

### 🟢 P3 — 可选优化（预估 3-5 天）

| # | 任务 | 预估工时 | 优先级说明 |
|---|------|---------|-----------|
| **P3-1** | 多主题支持（Light/Dark/High Contrast） | 3-4h | 提升可访问性，源项目有 3 主题 |
| **P3-2** | 前端性能优化（代码分割/懒加载/缓存策略） | 3-4h | 当前 JS 体积不大，优化收益有限 |
| **P3-3** | 文件上传/附件功能 | 5-6h | 需后端配合新增端点 |
| **P3-4** | PWA 支持（Service Worker / 离线缓存） | 3-4h | 可选增强 |
| **P3-5** | 前端 i18n 国际化框架 | 4-5h | 当前仅英文，源项目有多语言 |
| **P3-6** | MoonBit WASM 前端重写（长期） | 20-30 天 | 需评估 Rabbit-TEA/Rabbita 框架成熟度 |

---

## 4. 依赖拓扑

```
P0-1 (修复 static_server.mbt)
  └── P0-2 (注册静态文件路由)
        └── P0-3 (端到端验证)
              ├── P0-4 (更新测试)
              ├── P1-1 (侧边栏导航重构)
              │     └── P2-1~8 (管理面板) ── 可并行开发
              ├── P1-2 (错误处理增强)
              ├── P1-3 (API 适配层重构)
              └── P1-4 (冒烟测试)
                    └── P3-1~6 (可选优化)
```

关键约束：
- **P0 必须串行**：P0-1 → P0-2 → P0-3
- **P0-4 可与 P1 并行**
- **P2-1 至 P2-8 可完全并行开发**（8 个前端面板彼此独立）
- **P1 任务可与 P2 并行**，但建议 P1 先完成以建立良好基础

---

## 5. 里程碑计划

### M1: Web UI 可用（P0 完成）— 目标 1-2 天内

**验收标准**：
- [ ] `moon run cmd -- --server` 启动后，浏览器访问 `http://localhost:4000` 正常加载完整 Web UI
- [ ] 创建/切换/删除会话正常
- [ ] 发送消息 → SSE 流式响应正常
- [ ] 设置面板正常保存/读取
- [ ] 所有前端 JS 脚本加载无 404 错误
- [ ] `moon check` 0 errors
- [ ] `moon test lib/web` 全部通过（含新增 static_server 测试）

### M2: 功能完整（P1 + P2 完成）— 目标 7-10 天内

**验收标准**：
- [ ] 侧边栏包含全部 12 个管理面板入口
- [ ] 8 个管理面板全部功能可用
- [ ] 前后端 API 对接无误（每个面板至少覆盖核心 CRUD 流程）
- [ ] 错误处理和加载状态完善
- [ ] 移动端响应式布局正常

### M3: 生产就绪（P3 完成 + 全面测试）— 目标 15-20 天内

**验收标准**：
- [ ] 多主题切换正常
- [ ] 性能优化到位（首屏加载 < 2s）
- [ ] 全部 78+ 测试通过
- [ ] 浏览器兼容性验证（Chrome/Firefox/Edge）
- [ ] 与 TUI 界面功能一致性验证

---

## 6. 技术方案详解

### 6.1 static_server.mbt 文件读取方案选型

**方案 A：MoonBit `@fs` 包 Native FFI**（推荐）

```moonbit
// 使用 moonbitlang/x/fs 或 moonbitlang/core/builtin 中的文件 API
let content = @fs.read_file_to_string(full_path)
```

- 优点：MoonBit 原生，类型安全
- 缺点：需要确认当前 `@fs` 包是否有 `read_file_to_string` 方法
- 风险：低 — `lib/agent/session_store.mbt` 已使用类似方法

**方案 B：C FFI 绑定**

```moonbit
extern "c" fn c_read_file(path: CString, out_len: Ref[Int]) -> CString = "mb_read_file"
```

- 优点：完全控制，性能最优
- 缺点：需要写 C stub 文件，跨平台兼容性需额外处理
- 风险：中

**方案 C：在服务器启动时预加载文件到内存**

```moonbit
struct StaticServer {
  root_dir : String
  index_file : String
  file_cache : Map[String, String]  // 路径 → 内容
}
```

- 优点：零运行时文件 I/O
- 缺点：不适合大文件（如图片、字体），内存占用
- 风险：低

**建议**：优先方案 A，如果 `@fs` 不满足，fallback 方案 C（当前 assets/web/ 文件很小，总大小 < 50KB）。

### 6.2 crescent 静态文件路由配置方案

需要确认 crescent 框架的以下 API：
- `app.get_raw("/*path", handler)` 是否支持通配符
- 是否需要使用 `app.group` 中的优先级处理
- crescent 是否有内置 `StaticFiles` 中间件

> **行动项**：在开始编码前，使用 `moonbit-orientation` skill 或查阅 crescent 文档确认准确 API。

### 6.3 前端 JS 架构约定

为保持可维护性，所有新增 JS 模块遵循现有模式：

```javascript
// js/{name}.js — 模块模板
const ModuleName = {
  data: [],

  init() {
    // 绑定事件监听
    // 注册视图入口
  },

  async load() {
    // 从 API 加载数据
  },

  render() {
    // 渲染 DOM
  },

  async handleCreate() { /* ... */ },
  async handleDelete(id) { /* ... */ },
  async handleUpdate(id) { /* ... */ },
};
```

禁止使用的模式：
- ❌ 框架/构建工具（React/Vue/Webpack）— 保持零依赖原生 JS
- ❌ `eval()` 或 `innerHTML` 插入用户数据（使用 DOM API 防 XSS）
- ❌ 全局状态污染（使用模块级变量 + App 命名空间）

### 6.4 API 适配层设计

```javascript
// 统一 API 调用封装
const API = {
  baseUrl: '',

  async get(path) {
    const res = await fetch(this.baseUrl + path);
    if (!res.ok) throw await this.handleError(res);
    return res.json();
  },

  async post(path, body) {
    const res = await fetch(this.baseUrl + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw await this.handleError(res);
    if (res.status === 204) return null;
    return res.json();
  },

  async put(path, body) { /* 类似 post */ },
  async del(path) { /* 类似 get */ },

  async handleError(res) {
    const body = await res.json().catch(() => ({}));
    const err = new Error(body.error || `HTTP ${res.status}`);
    err.status = res.status;
    return err;
  },
};
```

---

## 7. 验证标准

### 7.1 每阶段验证清单

1. **编译检查**: `moon check` 通过，0 errors
2. **构建验证**: `moon build --target native` 成功
3. **测试通过**: `moon test lib/web` 全部通过（原生 native 目标）
4. **Web UI 冒烟**: `moon run cmd -- --server` 启动，浏览器验证全部页面功能
5. **代码格式化**: `moon fmt` 完成
6. **XSS 安全检查**: 所有用户输入经过 `Chat.escapeHtml()` 处理

### 7.2 浏览器兼容性目标

| 浏览器 | 最低版本 | 状态 |
|--------|---------|------|
| Google Chrome | 90+ | ✅ 目标 |
| Mozilla Firefox | 90+ | ✅ 目标 |
| Microsoft Edge | 90+ | ✅ 目标 |
| Safari | 15+ | 🟡 尽力支持 |
| 移动端浏览器 | 最新版 | 🟡 尽力支持 |

### 7.3 性能指标目标

| 指标 | 目标值 |
|------|--------|
| 首屏加载时间 (FCP) | < 1.5s |
| 可交互时间 (TTI) | < 2.0s |
| CSS 总大小 (gzip) | < 20KB |
| JS 总大小 (gzip) | < 60KB |
| API 响应时间 | < 500ms (P95) |

---

## 8. 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| crescent 框架 API 与预期不符 | 中 | 中 | 编码前通过 `moonbit-orientation` 确认 API |
| MoonBit native FFI 文件读取不可用 | 中 | 高 | 备选方案 C（内存预加载） |
| `moon test` native 目标下 crescent 用例失败 | 低 | 中 | 仅需 `moon check` 验证类型，运行时测试在 `moon run cmd -- --server` 中验证 |
| 开发计划文档中 Phase 14 "已完成" 假设干扰 | 高 | 低 | 本计划明确纠正，不受干扰 |
| 新增 JS 文件过多导致维护困难 | 低 | 中 | 每个面板 JS ≤ 250 行，模板化降低重复 |

---

## 附录

### A. 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/static_server.mbt` | ✏️ 重写 | 实现真实文件读取 |
| `lib/web/server.mbt` | ✏️ 修改 | 添加静态文件路由 |
| `assets/web/index.html` | ✏️ 修改 | 添加管理面板视图容器 + 导航按钮 + 新 JS 引用 |
| `assets/web/js/app.js` | ✏️ 修改 | 添加管理面板初始化和视图切换 |
| `assets/web/js/websocket.js` | ✏️ 修改 | API 适配层重构 |
| `assets/web/js/mcp.js` | ➕ 新建 | MCP 管理面板 |
| `assets/web/js/channels.js` | ➕ 新建 | Channels 管理面板 |
| `assets/web/js/schedules.js` | ➕ 新建 | Schedules 管理面板 |
| `assets/web/js/backups.js` | ➕ 新建 | Backups 管理面板 |
| `assets/web/js/billing.js` | ➕ 新建 | Billing 面板 |
| `assets/web/js/browser.js` | ➕ 新建 | Browser 控制面板 |
| `assets/web/js/trash.js` | ➕ 新建 | Trash 面板 |
| `assets/web/js/git_panel.js` | ➕ 新建 | Git 面板 |
| `lib/web/static_server_wbtest.mbt` | ➕ 新建 | 静态文件服务测试 |
| `docs/development-plan-WebUI.md` | ➕ 新建 | 本文档 |

### B. 参考资源

- crescent 框架文档: `moon ide doc bobzhang/crescent`
- crescent package: https://mooncakes.io/packages/bobzhang/crescent
- 现有前端代码: `d:/MoonBit/MBOpenClacky/assets/web/`
- 后端 API 定义: `d:/MoonBit/MBOpenClacky/lib/web/server.mbt`
- 后端 handler 实现: `d:/MoonBit/MBOpenClacky/lib/web/handlers*.mbt`
- MoonBit Web UI 框架（长期参考）:
  - Rabbit-TEA: MoonBit TEA (The Elm Architecture) 框架
  - Rabbita / moonbit-community/rabbita_tui: MoonBit 社区 TUI/Web 框架
