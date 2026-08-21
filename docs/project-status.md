# MBOpenClacky vs openclacky 功能对比分析

> 最后更新: 2026-08-21
> 对比基线: [openclacky](https://github.com/clacky-ai/openclacky) (Ruby) vs [MBOpenClacky](/mnt/d/MoonBit/MBOpenClacky) (MoonBit)

## 1. 项目概况

| 维度 | openclacky (Ruby) | MBOpenClacky (MoonBit) |
|------|-------------------|------------------------|
| 语言 | Ruby ≥ 3.1 | MoonBit (AOT native) |
| 源码文件数 | 428 `.rb` | 512 `.mbt`（排除 `.mbti`） |
| 核心库文件 | 223 (lib/clacky) | 470 (lib/) |
| 二进制大小 | ~50MB+ (含 Ruby 运行时) | ~3.6 MB (单一可执行) |
| 启动时间 | 秒级 | 毫秒级 |
| 包管理 | Bundler / RubyGems | moon (mooncakes) |
| 测试框架 | RSpec | `_wbtest.mbt` (白盒内联)，3,843 用例 |

## 2. 工具集对比

### 原项目 (16 个工具)

| 工具 | 说明 |
|------|------|
| base | 基础工具抽象 |
| browser | 浏览器自动化 |
| edit | 文件编辑 |
| file_reader | 文件读取 |
| glob | 文件搜索 |
| grep | 内容搜索 |
| invoke_skill | 技能调用 |
| request_user_feedback | 用户反馈请求 |
| security | 安全策略工具 |
| terminal | 终端执行 |
| todo_manager | 任务管理 |
| trash_manager | 回收站管理 |
| web_fetch | 网页获取 |
| web_search | 网页搜索 |
| write | 文件写入 |

### 当前项目 (16 个工具)

| 工具 | 说明 | 对标 |
|------|------|------|
| terminal | 终端执行 (PTY) | ✅ terminal |
| file_reader | 文件读取 | ✅ file_reader |
| edit | 文件编辑 | ✅ edit |
| write | 文件写入 | ✅ write |
| glob | 文件搜索 | ✅ glob |
| grep | 内容搜索 | ✅ grep |
| web_search | 网页搜索 | ✅ web_search |
| web_fetch | 网页获取 | ✅ web_fetch |
| browser | 浏览器自动化 | ✅ browser |
| invoke_skill | 技能调用 | ✅ invoke_skill |
| request_user_feedback | 用户反馈请求 | ✅ request_user_feedback |
| todo_manager | 任务管理 | ✅ todo_manager |
| trash_manager | 回收站管理 | ✅ trash_manager |
| security | 安全策略工具 | ✅ security |
| memory_tool | 记忆工具 | 🆕 新增 (原项目通过 skill 实现) |
| pty | PTY 会话管理 | 🆕 新增 (原项目内嵌于 terminal) |

**差距: 0 个缺失工具。** 当前项目覆盖原项目全部 16 个工具，并新增 memory_tool 和独立 PTY 管理。

## 3. 技能 (Skills) 对比

### 原项目 (17 个默认技能)

| 技能 | 说明 |
|------|------|
| browser-setup | 浏览器配置向导 |
| channel-manager | IM 渠道配置管理 |
| code-explorer | 代码探索 |
| cron-task-creator | 定时任务创建 |
| deploy | 部署 (Railway) |
| mcp-manager | MCP 服务器管理 |
| media-gen | 媒体生成 (图片/视频/音频) |
| new | 新项目脚手架 |
| onboard | 项目引导 |
| persist-memory | 持久化记忆 |
| personal-website | 个人主页生成 |
| product-help | 产品帮助 |
| recall-memory | 记忆召回 |
| search-skills | 技能搜索 |
| skill-add | 技能安装 |
| skill-creator | 技能创建/编辑 |
| meeting-summarizer | 会议总结 (SYSTEM_PROMPT 提及) |

### 当前项目 (18 个默认技能)

| 技能 | 说明 | 对标 |
|------|------|------|
| browser-setup | 浏览器配置向导 | ✅ |
| channel-manager | IM 渠道配置管理 | ✅ |
| code-explorer | 代码探索 | ✅ |
| cron-task-creator | 定时任务创建 | ✅ |
| deploy | 部署 | ✅ |
| mcp-manager | MCP 服务器管理 | ✅ |
| media-gen | 媒体生成 | ✅ |
| new | 新项目脚手架 | ✅ |
| onboard | 项目引导 | ✅ |
| persist-memory | 持久化记忆 | ✅ |
| personal-website | 个人主页生成 | ✅ |
| product-help | 产品帮助 | ✅ |
| recall-memory | 记忆召回 | ✅ |
| search-skills | 技能搜索 | ✅ |
| skill-add | 技能安装 | ✅ |
| skill-creator | 技能创建/编辑 | ✅ |
| meeting-summarizer | 会议总结 | ✅ |
| extend-openclacky | 扩展开发向导 | 🆕 新增 |

**差距: 0 个缺失技能。** 当前项目覆盖原项目全部 17 个技能，另新增 extend-openclacky（18 个）。

## 4. 扩展系统 (Extensions)

### 原项目 (6 个默认扩展)

| 扩展 | 说明 | 目录结构 |
|------|------|---------|
| coding | 编码助手 | agents/ + ext.yml |
| general | 通用助手 | agents/ + ext.yml |
| git | Git 操作 | panels/ + ext.yml |
| meeting | 会议辅助 | ext.yml |
| time_machine | 时间机器 | panels/ + ext.yml |
| ext-studio | 扩展工作室 | ext.yml |

### 当前项目

| 状态 | 说明 |
|------|------|
| ✅ 扩展加载器 | `lib/extension/loader.mbt` (10,962 行) |
| ✅ 扩展市场 | `lib/extension/marketplace.mbt` (18,587 行) |
| ✅ 扩展打包器 | `lib/extension/packager.mbt` (6,934 行) |
| ✅ 扩展脚手架 | `lib/extension/scaffold.mbt` (12,488 行) |
| ✅ 扩展验证器 | `lib/extension/verifier.mbt` (6,452 行) |
| ✅ 扩展热补丁 | `lib/extension/patch_loader.mbt` (4,026 行) |
| ⚠️ 默认扩展包 | 无内置扩展包目录 (原项目有 6 个) |

**差距: 缺少 6 个内置默认扩展包。** 扩展框架已完整实现，但未打包默认扩展 (coding/general/git/meeting/time_machine/ext-studio)。用户需通过市场或手动安装扩展。

## 5. 子系统对比

### 5.1 核心子系统

| 子系统 | 原项目 | 当前项目 | 状态 |
|--------|--------|----------|------|
| Agent 核心 | agent.rb | lib/agent/ (多个文件) | ✅ 完整 |
| 会话管理 | session.rb | lib/agent/session.mbt | ✅ 完整 |
| 上下文管理 | context_manager.rb | lib/agent/context.mbt | ✅ 完整 |
| 工具注册表 | tool_registry.rb | lib/tool/registry.mbt | ✅ 完整 |
| 技能系统 | skill.rb + skill_manager.rb | lib/skill/ (多个文件) | ✅ 完整 |
| Hook 系统 | hook_manager.rb | lib/agent/hook.mbt + lib/hook/ | ✅ 完整 |
| 时间机器 | time_machine.rb | lib/agent/time_machine.mbt | ✅ 完整 |
| 空闲压缩 | idle_compression_timer.rb | lib/agent/idle_timer.mbt | ✅ 完整 |
| GEP 进化 | skill_evolution.rb + skill_reflector.rb + skill_auto_creator.rb | lib/skill/evolution.mbt + reflector.mbt + auto_creator.mbt | ✅ 完整 |

### 5.2 网络/通信

| 子系统 | 原项目 | 当前项目 | 状态 |
|--------|--------|----------|------|
| Web Server | lib/clacky/server/ (36 文件) | lib/server/ (21 文件) + lib/web/ (85 文件) | ✅ 完整 |
| REST API | lib/clacky/web/ (多个 handler) | lib/web/handlers*.mbt | ✅ 完整 |
| WebSocket | ws.js + ws-dispatcher.js | lib/web/broadcast/hub.mbt | ✅ 完整 |
| MCP 协议 | lib/clacky/mcp/ | lib/mcp/ | ✅ 完整 |
| 流式聚合 | *_stream_aggregator.rb (3 文件) | format_*.mbt (3 文件) | ✅ 完整 |
| Provider 管理 | providers.rb (1084 行) | lib/config/provider.mbt | ✅ 完整 |

### 5.3 IM 渠道

| 渠道 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| 飞书 (Feishu) | server/channel/adapters/feishu/ | lib/channel/feishu*.mbt | ✅ 完整 |
| 企业微信 (WeCom) | server/channel/adapters/wecom/ | lib/channel/wecom*.mbt | ✅ 完整 |
| Telegram | server/channel/adapters/telegram/ | lib/channel/telegram*.mbt | ✅ 完整 |
| Discord | server/channel/adapters/discord/ | lib/channel/discord*.mbt | ✅ 完整 |
| 钉钉 (DingTalk) | server/channel/adapters/dingtalk/ | lib/channel/dingtalk*.mbt | ✅ 完整 |
| 微信 (Weixin) | server/channel/adapters/weixin/ | lib/channel/weixin*.mbt | ✅ 完整 |

**差距: 0 个缺失渠道。** 6/6 渠道全部覆盖。

### 5.4 文档解析器

| 解析器 | 原项目 | 当前项目 | 状态 |
|--------|--------|----------|------|
| PDF | pdf_parser.rb + 3 个 Python 脚本 | lib/parser/pdf.mbt | ✅ |
| DOCX | docx_parser.rb | lib/parser/docx.mbt | ✅ |
| PPTX | pptx_parser.rb | lib/parser/pptx.mbt | ✅ |
| XLSX | xlsx_parser.py | lib/parser/xlsx.mbt | ✅ |
| DOC | doc_parser.rb | lib/parser/doc.mbt | ✅ |
| WPS | wps_parser.rb | lib/parser/wps.mbt | ✅ |

**差距: 0 个缺失解析器。** 原项目 PDF 解析有 3 个 Python 辅助脚本 (OCR/plumber/VLM)，当前项目用 MoonBit 原生实现。

### 5.5 部署/运维

| 组件 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| Dockerfile | ✅ | ✅ | ✅ |
| docker-compose | ❌ 无 | ✅ deploy/docker-compose.yml | 🆕 超越 |
| systemd | ❌ 无 | ✅ deploy/systemd/ | 🆕 超越 |
| Homebrew | ✅ homebrew/ | ✅ deploy/homebrew/Formula/ | ✅ |
| Windows 安装器 | ❌ 无 | ✅ deploy/windows/*.iss | 🆕 超越 |
| logrotate | ❌ 无 | ✅ deploy/logrotate.d/ | 🆕 超越 |
| GitHub Actions | ✅ .github/workflows/ | ✅ .github/workflows/ | ✅ |
| 安装脚本 | install.sh + install.ps1 | install.sh + install.ps1 | ✅ |
| 卸载脚本 | uninstall.sh | uninstall.sh + uninstall.ps1 | ✅ |
| Desktop Installers | ❌ 无 (目录不存在) | ❌ 无 | — |

**差距: 当前项目在部署运维方面超越原项目，** 额外提供了 systemd、docker-compose、Windows ISS 安装器、logrotate 等配置。

### 5.6 Web 前端

| 组件 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| SPA 框架 | Vanilla JS (app.js 37KB) | Vanilla JS | ✅ |
| CSS | app.css (403KB) | web/style.css 等 | ✅ |
| 会话管理 | sessions.js (249KB) | lib/web/handlers_sessions.mbt | ✅ |
| 项目管理 | projects.js (57KB) | lib/web/handlers_projects*.mbt | ✅ |
| 设置页面 | settings.js (115KB) | lib/web/handlers_settings*.mbt | ✅ |
| 技能管理 | skills.js (18KB) | lib/web/handlers_skills*.mbt | ✅ |
| 国际化 | i18n.js (142KB) | lib/web/handlers_i18n*.mbt | ✅ |
| WebSocket | ws.js + ws-dispatcher.js | lib/web/broadcast/hub.mbt | ✅ |
| 设计样本 | design-sample.html/css | web/design-sample.html | ✅ |
| 微信二维码 | weixin-qr.html | web/weixin-qr.html | ✅ |
| 主题切换 | theme.js | ✅ | ✅ |
| 认证 | auth.js | lib/web/handlers_auth*.mbt | ✅ |

**差距: Web 前端功能基本完整。** 原项目的 Rich UI / UI2 组件系统 (lib/clacky/ui2/) 在当前项目中以 TUI 形式实现。

### 5.7 账单系统

| 组件 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| 账单记录 | billing/billing_record.rb | lib/billing/billing_record.mbt | ✅ |
| 账单存储 | billing/billing_store.rb | lib/billing/billing_store.mbt | ✅ |
| Web 界面 | web/features/billing/ | lib/web/handlers_billing.mbt | ✅ |
| 汇率转换 | — | lib/web/handlers_exchange_rate.mbt | 🆕 新增 |

### 5.8 备份/浏览器管理

| 组件 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| 备份管理器 | server/backup_manager.rb | lib/server/backup_manager.mbt | ✅ |
| 浏览器管理器 | server/browser_manager.rb | lib/server/browser_manager.mbt | ✅ |
| Git 面板 | server/git_panel.rb | lib/server/git_panel.mbt + git_staging.mbt | ✅ |

### 5.9 代理/品牌/配置

| 组件 | 原项目 | 当前项目 | 状态 |
|------|--------|----------|------|
| 代理配置 | proxy_config.rb | lib/utils/proxy_config.mbt | ✅ |
| 品牌配置 | brand_config.rb (90KB!) | lib/brand/ + lib/web/handlers_brand.mbt | ✅ |
| Agent Profile | agent_profile.rb | lib/agent/profile.mbt + profile_types.mbt | ✅ |
| Telemetry | telemetry.rb | ✅ | ✅ |
| 调度器 | server/scheduler.rb | lib/server/scheduler.mbt + cron.mbt | ✅ |

## 6. 独有功能

### 6.1 仅原项目有

| 功能 | 说明 | 影响 |
|------|------|------|
| Rich UI / UI2 系统 | lib/clacky/rich_ui.rb + lib/clacky/ui2/ | 低 - TUI 56 个文件已覆盖终端 UI |
| Fanout 系统 | lib/clacky/fanout.rb | 低 - fan_out/fan_out_labeled 已按 Ruby Fanout 语义实现（spec 13） |
| Search Config (Tavily) | lib/clacky/search_config.rb | 低 - web_search 已实现 |
| ~~Benchmark 基础设施~~ | ~~benchmark/ (fixtures + results)~~ | ✅ 已解决 - `test/benchmark/` 已实现（runner/scenario/stats/comparator/timer/persistence） |
| ~~默认扩展包~~ | ~~6 个内置扩展~~ | ✅ 已解决 - 已在 `assets/extensions/` |

### 6.2 仅当前项目有

| 功能 | 说明 | 价值 |
|------|------|------|
| memory_tool | 独立记忆工具 (区别于 skill) | 高 — 更灵活的记忆管理 |
| PTY 会话管理 | 独立 pty.mbt + pty_session.mbt | 高 — 更好的终端会话控制 |
| AOT 原生编译 | 单一 3.6MB 可执行文件 | 高 — 零依赖部署 |
| 静态类型安全 | ADT + Checked Error + Option[T] | 高 — 编译期错误检测 |
| 部署运维套件 | systemd + docker-compose + logrotate + ISS | 高 — 生产级部署支持 |
| 汇率转换 | handlers_exchange_rate.mbt | 低 — 国际化账单支持 |
| MoonBit 生态集成 | moon build/check/test/fmt | 中 — 现代工具链 |

## 7. 总体评估

### 功能完成度

| 类别 | 完成度 | 说明 |
|------|--------|------|
| 工具集 | **100%** | 16/16 全部覆盖 + 2 个新增 |
| 技能 | **100%** | 17/17 全部覆盖 |
| IM 渠道 | **100%** | 6/6 全部覆盖 |
| 文档解析器 | **100%** | 6/6 全部覆盖 |
| Web 前端 | **~95%** | 功能完整，Rich UI 组件差异 |
| 扩展系统 | **100%** | 框架完整 + 6 个内置扩展 (coding/general/git/meeting/time_machine/ext-studio) |
| 部署运维 | **110%** | 超越原项目 |
| MCP 协议 | **100%** | 完整实现 |
| 账单系统 | **100%** | 完整实现 + 汇率扩展 |
| 核心引擎 | **100%** | Agent + Session + Context + Hook |

### 总体完成度: **~99%**

MBOpenClacky 已实现 openclacky 的几乎所有核心功能，并在以下方面超越原项目:
1. **部署运维**: systemd / docker-compose / logrotate / Windows ISS
2. **工具扩展**: memory_tool + 独立 PTY 管理
3. **性能**: AOT 编译，3.6MB 单一可执行，毫秒启动
4. **类型安全**: 编译期错误检测，消除运行时 nil 错误

### 差分测试对齐（P2~P6，2026-08-21 全部完成）

以 diff-harness 沉淀（`test/diff` 145 用例、12 个 e2e 剧本、BUGS.md BUG-0001~0057、FEATURE_MATRIX 357 条目）为基线的行为对齐已全部完成，28 份 spec 归档于 `specs/completed/2026-08-18_02~29`：

- **P2 单元差分回归**: `test/diff` 145/145 通过（known_failure 闸门纪律）
- **P3 e2e 剧本**: `test/e2e` 14/14 通过（mock LLM server + 畸形 SSE 注入 + fixture 磁盘化）
- **P5 BUG 修复**: 16 份 spec 覆盖流式截断、重试退避、压缩语义、配置加载、错误分类、计费遥测等
- **P6 矩阵残留对齐**: 12 份 spec 覆盖只读工具、安全执行器、LLM 请求格式、消息持久化、核心循环、CLI、Web API、技能提示词、配置深度、计费遥测、e2e 链路层
- **全量测试**: `moon test` 3,843/3,843 通过，`moon check` 0 errors / 0 warnings

### 主要差距 (1%)

1. ~~Benchmark 基础设施~~ ✅ 已解决 - `test/benchmark/` 已实现（runner/scenario/stats/comparator/timer/persistence + wbtest）
2. ~~默认扩展包~~ ✅ 已解决 - 6 个内置扩展已在 `assets/extensions/`
3. ~~Rich UI 组件~~ ✅ 已覆盖 - TUI 56 个文件已对齐 ui2

### 建议优先级

| 优先级 | 任务 | 预估工作量 | 状态 |
|--------|------|-----------|------|
| P2 | 建立 Benchmark 基础设施 | 2-3 天 | ✅ 已完成（`test/benchmark/`） |
| P3 | P4 真模型基准（需真 API key + WSL Ruby 环境） | 待定 | 方法学见 `specs/completed/2026-08-18_01_diff-harness-matrix-backlog-overview.md` §6 |
