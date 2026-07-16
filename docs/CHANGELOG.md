# MBOpenClacky 项目变更日志

> 记录项目每次完成的重要功能、Bug 修复及关键重构，便于回顾每日工作进展。

---

## 格式说明

```
### YYYY-MM-DD  标题
- [类型] 变更描述
  - 详细说明（可选）
```

类型标签：
- `[feat]` — 新功能
- `[fix]` — Bug 修复
- `[refactor]` — 代码重构
- `[perf]` — 性能优化
- `[test]` — 测试相关
- `[docs]` — 文档相关
- `[chore]` — 工程配置 / 依赖 / CI

---

## 变更记录

### 2026-07-16  docs: 项目文档全量校准（指标同步与过时内容清理）

- `[docs]` **核心指标全量同步（基于实际统计）**
  - 源文件数：289 → **309** 个 `.mbt`（lib + cmd）
  - 测试文件：93 → **103** 个 `_wbtest.mbt`（lib + cmd + test）
  - 包数：23 → **24** 个 lib 顶级包（新增 `lib/zip`）+ 1 个 cmd 入口包
  - REST API 端点数：统一为 **~154**（修正 `codemaps/web.md` 等处的 "90+" 不一致表述）
  - 整体完成度：~90-92% → **~95%**（Web 前端 ~65%→95%、TUI ~85%→95%）
  - 原生二进制大小：~4.6 MB → **~3.8 MB**；`moon check` warnings：46 → **~500**
- `[docs]` **功能状态更新**
  - Web 前端：已由原生 JS 重写为 **MoonBit SPA**（`web/mb/` → `web/dist/`），所有管理面板与 i18n（692 key，覆盖率 99.4%）就位
  - TUI：Rich Dialogs / Agent Shell / Thinking Live View 已完成（异步事件循环 + Node 渲染）
  - Extension 框架：Loader/Verifier/Packager/Scaffold/Marketplace、API 扩展路由分发/热重载、PatchLoader/HookLoader、CLI 命令、Session ZIP 导出导入均已完成
- `[docs]` **受影响文件**：README.md、CLAUDE.md、docs/project-status.md、docs/gap_analysis_and_development_plan.md、codemaps/web.md
- `[docs]` **lib/extension/README.md 重写**：原文仍称 "MVP / Next Steps: 实现 loader/verifier/packager…"，实际框架已全部实现，更新为完整功能描述

### 2026-07-15  feat: i18n 翻译补齐与 Spec 归档

- `[feat]` **i18n 翻译补齐完成**（基于增量 Spec `2026-07-13_05_i18n-complete-translation.md`）
  - 英文词典：从 733 keys 去重后更新为 692 keys
  - 中文词典：从 735 keys 去重后更新为 692 keys，补齐 210+ 个缺失翻译
  - 翻译覆盖率：99.4%（英文和中文均为 99.4%）
  - 中英文词典对称性：100%（两个词典 key 集合完全一致）
- `[docs]` **Spec 归档**：`2026-07-13_05_i18n-complete-translation.md` 从 `specs/active/` 移动至 `specs/completed/`
  - 状态更新：开发中 → 已完成
  - 验收标准全部勾选
  - 添加详细验收报告（含关键指标、主要改动、修改文件、工具支持）
- `[chore]` **i18n 维护工具脚本**：创建 4 个工具脚本并移动至 `scripts/` 目录
  - `extract_i18n_keys.ps1` - 翻译 key 提取与差异分析工具
  - `verify_translation_coverage.py` - 翻译覆盖率验证工具
  - `dedup_zh_dict.py` - 字典去重工具
  - `check_zh_keys.py` - 中英文词典对称性检查工具
  - 详细说明见 `scripts/README_i18n_tools.md`

### 2026-07-13  docs: 全量文档指标同步与精简

- `[docs]` **项目指标全量同步**（基于实际统计）
  - 源文件数: 248 → 258，测试文件: 67 → 73
  - 源码行: ~55,700 → ~54,400，测试行: ~18,600 → ~17,400，总行: ~75,700 → ~73,200
  - 默认技能: 17 → 16（代码实际注册数）
  - `moon check` warnings: ~488 → ~522
  - 统一 REST API 端点描述为“90+”（消除“127”不一致）
- `[docs]` **受影响文件**：CLAUDE.md、README.md、docs/project-status.md、docs/getting-started.md、codemaps/README.md、codemaps/web.md、codemaps/skill.md
- `[docs]` **codemaps/skill.md 修正**：默认技能清单从 15 个更正为 16 个，补充完整技能名列表，修正“仅资源目录”为 `extend-openclacky` + `meeting-summarizer`

### 2026-07-13  docs: 合并废弃文档并同步实际状态

- `[docs]` **合并并删除 2 个过时文档**
  - `docs/brand-crypto-migration.md`：品牌加密升级迁移说明并入 `docs/getting-started.md`（新增「品牌加密与密钥派生」章节：PBKDF2-HMAC-SHA256 100,000 轮、升级后重新激活步骤、弱桩路径安全约束）
  - `docs/project_gap_analysis_and_development_plan.md`：差距分析结论已沉淀至 `docs/project-status.md`，不再单独保留
- `[docs]` **getting-started.md 同步实际状态**
  - 修正 `-lcurl` 描述：`lib/client/moon.pkg` 已默认启用 `-lcurl`（此前文档称需手动取消注释）
  - 修正 Windows brand 加密局限：Windows 已接入 BCrypt/CNG（`crypto_native.c`），弱桩仅存在于 `MBOPENCLACKY_NO_OPENSSL` 调试构建（编译期 `#error` + CI `check-crypto-build` 双重拦截）
- `[docs]` **引用修复**：`specs/README.md`、`specs/completed/2026-07-09_gap-driven-task-breakdown-overview.md` 将差距分析文档引用改为 `docs/project-status.md`
- `[docs]` **project-status.md**：P2「Brand crypto 弱桩路径构建期阻断」已落地，从短期目标移除

### 2026-07-12  docs: Spec 归档与文档同步更新

- `[docs]` **Spec 归档（Harness 方法论流程）**
  - 归档 3 份 spec 从 `specs/active/` 到 `specs/completed/`：
    - `2026-07-09_wasm-gc-target-feasibility.md` — 可行性评估完成，决策暂缓（根因：`moonbitlang/async` 缺 wasm-gc 支持）
    - `2026-07-09_web-api-contract-alignment.md` — 6 个端点全部实现，契约对照表完成，wbtest 已补齐
    - `2026-07-07_priority-analysis-and-specs-overview.md` — 决策文档，优先项已由后续 spec 覆盖
  - 14 份 spec 保留在 `specs/active/`（讨论中/实施中/待评审）
- `[docs]` **project-status.md 同步更新**
  - 移除已过时的已知问题：`derive_key` PBKDF2（已实现）、Windows BCrypt（已实现）、TUI Phase 6（已完成）
  - 更新 brand 模块完成度 80% → 90%、web 模块完成度 70% → 75%
  - 更新 wasm-gc 状态为“已评估，建议暂缓”
  - 更新短期目标对齐当前 gap-driven 任务划分
- `[docs]` **CHANGELOG.md**：补充本次归档记录

### 2026-07-08  docs: 文档合并精简

- `[docs]` **docs/ 目录精简**：10 → 3 个文档
  - 删除 5 个过时文档：`cli-interface-assessment-review-0629.md`、`compiler-error-efficiency-report.md`、`gap-analysis-between-projects-2026-06-30.md`、`TUI_DEBUG_PLAN.md`、`tui-overhaul-plan.md`
  - 归档 2 个到 specs/：`harness-methodology-application-plan.md` → `specs/decisions/`、`tui-inline-migration-plan.md` → `specs/completed/`
  - 重写 `project-status-and-deployment-guide.md` → `project-status.md`（精简为纯状态文档）
- `[docs]` **docs/ 以外文档同步更新**
  - `README.md`：精简，去掉与其他文档重复的内容，聚焦项目介绍+快速开始
  - `CLAUDE.md`：精简架构速查卡，与 AGENTS.md 分工明确
  - `AGENTS.md`：去重，专注开发规范
  - `codemaps/README.md`：同步最新指标
- `[docs]` **CHANGELOG.md**：补充本次文档合并记录
- 最终文档职责分工：README（介绍）→ getting-started（入门）→ project-status（状态）→ CLAUDE.md（AI 架构速查）→ AGENTS.md（开发规范）→ CHANGELOG（变更历史）

### 2026-07-07  feat(tool): 浏览器工具完善 — 表单交互增强、截图管道、快照压缩
**表单交互增强**：
- scroll 操作改用原生 MCP scroll_page 工具，失败时自动回退到 evaluate_script
- fill 操作增加 focus/blur 事件增强，提升 React/Vue 等框架兼容性
- 新增 escape_js_string 辅助函数，完整转义 JS 字符串特殊字符

**截图管道完善**：
- 支持 format（jpeg/png）和 quality 参数透传到 MCP
- 新增 savePath 自定义保存路径
- 参数 schema 新增 max_width/max_height 预留（TODO）

**快照压缩阈值门控**：
- compress_snapshot 增加 150KB 阈值判断，小快照跳过压缩
- 压缩日志记录三阶段大小（原始 → 去噪 → 合并）

**测试**：新建 browser_wbtest.mbt，18+ 个白盒测试覆盖全部功能
- `[verify]` `moon check` 0 errors，`moon test lib/tool` 85 tests 全部通过

### 2026-07-07  Phase 26 Web 管理面板后端全量实现（8 个面板 · 72 handler · 2,741 行）

- `[feat]` **实现全部 8 个 Web 管理面板后端 handler**（从 stub 到真实实现）
  - **Trash**（`handlers_trash.mbt`，325 行，9 handler）— 统一回收站系统：批量恢复/删除、类型过滤、过期追踪
  - **Git**（`handlers_git.mbt`，305 行，5 handler）— 完整 Git 操作：status/diff/stage/commit/push/pull/branch 管理，通过 C FFI（`git_exec.c`）执行 shell 命令
  - **MCP**（`handlers_mcp.mbt`，221 行，5 handler）— MCP 服务器 CRUD、工具列表与执行，通过 McpRegistry 集成
  - **Schedules**（`handlers_schedules.mbt`，451 行，11 handler）— Cron 定时任务 CRUD、手动触发、执行历史，与 Scheduler 集成
  - **Channels**（`handlers_channels.mbt`，410 行，8 handler）— 6 平台 IM 适配器 CRUD、连通性测试
  - **Backup**（`handlers_backup.mbt`，527 行，17 handler）— 文件快照创建/恢复/删除，文件系统持久化
  - **Billing**（`handlers_billing.mbt`，316 行，8 handler）— BillingStore 集成、套餐激活、用量导出
  - **Browser**（`handlers_browser.mbt`，186 行，9 handler）— BrowserManager 集成（预存实现）
  - 合计：**2,741 行后端代码，72 个 handler 函数，零 stub/TODO 残留**
