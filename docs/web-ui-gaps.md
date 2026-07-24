# Web UI 差距记录（当前项目尚未实现的能力）

> 判定规则见 `web-ui-test-plan.md` §3：只记"原项目有、当前项目没有"的能力；当前项目已有但实现有错误的记入 `web-ui-issues.md`。
> 状态：Open / In Progress / Done / Won't do

## 状态总览

| Gap ID | 标题 | 严重度 | 状态 | 实施 Spec |
|--------|------|--------|------|-----------|
| G-001 | 前端基线落后原项目一个大版本（v1.4.0 vs v1.5.0） | P1 | ✅ Done | `specs/active/2026-07-24_web-ui-fix-06-frontend-v15-sync.md` |
| G-002 | 技能发布到市场未实现（POST /api/my-skills/:name/publish 固定 501） | P2 | Open | — |
| ~~G-003~~ | ~~缺"公网绑定必须设访问密钥"的安全闸门~~ | ~~P1~~ | ✅ Done | `specs/completed/2026-07-24_web-ui-fix-05-public-binding-security.md` |
| G-004 | 运行期间缺少 cost / latency 增量 session_update（WS） | P3 | ✅ Done | `specs/active/2026-07-24_web-ui-fix-08-ws-cost-latency-update.md` |
| G-005 | 手动任务文件概念缺失（cron 列表只含调度条目） | P2 | Open | — |

**汇总**：5 项差距 — ✅ 已解决 3 项 / ❌ 待解决 2 项

---

## ✅ G-001 前端基线落后原项目一个大版本（v1.4.0 vs v1.5.0）

- 严重度：P1
- 范围：`web/` 全部前端资产
- 现状：已按 `web/UPSTREAM_SYNC.md` 流程完成 v1.5.0 同步（2026-07-24，fix-06），commit `52205e14`。15 个文件更新，ext_ui/ 与品牌资产排除保护完好。
- 影响：v1.5.0 前端新面板/新交互（reload-header、Advanced options、Extensions Brand 过滤、Background 主题等）已随升级到位。
- 状态：✅ Done（2026-07-24，fix-06）

## ❌ G-002 技能发布到市场未实现（POST /api/my-skills/:name/publish 固定 501）

- 严重度：P2
- 端点：`POST /api/my-skills/:name/publish`
- 原项目行为：发布我的技能到市场（`openclacky/lib/clacky/server/http_server.rb:745`，handler :5295）。
- 当前项目行为：路由存在但固定返回 501（`lib/web/server.mbt:546-554`），前端 Skills 面板的"发布"操作无法走通。
- 状态：Open

## ✅ G-003 缺"公网绑定必须设访问密钥"的安全闸门

- 严重度：P1（安全）
- 范围：server 启动与认证
- 原项目行为：`--host 0.0.0.0` 且未设 `CLACKY_ACCESS_KEY` 时**拒绝启动**（`openclacky/lib/clacky/cli.rb:1345-1363`）。
- 当前项目行为（修复前）：默认监听 `0.0.0.0:7071`，未设 `MBOPENCLACKY_WEB_API_KEY` 时**完全无认证**（`cmd/main.mbt:434`）；且 loopback 免认证的客户端 IP 取自可伪造的 `X-Forwarded-For`/`X-Real-IP`（`lib/web/server.mbt:144-156` 注释自认"只是开发便利而非安全边界"），公网暴露时伪造该头即可绕过认证。
- 修复内容：新增 `MBOPENCLACKY_WEB_HOST` 环境变量（默认 `127.0.0.1`）；公网绑定且未设 key 时拒绝启动；`allow_loopback_bypass` 默认改为 false（仅 `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 开启）。
- 状态：✅ Done（2026-07-24，未提交）。Spec：`specs/completed/2026-07-24_web-ui-fix-05-public-binding-security.md`

## ✅ G-004 运行期间缺少 cost / latency 增量 session_update（WS）

- 严重度：P3
- 范围：ws 消息流
- 原项目行为：LLM 调用完成前后推送两个 partial `session_update`：`{"cost":..,"cost_source":..}` 与 `{"latency":{ttft_ms,duration_ms,output_tokens,tps,...}}`。
- 当前项目行为：只有 `{"status":...}` 两类 partial 帧，无 cost/latency 增量。前端 shape-2 分支（ws-dispatcher.js:249-255）原生支持这四个字段，补发即可生效。
- 证据：`logs/web-compare/2026-07-24/ws-events.json` orig step 9 第 6-7 帧 vs current step 9；findings-ws.md WS-008
- 状态：✅ Done（2026-07-24，fix-08）。在 UsageUpdated hook 处补发 cost `{cost, cost_source}` 与 latency `{latency: {ttft_ms, duration_ms, output_tokens, tps}}` 两帧 partial session_update；delta_tokens=0 时与 token_usage 一并抑制。Spec：`specs/active/2026-07-24_web-ui-fix-08-ws-cost-latency-update.md`

## ❌ G-005 手动任务文件概念缺失（cron 列表只含调度条目）

- 严重度：P2
- 范围：`GET /api/cron-tasks` / 定时任务面板
- 原项目行为：cron 列表合并"手动任务文件"（无调度的 prompt 任务文件，`scheduled=false`），与调度条目一起展示（`openclacky/lib/clacky/server/scheduler.rb:129-145`，任务文件可读、可在会话中运行）。
- 当前项目行为：仅列出调度器条目（`schedule_state.val.scheduler.list_schedules()`），无任务文件概念。
- 证据：fix-04 spec 审核验证记录（2026-07-24）
- 状态：Open

---

## 追加模板

```
## G-XXX <标题>
- 严重度：P0/P1/P2/P3
- 范围/端点：
- 原项目行为：
- 当前项目行为：
- 证据：
- 状态：Open
```

## 有意差异备忘（不计入差距）

- web-parity-05 删除的 legacy 端点：meetings、全局 `/api/git`、`/api/backups`、`/api/settings`、`/api/models` 别名、`POST /api/sessions/:id/chat`（SSE）。
- `web/ext_ui/`（git、time-machine 面板）为当前项目**独有新增**能力。
- 端口（7071 vs 7070）、认证环境变量名（`MBOPENCLACKY_WEB_API_KEY` vs `CLACKY_ACCESS_KEY`）为刻意区分。
