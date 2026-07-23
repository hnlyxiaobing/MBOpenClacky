# vision - 视觉理解 · OCR · 图像描述 · 缓存

> 路径: `lib/vision/` · 6 mbt（src=4, test=2）+ moon.pkg/.mbti · 图像/视觉理解能力抽象层

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `VisionOCR::new()` | `ocr.mbt` | 创建 OCR 实例 |
| `VisionOCR::ocr(image_path)` | `ocr.mbt` | **主入口** - 对图像执行 OCR 文字识别 |
| `VisionOCR::is_available()` | `ocr.mbt` | 检查 OCR 服务是否可用 |
| `VisionResolver::new()` | `resolver.mbt` | 创建视觉解析器 |
| `VisionResolver::describe(input)` | `resolver.mbt` | 图像描述/视觉问答（调用多模态 LLM） |
| `VisionResolver::check_cache(key)` | `resolver.mbt` | 检查缓存 |
| `VisionResolver::cache_result(...)` | `resolver.mbt` | 缓存结果 |

## 关键类型

### OCR
- **`VisionOCR`** - OCR 引擎（持有 VisionResolver）
- **`OCRProvider`** - OCR 提供者 trait（`pub(open)`）：`ocr_name()`, `is_available()`, `ocr(path)`
- **`OCRResult`** - OCR 结果（text, confidence, regions）

### 视觉解析
- **`VisionResolver`** - 视觉解析器（config, cache）
- **`VisionConfig`** - 配置（model, max_tokens, cache_enabled, cache_dir）
- **`VisionInput`** - 输入枚举：`VisionBytes(Bytes) | DataUrl(String) | FilePath(String)`
- **`VisionResult`** - 结果（status, text, cached, error?）
- **`VisionStatus`** - `Ok | NotSupported | Error | Empty`

## 核心调用链

```
# OCR 文字识别
VisionOCR::ocr(image_path)
  └─ OCRProvider::ocr(path)
      └─ VisionResolver::describe(VisionInput::FilePath(path))
          ├─ VisionResolver::check_cache(cache_key)
          │   └─ cache hit -> 返回缓存结果
          └─ cache miss -> 调用多模态 LLM -> cache_result()

# 图像描述
VisionResolver::describe(input)
  └─ compute_cache_key(input, prompt)
  └─ 构建 LLM 请求（含 image content block）
  └─ Client.send_request() -> VisionResult
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `ocr.mbt` | VisionOCR、OCRProvider trait、OCRResult、count_ocr_words |
| `resolver.mbt` | VisionResolver、describe、缓存管理、compute_cache_key |
| `types.mbt` | VisionConfig、VisionInput、VisionResult、VisionStatus、构造器 |

## 外部依赖

- `lib/client` - 多模态 LLM 调用
- `lib/message` - ImageBlock、ContentBlock 构建图像请求
- `lib/config` - ModelConfig（视觉模型配置）
- `moonbitlang/x/fs` - 图像文件读取、缓存文件 I/O

## 风险点

1. **缓存失效** - 缓存基于内容哈希，模型变更后旧缓存可能不适用
2. **大图像** - base64 编码大图像可能导致请求体过大
3. **Provider 依赖** - OCR 依赖多模态 LLM，无独立 OCR 引擎
4. **缓存目录增长** - 无自动清理机制，缓存可能持续增长
5. **并发缓存写入** - 多个 describe 调用并发写入同一缓存文件可能冲突