- `[fix]` **构建与类型修复**
  - 修复 `lib/web/moon.pkg` 损坏的换行符
  - 修复 billing handler 中的元组类型错误
  - 修复 schedules handler 中的未使用 mut 和 Map API 问题
  - 新增 Git 面板 C FFI（`git_exec.c`）用于 shell 命令执行
- `[verify]` `moon check` 最终验证：0 errors

### 2026-07-06  Phase 25 CI/CD 流水线建设 + Harness 方法论落地 + Codemaps 生成

- `[chore]` **GitHub Actions CI 流水线** — 新建 `.github/workflows/ci.yml`（67 行）
  - PR + main push 自动触发 `moon check` + `moon build --target native --release cmd` + `moon test`
  - MoonBit 工具链缓存（`~/.moon/`，按 OS+v1 做 key）
  - 项目依赖缓存（`.mooncakes/`，按 `moon.mod` hash 做 key）
  - 缓存命中时跳过安装步骤，目标将 CI 总耗时从 ~3-5 分钟降低到 ~1-2 分钟
- `[chore]` **Docker 镜像自动构建** — 新建 `.github/workflows/docker.yml`（45 行）
  - 仅 main push 触发，使用现有 Dockerfile 多阶段构建
  - `docker/build-push-action@v6` + `docker/metadata-action@v5` 自动 tag（commit SHA + latest）
  - GHA layer cache 加速构建
- `[chore]` **Harness 方法论落地**
  - 新建 `specs/` 目录结构：`_templates/`（idea-doc / incremental-spec / task-package 3 个模板）、`active/`、`completed/`、`decisions/`
  - 首个 spec `2026-07-06_cicd-pipeline.md`（启动 spec）已创建并完成 3 个任务包（base-pipeline / docker-automation / cache-optimization）
  - 所有 CI/CD spec 已归档至 `specs/completed/`
- `[docs]` **Codemaps 代码地形索引** — 新建 `codemaps/` 目录（10 个核心包）
  - agent / client / tool / skill / mcp / channel / server / web / tui / config
  - 每个 codemap 含入口函数、关键类型、核心调用链、外部依赖、风险点
- `[docs]` **全量文档校准**
  - 更新指标数据：272 源文件 / ~56,951 源码行 / ~74,410 总行数 / 17 默认技能
  - 部署基础设施完成度从 ~30% 调整为 ~50%（CI/CD 已搭建）
  - 删除已被取代的 `gap-analysis-between-projects-0627.md`，新版加弃用提示
  - 历史文档加状态标注
- `[chore]` 整体完成度从 ~85-90% 调整为 ~87-92%
- `[verify]` `moon check` 最终验证：0 errors, 426 warnings

### 2026-07-03  Phase 24 功能扩展与文档同步

- `[feat]` **Terminal 工具 PTY 执行**
  - 新增 `lib/tool/pty.mbt` / `pty_unix.mbt` / `pty_windows.mbt` / `pty_stubs.c`
  - 支持交互式命令会话（`session_start/session_send/session_read/session_close`），Mac/Linux 基于 posix_openpt，Windows 使用 CreateProcess + 命名管道
- `[feat]` **Web API 扩展**
  - 新增汇率换算 (`handlers_exchange_rate.mbt`)
  - 新增本地图片处理 (`handlers_local_image.mbt`)
  - 新增媒体生成端点 (`handlers_media.mbt`)
  - 新增 OCR 文本识别端点 (`handlers_ocr.mbt`)
  - 新增 onboarding (`handlers_onboard.mbt`) 和版本信息 (`handlers_version.mbt`) 端点
  - REST API 端点总数从 68+ 增长到 **90+**
- `[feat]` **MCP 技能提供方**
  - 新增 `lib/mcp/skill_provider.mbt` / `lib/mcp/virtual_skill.mbt`
  - 将 MCP 工具暴露为 OpenClacky 技能，支持通过技能系统调用 MCP 服务器
- `[feat]` **TUI 视觉增强**
  - 新增 `lib/tui/block_font.mbt` — 标题/横幅大字体渲染
  - 新增 `lib/tui/thinking_verbs.mbt` — 动态思考状态动词提示
- `[feat]` **默认技能扩展**
  - `lib/skill/default_skills.mbt` 内置技能从 11 个扩展到 **16 个**
  - 新增 `browser-setup`、`channel-manager`、`cron-task-creator`、`mcp-manager`、`media-gen`、`obsidian-note-writer` 等技能
- `[chore]` **libcurl 链接依赖**
  - `lib/client/moon.pkg` 中 `-lcurl` 当前默认被注释；运行 native 测试或需要 HTTP 客户端时，需安装 libcurl-dev 并取消注释
- `[docs]` **项目文档全量同步**
  - 更新 `CLAUDE.md`、`README.md`、`AGENTS.md`、`docs/getting-started.md`、`docs/project-status-and-deployment-guide.md`、`docs/CHANGELOG.md`
  - 修正 TUI 依赖库名称（`moonbit-community/tty`）
  - 刷新项目指标：248 源文件、62 测试文件、~70,269 总代码行、1,400+ 测试用例、16 默认技能、90+ REST 端点、429 warnings

### 2026-07-01  Eval 框架全局重构
- `[refactor]` **Eval 框架从 `lib/tui/` 提取到独立的 `test/` 包体系**
  - 新建 `test/eval/eval_engine.mbt` (96行) — 通用 eval 引擎：结果类型 + 文件加载 + 报告格式化
  - 新建 `test/eval/eval_engine_wbtest.mbt` (77行) — 引擎单元测试 4 个
  - 新建 `test/tui/virtual_screen.mbt` (328行) — 从 `lib/tui/` 迁移
  - 新建 `test/tui/tui_eval_adapter.mbt` (570行) — 合并原 eval_scenario.mbt + eval_runner.mbt，使用 `@eval.EvalScenarioResult` 等通用类型
  - 新建 `test/tui/virtual_screen_wbtest.mbt` (132行) + `tui_eval_adapter_wbtest.mbt` (153行) — 迁移测试
  - 迁移 `assets/evals/tui/*.json` → `test/scenarios/tui/`
- `[chore]` **清理 `lib/tui/` eval 文件和依赖**
  - 删除 5 个文件：virtual_screen.mbt、eval_scenario.mbt、eval_runner.mbt、virtual_screen_wbtest.mbt、eval_runner_wbtest.mbt
  - `lib/tui/moon.pkg` 移除 json/fs/path 三个依赖
- `[chore]` **更新 `cmd/` 引用**
  - `cmd/moon.pkg` 添加 `test/eval` + `test/tui` 依赖
  - `cmd/main.mbt` `handle_tui_eval()` 改用 `@test_tui.run_eval_scenarios()` + `@eval.format_eval_report()`
- `[docs]` **更新 AGENTS.MD、project-status、CHANGELOG**

**架构设计要点**：
- 三层架构：`test/eval/`（通用引擎）→ `test/tui/`（插件式适配层）→ `test/scenarios/`（场景定义）
- 对 `lib/` 业务代码零侵入，通过 `pub(all)` API 驱动
- 可扩展至其他模块：在 `test/{module}/` 创建适配器，返回 `@eval.EvalScenarioResult` 即可接入统一报告

### 2026-07-01  Browser 模块拆分重构 + Vision OCR + 安装脚本增强

- `[refactor]` **Browser 模块拆分为 5 个职责单一的文件**
  - `browser.mbt` 从 ~900 行瘦身到 ~507 行，保留核心类型、MCP 调用、响应解析
  - `browser_action.mbt` (99行) — Action 分发、状态查询、错误分类
  - `browser_mcp_args.mbt` (265行) — MCP 工具参数构建器
  - `browser_page.mbt` (149行) — 页面缓存、错误恢复、就绪轮询
  - `browser_screenshot.mbt` (167行) — 截图管道（base64 提取/保存/尺寸检查）
  - `browser_snapshot.mbt` (239行) — 快照压缩/截断/查询/行合并
- `[feat]` **Vision OCR 模块** — `lib/vision/ocr.mbt` (122行)
  - `OCRResult` 结构体、`OCRProvider` trait（扩展点）、`VisionOCR` 实现
  - `count_ocr_words` 单词计数、`ocr_wbtest.mbt` (96行) 8 个测试
- `[feat]` **PDF OCR 回退** — `lib/parser/pdf.mbt` 新增 `parse_with_ocr` 方法
  - 文本提取产出 < 50 词时自动回退到 Vision LLM OCR
  - `lib/parser/moon.pkg` 添加 `lib/vision` 依赖
- `[feat]` **默认技能扩展** — `lib/skill/default_skills.mbt` 新增 5 个技能
  - `browser_setup` / `channel_manager` / `new` / `personal_website` / `skill_add`
- `[feat]` **安装脚本增强**
  - `install.ps1`：新增 `-AutoInstall` / `-ChinaMirror` / `-Target` 参数、MoonBit 自动安装、版本解析
  - `install.sh`：新增 `--yes` / `--install-moon` / `--target` / `--china-mirror` 参数、OS 检测、自动安装
- `[fix]` **对抗性审查修复**
  - `browser_screenshot.mbt`：base64 解码失败不再写入空文件，改为返回内联引用
  - `pdf.mbt`：`parse()` 完全失败时短路返回，不再浪费 OCR 调用
  - `install.sh`：`add_to_path` PATH 检测改用 `:PATH:` 包裹匹配，消除子串误判
  - `ocr.mbt`：`OCRProvider` trait 补充用途说明注释
  - `install.ps1`：消除 ChinaMirror 两分支 URL 相同的误导性逻辑
- `[verify]` `moon check` 最终验证：0 errors, 323 warnings


### 2026-07-01  TUI 布局修复：Yoga 引擎替换 + 视觉层次对齐

- `[fix]` **根因定位：onebit-yoga 的 yoga_stubs.c 是空桩，所有子节点坍塌到 (0,0)**
  - `onebit-yoga` 提供的 `yoga_stubs.c` 中 `YGNodeCalculateLayout` 返回全零布局（top=0, left=0, width=0, height=0）
  - Yoga 布局引擎在 Flexbox 列布局下，父节点无明确高度 → 子节点 flex(1.0) 被解析为 0 → 所有组件（状态栏/输入框/按钮/占位符）堆叠在终端左上角
  - 表现为截图中文字交叠（`stimated)00t yetP%P%P%P%...`）和 Submit/Quit 按钮乱入
- `[fix]` **替换为真实 Facebook Yoga 引擎**
  - `scripts/setup_yoga.sh` — 编译脚本：下载 Facebook Yoga 2.0.2 C++ 源码 + C wrapper（`vendor/yoga/`），构建 `libyoga_full.a` 静态库
  - `cmd/moon.pkg` / `lib/tui/moon.pkg` — 添加 `-lyoga_full -lstdc++` 链接标志
  - `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` — 从 native-stub 中移除空桩 yoga_stubs.c
  - 构建产物：`vendor/yoga/lib/libyoga_full.a`（~408KB）
