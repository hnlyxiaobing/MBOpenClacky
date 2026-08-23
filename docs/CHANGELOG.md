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

### 2026-08-23  stubfix 批次（01-08）全部实施完成归档 + 实施后对抗性代码审查修订

- `[feat]` **stubfix-05~08 四份 spec 实施**（此前 01-04 已完成）：调度器持久化（YAML 子集读写 + write-through + 共享时钟）、Telegram 真发送（http_post_json 同构实现 + 错误映射）、WsClient 薄封装 + Discord 网关连接层（@async.websocket，零新增依赖）、四基础设施模块文件操作真实现（@fs/@utils/@zip：output_dir/backup_manager/scripts/discover）
- `[fix]` **批次实施后对抗性代码审查修复 8 项 C 级缺陷**：
  - 调度器 save_config 错误被吞（写盘失败仍返回 Ok，重启丢任务）-> 传播 Err；web 层内存调度器（config_path 为空）显式跳过写盘
  - ChannelEvent.timestamp Int 32 位溢出（毫秒 epoch 约 1.78e12）-> 全平台改 Int64
  - Discord 客户端主动心跳缺失（仅被动响应服务端 op 1，约 60s 被断开）-> heartbeat_loop（首跳 jitter + 周期心跳 + 丢 ACK 检测）
  - run_gateway_loop 孤儿层（全仓库零调用，send 恒返 Adapter not running）-> ChannelManager::start_with_gateway + WebServer::start 接线
  - backup 三连假成功：.tar.gz 扩展名撒谎（实际 ZIP）、list() 字符串读 ZIP 必失败返回空、run() 静默丢二进制文件 -> 全部修复
  - discover is_process_alive 恒 true（崩溃残留 PID 当活 server）-> /proc 探测 + HTTP /health 双重校验
- `[fix]` **12 项 W 级修复**：output_dir cleanup 语义欺诈（max_age 实为 max_count）、total_size 字符数统计、ensure_exists 恒 Ok、update_schedule 半更新状态、任务名路径消毒（防目录穿越）、yml 转义、include_sessions 落地、op9 重连延迟、旧测试写共享 /tmp/schedules.yml、ws_client close 置 conn=None 等
- `[test]` **新增 23 个 wbtest**：scheduler_wbtest.mbt 10 例（持久化 roundtrip/脏数据容忍/原子性/路径穿越/写失败传播）、backup_wbtest.mbt 5 例（ZIP 含二进制往返/retention）、discord_wbtest.mbt 4 例（ISO8601 时区表驱动/溢出回归）、output_dir_wbtest.mbt 4 例（字节计数/max_files）
- `[docs]` **specs 归档**：stubfix 批次 9 份文档（00-overview + 01-08）全部归档至 specs/completed/，各 spec 变更记录附对抗性审查修订行；批次验收项「全仓库假成功型 stub 清零」grep 复验通过
- 验证：`moon check` 0 errors / 0 warnings；全量 `moon test` 3869/3869 全绿

### 2026-08-21  编译告警清零 + 28 份 P5/P6 spec 全部归档 + 文档校准

