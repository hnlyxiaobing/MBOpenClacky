# cmd 层桩位激活（让 cmd 真正跑起来） · 增量 Spec

> **创建日期**: 2026-07-07
> **状态**: 已完成（2026-07-07）
> **关联历史 spec**: docs/harness-methodology-application-plan.md §1.2 / §2.2

## 问题描述

cmd 层存在 4 处"日志桩"，功能声明存在但不产生真实行为：

| 桩位 | 文件 | 现状 |
|------|------|------|
| billing 子命令 | `cmd/main.mbt` `handle_billing()` | 打印 "not yet implemented -- Phase 6" |
| Hook 执行 | `cmd/hook_loader.mbt` `execute_hook()` | 只打印日志，不 spawn shell |
| Patch 应用 | `cmd/patch_loader.mbt` `apply_patches()` | 只按模块分组打印 |
| 扩展注册 | `cmd/api_extension_loader.mbt` `register_extensions()` | 只打印路由列表，无校验 |

## 现状分析（代码地形）

- `lib/billing` 已有完整 `BillingStore`（default/query/summary/daily_breakdown），cmd 只差接线
- `lib/tool/tool_stubs.c` 提供 `mb_system`（C system() FFI）；cmd 二进制经 web→tool 链路已链接该符号，可直接 extern 声明复用
- `lib/tool/terminal.mbt` 的 marker 方案（输出重定向 + `__CLACKY_DONE_<token>_<code>__`）可作为 hook 执行的参考实现
- `@sys.set_env_var` 可用于向 hook 子进程传递上下文（CLACKY_SESSION_ID 等）
- Web 端扩展路由注册已由 `lib/web/ext_dispatcher.mbt` 完成（server.mbt:376 已接线）

## 决策

1. **billing 接 BillingStore::default()**：显示总量 summary + 最近 7 天 daily_breakdown。为什么：数据层已就绪，纯接线。
2. **hook 用 mb_system + 输出文件 + marker 执行**：与 terminal.mbt 同构，跨平台（cmd.exe / sh）。上下文经环境变量传入（CLACKY_SESSION_ID / CLACKY_MESSAGE / CLACKY_WORKING_DIR）。非零退出码返回 Err。为什么：复用已验证的执行模式，不引入新依赖。
3. **patch 重定义为"启动脚本"语义**：MoonBit 是 AOT 编译，无法像 Ruby 原版那样运行时 monkey-patch。descriptor 新增可选 `command` 字段；apply = 执行 command（同 hook 执行机制）；无 command 的 patch 视为元数据声明，跳过并提示。为什么：这是编译型语言下唯一诚实可行的 patch 语义。
4. **register_extensions 做真实校验**：重名扩展、单扩展内重复路由（method+path）、非法 HTTP 方法 → 返回 Err；通过校验的输出摘要。为什么：cmd（CLI 模式）不承载 HTTP 路由，真实价值是启动期把配置错误暴露出来。

## 改动范围

- 涉及包：`cmd/`（仅此一个包）
- 涉及文件：
  - `cmd/main.mbt`（handle_billing 重写）
  - `cmd/hook_loader.mbt`（execute_hook 真实执行 + 新增 shell 执行 helper）
  - `cmd/patch_loader.mbt`（PatchInfo 增加 command 字段 + apply_patches 真实执行）
  - `cmd/api_extension_loader.mbt`（register_extensions 校验逻辑）
- 不涉及：
  - `lib/web/ext_dispatcher.mbt` 的 handler stub（扩展运行时属 web 任务包，另立 spec）
  - `lib/hook/shell_loader.mbt`（lib 层 ShellHookLoader 的 placeholder 属 lib/hook 任务包）
  - `cmd/channel_scaffold.mbt`（生成模板本身就是 scaffold 语义，生成代码含 stub 是合理的）
  - hook 超时强制中断（system() 无超时能力；Unix 用 `timeout` 命令包裹，Windows 暂不支持，文档注明）

## 验收标准

- [x] `mbopenclacky billing` 输出真实账单汇总（实测 368 请求 + by_model + 最近 7 天，日期算法真实化）
- [x] hook 命令真实执行：`echo ... > file` hook 运行后文件存在；退出码非 0 时返回 Err
- [x] hook 子进程能读到 CLACKY_SESSION_ID / CLACKY_WORKING_DIR 环境变量（实测 `session=pending` 写入成功）
- [x] patch 带 command 时真实执行（实测 CLACKY_PATCH_NAME 传递成功）；不带 command 时跳过并提示
- [x] 扩展重名 / 路由重复 / 非法 method 时 register_extensions 返回 Err
- [x] moon check 0 errors
- [x] moon build cmd 成功，真实二进制端到端验证以上行为（moon test cmd 11/11 通过）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| hook/patch 执行任意 shell 命令 | 高（本身即设计目的） | 仅从用户自己的 ~/.clacky/ 目录加载；enabled=false 可禁用；执行前打印命令 |
| mb_system 符号在裁剪构建中缺失 | 低 | cmd 声明 extern 复用；链路经 lib/web→lib/tool 恒定存在 |
| Windows 无 timeout 包裹 | 低 | 文档注明；hook 应快速返回 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | cmd 桩位激活任务启动 |
| 2026-07-07 | 新增 `cmd/shell_exec.mbt`（run_shell_command 共享 helper）；lib/billing 补真实时间 FFI（time_stub.c）与日期算法 | 实施中发现 billing 的 current_time_ms/ms_to_date_string 也是桩 |
| 2026-07-07 | 调试修复：system() 需 UTF-8 NUL 结尾 C 字符串（String::to_bytes 是 UTF-16LE 会导致 32512）；`{ }` 组内 exit 跳过 marker 改用 `( )` 子 shell；marker 缺失时 wait status 需 >>8 | 测试驱动发现的三个平台性陷阱 |
| 2026-07-07 | 完成：moon test cmd 11/11，端到端二进制验证 hook/patch/billing/extensions 全通过 | 任务收尾归档 |