- `[fix]` **根布局约束修复** — `lib/tui/tui.mbt` `build_main_layout`
  - 根 Column 容器添加 `.width(terminal_width.to_double())` 和 `.height(terminal_height.to_double())`，强制撑开全屏
  - 消息视图 `message_view_render` 改为从终端高度计算可见行数 + 自动滚动
  - `lib/tui/message_view.mbt` — `message_view_render` 重写：`max_visible_lines` 基于终端高度动态计算
- `[fix]` **状态栏重构** — `lib/tui/status_bar.mbt` (42 行重写)
  - 从顶部移至底部（输入栏上方），更接近源项目 Inline TUI 的视觉习惯
  - 显示内容：Agent 状态 / 模型名 / 迭代次数 / 工作目录 / 权限模式 / 活跃任务数
  - 颜色映射：running→Green / error→Red / completed→Blue / 其他→Gray
- `[feat]` **TuiState 扩展** — `lib/tui/state.mbt`
  - 新增字段：`working_dir : String`、`permission_mode : String`、`active_tasks : Int`
  - `from_agent` 工厂方法同步新增字段
- `[feat]` **Agent Hooks 增强** — `lib/tui/agent_hooks.mbt`
  - RunCompleted 事件中同步 `working_dir`、`active_tasks` 到 TuiState
- `[test]` **布局回归测试** — `lib/tui/tui_layout_wbtest.mbt` (94 行)
  - 验证：容器子节点 Y 轴偏移递增不重叠（Flex 列布局正确展开）
  - 验证：flex(1.0) 子节点获得正高度（弹性空间分配正确）
  - 验证：固定高度子节点不被压缩
- `[fix]` **构建依赖补充**
  - `lib/agent/moon.pkg`、`lib/client/moon.pkg`、`lib/tool/moon.pkg`、`lib/vision/moon.pkg` — 添加 `-lcurl` 链接标志（test 二进制链接 lib/client 需要 libcurl）
- `[verify]` **全量验证通过**
  - `moon check`：0 errors
  - `moon test --target native`：1,355 / 1,355 通过（+14 新测试）
  - TUI 交互验证：在 tmux 终端中运行 `_build/native/debug/build/cmd/cmd.exe`，确认渲染 OpenClacky / AI Agent TUI 欢迎横幅 + 输入栏，按 `q` 正常退出


### 2026-06-30  Phase 23 部署阻碍修复 + 文档全量校准 + 全量测试通过
- `[fix]` **P0/P1 级测试失败全部修复 — 1,341 / 1,341 测试通过（100%）**
  - 此前 gap analysis 标记的 4 项测试失败已全部解决：
    - `brand/crypto`：AES-256-GCM C FFI（OpenSSL native stub）修复 — `lib/brand/crypto_native.c` 实现 EVP AES-GCM 加解密 + RAND_bytes CSPRNG，72 个 brand 测试全过
    - `session_registry`：线程安全会话注册表逻辑修复 — `lib/server/session_registry_wbtest.mbt` 全过
    - `mcp/types`：`JsonRpcRequest` 的 `to_json` 序列化字段映射修复 — `lib/mcp/types.mbt` 修正
    - `web/static_server`：静态文件/SPA fallback 测试修复 — `lib/web/static_server.mbt` 实现真实文件系统读取 + SPA 回退
  - 测试用例从 1,254 增长到 **1,341**（+87），失败数从 13 降至 **0**
- `[fix]` **C FFI 链接问题排查与修复（moon #1488 + #1595）**
  - 根因：`lib/brand` 包含 `link: {}` 块触发 moon #1488 — moon 尝试将库包链接为独立可执行文件，因无 `main` 失败
  - cc-link-flags 不跨包传播（moon #1595），需在 `cmd/moon.pkg` 和 `lib/brand/moon.pkg` 各自声明 `-lcrypto`
  - `cmd/moon.pkg` 添加 `-Wl,--no-as-needed -lcrypto -Wl,--as-needed`，确保最终 cmd.exe 强制 NEEDED libcrypto.so.3
  - 构建命令改为 `moon build --target native --release cmd`（显式指定 cmd 包，绕过 brand.exe 误链接）
  - 验证 `readelf -d` 和 `ldd` 确认 libcrypto.so.3 正确链接
- `[fix]` **Dockerfile 完整重写**
  - 构建产物路径修正：`_build/native/release/build/cmd/cmd.exe`（原为错误的 debug 路径 `cmd/cmd`）
  - Builder 阶段安装 `libssl-dev`（链接 -lcrypto 所需）
  - Runtime 阶段安装 `libssl3`（运行时 libcrypto.so.3 所需）
  - 构建命令改为 `moon build --target native --release cmd`
  - COPY `moon.mod`（非 moon.mod.json，已确认文件名）
- `[feat]` **Web 服务端口统一为 7070**
  - `cmd/main.mbt`：硬编码 `server.start(4000)` 改为读取 `MBOPENCLACKY_WEB_PORT` 环境变量（默认 7070）
  - 兼容原版 OpenClacky 的用户习惯
  - `cmd/moon.pkg`：添加 `moonbitlang/core/strconv` import（用于端口解析）
- `[docs]` **全量文档校准**
  - `README.md`：更新全部项目指标（275 源文件 / 49 测试文件 / ~48,555 源码行 / 1,341 测试 / 323 warnings / 27 包）；新增"核心技术优势"章节（AOT / 静态类型 / struct+trait / GEP）；新增"已知问题与开发计划"章节
  - `docs/project-status-and-deployment-guide.md`：更新状态快照、Docker 部署指南（端口 7070）、Windows 构建验证表、测试覆盖差距表；新增"运维现状与规划"章节（CI/CD / systemd / docker-compose / 日志轮转）
  - `docs/getting-started.md`：更新构建命令（`moon build --target native --release cmd`）、端口说明（7070）、安装脚本局限性说明、前置依赖清单（OpenSSL）、moon #1488 故障排除
- `[verify]` 最终验证：`moon check` 0 errors / 323 warnings；`moon test` 1,341 / 1,341 通过


### 2026-06-30  Ruby → MoonBit 核心架构重构总结

> 以下为从 Ruby 到 MoonBit 的核心架构重构决策记录，贯穿 Phase 0-23 全周期。

- `[refactor]` **包粒度细化至 27 个**
  - Ruby 原项目以 mixin 隐式组织，模块边界模糊（如 `agent.rb` 70KB 含 11 个 mixin）
  - MoonBit 版本拆分为 27 个包（21 个 lib 顶级包 + 4 个 web 子包 + 1 个 lib 根包 + 1 个 cmd 入口包）
  - 每个包职责单一，通过 `pub` / `pub(open)` / `pub(all)` 三级可见性控制模块边界
- `[refactor]` **Checked Error 错误处理体系**
  - Ruby 使用分散的 `rescue` 捕获异常，错误路径不可追踪
  - MoonBit 使用 `raise` / `try ... catch` 编译期可追踪错误传播
  - 建立完整错误类型层次：`AgentError` / `BadRequestError` / `ToolCallError` / `RetryableError` / `UpstreamTruncatedError` / `AgentInterrupted` / `BrowserNotReachableError`
  - `is_agent_error()` / `is_retryable_error()` 谓词用于 catch-all 匹配
- `[refactor]` **消除 nil 访问风险**
  - Ruby 大量使用 `nil` 和 duck typing，运行期 `NoMethodError` 频发
  - MoonBit 使用 `Option[T]` 取代 `nil`，所有可选值在类型层面显式标注
  - 使用 `enum` / `struct` 代数数据类型取代 duck typing，编译期消除整类错误
- `[refactor]` **`struct + trait` 替代 Ruby mixin**
  - Ruby `agent` 模块依赖 11 个 mixin，调用关系隐式且易冲突
  - MoonBit 通过显式 trait 实现与组合（如 `Tool` trait + 14 个内置工具各自实现）
  - `AnyTool` 枚举分发替代 trait object，零开销且类型安全
- `[refactor]` **AOT 原生编译 — 零运行时依赖**
  - Ruby 需 VM + Bundler + Gem 依赖，启动延迟数百毫秒
  - MoonBit native 后端 AOT 编译为单一可执行文件（release ~3.8MB），启动毫秒级
  - 构建命令 `moon build --target native --release cmd` 产出可直接分发的二进制
- `[refactor]` **Hook 驱动 UI 同步（ADR-3）**
  - TUI 和 Web UI 通过 Hook 事件系统订阅 Agent 生命周期事件，解耦 UI 层与 Agent 内部
  - `HookManager::register(cb)` / `HookManager::emit(event)` 观察者模式
  - 7 种 Shell Hook 事件 + 10+ 种 Agent 生命周期事件
- `[refactor]` **AnyAdapter 枚举替代 trait object（IM 渠道）**
  - 6 平台 IM 适配器使用 enum-based type erasure（非 trait object）
  - 零开销分发，编译期穷尽匹配
- `[refactor]` **GEP 技能自进化系统**
  - Ruby 技能系统为静态预定义（SKILL.md）
  - MoonBit 版本引入 EvolutionEngine + SkillReflector（执行后反思）+ AutoCreator（模式检测自动创建）
  - 34 个演进测试用例验证


### 2026-06-30  已完整对齐的功能模块

> 以下模块已与 Ruby 原版功能对齐（行数比率 ≥ 1.0x 或功能完整度 ≥ 90%）。

| 模块 | Ruby 行数 | MoonBit 行数 | 比率 | 完整度 | 对齐状态 |
|------|----------|-------------|------|--------|---------|
| agent | 4,823 | 8,573 | 1.78x | 95% | ✅ 已超越 |
| billing | 371 | 691 | 1.86x | 100% | ✅ 已超越 |
| brand | 1,352 | 2,014 | 1.49x | 50%+ | ✅ 已超越（加密已修复） |
| channel | 4,757 | 9,529 | 2.00x | 100% | ✅ 已超越 |
| client | 1,916 | 4,211 | 2.20x | 100% | ✅ 已超越（3 协议） |
| config | 739 | 1,904 | 2.58x | 90% | ✅ 已超越 |
| errors | — | 149 | — | 100% | ✅ MB 新增 |
| hook | 50 | 344 | 6.88x | 100% | ✅ 已超越 |
| mcp | 790 | 1,212 | 1.53x | 95% | ✅ 已超越 |
| media | 921 | 1,285 | 1.40x | 90% | ✅ 已超越 |
| message | 821 | 1,171 | 1.43x | 100% | ✅ 已超越 |
| parser | 607 | 1,636 | 2.70x | 100% | ✅ 已超越 |
| pricing | 743 | 1,008 | 1.36x | 100% | ✅ 已超越 |
| skill | 1,876 | 1,937 | 1.03x | 85% | ✅ 已超越 |
| telemetry | 143 | 385 | 2.69x | 100% | ✅ 已超越 |
| tool | 5,384 | 5,225 | 0.97x | 90% | ✅ 基本对齐 |
| utils | 3,054 | 3,944 | 1.29x | 95% | ✅ 已超越 |
| vision | 138 | 538 | 3.90x | 80% | ✅ 已超越 |

**待持续改进的模块**（行数比率 < 1.0x 或功能完整度 < 80%）：