- `[fix]` **编译告警清零（4 个 unreachable_code）**：`lib/tool/security_wbtest.mbt`（2 处）与 `test/diff/path_handling_cases_wbtest.mbt`（2 处）的 catch `_ =>` 分支因 `expand_path`/`is_secret_path` 为单一错误类型（`raise SecurityError`）而不可达，删除冗余分支；顺手修复 `path_016_empty_string` 测试断言被误写入注释行导致测试体为空的问题（断言恢复生效）。`moon check` 0 errors / 0 warnings，全量 `moon test` 3843/3843 通过
- `[docs]` **specs/active/ 清空，28 份 P5/P6 差分对齐 spec 全部归档**：16 份 P5 BUG 修复 spec（02/05/07~09/12/14/18/19/23~29）+ 12 份 P6 矩阵残留簇 spec（03/04/06/10/11/13/15~17/20~22）均已实现完成并归档至 `specs/completed/`；总览索引 `2026-08-18_01_diff-harness-matrix-backlog-overview.md` 状态更新后一并归档（28 份子 spec 归档证据：moon test 3843/3843 全绿 + 各实现 commit）
- `[docs]` **文档指标校准**（README / CLAUDE.md / docs/project-status.md / specs/README.md）：源代码文件 291 -> 299（lib+cmd 非测试 `.mbt`）、测试文件 178 -> 197、代码行 ~127,500 -> ~148,600（源码 ~92,900 + 测试 ~55,700）、测试用例 3,100+ -> 3,843、REST 端点 216 -> 218 条路由注册（GET 90 / POST 86 / PATCH 15 / DELETE 18 / PUT 9，按 `lib/web/server.mbt` 实测口径）；CLAUDE.md 修正 provider 预设 12 -> 13（两处）与默认技能 17 -> 18；project-status.md 更新技能清单（新增 extend-openclacky，18 个）、Benchmark 基础设施差距标记已解决（`test/benchmark/` 已实现）、补记 P2~P6 差分测试对齐阶段完成状态；specs/README.md 清空过时的 Active 索引（T01~T18 早已完成）并补记 2026-08-21 收尾批次归档记录

### 2026-08-05  TUI 渲染层再重构 + 全面对齐原版 + 技能发现对齐 + CI 修复
- `[refactor]` **TUI 渲染层再重构**：废弃 mizchi/tui VNode 渲染（坐标 diff 与 commit-scrollback 物理滚动本质冲突，BUG-004），改为自研行级重绘（`tui_controller_render.mbt` 前缀 diff 只重写变化行）+ `screen_lines.mbt` 行模型原语；删除 `vnode_renderer.mbt`、`tui_controller_vnode.mbt`、`node_adapter.mbt`、`diff_renderer.mbt`、`brand_layout.mbt`；`mizchi/tui` 依赖收敛为仅 `core` 宽度测量
- `[feat]` **TUI 全面对齐原版布局与命令语义（SPEC-01/02/03）**：状态栏置底、无框输入区、todo 自动显隐；`/clear` `/undo` `/model` `/config` 语义对齐、技能动态斜杠命令；tui-eval 场景 47/47 通过
- `[feat]` **技能发现对齐原版**：新增 `Agent::discover_workspace_skills`（`lib/agent/skill_manager.mbt`）与 `@skill.read_skill_files`（`lib/skill/discovery.mbt`）；发现路径扩为 5 条（用户全局 `~/.mbopenclacky/skills/` 优先，项目级 `.clacky/skills/` 最后，同名后者覆盖）；CLI/Web/onboard 启动时自动发现
- `[fix]` **CI/Docker 构建失败修复**：`discover_workspace_skills` 方法定义及配套测试此前未提交，导致 `moon check` 报 `[4015]`（Agent 无该方法）与 `moon test` 旧断言（3 路径 vs 实际 5 路径）失败；已补提交（`7d96dbd`、`7b3f9f8`）
- `[docs]` **文档指标校准**：旧统计误将 `.mbti` 计为 `.mbt`，全部文档改为排除 `.mbti` 的口径（源文件 290、测试文件 173、~114,500 行）；Provider 预设 12 → 13（补 `volcengine-ark`）；REST 端点统一为 216 条路由（含别名）

### 2026-08-03  fix: Web UI 7 项修复对抗性审查补漏 + 4 项 spec + 复测 4 项修复

- `[fix]` **前一轮 7 项 Web UI 修复的对抗性审查与补漏**（详见 [web-ui-parity.md](web-ui-parity.md) 第三轮修复摘要）
  - 历史消息重复（created_at 打点/序列化 + has_more 游标化）、头像路由被 SPA fallback 短路（中间件豁免）、模型选择重启后丢失、错误路径持久化等
- `[feat]` **4 项 spec 实施归档**（`specs/completed/2026-08-03_*.md`）
  - Windows 原生构建断链修复（`@sys.get_cli_args` → core `@env.args()`，根因：工具链运行时布局变更）
  - 模型标识统一（`SessionData.model_config_id`，读写路径同名同义）
  - 历史分页改 offset 位置游标；working_dir 用户输入规范化
