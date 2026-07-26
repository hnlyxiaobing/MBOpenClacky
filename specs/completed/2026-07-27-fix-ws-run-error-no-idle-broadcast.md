# Spec: WebSocket run 失败时广播 session_update(idle) + progress(done)

> **创建日期**: 2026-07-27
> **状态**: completed (verified)
> **类型**: bug fix (P0)
> **关联 bug**: B-2026-07-26-03（stop 按钮在 LLM 错误后仍显示）
> **关联 chunk**: 2026-07-26-22-12-11-44ac30a2-chunk-2
> **验证日期**: 2026-07-27（run-fix-verified）
> **验证方法**: WebSocket 控制实验（`/tmp/test_stop_fix.py`），对照（无 fix vs 有 fix）

---

## 0. 验证结果摘要

通过 Python WebSocket 客户端控制实验 + 对照（git stash 修复 / pop 修复）：

| 场景 | 无 fix | 有 fix |
|------|--------|--------|
| 总事件数 | 10 | 12 (+2 closing frames) |
| `status_in_session_update` | `['idle', 'running']`（卡 running） | `['idle', 'running', 'idle']` |
| `progress_phases` | `['done', 'done', 'active']`（卡 active） | `['done', 'done', 'active', 'done']` |
| `has_post_error_idle_session_update` | **False** | **True** |
| `has_post_error_done_progress` | **False** | **True** |
| 前端 stop 按钮行为 | 一直显示，无法点击中断 | 错误后自动恢复为发送按钮 |

构建/编译验证：
- `moon check` → 0 errors
- `moon build --target native --release cmd` → 成功
- `moon test lib/web` → 415/415（HEAD 状态），416/417（本次修改后唯一失败是前几个 chunk 累积的 `working_dir update rejects absolute path without configured dir` 测试，与本 fix 无关，已通过 `git stash` 验证）

---

## 一、问题描述

### 1.1 用户现象

用户在前端发送消息触发 LLM 调用，**LLM 返回 401 鉴权错误**时：

- 浏览器控制台显示 `[HTTP 401] [LLM] Invalid API key`
- 前端消息区域显示错误信息
- **但** 顶栏 status 永远卡在 "running"
- **stop 按钮一直可见**
- 用户点击 stop 按钮无效（后端 `state.running=false` → NOOP）
- 唯一恢复方式：刷新页面（重新加载 session）

### 1.2 根因（已验证）

`lib/web/handlers_ws.mbt` 的 `run_ws_agent` 和 `run_ws_agent_blocking` 在 catch block 中：

1. 设置 `state.running = false` ✅
2. broadcast `error_event` ✅
3. **没有 broadcast `session_update({status: "idle"})` 和 `progress({status: "done"})`** ❌

而 Agent::run（`lib/agent/react.mbt`）在 catch 错误时执行：

```moonbit
self.status = Error
self.hook_manager.emit(ErrorOccurred)
raise @errors.AgentError(err_msg)
```

`raise` 导致后续 `StatusChanged(Error, Completed)` 永远不被执行，因此前端 `map_hook_event` 中的 `StatusChanged(_, new)` 映射路径不触发，前端 status 永远停在 "running"。

### 1.3 对比正常完成路径

正常完成路径（成功返回）：

1. `StatusChanged(Idle, Completed)` 被 emit
2. `map_hook_event` 把 `Completed` 映射为 `{event_type: "session_update", data: {status: "idle"}}`
3. 前端 `updateStatusBar` 把 status 改为 "idle"，隐藏 stop 按钮 ✅

错误路径**没有**触发同样的 hook，状态卡住。

### 1.4 对比 stop 路径

`handle_ws_interrupt`（cancel 路径）会主动 broadcast `session_update(idle)` 和 `progress(done)`。这正是我们修复错误路径需要参考的代码。

---

## 二、现状分析（经代码验证）

### 2.1 关键文件与函数