| 模块 | Ruby 行数 | MoonBit 行数 | 比率 | 完整度 | 差距说明 |
|------|----------|-------------|------|--------|---------|
| server | 13,983 | 3,593 | 0.26x | 60% | 运维功能差距，需补齐进程管理/监控 |
| tui/ui2 | 8,944 | 4,605 | 0.52x | 50%+ | TUI 组件待增强 |
| web | 33,888 | 5,672 | 0.17x | 40-50% | REST API 68+ 已实现，前端 SPA 待完善 |
| cmd | 1,322 | 1,016 | 0.77x | 60%+ | CLI 入口基本对齐 |

**此前标记为"待修复"的测试失败项 — 全部已解决 ✅**：

| 测试项 | 原严重度 | 修复日期 | 修复方式 | 当前状态 |
|--------|---------|---------|---------|---------|
| `brand/crypto`（AES-GCM C FFI） | P0 | 2026-06-30 | OpenSSL native stub 实现 | ✅ 72 测试全过 |
| `session_registry` | P0 | 2026-06-30 | 线程安全逻辑修复 | ✅ 全过 |
| `mcp/types`（JsonRpcRequest 序列化） | P1 | 2026-06-30 | to_json 字段映射修正 | ✅ 全过 |
| `web/static_server`（SPA fallback） | P1 | 2026-06-30 | 真实文件系统读取 + SPA 回退 | ✅ 全过 |


### 2026-06-30  Native 编译环境修复 + TUI Windows 渲染修复
- `[fix]` **Native 编译环境修复（Windows MSVC 兼容）**
  - `fix(build)`: 移除 `moon.mod` 全局 `-lcurl -lssl -lcrypto` 链接标志（Windows MSVC 不兼容 `-l` 语法，导致 LNK1181 错误）
  - `fix(build)`: 添加 `MB_WEAK` 跨编译器兼容宏（`brand_stubs.c`、`mb_stubs.c`）—— MSVC 下为空宏，GCC/Clang 保留 `__attribute__((weak))`
  - `fix(build)`: MSVC 条件编译排除与 `onebit-tui` 冲突的 curl stub 函数（`#ifndef _MSC_VER` 守护）
  - `fix(build)`: `lib/tool` 添加 `Frank-III/onebit-tui/ffi` 依赖，解决 `mb_system` 等标准符号链接问题
  - `feat(install)`: `install.ps1` 新增 vswhere 动态检测 + vcvarsall.bat 自动 MSVC 激活
  - `docs`: 各包 `moon.pkg` 改进 Linux/macOS 链接配置说明
- `[fix]` **TUI Windows 渲染修复**
  - `fix(tui)`: 修复 Windows VT Processing 时序——在 `createRenderer` 发送 ANSI 序列前启用 VT 处理
  - `fix(tui)`: 修复 `setupTerminal` C stub 签名与 MoonBit FFI 声明对齐（添加 `useAlternateScreen` 参数）
  - `fix(tui)`: 修复 `render()` 行尾清除（添加 `\033[K`）防止前帧残留
  - `fix(tui)`: 修复 TextBuffer 系列 FFI 签名不匹配（`createTextBuffer`、`textBufferSetSelection`、`bufferDrawTextBuffer`、`textBufferWriteChunk`）
  - `fix(tui)`: 修复 `sym()` Windows 实现（`return NULL` → `GetProcAddress` 真实符号查找）
  - `fix(tui)`: 修复 `buf_free` 对嵌入式结构体成员的 `free()` 未定义行为
  - `feat(tui)`: Banner 和 InputBar 组件自适应终端宽度


### 2026-06-26  Phase 22 差距填补方案启动实施

- `[feat]` **HTTP 服务器安全与广播基础设施**
  - 新增 `lib/web/middleware/error_envelope.mbt` — 统一错误信封响应
  - 新增 `lib/web/middleware/timeout.mbt` — 分层超时中间件
  - 新增 `lib/web/broadcast/hub.mbt` — WebSocket 广播集线器
  - 新增 `lib/web/template_processor.mbt` — 静态模板预处理器
  - 升级 `lib/web/middleware/auth.mbt` — 常量时间比较、Bearer/Query/Cookie 认证回退、IP 限制、回环绕过
  - 升级 `lib/web/handlers.mbt` / `server.mbt` / `sse/sse.mbt` — 广播、SSE 流式增强集成
  - 新增约 1,600+ 行代码
- `[feat]` **浏览器工具深度增强**
  - 升级 `lib/tool/browser.mbt` — 多标签管理、高级表单交互、截图/快照压缩、页面缓存与重试
  - 升级 `lib/utils/browser_detector.mbt` — Chrome DevTools 端点检测
  - 新增约 450+ 行代码
- `[feat]` **AES-GCM 加密 C FFI 脚手架**
  - 新增 `lib/brand/crypto_native.c` — OpenSSL/libcrypto native stub
  - 重构 `lib/brand/crypto.mbt` — HMAC/SHA256 真实实现、AES-GCM 加解密接口
  - 更新 `lib/brand/device.mbt` / `moon.pkg` / `brand_wbtest.mbt`
  - 新增约 360+ 行代码
- `[feat]` **TUI 控制器与输入增强**
  - 新增 `lib/tui/agent_hooks.mbt` — 完整 Agent Hook → UI 更新映射
  - 新增 `lib/tui/progress_stack.mbt` — 进度句柄栈语义
  - 新增 `lib/tui/editor.mbt` — 多行编辑器基础
  - 新增 `lib/tui/command_suggestions.mbt` — 命令建议下拉
  - 新增 `lib/tui/modal_lifecycle.mbt` — 模态生命周期管理
  - 新增 `lib/tui/cjk_width.mbt` — CJK 字符显示宽度
  - 升级 `lib/tui/tui.mbt` / `dialog.mbt` / `input_bar.mbt` / `state.mbt`
  - 新增约 580+ 行代码
- `[docs]` **全量文档校准**
  - 同步 `CLAUDE.md` / `README.md` 指标：源文件 293、源代码行 ~47,105、测试行 ~13,544、测试用例 1,254、完成度 ~85-90%
  - 更新 `moon check` 状态：0 errors, 280 warnings
  - 补充 Phase 22 进行中状态与差距填补计划文档 `docs/gap-filling-solutions-plan-0626.md`
- `[verify]` `moon check` 最终验证：0 errors, 280 warnings


### 2026-06-26  Phase 21 业务功能差距系统性补齐

- `[feat]` **Terminal 工具核心实现** — 从 15% 提升到 60%+
  - 真实命令执行（FFI + temp file）、会话管理器、后台命令
  - 慢命令自动检测（24种模式）、输出溢出处理、命令 echo 去除
  - 新增约 666 行代码
- `[feat]` **消息压缩系统增强** — 从 40% 提升到 80%+
  - Chunk MD 归档、分层摘要（4级）、关键信息提取
  - 空闲压缩定时器、溢出恢复、tool 结果截断
  - 新增约 850 行代码
- `[feat]` **Session Manager 增强** — 从 30% 提升到 70%+
  - 会话分叉、chunk 管理、全文搜索
  - MessageHistory 新增 6 个方法
  - 新增约 392 行代码
- `[feat]` **Agent 配置管理**
  - 模型运行时 ID、虚拟/会话级模型覆盖、媒体模型派生、动态模型切换
  - 新增约 352 行代码
- `[feat]` **Brand 配置系统** — 从 10% 提升到 50%+
  - 真实 TOML IO、许可证激活/心跳、品牌技能 CRUD、免费技能管理
  - 新增约 758 行代码
- `[feat]` **TUI/UI 基础设施** — 从 23% 提升到 50%+
  - 布局管理器、多行编辑器、输出/屏幕缓冲区、模态对话框、侧边栏面板
  - 新增约 1,584 行代码
- `[feat]` **Web 前端组件化** — 从 25% 提升到 60%+
  - 10 个新 feature 模块（品牌/技能增强/个人资料/分享/模型测试/版本/工作区/创建者/通知/引导）
  - 新增约 3,106 行 JS 代码
- `[feat]` **CLI 入口增强** — 从 30% 提升到 60%+
  - NDJSON 日志、补丁加载、Shell Hook 加载、Channel 脚手架、API 扩展加载
  - 新增约 786 行代码
- `[perf]` **编译警告治理**
  - 编译警告从 672 降至 276（减少 396 个）
- `[chore]` **项目指标更新**
  - 源代码行数从 ~34,400 增长到 ~43,157（+25.5%）
  - 总代码行数达 ~56,396，超过 Ruby 源项目（53,355行）
  - 新增/修改约 49 个文件，新增约 8,494 行代码
  - 0 编译错误
- `[verify]` `moon check` 最终验证：0 errors, 276 warnings


### 2026-06-25  Phase 20 文档校准：修正项目指标数据

- `[docs]` **全量文档校准**
  - 修正源文件数: 218 → 194（实际统计）
  - 修正测试文件数: 42 → 43
  - 修正源代码行数: ~39,400 → ~34,400
  - 修正测试用例数: 1,155 → 1,203
  - 修正 moon check warnings: 557 → 556
  - 更新各模块测试数（agent: 184, channel: 187, utils: 138, parser: 73, media: 53, server: 84, web: 87 等）
  - 标记 IM 渠道测试任务为已完成（187 个测试）
  - 修正 MCP 测试数（实际为 0，之前统计有误）
  - 修复 CLAUDE.md 内容重复 bug（移除 2 份重复内容，约 265 行）
  - 更新 README.md / development-plan-0623.md / compiler-error-efficiency-report.md 中的指标数据
- `[verify]` `moon check` 最终验证：0 errors, 556 warnings


### 2026-06-23  Phase 19 文档全面校准：同步项目最新状态指标

- `[docs]` **全量重新校准所有文档**
  - 实际项目指标同步：源文件 194 / 测试文件 43 / 源代码行 ~34,400 / 测试用例 1,203
  - `moon check` 状态：0 errors, 556 warnings
  - Phase 0-18 全部完成，覆盖率 ~97-99%
- `[docs]` **CLAUDE.md 全面重写**
  - 修复文档重复 bug：合并移除重复的旧版内容（200+ 行）
  - 补充 `assets/` 目录树（agents/skills/web）
  - 新增「Current State Metrics」状态汇总表
  - Package Layout 完整列出 21 个顶级包
  - Tool/LLM Client/Enhanced Features/Web API/Default Resources 完整描述
- `[docs]` **README.md 指标同步**
  - 源文件: 174 → 194
  - 测试文件: 39 → 43
  - 代码行数: ~27,000+ → ~34,400
  - 测试用例: 969 → 1,203
  - 警告数: 484 → 556
  - Phase 0-17 → Phase 0-18
  - 完成度: ~95-98% → ~97-99%
- `[docs]` **development-plan-0623.md 指标同步**
  - 技术栈对比表：源文件 169 → 194，测试 24 → 43
  - 项目指标表：源码行 ~27,000+ → ~34,400，完成比例全面重算
  - 测试覆盖差距表：测试用例 969 → 1,203，代码行 ~12,000 → ~13,100
  - 验证状态表：warnings 484 → 556，测试数 969 → 1,203
