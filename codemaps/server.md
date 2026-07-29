# server — Cron 调度 · 浏览器管理 · Git 面板 · 进程池

> 路径: `lib/server/` · 22 mbt（17 源 + 5 测试）· 后台服务管理

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Scheduler::load_from_config(path)` | `scheduler.mbt` | 从配置文件加载调度器 |
| `Scheduler::tick(min, hour, dom, mon, dow)` | `scheduler.mbt` | 每分钟 tick，检查并触发到期任务 |
| `BrowserManager::new(config_dir)` | `browser_manager.mbt` | 创建浏览器管理器 |
| `BrowserManager::start()` | `browser_manager.mbt` | 启动浏览器守护进程 |
| `ServerMaster::new(config?)` | `master.mbt` | 创建 Worker 池主进程 |
| `build_git_status(dir, branch, commit_time?)` | `git_panel.mbt` | 构建 Git 仓库状态快照 |

## 关键类型

### Cron 调度
- **`Scheduler`** — 调度器（config, state, last_check_at）
- **`SchedulerConfig`** — 调度配置（schedules, tasks_dir, config_path）
- **`SchedulerState`** — `Stopped | Running | Paused`
- **`Schedule`** — 定时任务（name, task_name, cron, enabled, last_run_at, next_run_at, run_count）
- **`CronExpression`** — Cron 表达式（minute, hour, day_of_month, month, day_of_week）
- **`CronField`** — `Any | Value(Int) | Step(Int,Int) | Range(Int,Int) | RangeStep(Int,Int,Int) | List(Array[Int])`

### 浏览器管理
- **`BrowserManager`** — 浏览器管理器（config, daemon_pid, client: JsonRpcClient?）
- **`BrowserConfig`** — 浏览器配置（enabled, chrome_version, mcp_command, features）
- **`BrowserStatus`** — 运行状态（enabled, daemon_running, chrome_version, pid, uptime...）
- **`BrowserProcess`** — 浏览器进程封装（handle, pid, alive），基于 `@async/process`（`spawn_orphan` + 双向管道 JSON-RPC）
- **`JsonRpcClient`** — JSON-RPC 客户端（process, id_counter）— 与浏览器守护进程通信

### 进程池
- **`ServerMaster`** — Worker 池主控（config, status, workers, next_worker_id）
- **`MasterConfig`** — 池配置（max_workers, min_workers, worker_timeout_ms, auto_restart）
- **`MasterStatus`** — `Starting | Running | ShuttingDown | MasterStopped`
- **`Worker`** — 工作进程（config, status, tasks_completed, last_heartbeat）
- **`WorkerConfig`** / **`WorkerId`** — Worker 配置与标识
- **`WorkerStatus`** — `Idle | Busy(String) | Stopping | Stopped | Failed(String)`
- **`PoolStats`** — 池统计（total/idle/busy/failed workers, tasks completed/failed）

### 会话注册
- **`SessionRegistry`** — 会话注册表（entries, max_sessions）
- **`SessionEntry`** — 会话条目（session_id, worker_id, created_at, last_activity, metadata）

### 备份管理
- **`BackupManager`** — 备份管理器（config, source_dir, config_path）
- **`BackupConfig`** — 备份配置（enabled, cron, dest_dir, keep, include_sessions）
- **`BackupEntry`** / **`BackupResult`** — 备份条目/结果

### Git 面板
- **`GitStatus`** — Git 状态（branch, ahead/behind, staged/modified/untracked/deleted/conflicts, last_commit）

### 错误
- **`SchedulerError`** / **`BrowserError`** / **`BackupError`** — 各子系统错误

## 核心调用链

```
# Cron 调度
Scheduler::tick(now)
  └─ for each schedule: CronExpression::matches(now)
      └─ if matches: spawn task → Agent::run(task_message)

# 浏览器管理
BrowserManager::start()
  ├─ BrowserProcess::spawn(command, args)  # @async/process（spawn_orphan + 双向管道）
  ├─ JsonRpcClient::new(process)
  └─ JsonRpcClient::initialize()  # MCP 握手

# Git 状态
build_git_status(dir)
  ├─ git rev-parse → branch
  ├─ git status --porcelain → 文件变更统计
  └─ git log -1 → 最近提交
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| Cron 调度 | `scheduler.mbt`, `scheduler_types.mbt`, `cron.mbt` | 定时任务调度 |
| 浏览器 | `browser_manager.mbt`, `browser_process.mbt`, `browser_jsonrpc.mbt`, `browser_types.mbt` | 浏览器守护进程管理（`@async/process`） |
| 进程池 | `master.mbt`, `worker.mbt` | Worker 池管理 |
| 会话注册 | `session_registry.mbt` | 会话→Worker 映射 |
| 备份 | `backup_manager.mbt`, `backup_types.mbt` | 项目备份 |
| Git | `git_panel.mbt`, `git_staging.mbt` | Git 仓库状态、暂存、命令执行（`@async/process`） |
| 服务发现 | `discover.mbt` | 本地服务实例发现（PID 文件） |

## 外部依赖

- `lib/agent` — Cron 任务触发 Agent::run()
- `moonbitlang/async`（`@async/process`）— 浏览器/子进程管理（替代原 `browser_process.c`，S-FFI-04）
- `moonbitlang/core/json` — 配置序列化

## 风险点

1. **Cron 精度** — 分钟级调度，无法支持秒级任务
2. **子进程生命周期** — 浏览器/Worker 子进程经 `@async/process` 管理，异常退出需确保 `wait`/`cancel` 被调用以防泄漏
3. **Worker 心跳超时** — `is_heartbeat_expired()` 依赖时间字符串比较，时区问题可能导致误判
4. **备份大项目** — `BackupManager::run()` 同步复制，大项目可能阻塞
5. **Git 命令依赖** — `build_git_status()` 依赖系统 git 命令，无 git 环境会失败
