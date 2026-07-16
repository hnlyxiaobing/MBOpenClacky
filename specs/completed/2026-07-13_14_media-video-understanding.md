# Media 视频理解 · 增量 Spec

> **创建日期**: 2026-07-13
> **完成日期**: 2026-07-16
> **状态**: 已完成
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G14（P2 增强性差距）
> **来源差距**: G14 - media 模块视频理解（video/understand）

## 问题描述

原项目 `POST /api/media/video/understand` 端点支持视频理解（上传视频 -> LLM 分析视频内容）。当前 `lib/media/` 有 MediaGenerator 架构但所有 web handler 均为返回 501 的 stub。差距分析中标记 media 模块完成度 75%，实际远低于此。

## 现状分析（经代码验证）

### Media 模块
- `lib/media/` 有 8 个 `.mbt` 源文件：`media_base.mbt`、`dashscope.mbt`、`gemini.mbt`、`openai_compat.mbt`、`generator.mbt`、`types.mbt`、`output_dir.mbt`、`media_wbtest.mbt`（+ `pkg.generated.mbti` 自动生成）
- **注意**：原 spec 提到的 `image_gen.mbt`、`audio_tts.mbt`、`video_gen.mbt` 文件名均不存在
- Media 模块有 `MediaGenerator` 架构，支持 DashScope/Gemini/OpenAI 兼容协议

### Web Handler 现状
- `lib/web/handlers_media.mbt`（84 行）：**所有 5 个 media 端点均为 stub，返回 501 Not Implemented**
  - `POST /api/media/image` -> 501
  - `POST /api/media/video` -> 501
  - `POST /api/media/audio/speech` -> 501
  - `POST /api/media/audio/transcriptions` -> 501
  - `POST /api/media/video/understand` -> 501
- `lib/web/handlers_media_wbtest.mbt` 已存在（63 行），覆盖所有 5 个 stub handler 的 501 状态验证
- **路由已在 `lib/web/server.mbt:516-524` 注册**，无需修改路由注册代码
- 文件头注释："They will be wired to @media.MediaGenerator once the media-capabilities branch lands"
- **结论**：所有 media 端点未接线，handler stub 和路由已就位，仅需替换 501 stub 为真实实现

### LLM Client 视觉能力
- `lib/client/client.mbt:31`：`vision_supported : Bool` 字段存在
- `lib/client/format_openai.mbt`：处理 vision 内容，非视觉模型自动剥离 image blocks
- `lib/client/client_wbtest.mbt`：有 "build_openai_request_strips_image_for_non_vision" 测试
- **结论**：client 层视觉 API 已就绪，视频理解可复用

## 决策

1. **视频理解用帧提取 + LLM 视觉 API**：提取关键帧（每 N 秒一帧），发送给 LLM 视觉模型分析，汇总结果。
2. **帧提取用 FFmpeg**：调用系统 FFmpeg 命令行提取帧，不引入新依赖库。
3. **复用现有 `lib/client` 视觉 API**：`lib/client/` 已支持 `vision_supported` 标志和 image block 处理，视频理解在此基础上构造多帧请求。
4. **REST 端点**：`POST /api/media/video/understand`，接收视频文件上传（base64 编码或 URL），返回分析结果 JSON。
5. **视频上传方式**：首版使用 base64 编码通过 JSON body 上传（避免 multipart 解析依赖），后续可扩展为文件路径或 URL。

## 改动范围

- **涉及包**：`lib/media`、`lib/web`
- **涉及文件**：
  - 新增 `lib/media/video_understand.mbt`：视频理解逻辑（帧提取 + LLM 视觉分析）
  - 修改 `lib/web/handlers_media.mbt`：将 `handle_media_video_understand` 从 501 stub 替换为真实实现
  - 修改 `lib/web/handlers_media_wbtest.mbt`：扩展测试覆盖真实实现（替代当前的 501 stub 测试）
  - **无需修改** `lib/web/server.mbt`：路由 `/video/understand` 已在 L522-524 注册
- **不涉及**：`lib/client`（复用现有 vision API）、TUI、前端

## 实施计划（任务包切分）

1. **视频帧提取**：调用 FFmpeg 提取关键帧到临时目录。
2. **LLM 视觉分析**：多帧发送给视觉模型，汇总结果。
3. **REST 端点实现**：替换 `handle_media_video_understand` 的 501 stub 为真实实现（handler 签名和路由已就位）。
4. **wbtest 更新**：扩展 `handlers_media_wbtest.mbt` 和新增 `media_wbtest.mbt` 测试，覆盖帧提取、分析结果格式。

## 验收标准

- [x] `POST /api/media/video/understand` 可接收视频并返回分析结果
- [x] 分析结果包含视频内容摘要
- [x] 无 FFmpeg 时返回友好错误消息
- [x] `moon check` 0 errors（`lib/media` + `lib/web`）
- [x] `moon test lib/media` 通过（76 tests passed）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| FFmpeg 未安装 | 中 | 启动时检测 FFmpeg 可用性，不可用时返回明确错误 |
| 长视频帧提取耗时 | 中 | 限制最大帧数（20 帧），超长视频截取前 5 分钟 |
| LLM 视觉 API 成本 | 低 | 用户自行承担 API 费用，端点返回 token 消耗 |
| base64 大文件性能 | 中 | 限制上传大小（如 50MB），后续支持 URL/路径方式 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G14，P2 增强性 |
| 2026-07-13 | 审核修正：修正"`image_gen.mbt`/`audio_tts.mbt`/`video_gen.mbt` 已有"的错误（文件名不存在）；修正"media 模块完成度 75%"（实际所有 handler 为 501 stub）；补充 `lib/client` 视觉能力的准确验证（`vision_supported` 字段 + wbtest）；补充视频上传方式决策（base64 JSON body） | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 审核修正：修正文件数（8 个 .mbt 源文件，非 9）；修正 `handlers_media.mbt` 行数（84 行，非 94）；补充实际已有 5 个端点（含 `audio/transcriptions` 和 `video/understand`）；路由已在 `server.mbt:516-524` 注册，无需修改；`handlers_media_wbtest.mbt` 已存在（63 行），仅需扩展非新增；更新实施计划反映当前代码状态 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 实现完成：新增 `lib/media/video_understand.mbt`（类型 + 纯逻辑）和 `lib/media/video_understand_wbtest.mbt`（20+ 测试）；修改 `lib/web/handlers_media.mbt`（替换 501 stub 为完整实现，含 FFmpeg 帧提取 + VisionResolver 视觉分析 + 摘要聚合）；更新 `lib/web/handlers_media_wbtest.mbt`（9 个测试覆盖 400/500 错误路径）；`moon check` 0 errors，`moon test lib/media` 76/76 通过 | 开发完成，验收标准全部满足 |