- `[docs]` **compiler-error-efficiency-report.md 校对**
  - 历史 Phase 18 数据保留，仅同步最新指标 (1,203 tests)
- `[verify]` `moon check` 最终验证：0 errors, 556 warnings


### 2026-06-23  Phase 18 深度补齐：计费 / 定价 / Utils扩展 / 服务器增强 / 消息历史 / 默认资源

- `[feat]` **新建计费系统** — `lib/billing/` 包（3文件）
  - `billing_record.mbt` (78行) — 计费记录创建/查询、Token 用量追踪
  - `billing_store.mbt` (381行) — 费用计算、存储与聚合
  - `billing_wbtest.mbt` (212行) — 11 个测试用例
- `[feat]` **新建模型定价表** — `lib/pricing/` 包（3文件）
  - `model_pricing.mbt` (677行) — 完整模型定价查询表，覆盖主流 LLM 模型
  - `cost_calculator.mbt` (108行) — 成本计算器
  - `pricing_wbtest.mbt` (224行) — 15 个测试用例
- `[feat]` **新建平台 HTTP 客户端** — `lib/client/platform_http.mbt` (329行)
  - 域名故障转移、重试逻辑、超时管理
  - `platform_http_wbtest.mbt` (166行) — 12 个测试用例
- `[feat]` **服务器进程管理增强** — `lib/server/` 新增 5 个文件
  - `master.mbt` (285行) — ServerMaster 主/工作进程架构
  - `worker.mbt` (140行) — Worker 进程实现
  - `session_registry.mbt` (255行) — 线程安全会话注册表
  - `git_panel.mbt` (371行) — Git 状态集成、文件变更追踪
  - `master_wbtest.mbt` (216行) + `session_registry_wbtest.mbt` (212行) + `git_panel_wbtest.mbt` (204行) — 53 个测试
- `[feat]` **Utils 工具库扩展** — `lib/utils/` 新增 13 个文件
  - `encoding.mbt` (139行) — UTF-8 编码处理
  - `environment_detector.mbt` (124行) — CI/Docker/WSL 环境检测
  - `epipe_safe_io.mbt` (72行) — EPIPE 安全 IO
  - `file_ignore_helper.mbt` (149行) — 文件忽略规则管理
  - `gitignore_parser.mbt` (253行) — .gitignore 规则解析
  - `limit_stack.mbt` (68行) — 递归深度限制
  - `logger.mbt` (242行) — 日志轮转系统
  - `proxy_config.mbt` (132行) — 代理配置管理
  - `string_matcher.mbt` (172行) — 模糊字符串匹配
  - `trash_directory.mbt` (183行) — 回收站目录管理
  - `utils_p2_wbtest.mbt` + `utils_p2b_wbtest.mbt` + `gitignore_wbtest.mbt` + `logger_wbtest.mbt` — 51 个测试
- `[feat]` **消息历史管理** — `lib/message/history.mbt` (342行) + `history_wbtest.mbt` (203行, 12 测试)
  - 内部字段过滤、UTF-8 清洗、悬空工具调用清理
- `[feat]` **Agent 核心增强** — `lib/agent/` 新增 3 个文件
  - `compressor_helper.mbt` (168行) — LLM 驱动压缩辅助
  - `default_profiles.mbt` (151行) — 默认 Agent 配置加载器
  - `session_restore.mbt` (252行) — 会话恢复增强
  - `compressor_wbtest.mbt` (242行) + `session_restore_wbtest.mbt` (344行) — 24 个测试
- `[feat]` **配置系统增强** — `lib/config/` 新增 2 个文件
  - `capabilities.mbt` (148行) — Provider 能力声明
  - `env_compat.mbt` (180行) — 环境变量兼容层
- `[feat]` **默认 Agent 配置** — `assets/agents/` 目录（6文件）
  - `coding/config.toml` + `coding/system_prompt.md` — 编码 Agent 配置
  - `general/config.toml` + `general/system_prompt.md` — 通用 Agent 配置
  - `SOUL.md` + `USER.md` — Agent 人格与用户配置
- `[feat]` **默认技能** — `assets/skills/` 目录（11 技能）
  - code-explorer / cron-task-creator / deploy / mcp-manager / media-gen
  - onboard / persist-memory / product-help / recall-memory / search-skills / skill-creator
  - `lib/skill/default_skills.mbt` (173行) — 技能加载器集成
- `[feat]` **工具系统增强** — `lib/tool/output_cleaner.mbt` (97行) — ANSI 输出清洗
- `[test]` 测试用例总数: **507 → 969**（新增 462 个测试用例）
  - 新增模块: billing(11) + pricing(15) + platform_http(12) + server(53) + utils(51)
  - 增强模块: message(12) + agent(24) + tool(11)
- `[chore]` `moon check` 通过: 0 errors, 484 warnings（deprecated 语法警告，从 693 降低）
- `[docs]` 更新 CLAUDE.md / README.md / development-plan-0623.md / CHANGELOG.md 同步 Phase 18 完成状态


### 2026-06-17  Phase 12-17 全量实现：MCP / Agent增强 / Web+TUI / 多模态 / 运维 / 商业扩展

- `[feat]` **Phase 12: MCP 协议** — 新建 `lib/mcp/` 包（9 文件）
  - `types.mbt` — MCP 类型定义（McpTool/McpServer/JsonRpcRequest/Response）
  - `transport.mbt` — Transport trait 定义（send/receive/close）
  - `stdio_transport.mbt` — 标准输入输出传输实现
  - `http_transport.mbt` — HTTP/SSE 传输实现
  - `client.mbt` — JSON-RPC 2.0 客户端（initialize/tools.list/tools.call）
  - `registry.mbt` — 多服务器注册管理（McpRegistry）
  - `virtual_skill.mbt` — MCP 工具映射为虚拟技能
  - `mcp_wbtest.mbt` — MCP 测试
- `[feat]` **Phase 12: 技能演进** — 扩展 `lib/skill/` 包（+4 文件）
  - `evolution.mbt` — EvolutionEngine 入口 + EvolutionScenario 分发
  - `reflector.mbt` — SkillReflector 执行后反思（评分/改进建议）
  - `auto_creator.mbt` — AutoCreator 自动技能创建（模式检测/置信度/阈值）
  - `evolution_wbtest.mbt` — 34 个演进测试用例
  - 技能包测试总数达 61 个，全部通过
- `[feat]` **Phase 13: Agent 增强** — 扩展 `lib/agent/` 包（+7 文件）
  - `time_machine.mbt` + `time_machine_types.mbt` — 文件快照 undo/redo（祖先链恢复算法）
  - `time_machine_wbtest.mbt` — Time Machine 测试
  - `profile.mbt` + `profile_types.mbt` — AgentProfile 加载器（搜索路径 + SOUL.md/USER.md）
  - `idle_timer.mbt` — IdleCompressionTimer（266s 空闲状态机）
  - Agent 包测试总数达 160 个，全部通过
- `[feat]` **Phase 13: Workspace Rules** — 新建 `lib/utils/workspace_rules.mbt`
  - 优先级: `.clackyrules` > `.cursorrules` > `CLAUDE.md`
  - 集成到 system_prompt 构建
- `[feat]` **Phase 13.5 + 14.3: TUI 增强** — 扩展 `lib/tui/` 包（+6 文件）
  - `slash_commands.mbt` — SlashCommand 枚举 + 解析器 + 自动补全（/config /model /clear /new /skills /help /exit）
  - `markdown.mbt` — Markdown→ANSI 渲染（heading/bold/italic/code/codeblock/list）
  - `theme.mbt` — 主题系统（ThemeName: Hacker/Minimal/Default）+ ANSI 色码
  - `progress.mbt` — Spinner 动画（Dots/Line/Arrow 三种样式，函数式不可变更新）
  - `realtime.mbt` — RealtimeRenderer 增量渲染（ANSI 光标控制）
  - `tui_enhanced_wbtest.mbt` — 28 个 TUI 增强测试
- `[feat]` **Phase 14.1: Web 前端 SPA** — 新建 `web/` 目录（8 文件）
  - `index.html` — SPA 入口
  - `style.css` — 暗色主题响应式样式
  - `app.js` — 前端核心逻辑
  - `chat.js` — 聊天界面 + SSE 流式（fetch + ReadableStream）
  - `sessions.js` — 会话列表管理
  - `settings.js` — 设置面板
  - `skills.js` — 技能管理界面
  - `websocket.js` — WebSocket + 自动重连
- `[feat]` **Phase 14.2: REST API 扩展** — 扩展 `lib/web/` 包（+12 文件）
  - `router.mbt` — Router 路由匹配（支持 `:param` 参数提取）+ HttpRequest/HttpResponse 类型
  - `static_server.mbt` — 静态文件服务 + MIME 映射 + SPA fallback
  - `handlers_mcp.mbt` — 5 个 MCP 端点
  - `handlers_channels.mbt` — 6 个 IM 渠道端点
  - `handlers_schedules.mbt` — 6 个定时任务端点
  - `handlers_backup.mbt` — 4 个备份端点
  - `handlers_billing.mbt` — 3 个计费端点
  - `handlers_skills.mbt` — 6 个技能管理端点
  - `handlers_browser.mbt` — 5 个浏览器端点
  - `handlers_trash.mbt` — 4 个回收站端点
  - `handlers_bridge.mbt` — crescent Event 适配桥接
  - `web_handlers_wbtest.mbt` — 35+ 个 handler 测试
  - REST API 总数从 20+ 扩展到 68+ 端点
- `[feat]` **Phase 15: 多模态** — 新建 3 个包
  - `lib/parser/`（6 文件）— PDF/DOCX(ZIP+XML)/PPTX/XLSX 文档解析器，38 个测试
  - `lib/media/`（6 文件）— Media 生成（OpenAI/Gemini/DashScope），27 个测试
  - `lib/vision/`（3 文件）— Vision OCR + SHA256 缓存，28 个测试
- `[feat]` **Phase 16: 运维集成** — 新建 `lib/server/` 包（10 文件）
  - `cron.mbt` — 完整 Cron 表达式解析器（*, */n, n-m, 列表）
  - `scheduler.mbt` — 定时任务调度（60 秒检查间隔）
  - `browser_manager.mbt` — Chrome DevTools MCP 守护进程管理
  - `backup_manager.mbt` — 配置备份到安全位置
  - `discover.mbt` — PID 文件服务器发现
  - 31 个运维测试全部通过
- `[feat]` **Phase 17.1: IM 渠道** — 新建 `lib/channel/` 包（12 文件）
  - AnyAdapter enum 模式（非 trait object）实现 6 平台适配器
  - 飞书/企微/Telegram/Discord/钉钉/微信
  - 25 个渠道测试全部通过
- `[feat]` **Phase 17.2: Brand/License** — 新建 `lib/brand/` 包（5 文件）
  - Brand 白标配置 + License key 格式验证（十六进制段）
  - 心跳/宽限期逻辑
  - 20 个 Brand 测试全部通过
