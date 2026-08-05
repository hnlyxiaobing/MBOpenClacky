# media - 多媒体生成 · 多 Provider · 图像/视频/语音

> 路径: `lib/media/` · 10 mbt（8 源 + 2 测试）+ moon.pkg/.mbti · 文生图/文生视频/TTS 多模型适配

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `MediaGenerator::new(config)` | `generator.mbt` | 创建媒体生成器 |
| `MediaGenerator::generate_image(request)` | `generator.mbt` | 生成图像 |
| `MediaGenerator::generate_video(request)` | `generator.mbt` | 生成视频 |
| `MediaGenerator::generate_speech(request)` | `generator.mbt` | 生成语音（TTS） |
| `MediaGenerator::detect_provider()` | `generator.mbt` | 检测可用 Provider |
| `MediaRequest::image(prompt)` | `types.mbt` | 构造图像请求 |
| `MediaRequest::video(prompt)` | `types.mbt` | 构造视频请求 |
| `MediaRequest::speech(text)` | `types.mbt` | 构造语音请求 |
| `MediaOutputDir::new(base_path)` | `output_dir.mbt` | 创建输出目录管理器 |

## 关键类型

### 核心 Struct
- **`MediaGenerator`** - 媒体生成器（config, provider）
- **`MediaGeneratorConfig`** - 配置（provider, api_key, base_url, model, output_dir）
- **`MediaRequest`** - 生成请求（prompt, type, model, size, quality, voice, duration...）
- **`MediaResult`** - 生成结果（success, output_path, error, provider, metadata）

### 枚举
- **`MediaProvider`** - `OpenAICompat | DashScope | Gemini`
- **`MediaType`** - `Image | Video | Speech`
- **`MediaCapability`** - `ImageGeneration | VideoGeneration | SpeechGeneration`
- **`MediaErrorType`** - `UnsupportedProvider | InvalidRequest | ApiError | NetworkError | FileError`

### 输出管理
- **`MediaOutputDir`** - 输出目录管理（ensure_exists, generate_path, list_files, cleanup, total_size）

## 核心调用链

```
Web API /api/media/* 或 Agent
  └─ MediaGenerator::new(config)
      └─ MediaGenerator::generate_image(MediaRequest::image(prompt))
          ├─ detect_provider() -> OpenAICompat/DashScope/Gemini
          ├─ OpenAI:   openai_generate_image()      # openai_compat.mbt
          ├─ DashScope: dashscope_generate_image()    # dashscope.mbt
          └─ Gemini:   gemini_generate_image()       # gemini.mbt
              └─ HTTP API 调用 -> 下载文件 -> MediaOutputDir
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 核心 | `generator.mbt`, `media_base.mbt` | MediaGenerator、配置、Provider 检测、能力查询 |
| 类型 | `types.mbt` | MediaRequest、MediaResult、MediaProvider、MediaType |
| OpenAICompat | `openai_compat.mbt` | OpenAI 兼容图像生成 + TTS |
| DashScope | `dashscope.mbt` | 阿里 DashScope 图像生成（通义万相） |
| Gemini | `gemini.mbt` | Google Gemini 图像 + 视频生成 |
| 视频理解 | `video_understand.mbt` | 视频内容理解 / 抽帧 |
| 输出 | `output_dir.mbt` | MediaOutputDir、文件路径管理、清理 |

## 外部依赖

- `lib/client` - HTTP API 调用
- `moonbitlang/x/fs` - 文件 I/O
- `moonbitlang/core/json` - JSON 序列化

## 风险点

1. **API Key 安全** - Provider API Key 存储在配置中
2. **大文件下载** - 视频/图像文件可能很大，需流式保存
3. **Provider 兼容性** - 不同 Provider 的 API 格式差异大，请求/响应转换易出错
4. **输出目录清理** - `cleanup()` 按时间清理，可能误删用户保留的文件
5. **超时** - 视频生成可能耗时较长，需合理设置超时
