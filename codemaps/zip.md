# zip - ZIP 压缩/解压 · 纯 MoonBit

> 路径: `lib/zip/` · 2 mbt（src=1, test=1）+ moon.pkg/.mbti · ZIP 归档创建与解压

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `create_zip(entries)` | `zip.mbt` | 创建 ZIP 归档（从文件名+内容列表），返回 `Result[Bytes, String]` |
| `extract_zip(data)` | `zip.mbt` | 解压 ZIP 归档，返回 `Result[Array[ZipEntry], String]` |
| `find_entry(data, name)` | `zip.mbt` | 按文件名查找条目，返回 `Bytes?` |

## 关键类型

- `ZipEntry`（`{ name : String, data : Bytes }`）：ZIP 条目

## 外部依赖

- 无 C FFI。纯 MoonBit 实现（仅依赖 core）：stored-only（method 0）ZIP + 查表法 CRC-32，已替换原 miniz_zip.c（同为 stored-only）

## 使用场景

- 会话导出/导入（`lib/extension/` 调用）
- 文档解析中的 ZIP 容器读取（`lib/parser/` 调用）