- `[feat]` **Phase 17.3: Shell Hook** — 新建 `lib/hook/` 包（3 文件）
  - 7 种 Shell Hook 事件 + exit code 语义
  - 20 个 Hook 测试全部通过
- `[feat]` **Phase 17.4: Telemetry** — 新建 `lib/telemetry/` 包（4 文件）
  - 匿名遥测（fire-and-forget）+ 环境变量退出
  - 15 个遥测测试全部通过
- `[fix]` 集成验证修复（7 个文件）
  - `lib/mcp/client.mbt` — `let UPPERCASE` → `const`、Json 构造器用法修正
  - `lib/mcp/registry.mbt` — `Map.each` 回调签名修正
  - `lib/agent/todo_wbtest.mbt` — 构造器歧义消歧（`TodoStatus::Cancelled`）
  - `lib/tui/slash_commands.mbt` — 补充 derive(Show)
  - `lib/tui/markdown.mbt` — 补充 derive(Show)
  - `lib/tui/theme.mbt` — 补充 derive(Show)
  - `lib/agent/time_machine_wbtest.mbt` — `String?` Show 格式更新
- `[test]` 全模块集成验证：**507 个测试全部通过**（`moon test --target wasm-gc`）
  - lib/skill: 61 | lib/parser: 38 | lib/media: 27 | lib/vision: 28
  - lib/server: 31 | lib/channel: 25 | lib/brand: 20 | lib/hook: 20
  - lib/telemetry: 15 | lib/agent: 160 | lib/errors: 6 | lib/config: 27 | lib/tool: 49
- `[chore]` `moon check` 通过：0 errors, 693 warnings（deprecated 语法警告）
- `[docs]` 更新 README.md、development-plan.md、development-plan-comprehensive.md 同步 Phase 12-17 完成状态


### 2026-06-17  Phase 11 核心补齐：Bedrock API / Provider 扩展 / 缺失工具

- `[feat]` 实现 Bedrock Converse API 格式支持 `lib/client/format_bedrock.mbt`（~370 行）
  - `build_bedrock_request` — 分离 system 消息、合并连续 tool result、转换 canonical 消息为 Bedrock 格式、toolSpec 工具定义、inferenceConfig 配置、cachePoint 缓存注入
  - `parse_bedrock_response` — 从 output.message.content 提取文本/toolUse 块、stopReason 映射（end_turn→stop, tool_use→tool_calls, max_tokens→length）、usage 归一化
  - `format_bedrock_tool_results` — canonical tool result 消息构建
  - `is_bedrock_api_key` — 匹配 ABSK 前缀或 abs- 模型前缀
  - `bedrock_converse_path` — 构建 `model/{modelId}/converse` 路径
- `[feat]` 实现 Bedrock 流式聚合器 `lib/client/stream.mbt`（+320 行）
  - `BedrockStreamAggregator` struct — 维护 blocks map（按 contentBlockIndex 索引）、role、stop_reason、usage
  - `handle(event, data_str)` — 处理 6 种 SSE 事件：messageStart/contentBlockStart/contentBlockDelta/contentBlockStop/messageStop/metadata
  - `to_json()` — 渲染为 parse_bedrock_response 可消费的 JSON 格式
  - `to_response()` — 调用 parse_bedrock_response 完成流式→非流式转换
  - `BedrockBlockKind` 枚举（Text/ToolUse/Reasoning）+ `BedrockBlockAcc` 块累加器
- `[feat]` 集成 Bedrock 分发逻辑到 `lib/client/client.mbt`（+33 行）
  - `is_bedrock_format()` 方法 — 判断是否使用 Bedrock API 格式
  - 6 处分发分支：build_request_body / build_simple_request / parse_response / format_tool_results / api_path / request_headers
  - Bedrock 检查在 Anthropic 之前，确保三协议正确分发
- `[feat]` 扩展 Provider 预设系统 `lib/config/provider.mbt`
  - 新增 6 个 Provider：DeepSeekV4、MiniMax、Kimi、Kimi-Coding、MiMo、GLM
  - 更新现有 Provider：Anthropic（default_model → claude-sonnet-4-6）、OpenRouter（添加 claude-opus-4-8）、Qwen（qwen3.x 系列）
  - Provider 总数从 6 个扩展到 12 个
- `[feat]` 实现 3 个新工具（`lib/tool/`）
  - `request_user_feedback.mbt`（~153 行）— 用户反馈请求工具，格式化 question/context/options 消息，参数 schema 与 Ruby 对齐
  - `trash_manager.mbt`（~228 行）— 文件回收管理工具，支持 list/restore/status/empty/help 五种操作，`format_bytes()` 公开工具函数
  - `browser.mbt`（~415 行）— 浏览器自动化工具结构化框架，完整参数 schema（9 个 action、12 个 act kind），配置检查框架，MCP 调用接口预留 Phase 12
- `[feat]` 集成新工具到 ToolRegistry
  - `types.mbt` — AnyTool 枚举新增 3 个变体
  - `any_tool.mbt` — 7 个 Tool trait 方法的 dispatch 分支（+24 行）
  - `registry.mbt` — 注册 3 个新工具，工具总数从 11 个扩展到 14 个
- `[test]` 新增/扩展测试（共 201 个新测试用例）
  - `client_wbtest.mbt`（+354 行，20+ 个 Bedrock 测试）— API key 检测、请求构建、响应解析、流式聚合、工具结果格式化、API 路径
  - `tool_wbtest.mbt`（新建，~481 行，49 个测试）— RequestUserFeedback(8)、TrashManager(12)、Browser(13)、Registry(8)、AnyTool dispatch(3)、FunctionDefinition(3)
  - `config_wbtest.mbt` — 新增 6 个 Provider 的查找/URL 匹配/api_type 测试
- `[docs]` 更新 `docs/development-plan-comprehensive.md` Phase 11 状态为已完成，更新验证状态表（测试数 265→466），更新里程碑 M1 为已完成

### 2026-05-23  Phase 10 增强功能：Memory / Subagent / TodoManager

- `[feat]` 实现 Agent 记忆系统 `lib/agent/memory.mbt`（202 行）+ `memory_types.mbt`（128 行）
  - `MemoryStore`：内存条目 CRUD（add/get/update/delete/search/by_category/all）
  - 5 种 `MemoryCategory`：UserPreference/ProjectInfo/TaskSummary/ExpertKnowledge/LearnedSkill
  - JSON 序列化/反序列化，支持持久化往返
  - `summary()` 方法生成可注入系统提示词的人类可读摘要
- `[feat]` 实现 SubAgent 支持 `lib/agent/subagent.mbt`（96 行）
  - `SubAgentConfig`：名称/模型/允许工具/系统提示覆盖/最大迭代数
  - `SubAgentStatus`：Pending/Running/Completed/Failed 生命周期
  - `SubAgentHandle`：状态转换（mark_running/mark_completed/mark_failed）+ is_done
- `[feat]` 实现 TodoManager 任务管理器 `lib/agent/todo.mbt`（211 行）+ `todo_types.mbt`（128 行）
  - `TodoManager`：任务 CRUD + 状态更新 + 依赖阻塞（blocked_by）
  - `TodoStatus`：Pending/InProgress/Completed/Cancelled/Failed
  - `list_actionable()` 返回不受阻塞的可执行任务
  - JSON 序列化/反序列化，`summary()` 方法
- `[feat]` 实现 AgentPool 子 Agent 池 `lib/agent/agent_pool.mbt`（96 行）
  - 并发控制：max_running/max_idle，can_spawn 限制
  - `collect_completed()` 批量清理已完成句柄
  - `summary()` 池状态概览
- `[feat]` Agent struct 扩展 4 个新字段（`skill_registry`/`memory_store`/`todo_manager`/`agent_pool`）
- `[feat]` 系统提示词扩展：Layer 7 Skills → Layer 8 Memory → Layer 9 Tasks 三层上下文注入
- `[feat]` 实现 3 个 Agent 上下文工具（`lib/tool/`）
  - `invoke_skill.mbt`（67 行）— 从注册中心按名调用技能
  - `memory_tool.mbt`（90 行）— 记忆条目增/搜/改/删/列表
  - `todo_tool.mbt`（91 行）— 任务增/改/列/删/依赖设置
