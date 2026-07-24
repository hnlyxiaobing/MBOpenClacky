# zip - ZIP 压缩/解压 · C FFI

> 路径: `lib/zip/` · 1 mbt（src=1, test=0）+ moon.pkg/.mbti · ZIP 归档创建与解压

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `create_zip(entries)` | `zip.mbt` | 创建 ZIP 归档（从文件名+内容列表） |
| `extract_zip(data)` | `zip.mbt` | 解压 ZIP 归档（返回文件列表） |

## 关键类型

- 无公开 struct/enum；通过 `extern "C"` FFI 调用底层 miniz 实现

## 外部依赖

- C FFI（miniz_zip）：ZIP 压缩/解压底层实现

## 使用场景

- 会话导出/导入（`lib/extension/` 调用）
- 文档解析中的 ZIP 容器读取（`lib/parser/` 调用）
