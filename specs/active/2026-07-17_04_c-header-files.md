# C 头文件提取 · 增量 Spec

> **创建日期**: 2026-07-17
> **状态**: 已就绪（对抗性审查通过，可选实施）
> **关联总览**: 大赛验收反馈 #5 - 缺失 C 文件与 native 头文件
> **来源差距**: C 源文件已存在但无配套 .h 头文件
> **依赖**: 无

## 问题描述 [必填]

评审反馈指出"缺失 C 文件与 native 头文件"。经验证：
- C 源文件已全部存在（`http_native.c`、`http_thread.c`、`mb_stubs.c`、`time_stub.c`）
- 项目内无任何 `.h` 头文件
- `moon check` 和 `moon test` 均通过，编译链接正常

如果复核要求提供头文件，需要从 C 源文件中提取函数声明到独立的 `.h` 文件。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "C 源文件存在" | `find lib/ -name "*.c"` | 4 个文件 | 确认存在 |
| "无 .h 头文件" | `find lib/ -name "*.h"` | 0 结果 | 确认缺失 |
| "编译正常" | `moon check` | 0 errors | 确认可编译 |

### 详细分析

当前 C 源文件是自包含的（所有声明在文件内部），不依赖外部头文件。MoonBit 的 FFI 机制通过 `extern "C"` 声明在 `.mbt` 文件中直接声明 C 函数签名，不需要项目自带 `.h` 文件。

`moonbit.h` 等工具链头文件由 MoonBit 编译器自动提供，不需要项目包含。

**结论**：头文件是可选的代码组织改进，不影响功能和编译。

## 决策 [必填 - 含为什么]

1. **提取头文件作为代码规范改进**：从 `http_native.c` 和 `http_thread.c` 中提取公共函数声明到 `.h` 文件，提高代码可读性和可维护性。
2. **不改动 `mb_stubs.c` 和 `time_stub.c`**：这两个文件较短（21 行），函数声明简单，提取头文件的收益不大。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/http_native.h` | 新建 | 提取 `http_native.c` 的公共函数声明 |
| `lib/client/http_native.c` | 修改 | 添加 `#include "http_native.h"` |
| `lib/client/http_thread.h` | 新建 | 提取 `http_thread.c` 的公共函数声明 |
| `lib/client/http_thread.c` | 修改 | 添加 `#include "http_thread.h"` |

### 不涉及文件

- `lib/client/mb_stubs.c` - 文件简短，无需提取
- `lib/billing/time_stub.c` - 文件简短，无需提取
- 所有 `.mbt` 文件 - FFI 声明方式不变

## 实施计划 [必填]

### 任务包 1：头文件提取（预估 0.5 天）
- 从 `http_native.c` 提取函数声明到 `http_native.h`
- 从 `http_thread.c` 提取函数声明到 `http_thread.h`
- 在 `.c` 文件中添加 `#include` 指令
- 验证编译不受影响

## 验收标准 [必填]

- [ ] `lib/client/http_native.h` 存在且包含正确的函数声明
- [ ] `lib/client/http_thread.h` 存在且包含正确的函数声明
- [ ] `http_native.c` 和 `http_thread.c` 包含对应的 `#include`
- [ ] `moon check` 0 errors
- [ ] `moon test lib/client` 通过
- [ ] `moon build --target native --release cmd` 构建成功

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 头文件提取后编译失败 | 低 | 只提取声明，不修改函数实现 |
| Windows 路径问题 | 低 | 使用相对路径 `#include "http_native.h"` |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈 #5 |
| 2026-07-17 | 对抗性审查：确认低优先级 | `moon check` 0 errors 已通过；MoonBit FFI 不需要项目自带 .h 文件；该改造为纯代码组织改进，无功能影响，可作为 P3 可选项 |