- `[fix]` **晚间复测 4 项根因修复**
  - 路径斜杠混用真凶：MoonBit `String::replace` 只换首个匹配 → `replace_all`（含回归测试）
  - "默认模型"双概念（Settings 徽标 vs current_model_id）统一为徽标权威，全部写入路径双向同步
  - 目录切换：绝对路径沙盒改 opt-in、目录选择器失败时回退真实文件系统浏览
  - 占位会话名（`Session N`）首条消息后按内容自动重命名并 WS 广播
- `[test]` 全量 `moon test` 3256/3256；两阶段 E2E（含重启恢复、分页、头像、模型选择）全过

### 2026-07-29  feat: Agent 增量规格 + 文档整理

- `[feat]` **agent-01~08 规格全部实现**（specs 归档至 `specs/completed/2026-07-29_agent-*.md`）
  - session context 注入（日期/OS/工作目录）、reasoning_content 透传、空响应检测重试
  - 压缩阈值配置化、压缩失败回滚、URL fallback、空闲压缩定时器、skill evolution hooks
- `[docs]` **docs/ 目录删减合并**
  - 删除 7 份过时文档（两份 gap 分析、两份 UI 对比报告、两份 TUI 重设计文档、ffi-c-migration）
  - 新增 `tui-architecture.md`；重写 `project-status.md`、`web-ui-parity.md`；同步根目录 README/CLAUDE

### 2026-07-28  feat: TUI mizchi 基础迁移 + parity 修复

- `[refactor]` **TUI 渲染层迁移至 mizchi/tui VNode 基础**（Phase 1-4 完成，`lib/tui/vnode_renderer.mbt`，状态管理采用 mizchi/signals）
- `[feat]` **tui-parity-01~08 规格实施完成**（specs 归档）
  - 状态栏渲染截断修复与内容对齐、斜杠命令单次 Enter 执行
  - 欢迎 banner / 输入区 / 帮助与命令集对齐、窄屏自适应
  - tui-parity-08 渲染架构决策：维持 inline scrolling（不迁全屏分屏）

### 2026-07-27  feat: gap 分析 18 项差距全部实现

- `[feat]` **2026-07-27 gap 分析规格全部实现并归档**（`specs/completed/2026-07-27_gap-analysis-overview.md`）
  - MCP 配置文件加载与 HTTP transport、Time Machine 接入 tool_executor
  - WebSocket token 级流式推送、LLM 调用重试 / fallback 统一化等

### 2026-07-26  feat: web-ui2 规格实施 + 告警清零 + 文档同步

- `[feat]` **web-ui2 规格实施完成（04~10）**（7 个规格全部归档至 `specs/completed/`）
  - **web-ui2-04**：Skills YAML block scalar 解析（`lib/skill/loader.mbt`）
  - **web-ui2-05**：Channels 平台专属字段（`lib/web/handlers_channels.mbt` + 测试）
  - **web-ui2-06**：Agents 本地化（`lib/web/handlers_agents.mbt` + ext-developer agent + 3 个 avatar.png）
  - **web-ui2-07**：Exchange rate 日期格式化（`lib/web/handlers_exchange_rate.mbt`）
  - **web-ui2-08**：Dirs 路径规范化（`lib/web/handlers_dirs.mbt`）
  - **web-ui2-09**：Session mutation 契约对齐（handlers + wbtest）
  - **web-ui2-10**：Response field 清理（handlers + protocol/types.mbt）
  - 合计：30 个文件修改，+828/-128 行代码
- `[feat]` **ext-developer agent 新增**
  - 新增 `assets/agents/ext-developer/`（config.toml + system_prompt.md + avatar.png）
  - 新增 `assets/agents/coding/avatar.png` 和 `assets/agents/general/avatar.png`
