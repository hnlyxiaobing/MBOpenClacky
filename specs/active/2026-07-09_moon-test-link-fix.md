# `moon test` 链接修复 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P0-1）  
> **负责方向**: Agent-F（测试）

## 问题描述

`moon test` 在 native 目标链接失败：

```
/usr/bin/ld: .../lib/client/libclient.a(http_native.o): undefined reference to `curl_easy_init'
... (curl_easy_setopt / curl_easy_perform / curl_easy_cleanup / curl_slist_* ...)
collect2: error: ld returned 1 exit status
```

即 `lib/client/http_native.c` 调用 libcurl，但 curl 符号未进入**测试可执行文件**的最终链接。`lib/client/moon.pkg` 与 `cmd/moon.pkg` 均已声明 `cc-link-flags: "-lcurl"`，且 `libcurl4-openssl-dev` 已安装（`/lib/x86_64-linux-gnu/libcurl.so` 存在），因此问题不在"依赖缺失"或"标志未写"，而在**链接标志未传播到测试目标**。

## 现状分析

- `lib/client/moon.pkg`：`link: { "native": { "cc-link-flags": "-lcurl" } }`（已开启，非注释状态）。
- `cmd/moon.pkg`：`link: { "native": { "cc-link-flags": "-lcrypto -lcurl" } }`，并注释 "Package 'cmd' overrides C/C++ linker flags, `tcc -run` will be disabled"。
- `moon build --target native --release cmd` 成功（主二进制链接正常），说明 cmd 的 link flags 生效；仅 `moon test` 失败。
- 原项目 Ruby 无对应问题（解释型）。
- 根因方向：MoonBit 测试可执行文件的链接阶段未把依赖包的 `cc-link-flags` 汇总到测试 link 行（疑似 moon 工具链对 library 包 link flags 在 test target 的传播限制，参考 `moon#1488` 类问题）。

## 决策

1. **优先用工程内最小改动让测试链接通过**，而非改 moon 工具链。
2. **首选方案**：在 `http_native.c` 顶部对 GCC/Clang 增加 `#pragma comment(lib, "curl")` 风格的等价手段不通用（GCC 不支持 `#pragma comment`），因此改用"在测试入口包补 link flags"。
3. **备选方案 A**：把 curl 依赖收口到 `cmd` 层，让 `lib/client` 的测试通过 mock/stub 跳过真实 HTTP（若传播问题难解）。
4. **备选方案 B**：为 `lib/client` 增加 `test/moon.pkg`（测试专用包配置）显式声明 `-lcurl`。
5. 不在 CI 中临时 `apt install` 绕过--依赖已存在，应修链接。

## 改动范围

- **涉及包**：`lib/client`（主）、可能 `cmd`、可能新增 `lib/client/test/moon.pkg`。
- **涉及文件**：`lib/client/moon.pkg`、`lib/client/http_native.c`（如需条件编译）、`AGENTS.md`（测试说明）。
- **不涉及**：curl 调用逻辑、HTTP 客户端行为、其他包源码。

## 实施计划（任务包切分）

1. **诊断**：用 `moon test -v` 查看测试链接命令行，确认 `-lcurl` 是否出现、出现在哪个位置；确认是否 link 顺序问题（`-lcurl` 在引用它的 `.o` 之前）。
2. **最小修复**：尝试在测试目标补充 link flag（test 专用 moon.pkg 或环境 `CC_LINK_FLAGS`）。
3. **回归**：`moon test lib/client` 全绿后跑全量 `moon test`。
4. **CI 同步**：确认 `.github/workflows/ci.yml` 在修复后无需额外 apt 包即通过。

## 验收标准

- [ ] `moon test` 全量通过（0 link error）
- [ ] `moon test lib/client` 通过
- [ ] `moon check` 0 errors
- [ ] CI 的 test 步骤绿灯（无需新增系统依赖）
- [ ] 修复方案有注释说明根因，避免回退

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| moon 工具链限制无法传播 link flags | 高 | 回退备选方案 B（test 专用 moon.pkg）或方案 A（测试 mock） |
| 修复仅在本地生效、CI 仍失败 | 中 | CI 显式验证；记录 `libcurl4-openssl-dev` 为测试前置依赖 |
| link 顺序调整影响主二进制 | 低 | 主二进制已成功，回归 `moon build --release cmd` 确认 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P0-1 |
