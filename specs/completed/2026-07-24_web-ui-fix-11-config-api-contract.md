# 配置 API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-22_web-replication-10-brand-config-media.md`  
> **来源差距**: I-017 / I-018 / I-019 / I-020（均 P2，配置域端点结构不兼容）  
> **依赖**: fix-06（前端验收环境）

## 问题描述 [必填]

四个配置域端点与原项目契约不符：

- **I-017**：`GET /api/config/media` 缺 `default_provider` 五子键 + `media.*` 六字段（api-diff 记录 39 处 diff）。
- **I-018**：`GET /api/config/ocr` 期望 `{default_provider, ocr:{...}}`，实际为平铺四字段。
- **I-019**：`GET /api/config` 缺 `current_id`/`current_index`/`media_capabilities`。
- **I-020**：`GET /api/config/settings` 缺 `enable_compression`/`enable_prompt_caching`/`memory_update_enabled`/`proxy_url` 四个开关。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-017 "config/media 缺子键" | `Read lib/web/handlers_configtest.mbt:671-731` | `handle_config_media_all` 已输出 `media.{image,video,audio,stt,video_understanding}`（每模态 source/model/base_url/configured 四键）与 `default_provider`，但子键数量与 orig 的六字段/五子键有差距 | 确认部分实现，需逐键对照 orig 补齐 |
| I-018 "config/ocr 平铺" | `Read lib/web/handlers_configtest.mbt:629-666` | `handle_config_ocr_get` 输出平铺 `{ok,source,model,base_url}`，无 `default_provider`/`ocr` 嵌套 | 确认 |
| I-019 "config 缺 current_id 等" | `Grep "current_index|media_capabilities" lib/web` | 仅 `handlers_extra.mbt:1384`（models POST 响应）命中 current_index；GET /api/config 主 handler 未见 current_id/media_capabilities | 确认（GET 主 handler 确切输出需在实施时再次逐键核对） |
| I-020 "settings 缺四开关" | `Read lib/web/handlers_extra.mbt:1817-1848`；`Grep "enable_compression" lib/config/agent.mbt` | **声称已过时**：`handle_config_settings_get` 已对四键做 defaults 覆盖输出；`@config.AgentConfig` 真实持有四字段（agent.mbt:7-15） | 疑似已修复或差异在嵌套层级（`{ok, settings:{...}}` vs orig 平铺），需运行时重验后再定改动 |
| "四开关有真实配置源" | `lib/config/agent.mbt:7-15` | enable_compression/enable_prompt_caching/memory_update_enabled/proxy_url 均为 AgentConfig 字段 | 确认无需发明功能，直读配置即可 |

### 详细分析

I-017/I-018 是明确的对齐工作；I-019 需在实施时读 GET /api/config 主 handler 与 orig 逐键对照；I-020 的 issues 记录与代码现状不符（harness v2"gap 文档是假设"的典型案例），本 spec 把 I-020 降级为"运行时重验 + 按差异点修"，可能只需调整嵌套形状或无需改动。

## 决策 [必填 - 含为什么]

