# 技能发布到市场（publish）· 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md`  
> **关联历史 spec**: `specs/completed/2026-07-07_skills-web-api.md`  
> **来源差距**: G-002 - 技能发布到市场未实现（POST /api/my-skills/:name/publish 固定 501，P2）  
> **依赖**: fix-15（技能数据通路）、fix-16（creator/skills 形状与 licensed 口径）

## 问题描述 [必填]

`POST /api/my-skills/:name/publish` 路由存在但固定返回 501（`lib/web/server.mbt:546-554`，注释自承 "publish not yet supported"），前端 Skills/Studio 面板的"发布"操作无法走通。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| G-002 "固定 501" | `Grep "publish" lib/web/server.mbt` → :546-554 | handler 固定返回 501 + `{error: "publish not yet supported"}` | 确认 |
| "orig publish 完整流程" | `sed -n '5295,5380p' D:/MoonBit/openclacky/lib/clacky/server/http_server.rb`；`sed -n '529,590p' brand_config.rb` | 五步：① `user_licensed?` 否则 403；② 技能不存在 404；③ source 为 default/brand 则 422（内置技能不可发布）；④ 技能目录打 ZIP（排除 `__pycache__/.git/node_modules` 等目录与 `.pyc/.so/.exe` 等模式）；⑤ HMAC-SHA256 签名（license_key 对 `user_id:device_id:ts:nonce`）multipart POST `/api/v1/client/skills`（force=true 时 PATCH 覆盖）；成功后 `record_upload!` 记录 platform_version，返回 `{ok,name,platform_version}`；已存在返回 422 + `already_exists` | 确认逐键/逐步语义 |
| "licensed 门卫数据可得" | `Grep "user_licensed" lib/brand/config.mbt` → :174 | `BrandConfig::user_licensed()` 存在 | 确认 |
| "ZIP 能力" | `codemaps/zip.md` + `ls lib/zip`（隐含） | 项目已有 zip 包（会话导入导出在用） | 确认有基础，需核实是否支持"创建"ZIP（导出侧） |
| "multipart 上传能力" | `Grep "multipart" lib/` | 仅 channel 层有半成品（discord 有 boundary 常量但 body 构建为 TODO），无通用 multipart POST 客户端 | 确认需新建，是主要工作量 |
| "upload_meta 持久化" | fix-16 验证记录 | 当前项目无 upload_meta 存储 | 确认需新增（记录 platform_version/uploaded_at） |

### 详细分析

orig 的发布是一个真实的云上传管线（签名 + multipart + 平台 API）。当前项目品牌/授权基础设施已存在（`BrandConfig.user_licensed`、license_key、device_id），但缺三段：ZIP 构建、multipart 客户端、upload_meta 持久化。需要决策的核心问题是**平台后端对接口径**：orig 上传到 openclacky 厂商平台，MBOpenClacky 是否对接同一平台、用同一 license 体系，需人工确认（见风险）。

## 决策 [必填 - 含为什么]

1. **按 orig 五步流程完整实现，不做"形状对齐的假发布"**：publish 是写操作，假实现对用户是数据欺骗；实现不了平台对接就保持明确错误而非假成功。
2. **本地可独立完成的四步先行**（licensed 403 / not-found 404 / builtin 422 / ZIP 构建 + 排除规则），平台上传作为任务包 3，中间任何一步失败按 orig 状态码返回——即使平台对接最终未确认，前四步也让端点行为基本对齐。
3. **multipart 客户端实现为 lib/client 或 lib/web 内的最小私有实现**（只支持本用途的单文件 binary part），不抽象通用 multipart 库；channel 层的 TODO 不在本 spec 范围。
4. **upload_meta 用 JSON 文件存于品牌配置目录**（参照 orig `record_upload!` 语义），键为技能名，值含 platform_version/uploaded_at，供 fix-16 的 local_skills 读取。
5. **平台 base URL 与 license 互通性作为人工确认 gate**：实施前需确认 MBOpenClacky 的 license 能否调用目标平台 API；不能则任务包 3 降级为"返回 503 + 明确错误信息"，其余步骤照常交付。
6. **MoonBit 约束检查**：ZIP 用现有 lib/zip（需先核实导出能力）；HTTP 上传走 `@client` 既有异步 POST 或原生 HttpRequest 扩展，无动态 trait；不涉及 FFI 新增。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | :546-554 501 stub 替换为真实 handler 接线 |
| `lib/web/handlers_skills.mbt`（或新建 handlers_publish.mbt） | 修改/新建 | publish 五步流程 |
| `lib/brand/config.mbt` | 可能修改 | upload_meta 读写（record_upload/load_upload_meta） |
| multipart 上传实现（新文件） | 新建 | 单用途 multipart POST/PATCH |
| `lib/web/handlers_skills_wbtest.mbt` | 修改 | 各错误分支 + 成功路径（mock 平台）测试 |

