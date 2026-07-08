# Auth Loopback Bypass 安全修复 · 增量 Spec

> **创建日期**: 2026-07-07  
> **状态**: 已评审，进入实施  
> **关联历史 spec**: `docs/project-status-and-deployment-guide.md` §问题1（HTTP 服务器安全增强）  
> **灰度 key**: N/A

## 问题描述

`lib/web/middleware/auth.mbt` 的 `auth_middleware()` 中存在**认证绕过漏洞**：

```moonbit
// lib/web/middleware/auth.mbt:197-199
// Loopback bypass: skip auth for localhost requests
if is_loopback_ip(client_ip) {
  return next()
}
```

任何来自 `127.0.0.1`、`::1`、`localhost`、`[::1]` 的请求**完全跳过 API Key 认证**，直接进入路由处理。

### 攻击场景

> **评审修正（2026-07-07）**：实际漏洞比初版描述**更严重**。crescent 框架的
> `HttpRequest`（见 `.mooncakes/bobzhang/crescent/core/pkg.generated.mbti`）**不暴露
> socket remote address**，`extract_client_ip()` 只能读 `X-Forwarded-For` /
> `X-Real-IP` 请求头，无头时返回 `"unknown"`。因此 **任何远程攻击者只需在请求中
> 附带 `X-Forwarded-For: 127.0.0.1` 头即可伪装成 loopback、100% 绕过认证** ——
> 这是一个可远程利用的认证绕过，而非仅限本机的风险。

| 场景 | 风险 | 说明 |
|------|------|------|
| **伪造代理头** | 🔴 严重 | 任意远程客户端发送 `X-Forwarded-For: 127.0.0.1`（或 `X-Real-IP: ::1`）→ `extract_client_ip()` 返回 loopback → 完全绕过认证。无需任何本机访问权限 |
| **反向代理** | 🔴 高 | nginx/caddy 反代时若透传/追加 XFF，首个 IP 可被客户端控制 |
| **SSH 隧道** | 🟡 中 | `ssh -L 7070:localhost:7070` 转发后，远端用户通过 localhost 访问绕过认证 |
| **同机进程** | 🟡 中 | 同一机器上的任意进程可直接访问 API 无需认证 |
| **共享开发环境** | 🟡 中 | 多人共享的开发服务器，任何人可通过 localhost 绕过认证 |

### 根因分析

`is_loopback_ip()` 的设计初衷可能是方便本地开发（不用每次传 API Key），但：
1. 没有做**可配置化**（硬编码，无法关闭）
2. 没有**区分公共端点和私有端点**（所有端点都绕过）
3. **信任了客户端可控的请求头做安全决策**：`extract_client_ip()` 取
   `X-Forwarded-For` 第一个 IP（客户端可伪造），且框架层无 socket remote addr
   可交叉验证 —— 基于 IP 的 bypass 在当前框架能力下**不可能做安全**
4. 附带问题：auth 中间件是 app 级全局中间件，`/health`（server.mbt:149，注释写
   "no auth required"）在配置了 api_key 且请求无伪造头时**实际也要求认证**，
   与注释意图不符 —— 需要公共端点白名单机制

## 现状分析（代码地形）

### auth.mbt 当前结构

```
auth_middleware(api_key) → Middleware
├── extract_client_ip(req)           // 从 X-Forwarded-For / X-Real-IP / remote_addr 提取
├── is_loopback_ip(client_ip)        // ← 漏洞点：直接 return next()
├── IpRateLimiter::is_limited()      // IP 限流
├── extract_api_key(req)             // Bearer / X-API-Key / query / cookie
├── secure_string_compare()          // 常量时间比较
├── record_success / record_failure  // 限流记录
└── next()                           // 放行到路由
```

### 需要验证的关联问题（评审后已确认）

1. **`extract_client_ip()` 实现**（已核实，auth.mbt:115-131）：优先取 `X-Forwarded-For`
   第一个 IP → 回退 `X-Real-IP` → 无头时返回 `"unknown"`。crescent `HttpRequest`
   不提供 socket remote addr，**IP 完全由客户端可控请求头决定**
2. **公共端点白名单**：`/health` 用 `app.get_raw` 注册（server.mbt:149），但 auth
   是全局中间件，仍会拦截；`/api/version` 组（server.mbt:409）同样在 auth 之后。
   需要白名单机制（对齐原项目 `public_path?`）
3. **config 无 auth 相关配置**：已核实 `lib/config/agent.mbt` 的 `AgentConfig`
   无任何 server/auth 字段；`auth_middleware` 只接收 `api_key` 一个参数

## 决策

### 决策 1：移除硬编码 loopback bypass，改为可显式启用（默认关闭）

```moonbit
// 之前：硬编码绕过
if is_loopback_ip(client_ip) {
  return next()  // ← 移除
}

// 之后：可配置，默认关闭
// auth_middleware(api_key, allow_loopback_bypass? : Bool = false)
if allow_loopback_bypass && is_loopback_ip(client_ip) {
  return next()
}
```

**为什么**：安全默认原则（secure by default）。开发时可显式启用，生产环境默认关闭。

> **评审修正**：由于 `client_ip` 来自客户端可控请求头（见根因分析 3），即使
> `allow_loopback_bypass = true`，该开关也**只是开发便利，不构成任何安全边界**
> ——远程攻击者伪造 XFF 头同样能命中 bypass。因此：
> 1. 默认必须为 `false`
> 2. 启用时在启动日志打印醒目警告（"loopback bypass enabled — do NOT expose this port"）
> 3. 文档注明其唯一适用场景是本机开发

