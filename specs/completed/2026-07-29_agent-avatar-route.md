# Agent 头像路由 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: ✅ 已完成
> **来源差距**: Bug 5（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

新建 session 高级视图中，三个 agent 卡片的头像全部显示为破碎图片。后端生成的 avatar URL `/agent_avatar/<id>` 没有对应的路由处理器，请求落入 SPA fallback 返回 `index.html`（text/html），浏览器收到 HTML 而非图片。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 后端生成 /agent_avatar/ URL | `file_reader lib/web/handlers_agents.mbt:142-148` | `("/agent_avatar/" + id).to_json()` | **确认** |
| server.mbt 无对应路由 | `grep "agent_avatar" lib/web/server.mbt` | 0 命中 | **确认**：路由缺失 |
| 头像文件实际存在 | `glob "assets/agents/*/avatar.png"` | 3 个结果（coding, general, writing） | **确认** |
| SPA fallback 返回 index.html | `file_reader lib/web/server.mbt:804-820` | 非 API 路径 404 时返回 `web/index.html` | **确认** |

### 详细分析

请求链路：
1. 浏览器请求 `GET /agent_avatar/coding`
2. 静态文件中间件在 `web/` 目录下找不到 → 404 → `next()`
3. SPA fallback 返回 `web/index.html`，`Content-Type: text/html`
4. 浏览器收到 HTML 而非图片 → `naturalWidth: 0`

## 决策 [必填 - 含为什么]

1. **在 `server.mbt` 中添加 `/agent_avatar/:id` 路由**：因为这是最直接的修复方式，与现有路由注册模式一致（`/api/` 前缀路由 + 静态文件 + SPA fallback 的三层结构）。
2. **从 `assets/agents/<id>/avatar.png` 读取文件**：因为 `handlers_agents.mbt` 中的路径逻辑已经使用 `assets/agents/` 目录，保持一致。
3. **设置 `Content-Type: image/png`**：因为所有 agent 头像均为 PNG 格式。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 在静态文件中间件之前添加 `/agent_avatar/:id` 路由 |

### 不涉及文件

- `lib/web/handlers_agents.mbt`：URL 生成逻辑正确，无需修改
- `web/` 前端文件：无需修改
- `assets/agents/`：头像文件已存在

## 实施计划 [必填]

### 任务包 1：添加路由（0.2 天）
- 在 `server.mbt` 中，静态文件中间件之前注册路由：
  ```moonbit
  app.get("/agent_avatar/:id", (event) => {
    let id = event.param("id").unwrap_or("")
    let path = "assets/agents/" + id + "/avatar.png"
    if !@fs.path_exists(path) {
      return @core.HttpResponse::not_found().body("Not Found")
    }
    let bytes = @fs.read_file_to_bytes(path) catch {
      _ => return @core.HttpResponse::not_found().body("Not Found")
    }
    @core.HttpResponse::{
      status: 200,
      body: "",
      body_bytes: Some(bytes),
      content_type: "image/png",
      headers: [],
    }
  })
  ```
- 使用 `@fs.read_file_to_bytes`（经 `static_server.mbt:137` 确认可用）
- 使用 `body_bytes` 字段返回二进制内容（经 `static_server.mbt:76` 确认模式）

### 任务包 2：测试验证（0.1 天）
- 手动测试：打开新建 session 高级视图 → 验证三个 agent 头像正常显示
- 浏览器 DevTools 验证：`GET /agent_avatar/coding` 返回 200 + `image/png`
- `moon check`

## 验收标准 [必填]

- [ ] 三个 agent 卡片头像正常显示（coding, general, writing）
- [ ] `GET /agent_avatar/coding` 返回 200 + Content-Type: image/png
- [ ] 不存在的 agent ID 返回 404
- [ ] `moon check` 0 errors

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~crescent 路由不支持通配路径参数~~ | ~~低~~ | 已验证 crescent 支持 `:id` 路径参数（`server.mbt:179`） |
| ~~文件读取 API 不同~~ | ~~低~~ | 已确认使用 `@fs.read_file_to_bytes` + `body_bytes` 字段（`static_server.mbt:76,137`） |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 5 验证确认 |
| 2026-07-29 | 审核修正：修正文件读取 API（`read_file_bytes` → `read_file_to_bytes`）和响应构造方式（使用 `body_bytes` 字段） | 对抗性审核验证 crescent API |