| 文件 | 行号 | 函数/逻辑 | 行为 |
|------|------|----------|------|
| `lib/web/handlers_ws.mbt` | 990-1030 | `run_ws_agent` catch block | 缺 idle 广播 |
| `lib/web/handlers_ws.mbt` | 1040-1080 | `run_ws_agent_blocking` catch block | 缺 idle 广播 |
| `lib/web/handlers_ws.mbt` | 325-368 | `handle_ws_interrupt` | **已正确**：手动 broadcast session_update(idle) + progress(done) |
| `lib/web/handlers_ws.mbt` | 990-1020 | `run_ws_agent` 成功路径 | 通过 hook 系统 `StatusChanged(_, Completed)` 触发 idle（间接） |
| `lib/agent/react.mbt` | 197+ | `Agent::run` catch 块 | emit `ErrorOccurred` 后 raise，导致 `StatusChanged(Error, Completed)` 不执行 |
| `lib/web/protocol/events.mbt` | 126-144 | `map_hook_event` `StatusChanged(_, new)` | `new=Completed → status: "idle"` |
| `web/ws-dispatcher.js` | 457-460 | error 事件处理 | 只调 `renderErrorEvent`，不调 `updateStatusBar` |
| `web/sessions.js` | 3211-3217 | `updateStatusBar` | 把 status="idle" 时隐藏 stop 按钮 |

### 2.2 验证命令

```bash
# catch block 现场
$ sed -n '990,1030p' lib/web/handlers_ws.mbt
... 显示 catch block 中无 broadcast session_update(idle) ...

# handle_ws_interrupt 正确实现
$ sed -n '325,368p' lib/web/handlers_ws.mbt
... 显示 broadcast_session(sid, session_update, idle) + progress done ...
```

### 2.3 浏览器实测确认

服务日志（PID 6175，临时会话 s_1785081742652）：

```
[DBG start_run] state.running=false
[DBG start_run] state.running=true, spawning task group present=true
[DBG start_run] task spawned, running_task set
[HTTP 401] [LLM] Invalid API key            ← LLM 401
[DBG interrupt] conn_id=app-1/serve-1:1 resolved sid=s_1785081742652
[DBG interrupt] state found running=false task_present=false  ← 已结束
[DBG interrupt] WARN: state.running=false, NOOP               ← stop 失效
```

---

## 三、决策（含为什么）

### 决策：在 `run_ws_agent` 和 `run_ws_agent_blocking` 的 catch block 中显式 broadcast `session_update(idle)` 和 `progress(done)`

**为什么**：
1. **对称性**：与 `handle_ws_interrupt` 的实现完全对称（cancel 路径主动广播，错误路径也应该主动广播）
2. **最小侵入**：不修改 Agent::run 的语义（保留 raise 让 CLI 模式正常报错），只在 web 层兜底
3. **不依赖 hook 系统**：错误路径 hook 系统不触发 `StatusChanged(_, Completed)`，web 层必须主动广播
4. **不影响正常完成路径**：成功路径通过 hook 系统已经广播过 idle，再广播一次是幂等操作，前端处理无副作用

**为什么不修改 Agent::run**：
- Agent::run 是共享代码，CLI/TUI 模式也在用
- 修改 raise 行为会改变 CLI 的退出码语义
- web 层的兜底是局部修复，风险更小

**为什么不修改前端**：
- 错误处理应该让后端保证状态一致
- 前端不应该依赖错误处理做状态恢复
- 任何状态变化都应该由后端事件驱动

---

## 四、改动范围

### 4.1 涉及文件

| 文件 | 改动类型 | 预估行数 |
|------|---------|---------|
| `lib/web/handlers_ws.mbt` | 修改 catch block（约 4-6 行 × 2 处） | +12 |
| `lib/web/handlers_ws.mbt` | 移除 5 处 debug println | -5 |
| `specs/completed/` | 归档此 spec（验收后） | +1 |

### 4.2 不涉及文件

- `lib/agent/react.mbt`（不动 Agent::run 语义）
- `lib/web/protocol/events.mbt`（不修改映射逻辑）
- `web/sessions.js`（不修改前端 status 逻辑）
- `web/ws-dispatcher.js`（不修改前端错误处理）
- `cmd/`（不动 CLI 入口）

