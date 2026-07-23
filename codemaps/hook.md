# hook - Shell Hook 加载器 · 生命周期事件执行

> 路径: `lib/hook/` · 4 mbt（3 源 + 1 测试）+ moon.pkg/.mbti · 外部 Shell 脚本 Hook 系统

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `ShellHookLoader::new(config_dir)` | `shell_loader.mbt` | 创建 Hook 加载器 |
| `ShellHookLoader::load()` | `shell_loader.mbt` | 从 `hooks.yml` 加载配置 |
| `ShellHookLoader::load_into(event_types)` | `shell_loader.mbt` | 加载并注册到 Agent HookManager |
| `ShellHookLoader::execute_hook(event, context)` | `shell_loader.mbt` | 执行匹配的 Shell Hook 脚本 |
| `ShellHookLoader::hooks_for_event(event)` | `shell_loader.mbt` | 获取事件对应的 Hook 列表 |
| `default_hooks_yml()` | `shell_loader.mbt` | 返回默认 hooks.yml 模板 |

## 关键类型

### 核心 Struct
- **`ShellHookLoader`** - Hook 加载器（config_dir, hooks: Array[ShellHook]）

### 配置类型
- **`ShellHook`** - Hook 定义（event, command, timeout, blocking）
- **`ShellHookConfig`** - Hook 配置集合
- **`ShellHookEvent`** - 事件枚举（对应 Agent 生命周期事件）
- **`HookExecResult`** - 执行结果（`Success | Failed | Timeout | Skipped`）

## 核心调用链

```
Agent 启动
  └─ ShellHookLoader::load_into(event_types)
      └─ HookManager::on(event, callback)
          └─ ShellHookLoader::execute_hook(event, context)
              └─ shell 执行 command（带 timeout 控制）
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `shell_loader.mbt` | ShellHookLoader 主体、加载/执行/脚手架 |
| `shell_types.mbt` | ShellHook、ShellHookEvent、ShellHookConfig、HookExecResult 类型定义 |

## 外部依赖

- `lib/agent` - HookManager 注册回调（通过 load_into）
- YAML 解析（自实现或内联）

## 风险点

1. **Shell 注入** - Hook command 直接执行，需确保配置文件来源可信
2. **超时阻塞** - blocking=true 的 Hook 超时后会杀进程，但可能留下子进程
3. **事件名映射** - `parse_hook_event()` 字符串->枚举映射需与 Agent HookEvent 保持同步
