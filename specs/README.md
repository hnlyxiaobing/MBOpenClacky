# Specs 目录

本目录是 MBOpenClacky 项目的 **活 spec** 体系，所有开发决策的真相源。

> **核心原则**: No Spec, No Code — 超过 100 行改动的任务，先写 spec 再动手。

## 目录结构

```
specs/
├── README.md              ← 你在这里
├── _templates/            ← spec 和任务包模板
│   ├── idea-doc-template.md
│   ├── task-package-template.md
│   └── incremental-spec-template.md
├── draft/                 ← 草稿 spec（待对抗性审查）
├── active/                ← 进行中的 spec
├── completed/             ← 已完成的 spec（归档）
├── deprecated/            ← 被否决或废弃的 spec（方案变更、需求不再适用等）
└── decisions/             ← 架构决策记录（ADR）
```

## 工作流

1. **新任务** → 从 `_templates/` 选模板，在 `draft/` 创建 spec
2. **审查** → 通过对抗性审查后移入 `active/`
3. **开发中** → spec 随开发推进不断回写（活 spec）
4. **checkpoint** → 协作中发现的东西沉淀回 spec
5. **完成后** → spec 从 `active/` 移到 `completed/`
6. **废弃时** → spec 从 `active/` 移到 `deprecated/`（方案变更、需求不再适用等）

## Spec 文件命名规范

- 格式：`YYYY-MM-DD_<short-slug>.md`
- 日期为创建日期
- slug 用 kebab-case

## Active Spec 索引

**当前无活跃 spec**（截至 2026-08-21）。2026-08-18 批次的 28 份 P5/P6 差分对齐 spec（16 份 P5 BUG 修复 + 12 份 P6 矩阵残留簇）已全部实现并归档至 `specs/completed/`，`specs/active/` 已清空。新的开发任务从 `specs/draft/` 起草。

> 历史：上一批活跃 spec 为 2026-07-27 的 T01~T18（gap 分析 18 项），已于 2026-07-27~29 全部完成归档。

## 最近归档 Spec

### 2026-08-21 - P5 差分修复收尾批次（7 项完成 + 总览归档，`specs/active/` 清空）

| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 23 | 可观测性统计字段（P5） | BUG-0006 三协议聚合器补 frames_seen/bytes_seen/parse_failures/saw_done + approximate_output_tokens；BUG-0051 usage 补 cached_tokens 兜底（stream-020 断言=50）；BUG-0034 Latency 7 字段（duration_ms/ttft_ms/tps 等）测量挂载 assistant 消息；BUG-0035 wire 层补 display_text/display_files；known_failure 移除 BUG-0006，stream-005/007/011/012/013/019 统计断言转绿 | test/diff 145/145、test/e2e 14/14、lib/client 123/123、lib/agent 471/471、lib/message 63/63 ✅ |
| 24 | 工具错误 tool_result JSON（P5） | BUG-0040 build_error_result/build_denied_result 输出标准 JSON；wbtest 补 JSON parse + 特殊字符往返 + denied 三字段断言；e2e 014 assert_tool_results_valid_json 闸门移除转绿；known_failure 移除登记 | e2e 014 转绿 ✅ |
| 25 | write 工具边界检查（P5） | BUG-0003 空检查改 trim（纯空白报 "Path cannot be empty"）；BUG-0002 新增 is_dir 预检；BUG-0047 父目录递归创建；write_004 冻结期望按决策 2 修正；known_failure 移除 3 编号 | lib/tool 395 绿、test/diff 145/145、全量 3881 绿 ✅ |
| 26 | edit 工具对齐（P5） | BUG-0044/0045/0046 分层匹配/参数校验/UTF-8 健壮性（edit.mbt 重构 + 新增 string_matcher.mbt 247 行） | lib/tool 全绿 ✅ |
| 27 | 路径处理补全（P5） | BUG-0005/0008 ~user 解析对齐（"user X doesn't exist"，~\foo 同步按 ~user 解析）；BUG-0007 经台账核验判定无效（不修，台账与实测证据不符） | test/diff 145/145 ✅ |
| 28 | 平台 HTTP failover 域名（P5） | BUG-0031 三域 failover 链补齐 | lib/client 全绿 ✅ |
| 29 | Session Context 对齐（P5） | BUG-0033 OS 探测/Desktop/session_date 按日去重 | lib/agent 全绿 ✅ |
| 01 | 矩阵残留 Backlog 总览（索引） | 28 份子 spec 全部归档后，总览索引一并移入 `specs/completed/`，`specs/active/` 清空 | 全量 3843/3843 ✅、moon check 0 errors/0 warnings |

### 2026-08-21 - e2e 链路层补全（P3 收尾，1 项完成）
| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 22 | e2e 链路层补全（P6） | mock 新增 malformed 类型（frames 原始帧逐字节透传）+ finish_override 字段（content/tool_calls 收尾帧）；011 剧本重写混排 4 类畸形帧 + A 级断言回填（status=success/1 请求/final_text）；012 剧本真实下发 stop+tool_calls + 断言重导（2 请求/exit=0）；005 fixture 磁盘化 `test/e2e/fixtures/big.txt` 315000B 与 diff-harness FIXTURES 逐字节一致（删内存生成函数） | test/e2e 14/14 ✅、moon check 0 errors |

### 2026-08-19 — 配置加载对齐 + 消息会话持久化对齐 + 核心循环与 subagent 对齐（3 项完成）

| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 13 | 核心循环与 subagent 对齐（P6） | length 截断恢复（丢 tool_calls + 详细提示 + 3 次致歉 Success）；fake tool call 大小写不敏感正则 + 超限 Error；空响应重试下沉 llm_caller 且排除 stop/length；400 置 pending_error_rollback；fork_subagent 全链路（config 继承/覆盖、lite、forbidden/allowed 执行期拦截）；fan_out/fan_out_labeled（Ruby Fanout 语义 + 超时取消保持 None）；决策 6：AgentPool 移除、max_iterations 上限 200、check_stale! 豁免记录 | lib/agent 434/434 ✅、全量 3773/3773 ✅ |
| 12 | 配置加载对齐（P5） | 决策 1 选项 B：max_tokens 判原版缺陷（CONFIG_SETTINGS_KEYS/to_yaml 双双遗漏），MB 保留加载/保存，config-002/011 冻结 MB 行为（8192/4096）；from_toml 自动锚定 current_model_id（default badge 优先，回退第一个模型，BUG-0014）；switch_model_by_id 失败消息对齐 "model not found"（BUG-0020）；config-012 断言修正 false、BUG-0013 关闭为语义等价；known_failure 移除 5 编号 | lib/config 139/139 ✅、test/diff 145/145 ✅、全量 3756/3756 ✅ |
| 11 | 消息格式与会话持久化对齐 | `Agent.history` 迁移 `MessageHistory`（"(interrupted)" 配对修复 + reasoning pad + rollback 身份语义 + task_chain 过滤）；会话 ID 随机 hex + 文件名日期前缀 + 旧格式兼容；三级清理策略（pinned 豁免 → 软删除 → 回收站）；restore_session_enhanced 生产接线（todos/time_machine/channel_info/previous_total_tokens 恢复 + system prompt 刷新 + 错误回滚）；列表 updated_at 降序 + 前缀匹配；fork 保留 time_machine；`compress_old_sessions_if_needed` 移除（裁决）；全文搜索 snippet + 5000ms 软超时；ZIP 导出导入保留（MB 超集，记录豁免） | lib/agent 417/417 ✅ |

### 2026-08-05 — TUI 全面对齐原版（4 项完成）

| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 00 | 总览（决策反转） | 推翻 tui-parity-08"刻意差异"定位：布局/命令语义完全对齐 openclacky ui2 v1.5.4 | — |
| 01 | 布局对齐 | `brand_layout.mbt` 单一布局（状态栏置底/无框输入区）；`output_buffer.mbt` live_display_lines/commit_oldest_display_lines；commit-scrollback 滚动模型；todo 自动显隐；tips 2s 自动消失；鼠标捕获退役 | 3280/3280 ✅ |
| 02 | 命令语义对齐 | `/clear` 新会话语境（reset_session + idle_timer rebind）；`/undo` 交互菜单 + redo（switch_to_task）；`/model` 两级抽屉 + 持久化；`/config` 连接测试 + 摘要；`?` = `/help`；技能动态斜杠命令 | 3280/3280 ✅ |
| 03 | 扩展功能取舍 | 删除 `/new` `/todo` `/meeting` `/skills`、`/config key value`、文件浏览 + shell 模式、ClaudeCodeLike/Compact 模板、鼠标捕获；保留 `/theme`、Ctrl+Y、GFM 表格、输出折叠、上下文建议、Ctrl+L、`--tui-eval` | tui-eval 46/46 ✅ |

人工确认项：SPEC-01 并排运行原版对比；SPEC-02 C4 连接测试真实网络、C6 真实 LLM 技能调用。

### 2026-07-29 — Agent 增量 Spec（8 项完成）

| Spec | 名称 | 关键实现 | 测试 |
|------|------|---------|------|
| 01 | Session Context 注入 | `react.mbt:build_session_context()` — per-run 动态注入日期/星期/OS/工作目录 | 318/318 ✅ |
| 02 | reasoning_content 字段 | `LlmResponse.reasoning_content` + OpenAI/Anthropic/Bedrock 流式聚合 | 318/318 ✅ |
| 03 | 空响应检测 | `react_loop_async` 空 content 重试机制（含 thinking-mode 静响应） | 318/318 ✅ |
| 04 | compression_threshold 配置 | `AgentConfig.compression_threshold` → `needs_compression()` 使用配置值 | 318/318 ✅ |
| 05 | 压缩失败回滚 | `compress_with_safety` 失败时 `compression_level - 1` | 318/318 ✅ |
| 06 | URL Fallback | `try_url_fallback()` — 重试耗尽后切换备用 Base URL | 318/318 ✅ |
| 07 | Idle 压缩定时器 | `IdleCompressionTimer` — run 完成后启动，新输入取消，266s 触发 | 318/318 ✅ |
| 08 | Skill Evolution 集成 | `run_skill_evolution_hooks()` — 成功 run 后自动检测模式 | 318/318 ✅ |

## 模板说明

| 模板 | 用途 | 适用场景 |
|------|------|---------|
| `idea-doc-template.md` | 0→1 启动 spec | 全新功能/项目，目标还不清楚时 |
| `incremental-spec-template.md` | 1→N 增量 spec | 在现有系统上修改/修复 |
| `task-package-template.md` | 任务包 | 每轮具体执行的任务切片 |