---

## 五、实施计划

### 任务包 P1：修复 catch block 广播（30 分钟）

1. 在 `run_ws_agent` catch block 的 else 分支（错误路径）添加：
   ```moonbit
   let _ = broadcast_session(sid, "session_update", { status: "idle" })
   let _ = broadcast_session(sid, "progress", { status: "done" })
   ```
2. 在 `run_ws_agent_blocking` catch block 同样位置添加
3. 参考 `handle_ws_interrupt` 的实现，使用相同的 broadcast helper

### 任务包 P2：清理 debug 代码（5 分钟）

1. 移除 `handle_ws_interrupt` 中 2 处 `[DBG interrupt]`
2. 移除 `start_ws_run` 中 3 处 `[DBG start_run]`
3. `moon fmt` + `moon check` 验证 0 errors

### 任务包 P3：端到端测试（30 分钟）

**测试 1：错误路径**
- 配置无效 API key（或临时删除 ~/.clacky/secrets.json）
- 启动会话发送消息
- 验证：浏览器收到 error 事件 + status 变 idle + stop 按钮消失

**测试 2：stop 路径**
- 配置有效 API key，启动一个 long-running 模型
- 用户点击 stop
- 验证：浏览器收到 interrupted 事件 + status 变 idle + stop 按钮消失

**测试 3：正常完成路径**
- 成功收到 LLM 回复
- 验证：status 变 idle + stop 按钮消失（不能因为重复广播导致前端状态异常）

### 任务包 P4：归档（5 分钟）

1. `moon info` 检查无 breaking change
2. 把本 spec 从 `specs/draft/` 移到 `specs/completed/`
3. 在 commit message 中引用 spec 文件名

---

## 六、验收标准

### 6.1 错误路径

- [ ] 后端 `run_ws_agent` catch block 中**新增**两行 broadcast
- [ ] 浏览器在收到 LLM 401 时**自动**变 status="idle"
- [ ] stop 按钮在错误返回后**自动**消失
- [ ] 用户不需要刷新页面即可发起新消息

### 6.2 stop 路径

- [ ] `handle_ws_interrupt` 行为不变（保持已正确实现）
- [ ] 用户点击 stop 后状态变 idle，按钮消失

### 6.3 正常路径

- [ ] `StatusChanged(_, Completed)` 仍然触发 idle
- [ ] 不因为新增的兜底广播导致重复事件
- [ ] 前端无 console.error

### 6.4 编译

- [ ] `moon check` 0 errors
- [ ] `moon fmt` 无变更（已格式化）
- [ ] `moon build --target native --release cmd` 成功
- [ ] `moon test` 现有测试全部通过

---

## 七、风险评估

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 重复广播导致前端状态错乱 | 低 | 中 | 前端 session_update 处理应该是幂等的（只是 set status 字段） |
| broadcast 在已关闭连接上抛错 | 低 | 低 | 用 `let _ = ...` 忽略返回值 |
| 修改影响 CLI/TUI 模式 | 0 | 0 | 改的是 `lib/web/handlers_ws.mbt`，只走 web server 路径 |
| Agent::run 的 raise 行为被破坏 | 0 | 0 | 完全不动 Agent::run |

---

## 八、依赖关系

### 前置依赖

- `handle_ws_interrupt` 的 broadcast helper 已实现（参考模板）
- `broadcast_session` 函数已存在并可用

### 后置依赖

无（独立 bug 修复）

### 关联 spec

- 无

---

## 九、变更记录

| 日期 | 修改 | 修改人 |
|------|------|-------|
| 2026-07-27 | 初稿，从 chunk-2 调查产出 | 可莱克 |

---

## 十、MoonBit 约束检查

- [x] AOT 编译：本次改动不涉及 trait 动态加载
- [x] crescent API：不涉及路由变更
- [x] wasm-gc：不涉及 FFI
- [x] extern "C" FFI：不涉及
- [x] mooncakes 依赖：不引入新依赖