- `[fix]` **moon check 告警清零**（`moon check` 从 ~500 warnings → 0 warnings）
  - **supported_targets 级联修复**：为 5 个 native-only 包添加 `supported_targets = "native"` 声明
    - `lib/tool/moon.pkg`（新增）
    - `lib/extension/moon.pkg`（新增）
    - `lib/agent/moon.pkg`（新增）
    - `lib/web/handler/moon.pkg`（新增）
    - `lib/web/protocol/moon.pkg`（新增）
  - **E0020 弃用告警清零**：移除 13 个 `Json` 值上的冗余 `.to_json()` 调用
    - `lib/channel/dingtalk_api.mbt`（4 处）
    - `lib/channel/dingtalk.mbt`（2 处）
    - `lib/channel/discord_api.mbt`（1 处）
    - `lib/channel/feishu_api.mbt`（3 处）
    - `lib/web/handlers_billing.mbt`（3 处）
- `[docs]` **文档指标同步**
  - 更新 CLAUDE.md、README.md、docs/project-status.md 中的指标：
    - 测试用例：3,060+ → 3,093
    - `moon check` 状态：0 errors, ~500 warnings → 0 errors, 0 warnings
- `[verify]` 最终验证：`moon check` 0 errors/0 warnings，`moon test --target native` 3093/3093 pass

### 2026-07-29  feat: 8 个 Agent 增量 Spec 全部实现（session context → skill evolution）

- `[feat]` **Spec-01: Session Context 注入** — `run()` 入口注入 per-run 动态消息（日期/星期/OS/工作目录/模型），`system_injected: true` 标记
- `[feat]` **Spec-02: reasoning_content 字段** — `LlmResponse` + `Message` + 三方协议（OpenAI/Anthropic/Bedrock）流式聚合
- `[feat]` **Spec-03: 空响应检测** — `react_loop_async` 空 content 重试机制，含 thinking-mode 静响应检测
- `[feat]` **Spec-04: compression_threshold 配置** — `AgentConfig.compression_threshold` → `needs_compression()` 使用配置值
- `[feat]` **Spec-05: 压缩失败回滚** — `compress_with_safety` 失败时 `compression_level - 1`，成功时 +1
- `[feat]` **Spec-06: URL Fallback** — `try_url_fallback()` 重试耗尽后切换备用 Base URL，仅触发一次
- `[feat]` **Spec-07: Idle 压缩定时器** — `IdleCompressionTimer` run 完成后启动，新输入取消，266s 触发
- `[feat]` **Spec-08: Skill Evolution 集成** — 成功 run 后自动调用 `run_skill_evolution_hooks()`
- `[chore]` 8 个 spec 从 `draft/` 归档至 `completed/`
- `[test]` 318 agent + 89 skill + 107 client + 59 message = 573 tests 全部通过

### 2026-07-25  refactor: FFI C 依赖消减（S-FFI-01~08）完成
- `[refactor]` **自写 C 代码从 16 文件 / 4,781 行消减至 5 文件 / 610 行；`-lcurl` 全项目清零**
  - HTTP 传输：`lib/client` 的 `http_native.c`/`http_thread.c`/`mb_stubs.c` 迁往 `@async/http`（S-FFI-06）
  - 进程管理：`lib/server` 的 `browser_process.c`、`lib/web`/`lib/server` 的 `git_exec.c` 迁往 `@async/process`（S-FFI-03/04）
  - PTY：`lib/tool` 的 `pty_stubs.c`/`tool_stubs.c` 迁往 `moonbit-community/pty@0.2.2`（S-FFI-08）
  - ZIP/multipart：`miniz_zip.c`、`multipart_upload.c` 改为纯 MoonBit（S-FFI-02/05）
  - 时间/getcwd：迁往 `core/env::now()`、`core/env::current_dir()`、`x/time`（S-FFI-01）
  - brand HTTP：`crypto_native.c` 的 `http_get` 部分迁往 `@async/http`（S-FFI-07）
  - 保留 5 个 C 文件（agent/time_stub、utils/sys_native、tui/console_cp_native、brand/crypto_native、brand/brand_stubs），均有「OS 生态空白」或「安全审计」保留理由
  - 现状详见 [docs/project-status.md](project-status.md)「FFI / C stub 现状」章节；CI 与 Dockerfile 已移除 `libcurl4-openssl-dev` 依赖
- `[docs]` 同步更新 11 个 codemaps、`getting-started.md`、CI 的 FFI/C 描述