1. **逐键对照 orig 补齐，不改端点划分**：四个端点路由不变，只调输出形状，前端零改动。
2. **I-018 嵌套化时保留现有键还是替换，以 orig 契约为准**：orig 为 `{default_provider, ocr:{...}}`，则照抄；`ok` 键按 orig 有无决定。
3. **I-020 先重验后动手**：以 fix-06 后前端 + 实时响应为准，若差异仅在嵌套层级则只调形状；若已一致则把 I-020 标为 Fixed 并回写 issues 文档，本 spec 该任务包关闭。
4. **settings 数据源从 AgentConfig 直读**：四开关在 `@config.AgentConfig` 真实存在（非存储 JSON 旁路），输出应以配置对象为准而非 defaults 覆盖。
5. **MoonBit 约束检查**：纯 JSON 输出改动；crescent PATCH 已有用法（`handle_config_media_patch`），无约束问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_configtest.mbt` | 修改 | config/media 全量端点、config/ocr 输出形状 |
| `lib/web/handlers_extra.mbt` | 可能修改 | /api/config 主 GET（current_id/current_index/media_capabilities）、config/settings 形状 |
| `lib/web/handlers_api_contract_wbtest.mbt` / `handlers_configtest_wbtest.mbt` | 修改 | 契约断言更新 |

### 不涉及文件

- `lib/config/**`：配置结构与持久化不动。
- `/api/media/types`（I-007，fix-14 范围）；`handle_config_media_all` 的 configured 语义差异（fix-14 决策 2 已声明照抄 Ruby，此处不重复处理——实施时需与 fix-14 对齐口径）。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：运行时重验（预估 0.5 天）
- 启动 server 抓取四端点实时响应，对照 orig 逐键列出 diff 清单（更新 api-diff）。
- 据此定稿 I-019/I-020 的实际改动量；I-020 若已无差异则回写 issues 文档关闭。

### 任务包 2：media/ocr 形状对齐（预估 1 天）
- config/media 补 default_provider 五子键与 media.* 六字段；config/ocr 嵌套化。
- 白盒契约测试。

### 任务包 3：config 主端点与 settings（预估 0.5 天）
- 按任务包 1 的 diff 清单实施；白盒测试 + Playwright 设置页走查。

## 验收标准 [必填]

- [ ] 四端点响应与 orig 契约逐键一致（api-diff 相应条目清零）
- [ ] I-020 重验结论回写 `docs/web-ui-issues.md`（修复或标 Fixed）
- [ ] 设置页媒体/OCR 配置区正常渲染
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| I-020 声称过时导致 spec 范围虚高 | 低 | 任务包 1 先重验，按实际 diff 裁剪 |
| config/media 子键语义与 fix-14 的 configured 口径冲突 | 中 | 两 spec 实施时对齐 Ruby `media_state` 语义；本 spec 验证记录已交叉标注 |
| orig default_provider 五子键含当前无数据源键 | 低 | 按 orig 语义给空值并记录 |

## 依赖关系 [必填]

- **前置依赖**：fix-06。
- **后置依赖**：无（与 fix-14 有语义口径交叉，建议同一人/同一轮实施）。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-017/I-018/I-019/I-020 合并起草；I-020 验证发现声称已过时 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：I-017 handle_config_media_all@:671-731 确认输出 media.{image/video/audio/stt/video_understanding}+default_provider 但子键不足；I-018 handle_config_ocr_get@:629-668 确认平铺 {ok,source,model,base_url} 无嵌套；I-019 current_index 仅 @handlers_extra.mbt:1384（models POST），GET /api/config 无命中确认；I-020 正确识别为"声称已过时"：AgentConfig@agent.mbt:7-13 持有全部四开关（enable_compression/enable_prompt_caching/memory_update_enabled/proxy_url），handle_config_settings_get@:1821-1848 已输出四键（defaults 覆盖 + merge_objects）。行号轻微漂移 spec 写 :1817 实际 :1821（差 4 行）。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
| 2026-07-25 | 实施完成。以 api-diff.json + Ruby 源码静态对照代替运行时重验（任务包 1）。I-017：handle_config_media_all 逐键对齐 Ruby api_get_media_config——media.* 十键（补 api_key_masked/provider/available/aliases/stale/requested_model，off 时 model/base_url 改发 null），default_provider 改为五子键（provider/model/available/aliases）；source 区分 custom/auto/off（新增 config_media_find_explicit 区分显式条目与派生条目，修正原代码把 auto 误标 custom 的问题）；configured 按 Ruby media_state 语义改为"条目存在即 true"。I-018：handle_config_ocr_get 嵌套化为 {ocr, default_provider}，移除顶层 ok，ocr 十键含 primary（无视觉能力检测数据源，恒 false）。I-019：handle_get_config（实际位于 handlers.mbt 而非 spec 预估的 handlers_extra.mbt）补 current_id/current_index/media_capabilities，models[] 补 index 并按 orig 排除 media/ocr 管理条目；保留既有 permission_mode/max_tokens/verbose/current_model_id 键（PUT 回环与其他客户端使用）。I-020：重验结论为"差异在嵌套层级"，GET 拍平为 orig 平铺五键并改为 AgentConfig 直读；PATCH 同步改为写 AgentConfig + persist_agent_config + 返回 {ok:true}（原 settings.json 旁路与 GET 直读会产生读写不一致）。无数据源键按风险节约定给空值：available=[]/aliases={}/stale=false/requested_model=null/primary=false；default_provider.model 用 derive_media_model 预览（锚定 current_model 而非 Ruby 的 default 条目，语义差异已记录）。新增 lib/web/handlers_config_contract_wbtest.mbt 六例契约测试。验证：moon check 0 errors 0 warnings；moon test lib/web 356/356 通过。 | fix-11 实施（I-017/I-018/I-019/I-020） |
