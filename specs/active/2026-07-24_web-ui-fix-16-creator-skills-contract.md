# /api/creator/skills 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-07_skills-web-api.md`  
> **来源差距**: I-016（P2）- /api/creator/skills 结构不兼容  
> **依赖**: fix-06（前端验收环境）；被 fix-17 依赖

## 问题描述 [必填]

`GET /api/creator/skills` 期望 `{ok, licensed, cloud_skills, local_skills, ...}`，实际 `{skills, total}`。创作者（Studio）面板据此区分"已发布到平台"与"仅本地"两组技能，当前形状下无法渲染。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-016 "返回 {skills,total}" | `Read lib/web/handlers_skills.mbt:461-474` | `handle_creator_skills` 输出 `{skills, total}`，数据源为 `scan_skills(user_skills_dir(), "user")` | 确认 |
| "路由位置" | `Grep "creator/skills" lib/web/server.mbt` → :561 | `api.get("/creator/skills", ...)` 已注册 | 确认端点存在仅形状不符 |
| "orig 完整语义" | `sed -n '4657,4745p' D:/MoonBit/openclacky/lib/clacky/server/http_server.rb` | orig 返回 `{ok, licensed, cloud_skills, local_skills, platform_fetch_error}`；licensed 取自 `BrandConfig.user_licensed?`；cloud_skills 需授权后 `fetch_my_skills!` 拉平台列表（含 download_count/status/has_local_changes）；local_skills 为未发布的本地技能（含 platform_version/uploaded_at/local_modified_at/shadowing_brand） | 确认逐键语义 |
| "licensed 数据可得" | `Grep "user_licensed" lib/web/handlers_brand.mbt` → :147 | 品牌配置已有 `user_licensed` 派生 | 确认数据源存在 |
| "upload_meta 概念缺失" | `Grep "load_upload_meta" lib/`（隐含）| 当前项目无上传元数据存储 | 确认 platform_version/uploaded_at 无本地数据源 |

### 详细分析

orig 的 cloud_skills 依赖平台服务端（`fetch_my_skills!`），这与 fix-17（publish 501）同属"市场后端是否可对接"的问题族。本 spec 的策略是**形状对齐 + 无平台后端时的降级**：`licensed` 按本地品牌配置真实输出；`cloud_skills` 在无平台对接时为空数组；`platform_fetch_error` 为 null；`local_skills` 输出真实本地技能（upload_meta 相关键给 null）。这样前端 Studio 面板可正常渲染两组结构，发布通路留待 fix-17。

## 决策 [必填 - 含为什么]

1. **形状全对齐、云端数据降级为空**：不发明平台后端；`licensed:false` 时 orig 本就返回空 cloud_skills，降级行为与 orig 未授权路径一致，前端有原生文案兜底（"成为创作者才能上传"）。
2. **local_skills 复用 fix-15 增强后的扫描**：upload_meta 无源的键（platform_version/uploaded_at/local_modified_at/shadowing_brand）给 null/false，文件 mtime 可取则填。
3. **不实现 upload_meta 存储**：属 fix-17 发布链路的持久化问题，本 spec 只做读取形状。
4. **MoonBit 约束检查**：纯 JSON 输出，无约束问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_skills.mbt` | 修改 | handle_creator_skills 输出 {ok,licensed,cloud_skills,local_skills,platform_fetch_error} |
| `lib/web/handlers_skills_wbtest.mbt` | 修改 | 契约断言更新（现有 :200 行测试需改） |

### 不涉及文件

- 平台对接与 publish（fix-17）。
- `/api/skills` 条目字段（fix-15）。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：形状对齐（预估 0.5 天）
- 按 orig 逐键实现输出；licensed 接品牌配置；local_skills 真实数据。
- 白盒测试 + Studio 面板走查（未授权态文案、本地列表渲染）。

## 验收标准 [必填]

- [ ] 响应含 ok/licensed/cloud_skills/local_skills/platform_fetch_error 五键，形状同 orig
- [ ] 本地用户技能出现在 local_skills；未授权时 cloud_skills 为 [] 且 licensed:false
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 前端对 cloud_skills 非空有强依赖的交互不可验 | 低 | 未授权路径 orig 行为一致；fix-17 完成后再端到端验发布态 |
| 与 fix-15 同文件改动冲突 | 低 | 协调实施顺序（fix-15 先行） |

## 依赖关系 [必填]

- **前置依赖**：fix-06；建议 fix-15 先完成（共用 scan_skills）。
- **后置依赖**：fix-17（publish 后 cloud_skills 才能有真实数据）。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-016 起草；已读 orig Ruby 确认逐键语义与降级路径 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_creator_skills@handlers_skills.mbt:462-474 确认输出 {skills,total}（spec 写 :461 实际 :462 差 1 行）；路由@server.mbt:561 确认；user_licensed@handlers_brand.mbt:147 确认（activated.to_json()）。orig Ruby 逐行验证：api_creator_skills@http_server.rb:4664-4745 确认五键响应 {ok,licensed,cloud_skills,local_skills,platform_fetch_error}；licensed=brand.user_licensed?@:4669 确认；unlicensed 时 cloud_skills=[] 降级路径@:4697 确认（与 spec 降级策略一致）；local_skills 含 platform_version/uploaded_at/local_modified_at/shadowing_brand@:4686-4693 确认；upload_meta 概念 MoonBit 侧缺失确认。交叉引用 skills-web-api.md@completed/ 存在。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