### 决策 2：引入公共端点白名单

部分端点（如 `/health`）应免认证。引入 `public_paths` 集合：

```moonbit
// 评审修正：MoonBit core 无 Set::of；用 Array 常量 + 前缀/精确匹配即可（条目极少）
let public_paths : Array[String] = ["/health", "/api/version"]
```

认证中间件先检查路径是否在白名单中，是则放行。这与原项目 `ApiExtensionDispatcher.public_path?` 机制一致。

**为什么**：健康检查端点不应要求认证（监控工具需要无凭证访问）。当前 `/health`
虽用 `get_raw` 注册且注释标注 "no auth required"，但全局 auth 中间件仍会拦截它
——白名单同时修复此不一致。

> 匹配规则：`/health` 精确匹配；`/api/version` 匹配 `GET /api/version`（版本查询），
> 但 **`POST /api/version/upgrade` 不在白名单内**（触发升级属敏感操作）。

### 决策 3：`extract_client_ip()` 定位为"尽力而为"标识，不作为安全依据

已核实实现（XFF 第一个 IP → X-Real-IP → `"unknown"`），解析本身正确。但 crescent
框架不暴露 socket remote addr，**头部 IP 可伪造，永远不能作为认证决策输入**：
- `extract_client_ip()` 保留，仅用于**限流 key 和日志**（伪造者只会把自己"伪装进"
  别人的限流桶，不产生提权）
- auth 决策仅由 API Key 决定（除非显式开启 dev bypass）
- 不引入"信任代理列表"机制——框架无 socket addr，无从验证代理身份，属过度设计

**为什么**：loopback bypass 的安全性依赖于 IP 来源可信，而当前框架能力下 IP 不可信。
诚实的做法是承认这一点并把 IP 降级为非安全用途。

### 决策 4：bypass 开关用环境变量传递，不动 TOML config 结构

```
MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1   # 仅开发环境
```

`cmd/main.mbt`（或 `lib/web/server.mbt` 构造处）读取该环境变量，传给
`auth_middleware(api_key, allow_loopback_bypass=...)`。`public_paths` 作为
`lib/web/middleware/auth.mbt` 内的常量（不需要运维配置）。

**为什么（评审修正）**：已核实 `AgentConfig` 无 server 段，为一个 dev-only 开关
新增 TOML 配置面（types + loader + 默认值 + 测试）性价比低；环境变量与现有
`MBOPENCLACKY_WEB_API_KEY` 的传递方式一致，改动集中在 web 层。若未来出现更多
server 配置项，再统一收敛到 `[server]` 段。

## 改动范围

- **涉及包**：`lib/web`（含 `lib/web/middleware`）
- **涉及文件**：
  - `lib/web/middleware/auth.mbt` — 移除硬编码 bypass、新增 `allow_loopback_bypass?` 可选参数（默认 `false`）、新增 `public_paths` 常量 + 路径检查
  - `lib/web/server.mbt` — `auth_middleware()` 调用点读取 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK` 环境变量并传参；启用时打印警告
  - `lib/web/middleware/auth_wbtest.mbt`（新建）— 测试用例
- **不涉及**（评审修正）：
  - `lib/config/*` — 不新增 TOML 配置项（用环境变量，见决策 4）
  - `extract_client_ip()` 逻辑本身 — 解析正确，保留用于限流/日志（见决策 3）
  - `is_loopback_ip()` 函数本身（保留，供可配置 bypass 使用）
  - `IpRateLimiter` 逻辑（不受影响）
  - `secure_string_compare()` 逻辑（不受影响）
  - TLS/HTTPS 配置（独立关注点）

## 验收标准

- [ ] 默认配置下（未设 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK`），带 `X-Forwarded-For: 127.0.0.1` 伪造头的请求**不能**绕过认证 → 401
- [ ] 默认配置下，localhost 请求也需要 API Key 认证
- [ ] `allow_loopback_bypass = true` 时，loopback IP 请求绕过认证（开发模式），且启动日志有警告
- [ ] `/health` 和 `GET /api/version` 端点免认证（公共白名单）；`POST /api/version/upgrade` 仍需认证
- [ ] 非白名单端点 + 无 API Key → 返回 401
- [ ] 限流逻辑不受影响（白名单/成功认证路径不记录 failure）
- [ ] `moon check` 0 errors
- [ ] `moon test lib/web` 全部通过
- [ ] 新增测试覆盖：伪造 XFF 头不绕过、bypass on/off、公共端点、IP 提取

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 移除 bypass 后本地开发不便 | 低 | 环境变量 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 显式启用 |
| 已有集成测试依赖 bypass | 中 | 检查测试中是否有依赖 loopback bypass 的用例，修正 |
| 限流以伪造 IP 为 key，攻击者可换头绕限流 | 低 | 已知限制；限流是防爆破的辅助手段，主防线是 API Key + 常量时间比较 |
| 白名单路径匹配过宽 | 低 | 精确匹配 + 明确排除 `/api/version/upgrade`，测试覆盖 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | 项目对比分析识别为安全高优先级修复点 |
| 2026-07-07 | 评审修正：确认漏洞可远程利用（伪造 XFF 头）；`extract_client_ip` 降级为非安全用途；bypass 开关改用环境变量而非 TOML 配置；白名单排除 `/api/version/upgrade`；改动范围移除 lib/config | 结合代码实读评审（crescent 无 socket remote addr；AgentConfig 无 server 段） |
