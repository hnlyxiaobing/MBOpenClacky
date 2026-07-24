# 公网绑定安全闸门 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md` G-003  
> **来源差距**: G-003 - 缺"公网绑定必须设访问密钥"的安全闸门  
> **依赖**: 无  
> **优先级**: P1（安全）  
> **灰度 key**: 无

## 问题描述 [必填]

当前 server 默认监听 `0.0.0.0:7071`，未设 `MBOPENCLACKY_WEB_API_KEY` 时**完全不注册 auth 中间件**，公网暴露时无任何认证。即使设置了 API key，loopback 免认证的客户端 IP 取自可伪造的 `X-Forwarded-For`/`X-Real-IP` 头，远程攻击者伪造该头即可绕过认证。

原项目在 `--host 0.0.0.0` 且未设 `CLACKY_ACCESS_KEY` 时**拒绝启动**。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 默认绑定 0.0.0.0 | `grep "0\.0\.0\.0" cmd/main.mbt` | 第 451 行 `println("Starting MBOpenClacky web server on http://0.0.0.0:\{port}")` | 确认：无 host 参数控制，硬编码 0.0.0.0 |
| 无 key 时不注册 auth | 读 `lib/web/server.mbt` 第 142-156 行 | `match self.api_key { Some(key) => ...; None => () }` | 确认：api_key 为 None 时跳过 auth 中间件注册 |
| loopback bypass 默认开启 | 读 `lib/web/server.mbt` 第 145-150 行 | `allow_loopback` 默认 true（除非 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=0`） | 确认：默认开启 loopback bypass |
| client_ip 来自可伪造头 | 读 `lib/web/middleware/auth.mbt` 第 120-132 行 | `extract_client_ip` 先查 `X-Forwarded-For`，再查 `X-Real-IP`，默认 `127.0.0.1` | 确认：IP 来自客户端可控头 |
| loopback bypass 用 client_ip | 读 `lib/web/middleware/auth.mbt` 第 172-174 行 | `if allow_loopback_bypass && is_loopback_ip(client_ip) { return next() }` | 确认：伪造 `X-Forwarded-For: 127.0.0.1` 即可绕过 |
| 无 key 时完全无认证 | `match self.api_key { None => () }` | 无 auth 中间件 = 所有请求直接通过 | 确认：公网暴露 + 无 key = 完全开放 |
| 端口可配但 host 不可配 | `grep "MBOPENCLACKY_WEB_PORT\|MBOPENCLACKY_WEB_HOST" cmd/main.mbt` | 只有 PORT 环境变量，无 HOST | 确认：无法通过环境变量指定绑定地址 |
| server.start 签名 | `grep "fn.*start" lib/web/server.mbt` | 需确认 start 是否接受 host 参数 | 待验证 |

### 详细分析

**两道安全缺口**：

1. **无 key = 无认证**：`api_key` 为 None 时，`build_app()` 不注册 auth 中间件。Server 绑定 `0.0.0.0`，任何能访问该端口的客户端均可操作所有 API。

2. **loopback bypass 可伪造**：即使设置了 key，`allow_loopback_bypass` 默认为 true。`extract_client_ip` 从 `X-Forwarded-For` / `X-Real-IP` 取 IP（这些是客户端可设的 HTTP 头），攻击者发送 `X-Forwarded-For: 127.0.0.1` 即可跳过认证。

**原项目行为**（gap 文档引用 `openclacky/lib/clacky/cli.rb:1345-1363`）：
- `--host 0.0.0.0` 且未设 `CLACKY_ACCESS_KEY` 时拒绝启动
- loopback 判定使用真实 TCP 对端 IP

## 决策 [必填 - 含为什么]

1. **增加 host 环境变量**：新增 `MBOPENCLACKY_WEB_HOST` 环境变量（默认 `127.0.0.1`）。用户显式设为 `0.0.0.0` 时视为公网绑定。

2. **公网绑定安全闸门**：在 `cmd/main.mbt` 中，若 host 为非回环地址且 `MBOPENCLACKY_WEB_API_KEY` 未设置，**拒绝启动**并打印安全警告。

3. **默认绑定改为 127.0.0.1**：将默认绑定地址从 `0.0.0.0` 改为 `127.0.0.1`，与原项目行为一致。需要公网访问时显式设置 `MBOPENCLACKY_WEB_HOST=0.0.0.0`。

4. **loopback bypass 默认关闭**：将 `allow_loopback_bypass` 默认值从 true 改为 false。仅在显式设置 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 时开启。

5. **loopback 判定改用真实对端 IP（如可行）**：检查 crescent 是否暴露 TCP peer 地址。若可用，loopback 判定改用真实 peer IP 而非 HTTP 头。若 crescent 不暴露 peer 地址，则在公网绑定场景下强制关闭 loopback bypass。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及
- crescent 路由：需验证 crescent 是否提供 TCP peer 地址 API
- FFI：不涉及
- mooncakes 依赖：不涉及
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `cmd/main.mbt` | 修改 | 增加 `MBOPENCLACKY_WEB_HOST` 环境变量读取；默认 127.0.0.1；公网绑定 + 无 key 时拒绝启动 |
| `lib/web/server.mbt` | 修改 | `build_app` 中 `allow_loopback_bypass` 默认改为 false；传递 host 参数给 start |
| `lib/web/middleware/auth.mbt` | 修改 | `extract_client_ip` 在无代理头时返回真实 peer（若 crescent 支持）；注释更新 |

### 不涉及文件

- 前端 JS（零修改）
- `lib/agent/` 层（不涉及）
- WS 协议层（不涉及）
- 已有的 auth 中间件逻辑（rate limiting、key extraction 等不变）

## 实施计划 [必填]

### 任务包 1：host 环境变量与安全闸门（0.5 天）
- `cmd/main.mbt`：新增 `MBOPENCLACKY_WEB_HOST` 读取，默认 `127.0.0.1`
- 公网绑定（非回环地址）且 `api_key` 为 None 时：打印安全警告并 `exit(1)`
- 更新启动日志显示绑定地址

### 任务包 2：loopback bypass 安全加固（0.5 天）
- `lib/web/server.mbt`：`allow_loopback_bypass` 默认改为 false
- 仅 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 时开启
- 检查 crescent 是否暴露 TCP peer 地址（`grep "peer\|remote\|addr" .mooncakes/.../crescent/`）
- 若可用，`extract_client_ip` 优先使用真实 peer 地址
- 若不可用，注释说明限制并确保公网绑定时 bypass 关闭

### 任务包 3：测试与文档（0.5 天）
- 更新 auth 白盒测试：验证 loopback bypass 默认关闭
- 新增测试：公网绑定 + 无 key 时拒绝启动
- 更新启动日志文案

## 验收标准 [必填]

- [ ] 默认绑定 `127.0.0.1`（非 `0.0.0.0`）
- [ ] `MBOPENCLACKY_WEB_HOST=0.0.0.0` 且未设 key 时拒绝启动
- [ ] `MBOPENCLACKY_WEB_HOST=0.0.0.0` 且设了 key 时正常启动
- [ ] `MBOPENCLACKY_WEB_HOST=127.0.0.1` 且未设 key 时正常启动（本地开发）
- [ ] loopback bypass 默认关闭
- [ ] 伪造 `X-Forwarded-For: 127.0.0.1` 无法绕过认证（bypass 关闭时）
- [ ] `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 时 bypass 开启（仅本地开发）
- [ ] `moon check` 0 errors（cmd, lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 默认改为 127.0.0.1 影响已有公网部署 | 中 | 启动日志明确提示需设置 `MBOPENCLACKY_WEB_HOST=0.0.0.0`；更新文档 |
| crescent 不暴露 TCP peer 地址 | 中 | 公网绑定时强制关闭 loopback bypass；本地开发场景不影响 |
| 改变默认行为影响 CI/Docker | 低 | Docker 环境通常设了 host 和 key；检查 Dockerfile 是否需更新 |
| 已有用户依赖 loopback bypass | 低 | 通过 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 可恢复旧行为 |

## 依赖关系 [必填]

- **前置依赖**: 无
- **后置依赖**: 无（独立安全加固）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | G-003 P1 安全闸门 |