### 不涉及文件

- fix-16 的 creator/skills 读取形状（只约定 upload_meta 文件格式接口）。
- channel 层 multipart TODO。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 0：人工确认（gate）
- 确认平台对接口径（目标 base URL、license 互通性、是否允许对接 orig 平台）。结论记入变更记录。

### 任务包 1：前置校验与 ZIP（预估 1 天）
- licensed/存在性/builtin 三分支 + ZIP 构建与排除规则（照抄 orig 清单）。
- 白盒测试（三分支 + ZIP 内容断言）。

### 任务包 2：上传与持久化（预估 1 天）
- HMAC 签名 + multipart 客户端 + force 参数 PATCH 路径。
- upload_meta 落盘；成功/失败（含 already_exists）响应形状。
- mock 平台的白盒测试；平台对接未确认时按决策 5 降级。

## 验收标准 [必填]

- [ ] 未授权 403、技能不存在 404、内置技能 422，响应形状同 orig
- [ ] 成功路径返回 `{ok,name,platform_version}`；重复发布返回 422 + already_exists，force=true 走覆盖
- [ ] upload_meta 落盘可被 fix-16 的 local_skills 读取（platform_version/uploaded_at 非空）
- [ ] `moon check` 0 errors（lib/web、lib/brand）；`moon test lib/web lib/brand` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 平台后端不对 MBOpenClacky 开放（license 不互通） | 高 | 任务包 0 人工确认；不互通则上传步降级 503 明确错误，不造假成功 |
| lib/zip 只支持读取/解压不支持创建 | 中 | 任务包 1 先核实；缺则补 ZIP 写入（参考 make-moonbit-c-bindings 或纯 MoonBit deflate 现有能力） |
| multipart 实现引入二进制体 bug（ZIP 含 null 字节） | 中 | 照抄 orig 二进制拼接注意事项；测试用含二进制内容的 ZIP |
| license_key 参与签名/传输的泄露面 | 中 | key 不出进程，只发 hash 与 HMAC 签名（orig 已是此设计，照抄即可） |

## 依赖关系 [必填]

- **前置依赖**：fix-15、fix-16；任务包 0 的人工确认。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | G-002 起草；已读 orig 源码确认五步流程与签名方案 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：publish 501 stub@server.mbt:548-555（spec 写 :546-554 差 2 行）确认返回 {error:"publish not yet supported"}；BrandConfig::user_licensed()@brand/config.mbt:174 确认；multipart 能力缺口确认--discord upload_file@discord_api.mbt:136 有 boundary 常量但 body 构建为 TODO（spec 描述精确）；lib/zip/zip.mbt 存在确认。orig Ruby 逐行验证：api_publish_my_skill@http_server.rb:5295-5380 确认五步流程（① licensed 403@:5298 ② not-found 404@:5307 ③ builtin 422@:5315 ④ ZIP 排除 __pycache__/.git/.svn/node_modules/.cache+.pyc/.so/.exe@:5341-5342 ⑤ upload_skill!+record_upload!@:5355,5372）；成功 {ok,name,platform_version}@:5370、已存在 422+already_exists@:5374 确认。人工确认 gate 已标注。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
