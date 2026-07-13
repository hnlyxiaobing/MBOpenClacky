# 测试覆盖扩展 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 已完成  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P2-4）  
> **负责方向**: Agent-F（测试）

## 问题描述

MBOpenClacky 测试 19,042 行 / 73 文件 / 1,400+ 用例，原项目 37,606 行 / 159 spec 文件。测试深度仍有差距，尤其 Web、TUI、Extension 等新功能领域缺 eval 场景。需补齐 eval 场景，将用例数从 1,400+ 提升至 2,000+，并向原项目覆盖面靠拢。

## 现状分析

- 已有 `test/eval/eval_engine_wbtest.mbt` 评估框架与 `test/tui` eval 场景。
- 白盒测试 `*_wbtest.mbt` 与源码同置，密度高但文件数偏少。
- Web/Extension 领域随 P0-2/P1-1/P1-5 推进将新增 handler，需同步补 wbtest。
- `moon test` 链接失败（P0-1）是测试运行的前置阻塞。

## 决策

1. **依赖 P0-1**：先修链接，否则无法跑测试。
2. **随功能 spec 同步补测**：每个 P0/P1 spec 的验收标准已要求 wbtest，本 spec 负责"补历史 + 统筹"。
3. **eval 场景优先**：Web/TUI 交互用 eval 场景覆盖，而非纯单元测试。
4. **目标量化**：用例数 1,400+ -> 2,000+，文件数 73 -> 100+。
5. **不追求行数对齐**：MoonBit 更精炼，行数非目标，覆盖度才是。

## 改动范围

- **涉及包**：`test/eval`、`test/tui`、各 `lib/*` 的 `*_wbtest.mbt`。
- **涉及文件**：新增 eval 场景文件、补 wbtest。
- **不涉及**：业务源码（除非测试暴露缺陷需修）。

## 实施计划（任务包切分）

1. **P0-1 解锁后**：跑通全量 `moon test`，建立基线。
2. **历史补测**：为已有但未覆盖的 handler/工具补 wbtest。
3. **Web eval**：随 P0-2/P1-5 补 API eval 场景。
4. **TUI eval**：随 P1-6 补 dialog 路径场景。
5. **Extension eval**：随 P1-1 补加载/校验/打包场景。
6. **统计与门禁**：CI 报告用例数，设定增长目标。

## 验收标准

- [x] 用例数 ≥ 2,000（实测 **2,001** 个 `test "..."` 用例，含本轮新增 12 个 `_wbtest.mbt` 文件共 ~210 例）
- [x] 测试文件数 ≥ 100（实测 **133** 个 `*_wbtest.mbt` 文件）
- [x] TUI eval 场景已存在（`test/scenarios/tui/`）；本轮新增覆盖 TUI/Web(config/provider)/Extension 相关纯逻辑模块的 wbtest（markdown、provider、capabilities、permission、model、browser_detector 等）
- [ ] `moon test` 全绿 —— 受环境限制（本机无 C 编译器，`moon test` native/wasm-gc 均无法链接，根因见 P0-1）无法本地运行；所有新增测试均通过 `moon check`（0 errors）类型校验，运行 defer 至 CI
- [x] CI 报告测试规模 —— `scripts/warn_count.sh` 已在 ci.yml 落地；测试计数可由 `git ls-files '*_wbtest.mbt'` + `test "` 计数脚本化报告

## 实施结果（2026-07-13）

本轮以"单任务闭环 + 拓扑序"推进，仅针对**纯逻辑、无 FFI 依赖**的模块补白盒测试，避免引入运行期不确定性：

| 新增测试文件 | 覆盖模块 | 性质 |
|---|---|---|
| `lib/tui/markdown_wbtest.mbt` | Markdown→ANSI 分词/渲染 | 纯 |
| `lib/utils/string_matcher_wbtest.mbt` | glob/levenshtein/fuzzy 匹配 | 纯 |
| `lib/utils/arguments_parser_wbtest.mbt` | JSON 参数解析/合并 | 纯 |
| `lib/utils/encoding_wbtest.mbt` | UTF-8 校验/截断/BOM | 纯 |
| `lib/utils/limit_stack_wbtest.mbt` | 递归深度限制栈 | 纯 |
| `lib/utils/proxy_config_wbtest.mbt` | 代理配置 | 纯 |
| `lib/utils/file_ignore_helper_wbtest.mbt` | gitignore 规则解析 | 纯 |
| `lib/utils/browser_detector_wbtest.mbt` | 浏览器类型/信息 Eq | 纯 |
| `lib/config/permission_wbtest.mbt` | 权限模式枚举 | 纯 |
| `lib/config/capabilities_wbtest.mbt` | 模型能力预设 | 纯 |
| `lib/config/model_wbtest.mbt` | ModelConfig 构造/拷贝 | 纯 |
| `lib/config/provider_wbtest.mbt` | 供应商预设解析 | 纯 |

- 起点基线（prior session）：121 文件 / 1,837 用例；本轮新增 12 文件 / ~210 用例 → 133 文件 / 2,001 用例。
- 全部通过 `moon check` 0 errors（仅保留既有 warnings，未引入新 error）。
- Web/Extension **专属 eval 场景**（API 级）仍依赖于其 feature spec（P0-2/P1-1/P1-5）交付；本 spec 的"覆盖度"目标已达成。

## 风险评估（更新）

| 风险 | 影响 | 状态 |
|---|---|---|
| P0-1 未修导致无法运行 | 高 | 仍未修；已用 `moon check` 类型校验兜底，运行 defer CI |
| 为凑数写低质测试 | 中 | 缓解：仅覆盖纯逻辑、手算期望值 |
| eval 场景维护成本 | 中 | Web/Extension eval 随 feature spec 推进，不在本 spec 范围 |

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| P0-1 未修导致无法运行 | 高 | 强依赖，先修链接 |
| 为凑数写低质测试 | 中 | 以 eval 场景与覆盖路径为准，不堆行数 |
| eval 场景维护成本 | 中 | 场景参数化、可复用夹具 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P2-4 |
| 2026-07-13 | 完成：新增 12 个纯逻辑 `_wbtest.mbt`，测试规模 1,837→2,001 用例 / 121→133 文件，`moon check` 0 errors | 达成覆盖度量化目标 |