- `[feat]` `lib/agent/tool_executor.mbt` 新增 Agent 上下文拦截路由：`invoke_skill`/`memory`/`todo_manager` 在泛型工具分发前被截获并委派到 Agent 内状态
- `[feat]` `lib/tool/any_tool.mbt`/`types.mbt`/`registry.mbt` — AnyTool 枚举 + 默认注册表扩展 3 个 Agent 工具
- `[refactor]` Agent.try_activate_fallback 加入 skill_registry/agent_pool/memory_store/todo_manager 恢复
- `[test]` 新增 5 个测试文件（~81 个测试用例）
  - `memory_wbtest.mbt`（317 行，20 个用例）— MemoryStore CRUD/搜索/分类/JSON 往返
  - `subagent_wbtest.mbt`（293 行，13 个用例）— SubAgent 生命周期/AgentPool 并发
  - `todo_wbtest.mbt`（292 行，22 个用例）— TodoManager CRUD/依赖阻塞/状态流转
  - `skill_wbtest.mbt`（391 行，23 个用例）— Frontmatter 解析/Skill 加载/SkillRegistry
  - `agent_wbtest.mbt`（+2 个用例）— `to_json` → `stringify()` 迁移
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@skill`

### 2026-05-23  Phase 9 技能系统

- `[feat]` 实现技能加载与解析 `lib/skill/loader.mbt`（257 行）
  - `parse_frontmatter`：YAML 风格 frontmatter 解析（key: value 格式）
  - `load_skill_from_content`：从 SKILL.md 内容加载 Skill struct（17 字段）
  - `load_skill_from_json_value`：从 JSON 值加载技能
  - 字段支持：name/description/allowed_tools/forbidden_tools/fork_agent/model/auto_summarize 等
- `[feat]` 实现技能注册中心 `lib/skill/registry.mbt`（86 行）
  - `SkillRegistry`：Map[String, Skill] 存储，register/get/has/remove/all
  - `list_user_invocable` / `list_by_agent_type` 筛选查询
- `[feat]` 实现技能发现机制 `lib/skill/discovery.mbt`（69 行）
  - `default_discovery_paths`：3 个标准技能路径（.qoder/skills, skills, .skills）
  - `discover_skills`：从文件内容 Map 中自动发现 SKILL.md / skill.json
- `[feat]` 实现技能执行器 `lib/skill/executor.mbt`（92 行）
  - `build_skill_context`：生成技能注入系统提示词的上下文字符串
  - `build_skills_summary`：生成所有可用技能的人类可读摘要
- `[feat]` Agent 端技能管理 `lib/agent/skill_manager.mbt`（29 行）
  - `load_skills`：从文件内容注册技能到 Agent 的 SkillRegistry
  - `get_skill` / `available_skills_summary`：运行时技能查询
- `[chore]` `lib/skill/skill.mbt` 扩展至 17 个字段（新增 name_zh/description_zh/user_invocable/context/agent_type/argument_hint/hooks/fork_agent/model/forbidden_tools/auto_summarize/source/directory）

### 2026-05-23  MoonBit v0.9.3 编译器迁移修复

- `[fix]` 修复 10 个文件的 moonc v0.9.3 破坏性变更（216 行新增，125 行删除）
  - `lib/web/server.mbt` — `self` 显式类型注解（`self : WebServer`）、`fn(params) { }` → `(params) => { }` lambda 语法、`panic()` 不再接受字符串参数
  - `lib/web/handlers.mbt` — `body[Json]()` → `body()`、`{ ... } : Json` → `Json::object({ ... })`、`raise HttpError` → 返回 `HttpResponse::error()`、`event.require_param` → `event.param` + 错误返回、`Bool(b)` → `True`/`False` 枚举模式、`PermissionMode_to_string` 函数重命名、`{}` 空代码块 → `()`、`ignore expr` → `let _ =`
  - `lib/web/types.mbt` — `impl ToJson` → `pub impl ToJson`（跨包可见性）
  - `lib/web/sse/sse.mbt` — `{ ... } : Json` → `Json::object({ ... .to_json() })` 语法迁移
  - `lib/web/middleware/auth.mbt` + `logging.mbt` — `fn(params) { }` → `(params) => { }` lambda 语法
  - `lib/agent/session_store.mbt` — `load_session` 改为 noraise（裸 `raise` 无法跨包 `catch`），内部用 `catch` 处理异常
  - `lib/agent/session_data.mbt` — `impl ToJson` → `pub impl ToJson`
  - `cmd/main.mbt` — `fn main` → `async fn main`、`handle_server` 改为 `async fn`、`server.start(port=4000)` → `server.start(4000)`（位置参数无标签）、`handle_server() catch` 处理异步错误
  - `cmd/moon.pkg` — 新增 `"moonbitlang/async"` 导入
- `[chore]` `moon info` 编译检查通过：0 errors, 154 warnings（均为依赖包过时代码 + 微小 deprecated 警告）

### 2026-05-23  Phase 8 Web 服务器（crescent 框架）

- `[feat]` 实现基于 `bobzhang/crescent` 的 Web 服务器（`lib/web/`，9 文件，~1,147 行）
  - `server.mbt`（141 行）— WebServer 状态管理 + `get_or_create_agent` + `start`（路由注册/中间件/启动）
  - `handlers.mbt`（553 行）— 14 个 HTTP handler 覆盖全部 API 端点
  - `types.mbt`（257 行）— 15 个 DTO 类型 + `ToJson` 序列化
  - `sse/sse.mbt`（85 行）— SSE 事件格式化 + HookEvent 捕获 + SSE body 构建
  - `middleware/auth.mbt`（18 行）— `X-API-Key` 认证中间件
  - `middleware/logging.mbt`（15 行）— 请求日志中间件（method/path/duration）
- `[feat]` 实现 20+ REST API 端点
  - 会话管理：`GET/POST /api/sessions`、`GET/DELETE /api/sessions/:id`、`POST /api/sessions/:id/restore`
  - 对话：`POST /api/sessions/:id/chat`（阻塞）、`POST /api/sessions/:id/chat/stream`（SSE 流式）
  - 会话状态：`GET /api/sessions/:id/status`、`POST /api/sessions/:id/cancel`、`GET /api/sessions/:id/cost`、`GET /api/sessions/:id/tools`
  - 配置：`GET/PUT /api/config`、`GET /api/config/models`、`GET /api/config/permissions`
  - 统计：`GET /api/stats`、`GET /api/stats/aggregate`
  - 信息：`GET /api/info`、`GET /health`
- `[feat]` 实现 WebSocket 端点 `WS /ws/sessions/:id`（`handlers.mbt` 中 `handle_websocket`，68 行）
  - 双向实时通信：接收 JSON 消息 → Hook 事件捕获 → 事件推送
  - `Open`/`Message`（Text）/`Close` 事件处理
- `[feat]` 实现 SSE 流式端点（`POST /api/sessions/:id/chat/stream`）
  - Hook 事件批量捕获 → SSE 格式化 → `Content-Type: text/event-stream` 响应
  - 事件类型：`status`/`iteration`/`llm_start`/`llm_end`/`message_added`/`tool_executing`/`tool_executed`/`error`/`done`
- `[feat]` `cmd/main.mbt` — `server` 子命令实现：加载配置 → 创建 WebServer → 监听端口
- `[chore]` `cmd/moon.pkg` 新增依赖：`@web`
- `[chore]` `moon.mod.json` 新增依赖：`bobzhang/crescent: 0.10.0`、`moonbitlang/async`（`http` / `websocket`）
- `[chore]` `lib/web/moon.pkg` 配置依赖：`crescent`、`crescent/core`、`crescent/cors`、`crescent/websocket`、`async`、`async/http`
- `[docs]` `docs/development-plan.md` — 更新 Phase 8 完成状态

### 2026-05-23  Phase 7 TUI 交互界面 + Hook 事件系统

- `[feat]` 实现 Hook 事件系统 `lib/agent/hook.mbt`（77 行）
  - `HookEvent` 枚举：10 种生命周期事件（StatusChanged/BeforeIteration/AfterIteration/BeforeLlmCall/AfterLlmCall/MessageAdded/ToolExecuting/ToolExecuted/ErrorOccurred/RunCompleted）
  - `HookManager` 结构体：register/emit/clear 方法，FIFO 回调调度
- `[feat]` Agent 核心集成 Hook 事件（`lib/agent/react.mbt`）
  - 在 `run()` 中发射 StatusChanged、MessageAdded、ErrorOccurred、RunCompleted 事件
  - 在 `react_loop()` 中发射 BeforeIteration、AfterIteration 事件
  - 在 `think()` 中发射 BeforeLlmCall、AfterLlmCall、MessageAdded 事件
  - 在 `act()` 中发射 ToolExecuting、ToolExecuted 事件
  - 在 `observe()` 中发射 MessageAdded 事件
  - 共计 11 个发射点覆盖完整 ReAct 生命周期
- `[feat]` `lib/agent/agent.mbt` — Agent struct 新增 `hook_manager : HookManager` 字段
- `[feat]` 实现基于 onebit-tui 的 TUI 界面（`lib/tui/`，10 文件，~667 行）
  - `tui.mbt`（232 行）— 主入口 `run_tui_interactive`、事件循环、Hook→TUI 状态同步
  - `state.mbt`（79 行）— `TuiState` 共享状态（Idle/Running 双模式）
  - `message_view.mbt`（44 行）— 带角色着色与 ScrollBox 的会话历史组件
  - `input_bar.mbt`（38 行）— TextInput + Submit/Quit 按钮
  - `status_bar.mbt`（33 行）— Agent 状态 + 模型名 + 迭代次数
  - `stats_bar.mbt`（49 行）— Token/成本/缓存统计栏
  - `tool_view.mbt`（27 行）— 工具执行输出面板
- `[chore]` `cmd/main.mbt` — 无 `--message` 时自动启动 TUI 交互模式，替代 Phase 5 的占位消息
- `[chore]` `cmd/moon.pkg` 新增依赖：`@tui`
- `[chore]` `moon.mod.json` 新增依赖：`Frank-III/onebit-tui: 0.1.3`，目标改为 `preferred-target: native`
- `[test]` `lib/agent/hook_wbtest.mbt` — 新增 11 个测试用例（Hook 注册/发射/清除/事件负载/集成验证）
- `[test]` `lib/tui/tui_wbtest.mbt` — 新增 9 个测试用例（TuiState 构建/可变性/成本格式化/Hook 事件处理/TuiMode 相等性）
- `[docs]` `docs/development-plan.md` — 更新 Phase 7 完成状态

### 2026-05-23  Phase 6 会话持久化（Session 存储与管理）

- `[feat]` 实现会话文件存储 `lib/agent/session_store.mbt`（106 行）
  - `save_session` — 将会话数据持久化为 JSON 文件到 `~/.mbopenclacky/sessions/`
  - `load_session` — 按 session_id 从磁盘加载会话
  - `delete_session` — 删除指定会话文件
  - `list_sessions` — 列出所有保存的会话（按 created_at 排序）
  - `find_most_recent` — 查找最近一次会话
- `[feat]` 实现会话生命周期管理 `lib/agent/session_manager.mbt`（119 行）
  - `enforce_session_cap` — 超过 200 会话上限时自动清理最旧会话
  - `truncate_session` — 消息超限截断，仅保留最近 20 条，标记压缩摘要
  - `compress_old_sessions_if_needed` — 批量检查旧会话并执行压缩
  - `format_session_summary` — 格式化会话摘要行用于 `--list` 输出
- `[feat]` 实现跨平台毫秒级时间戳 `lib/agent/time.mbt`（25 行）+ `time_stub.c`（30 行）
  - native 后端：通过 FFI 调用系统 API（Windows FILETIME / POSIX gettimeofday）
  - wasm/js 后端：返回 0 作为桩
- `[feat]` 实现 SessionData JSON 序列化与反序列化
  - `lib/agent/session_data.mbt` — `SessionStats` + `SessionData` 的 `ToJson`/`FromJson`
  - `lib/message/content.mbt` — `TextBlock`/`ImageBlock`/`ContentBlock` 的 `FromJson`
  - `lib/message/message.mbt` — `Message` 的 `FromJson`（含所有可选字段）
  - `lib/message/tool_call.mbt` — `FunctionCall`/`ToolCall` 的 `FromJson`
- `[feat]` CLI 集成会话管理（`cmd/main.mbt`）
  - 新增 `--continue` 标志：恢复最近一次会话
  - 新增 `--list` 标志：列出所有保存的会话
  - 新增 `--attach <id>` 选项：附加到指定会话
  - `run_non_interactive` 执行后自动保存会话 + 强制执行上限 + 压缩旧会话
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@utils`、`@fs`、`@path`、`@sys`，新增 `native-stub: ["time_stub.c"]`
- `[chore]` `cmd/moon.pkg` 新增依赖：`@fs`、`@path`、`@utils`
- `[chore]` `lib/agent/agent.mbt` — `Agent::new` 的 `created_at` 改为实时时间戳
- `[test]` `lib/agent/agent_wbtest.mbt` — 新增 10 个测试用例（Session JSON 序列化往返、会话摘要格式化、ID 生成）

### 2026-05-23  Phase 5 CLI 入口实现

- `[feat]` 基于 `TheWaWaR/clap` 实现完整 CLI 入口（`cmd/main.mbt`，~280 行）
  - 支持顶层参数：`--message/-m`、`--mode`、`--model`、`--agent`、`--path`、`--verbose/-v`、`--version/-V`
  - `--mode` 使用 clap `choices` 约束，仅接受 `auto_approve/confirm_safes/confirm_all`
  - 子命令：`billing`、`server`（Phase 5 中为 stub）
  - 默认无参数时显示帮助信息
