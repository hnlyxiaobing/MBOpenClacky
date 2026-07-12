# 任务包：Meeting（会议）功能支持

> **关联 spec**: 本任务包为独立功能开发  
> **创建日期**: 2026-07-13  
> **状态**: 进行中

## 目标

在 MBOpenClacky 中实现会议（Meeting）能力，包括会议数据的 CRUD 管理、REST API 端点、以及 meeting-summarizer 默认 skill 注册。用户可以创建会议记录、上传转录文本、触发摘要生成，并通过 Web UI 或 API 管理会议生命周期。

## 边界

### 要做

- 在 `lib/web/handlers_meetings.mbt` 中实现 MeetingData 数据模型和持久化层（JSON 文件存储，遵循 trash/schedules 模式）
- 实现 6 个 REST API 端点（CRUD + summarize），通过 bridge 模式接入 crescent 框架
- 在 `lib/web/server.mbt` 中注册 `/api/meetings` 路由组
- 在 `lib/web/handlers_bridge.mbt` 中添加 meeting bridge 函数
- 在 `lib/skill/default_skills.mbt` 中注册 `meeting-summarizer` skill
- 创建 `assets/skills/meeting-summarizer/SKILL.md` skill 提示词
- 编写白盒测试 `lib/web/handlers_meetings_wbtest.mbt`

### 明确不做

- 不创建独立的 `lib/meeting/` 包（数据层内联在 `lib/web/` 中，与 trash/schedules 一致）
- 不实现实际的 AI 摘要生成逻辑（summarize 端点返回待处理状态，实际摘要由 skill 系统异步执行）
- 不修改现有代码的 `use` -> `using` 语法迁移
- 不修改 `lib/extension` 包（非 cmd 依赖，moon check 已有 622 个已知错误）

## 自由度

- **模型可以**：选择具体的数据字段命名、JSON 序列化格式、ID 生成策略
- **但不能**：引入新依赖包、修改 moon.pkg 的 import 列表（lib/web 已有所有需要的依赖）、改变现有代码风格

## Checkpoint 规则

- 每次准备改代码前先复述 diff 计划
- 发现"想做但不应做"的事情，立刻暂停汇报
- 引入新依赖前必须 checkpoint
- 跨包改动前必须 checkpoint

## 验收标准

- [ ] `moon build --target native cmd` 0 errors
- [ ] `moon test lib/web --filter "meeting*"` 全部通过
- [ ] REST API 端点完整：GET/POST/PUT/DELETE + summarize
- [ ] 数据持久化到 `~/.mbopenclacky/meetings.json`
- [ ] meeting-summarizer skill 已注册并可通过 API 列出

---

## 实现方案

### 数据模型

```moonbit
pub(all) struct MeetingData {
  id : String
  title : String
  transcript : String
  summary : String?
  participants : Array[String]
  status : String         // "active" | "completed" | "summarized"
  created_at : String     // epoch-seconds
  updated_at : String     // epoch-seconds
}
```

### REST 端点

| Method | Path | Handler | 说明 |
|--------|------|---------|------|
| GET | `/api/meetings` | `handle_meetings_list` | 列出所有会议 |
| POST | `/api/meetings` | `handle_meetings_create` | 创建会议 |
| GET | `/api/meetings/:id` | `handle_meetings_get` | 获取单个会议详情 |
| PUT | `/api/meetings/:id` | `handle_meetings_update` | 更新会议 |
| DELETE | `/api/meetings/:id` | `handle_meetings_delete` | 删除会议 |
| POST | `/api/meetings/:id/summarize` | `handle_meetings_summarize` | 触发摘要生成 |

### 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_meetings.mbt` | 新建 | 数据模型 + 持久化 + CRUD handlers |
| `lib/web/handlers_bridge.mbt` | 修改 | 添加 6 个 bridge 函数 |
| `lib/web/server.mbt` | 修改 | 注册路由组 |
| `lib/web/handlers_meetings_wbtest.mbt` | 新建 | 白盒测试 |
| `lib/skill/default_skills.mbt` | 修改 | 添加 meeting-summarizer |
| `assets/skills/meeting-summarizer/SKILL.md` | 新建 | Skill 提示词 |

---

## 验收报告（完成后填写）

### 改了什么

- 新建/修改了哪些文件（diff 摘要）

### 跑了什么验证

- `moon build --target native cmd` -> 结果
- `moon test lib/web --filter "meeting*"` -> 结果

### 验收标准对照

- [ ] 标准 1：✅/❌
- [ ] 标准 2：✅/❌

### 没覆盖的

- 实际 AI 摘要生成（由 skill 系统异步执行）
- Web UI 前端组件

### 后续排查建议

- 如果 persist 出问题，检查 `@utils.config_dir()` 返回值
- 如果路由 404，检查 server.mbt 路由注册顺序