### 2026-07-16  chore: Web 服务默认端口统一为 7071

- `[chore]` **默认端口 7070 -> 7071（与原版 OpenClacky 区分，避免本地端口冲突）**
  - 源码 `cmd/main.mbt` 默认端口已为 7071；本次补齐遗留 7070 的文档与部署配置
  - `Dockerfile`（`ENV`/`EXPOSE`/`HEALTHCHECK`）、`deploy/docker-compose.yml`、`deploy/systemd/mbopenclacky.service`、`deploy/README.md`、`README.md`、`AGENTS.md`、`CLAUDE.md`、`docs/getting-started.md`、`assets/skills/product-help/SKILL.md` 全部同步
  - 注释中"兼容原版 OpenClacky"措辞更正为"与原版区分"（原版仍为 7070）
  - 历史条目（2026-06-30 CHANGELOG 记录、已完成 spec）保留原值 7070 不变

### 2026-07-16  docs: 项目文档全量校准（指标同步与过时内容清理）
- `[docs]` **核心指标全量同步（基于实际统计）**
  - 源文件数：289 → **309** 个 `.mbt`（lib + cmd）
  - 测试文件：93 → **103** 个 `_wbtest.mbt`（lib + cmd + test）
  - 包数：23 → **24** 个 lib 顶级包（新增 `lib/zip`）+ 1 个 cmd 入口包
  - REST API 端点数：统一为 **~154**（修正 `codemaps/web.md` 等处的 "90+" 不一致表述）
  - 整体完成度：~90-92% → **~95%**（Web 前端 ~65%→95%、TUI ~85%→95%）
  - 原生二进制大小：~4.6 MB → **~3.8 MB**；`moon check` warnings：46 → **~500**
- `[docs]` **功能状态更新**
  - Web 前端：采用托管 fork 方式导入上游 OpenClacky 原生 JS 资产（87 文件），所有管理面板与 i18n（692 key，覆盖率 99.4%）就位
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
  - 统一 REST API 端点描述为"90+"（消除"127"不一致）
- `[docs]` **受影响文件**：CLAUDE.md、README.md、docs/project-status.md、docs/getting-started.md、codemaps/README.md、codemaps/web.md、codemaps/skill.md
- `[docs]` **codemaps/skill.md 修正**：默认技能清单从 15 个更正为 16 个，补充完整技能名列表，修正"仅资源目录"为 `extend-openclacky` + `meeting-summarizer`

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
  - 更新 wasm-gc 状态为"已评估，建议暂缓"
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

- `[feat]` Bedrock Converse API 格式支持 + 流式聚合器（`lib/client/`）
- `[feat]` Provider 预设从 6 个扩展到 12 个（新增 DeepSeekV4/MiniMax/Kimi/Kimi-Coding/MiMo/GLM）
- `[feat]` 3 个新工具（RequestUserFeedback/TrashManager/Browser），工具总数 11 → 14
- `[test]` +201 个测试用例

### 2026-05-23  Phase 2-10 核心框架搭建（项目初始化至 Agent 增强）

> 项目创建当日完成 Phase 0-10 全部实现，奠定核心架构。

- **Phase 2**: LLM 客户端核心（OpenAI/Anthropic 双协议 + SSE 流式）
- **Phase 3**: 工具系统（10 个工具模块 + ToolRegistry + 安全校验）
- **Phase 4**: Agent 核心（ReAct 循环 + Fallback 状态机 + 成本追踪 + 压缩器）
- **Phase 5**: CLI 入口（clap 解析 + 非交互式运行）
- **Phase 6**: 会话持久化（JSON 文件存储 + 上限清理 + 压缩）
- **Phase 7**: TUI 界面 + Hook 事件系统（10 种生命周期事件）
- **Phase 8**: Web 服务器（crescent 框架 + 20+ REST 端点 + SSE + WebSocket）
- **Phase 9**: 技能系统（SKILL.md 解析/注册/发现/执行）
- **Phase 10**: Agent 增强（Memory/SubAgent/TodoManager/AgentPool + 3 个上下文工具）
- 测试用例：0 → 466，`moon check` 0 errors