- `[feat]` 实现非交互式 Agent 运行（`--message`/`-m`）
  - 加载配置 → 检查 API Key → 构建 Client → 创建 Agent → 执行 run() → 打印结果 → 退出
  - 支持 `--mode`、`--model`、`--verbose` CLI 覆盖
  - 错误处理：AgentInterrupted / AgentError / RetryableError 分类处理
- `[chore]` `cmd/moon.pkg` 新增依赖：`hashset`、`sys`、`@clap`、`@errors`
- `[chore]` `cmd/moon.pkg` 移除未使用依赖：`message`、`tool`、`utils`
- `[docs]` `docs/development-plan.md` — 更新 Phase 5 完成状态，标记 CLI 差距已消除

### 2026-05-23  Phase 4 Agent 核心实现（10 个 mixin 模块）

- `[feat]` 实现 10 个 Agent mixin 模块（共 ~1,400 行）
  - `lib/agent/react.mbt`（155 行）— ReAct 主循环（think → act → observe）
  - `lib/agent/llm_caller.mbt`（145 行）— LLM 调用 + Fallback 状态机 + 上下文溢出处理
  - `lib/agent/tool_executor.mbt`（120 行）— 工具执行 + 权限确认 + 结果构建
  - `lib/agent/cost_tracker.mbt`（130 行）— CostSource/CacheStats/IterationTokenData + track_cost
  - `lib/agent/system_prompt.mbt`（85 行）— 6 层系统提示词构建
  - `lib/agent/compressor.mbt`（95 行）— 消息压缩阈值检测 + 压缩执行
  - `lib/agent/session_data.mbt`（75 行）— SessionStats/SessionData + 会话恢复
  - `lib/agent/agent_result.mbt`（45 行）— RunStatus/RunResult + build_result
  - `lib/agent/agent_wbtest.mbt`（558 行）— 42 个测试用例
- `[refactor]` `lib/agent/agent.mbt` — Agent struct 扩展至 20+ 字段（client/config/tool_registry/cache_stats/fallback_state/compression_level 等）, 新增 FallbackState 枚举状态机 + `current_model`/`set_reasoning_effort` 方法
- `[refactor]` `lib/errors/errors.mbt` — 6 个 suberror 类型的 `pub` 改为 `pub(all)`（AgentInterrupted/AgentError/BadRequestError/ToolCallError/BrowserNotReachableError/RetryableError/UpstreamTruncatedError）
- `[refactor]` `lib/message/message.mbt` — `tool_calls` 字段改为 `mut`
- `[refactor]` `lib/tool/any_tool.mbt` — 7 个 trait impl 的 `impl` 改为 `pub impl`
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@client`、`@config`、`@tool`、`@errors`、`@json`
- `[chore]` `cmd/moon.pkg` 新增依赖：`@client`、`@tool`、`@json`
- `[chore]` `cmd/main.mbt` — 更新 smoke test，展示 Agent/Client/Config/CacheStats/SessionData/ToolRegistry 集成
- `[docs]` `docs/development-plan.md` — 更新 Phase 4 完成状态，新增 Phase 4 验证结果表及 Phase 5 CLI 入口计划

### 2026-05-23  Phase 3 工具系统实现 + 编译错误系统性修复

- `[feat]` 完成 10 个工具模块实现（共 ~2,100 行）
  - `lib/tool/terminal.mbt`（226 行）— 终端命令执行，支持 run/background/continue/poll/kill 五种调用方式
  - `lib/tool/grep.mbt`（358 行）— 文件内容搜索，支持正则、通配符、上下文行、递归搜索
  - `lib/tool/registry.mbt`（264 行）— 工具注册中心，支持别名、分类、注册/注销/查找
  - `lib/tool/security.mbt`（257 行）— 安全校验，命令白名单/路径保护/密钥检测
  - `lib/tool/file_reader.mbt`（207 行）— 文件读取，支持偏移量/行数限制
  - `lib/tool/web_fetch.mbt`（131 行）— 网页抓取
  - `lib/tool/web_search.mbt`（93 行）— 网页搜索
  - `lib/tool/write.mbt`（101 行）— 文件写入
  - `lib/tool/edit.mbt`（165 行）— 精确字符串替换编辑
  - `lib/tool/glob.mbt`（168 行）— 通配符文件查找
  - `lib/tool/any_tool.mbt`（121 行）— AnyTool 动态分发适配器
  - `lib/tool/types.mbt`（15 行）— ToolCategory trait 定义
- `[chore]` `lib/tool/moon.pkg` 新增依赖：`@string`、`@fs`、`@path`、`@sys`
- `[fix]` 修复 client 包 `json.value()` 弃用警告（46 处），替换为 `if json is Object(obj)` 模式匹配
- `[fix]` 修复工具包 `starts_with`/`ends_with` 弃用，替换为 `has_prefix`/`has_suffix`
- `[fix]` 修复 `Number(n)` → `Number(n, ..)` 缺少参数模式
- `[refactor]` 消除 48 处 trait 方法中未使用的 `self` 参数（改为 `_`）
- `[chore]` 扩展 `.gitignore`：排除 `_check_output*.txt`、`_tmp_*`、`assets/`、`logs/`、`memory/`
- `[docs]` 新增 `docs/compiler-error-efficiency-report.md`：65 个编译错误的根因分析与修复路线图

### 2026-05-23  Phase 2 LLM 客户端核心实现

- `[feat]` 实现 LLM 客户端核心 `lib/client/client.mbt`（410 行）
  - Client struct：API 密钥 / base_url / 模型 / API 类型 / Provider ID
  - 请求构建分发（build_request_body / build_simple_request）
  - 响应解析分发（parse_response）
  - 工具结果格式化（format_tool_results）
  - API 端点 / HTTP 头 / URL 构建（api_path / request_headers / build_url）
  - Prompt Caching 检测（Claude 3.5+ 模型匹配）
  - HTTP 错误映射（400-599 状态码 → 可读错误信息）
  - HTML 响应检测与错误信息提取
  - 流式选项注入（add_stream_options / add_stream_flag）
- `[feat]` 实现 OpenAI 消息格式 `lib/client/format_openai.mbt`（333 行）
  - 请求构建：消息转换、工具定义、vision 过滤、reasoning_effort
  - 响应解析：choices/message/usage/tool_calls 提取
  - 工具结果格式化：canonical tool result 消息构建
  - Prompt Caching：末位工具 cache_control 注入
- `[feat]` 实现 Anthropic 消息格式 `lib/client/format_anthropic.mbt`（480 行）
  - 请求构建：系统消息分离、工具格式转换（parameters→input_schema）
  - 消息转换：tool_use 块、tool_result 块、图片 base64 处理
  - 响应解析：content blocks / stop_reason 映射 / usage 归一化
  - reasoning/thinking 支持（adaptive thinking + effort 配置）
  - Anthropic API 路径检测（/v1/messages vs messages）
- `[feat]` 实现 SSE 流式处理 `lib/client/stream.mbt`（559 行）
  - 通用 SSE 帧解析器（event/data 逐帧提取）
  - StreamCallback trait（流式进度通知接口）
  - OpenAiStreamAggregator：流式内容/工具调用/usage 聚合
  - AnthropicStreamAggregator：content_block 流式聚合（text/tool_use/thinking_delta）
- `[feat]` 扩展 `lib/client/types.mbt`（97 行）
  - Usage：from_openai / from_anthropic 工厂方法（cache 归一化）
  - LlmResponse：text_only / has_tool_calls / is_finished 便捷方法
  - Latency：duration_ms / ttft_ms 延迟度量
- `[chore]` `lib/client/moon.pkg` 新增依赖：`@config`（lib/config）
- `[test]` 新增 `lib/client/client_wbtest.mbt` 白盒测试（38 个用例）
  - SSE 帧解析（7）、OpenAI 请求构建（3）、OpenAI 响应解析（3）
  - Anthropic 请求构建（3）、Anthropic 响应解析（4）
  - 工具结果格式化（3）、错误信息提取（4）
  - Prompt Caching 检测（3）、URL 构建（4）
  - OpenAI 流式聚合（4）、Anthropic 流式聚合（2）、Usage 工具（2）

### 2026-05-23  清理 .qoder/repowiki 误追踪 + 开发计划文档

- `[chore]` 从 Git 索引移除 `.qoder/repowiki/`（29 个文件），该目录已在 .gitignore 中
- `[docs]` 新增 `docs/development-plan.md`：更新里程碑统计与 Phase 2 行动计划

### 2026-05-23  新增 .gitignore，清理 _build/ 构建产物

- `[chore]` 创建 `.gitignore`，排除 `_build/`、`.mooncakes/`、`.repos/`、`.qoder/`、`*.mbti` 等生成文件
- `[fix]` 从 Git 索引中移除 `_build/` 目录（580+ 个构建产物文件），本地文件保留

### 2026-05-23  配置加载与 Provider 预设系统

- `[feat]` 新增 `lib/utils/` 工具包
  - `env.mbt` — 环境变量类型安全访问（字符串/布尔/整数）
  - `path.mbt` — 配置目录路径解析（home_dir、config_dir、config_file、sessions_dir、skills_dir）
  - `utils_wbtest.mbt` — 白盒测试（环境变量读写、路径构建、整数解析）
- `[feat]` 实现配置加载器 `lib/config/loader.mbt`
  - TOML 配置文件读写（settings 节 + models 数组）
  - 环境变量覆盖（`MBOPENCLACKY_API_KEY` / `BASE_URL` / `MODEL` / `VERBOSE`）
  - 默认配置路径 `~/.mbopenclacky/config.toml`
- `[feat]` 实现 Provider 预设系统 `lib/config/provider.mbt`
  - `ApiType` 枚举（OpenAICompletions / AnthropicMessages / Bedrock / OpenAIResponses）
  - `Providers` 内置预设：OpenClacky、OpenRouter、Anthropic、OpenAI、DeepSeek、Qwen
  - Lite model 映射与 fallback model 链
  - 通过 base_url 或 id 自动匹配 Provider
- `[refactor]` `AgentConfig` 所有字段改为 `mut`，支持运行时修改
- `[chore]` `lib/config/moon.pkg` 新增依赖：`bobzhang/toml`、`moonbitlang/x/fs`、`moonbitlang/x/path`、`moonbitlang/x/sys`、`lib/utils`
- `[test]` 新增 `lib/config/config_wbtest.mbt` 白盒测试（29 个用例）
  - 覆盖：默认值、TOML 解析/序列化/往返、Provider 查询、环境变量叠加、模型选择

### 2026-05-23  项目初始化与基础框架搭建

- `[feat]` 建立项目目录结构
  - `cmd/` — 入口程序
  - `lib/agent` — Agent 核心模块
  - `lib/client` — LLM API 客户端
  - `lib/config` — 配置管理
  - `lib/errors` — 错误类型定义
  - `lib/message` — 消息结构
  - `lib/skill` — 技能系统
  - `lib/tool` — 工具系统
- `[chore]` 配置 `moon.mod.json` 及各包 `moon.pkg`
- `[docs]` 添加项目 README 与 MIT LICENSE

