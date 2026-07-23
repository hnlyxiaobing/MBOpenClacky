# Brand 与 Config/Media 端点 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.1  
> **关联历史 spec**: 无  
> **来源差距**: GET /api/brand、POST brand/skills/:name/install、GET /api/config/media 缺失或不完整  
> **依赖**: `web-replication-02`  
> **优先级**: P2

## 问题描述 [必填]

1. `GET /api/brand` — 前端启动时获取品牌信息（名称/logo/主题色），当前 404。
2. `POST /api/brand/skills/:name/install` — 品牌预置技能安装，当前 404。
3. `GET /api/config/media` — 设置面板 Media 分区初始化数据（TTS/STT/图片生成配置），当前不完整。
4. `POST /api/my-skills/:name/publish` — 技能发布，当前 404。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| brand 路由 | `grep "brand" lib/web/server.mbt` | 有部分 /api/brand/* 路由 | 需核实 GET /api/brand 是否存在 |
| config/media | `grep "media" lib/web/server.mbt` | 有 /api/config/media 但可能不完整 | 需核实响应字段 |
| lib/brand 包 | `ls lib/brand/` | 存在 | 有品牌配置逻辑 |
| my-skills publish | `grep "publish\|my-skills" lib/web/server.mbt` | 无 | 确认 404 |

### 详细分析

- `GET /api/brand` 返回：`{name, display_name, logo_url, primary_color, version}`
- `GET /api/config/media` 返回：`{tts: {...}, stt: {...}, image_gen: {...}, providers: [...]}`
- brand skills install：将品牌预置技能复制到用户技能目录

## 决策 [必填 - 含为什么]

1. **GET /api/brand 读 lib/brand 配置**：返回当前品牌名（"MBOpenClacky"）+ 默认主题色。
2. **config/media 补全字段**：对照原项目 `http_server.rb` 的 media 段，确保所有字段存在（无配置时给 null/空对象）。
3. **my-skills/publish 可先返回 501**：技能发布涉及远程 registry，非核心功能。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册/修复路由 |
| `lib/web/handlers_brand.mbt` | 修改 | GET /api/brand 实现 |
| `lib/web/handlers_config.mbt` | 修改 | config/media 响应补全 |
| `lib/web/handlers_skills.mbt` | 修改 | publish 端点（501 或实现） |

### 不涉及文件

- `lib/brand/` 核心逻辑
- 前端 JS

## 实施计划 [必填]

### 任务包 1：brand 端点（0.25 天）
- GET /api/brand — 读配置返回品牌信息
- POST /api/brand/skills/:name/install — 技能安装

### 任务包 2：config/media 补全（0.25 天）
- 对照原项目响应格式，补齐缺失字段
- 无配置时给合理缺省值

### 任务包 3：my-skills publish（0.25 天）
- 返回 501 + `{error: "publish not yet supported"}`
- 或对接 lib/skill 实现

## 验收标准 [必填]

- [ ] GET /api/brand 返回正确品牌信息
- [ ] 设置面板 Media 分区可正常渲染
- [ ] brand skills 安装操作有响应
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| config/media 字段多，对照工作量大 | 低 | 缺省值兜底 |
| publish 功能复杂 | 低 | 501 降级 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P2 品牌与设置 |
