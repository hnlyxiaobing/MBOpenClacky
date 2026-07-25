# ZIP 归档迁移至纯 MoonBit Stored-Only · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 讨论中
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-02）
> **来源差距**: `docs/ffi-c-code-report.md` 第 10 节
> **依赖**: 无

## 问题描述 [必填]

`lib/zip/native-stub/miniz_zip.c`（545 行）实现 ZIP 归档的创建/提取，对外是 8 个 FFI + handle 模型。代码审计（见下）发现：**该 C 实现根本不压缩，所有 entry 写入 compression method = 0（stored），extract 端也只是 `memcpy` 原始字节**——所谓「deflate method 8」是注释里的愿景，不是现状。

既然现状就是 stored-only，本 spec 的目标是纯 MoonBit 重写这层（极薄的）ZIP 容器逻辑，删除整个 C 文件。**不需要 deflate、不需要 gzip、不需要引入 `@async/gzip`**。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| C 端写入 compression=0 | `grep -n "write_le16.*0.*compression" lib/zip/native-stub/miniz_zip.c` | 第 325/354 行写 `0`，注释 `/* compression (stored) */` | **stored-only，非 deflate** |
| C 端 extract 无解压 | 读 `miniz_zip.c:460-475` | `memcpy(entry->data, input + data_offset, comp_size)` 直接复制 | 仅 stored 路径 |
| C 端自述意图 | 读 `miniz_zip.c:161-163` | `For a production version, we'd integrate miniz's deflate. This implementation stores entries uncompressed (method 0).` | 注释自承 stored-only |
| zip 对外 API | `grep -n "pub fn\|pub struct" lib/zip/*.mbt` | `create_zip`/`extract_zip`/`find_entry`/`ZipEntry` | 三个公开函数 + 一个结构 |
| miniz 无外部依赖 | `cat lib/zip/moon.pkg` | 仅 `native-stub: [miniz_zip.c]`，无 link | 自包含，删后无链接副作用 |
| 消费方 | `grep -rn "@zip\.\|lib/zip" lib/ cmd/ --include="*.mbt"` | `agent/session_serializer.mbt`（多处）、`web/handlers_publish.mbt`（:121/:126） | 两个消费方，API 需保持兼容 |

### 关键反驳：初版 spec 的两处错误

1. **「写入 Deflate method 8」错误**：实际写 method 0，无压缩。
2. **「复用 `@async/gzip` deflate 内核」错误**：`@async/gzip` 是 gzip wrapper（10 字节头 + CRC32 trailer），不暴露 raw deflate 流；且其 API 是 async Reader/Writer 模式，与 ZIP 同步 Bytes 处理模型不匹配。**幸好现状根本不需要 deflate，此坑自然绕开**。

### 详细分析

- 现有 ZIP 写出路径：构造 Local File Header（30 字节定长头 + 文件名）→ 写入原始数据 → 写 Central Directory（46 字节定长头 + 文件名）→ 写 EOCD（22 字节定长）。CRC-32 取自 entry 字段。
- 现有 ZIP 解析路径：扫 EOCD → 读 Central Directory 找 entry → 跳到 Local File Header → `memcpy` 数据。**忽略 compression 字段**。
- 容器层是固定字节布局，MoonBit `Bytes`/`Buffer` 完全胜任；CRC-32 用纯 MoonBit 实现（约 30 行，查表法）。
- 消费场景均为非热路径（session 打包、扩展发布），stored-only 的体积代价可接受。

## 决策 [必填 - 含为什么]

1. **Stored-only 纯 MoonBit ZIP（不引入 deflate/gzip）**：现状本来就不压缩，迁移后语义完全等价。最小变更、零依赖、零风险。
2. **对外 API 签名保持不变**：`create_zip`/`extract_zip`/`find_entry`/`ZipEntry` 不变，两个消费方零改动。
3. **CRC-32 用 IEEE 多项式查表法**：约 30 行纯 MoonBit，无需引入包。
4. **读取端继续忽略 compression 字段**：与 C 端行为一致。如果未来读到 method 8 的 ZIP，返回错误而非崩溃（边界处验证，提高健壮性，相对 C 端是改进）。
5. **不引入社区 `zipc`/`fzip`/`flate`**：stored-only 场景下都是过度方案。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/zip/zip.mbt` | 重写 | 删 8 个 FFI，纯 MoonBit 实现 stored-only 容器层 + CRC-32 |
| `lib/zip/native-stub/miniz_zip.c` | 删除 | 整文件 |
| `lib/zip/native-stub/` 目录 | 删除 | 若为空目录则一并删 |
| `lib/zip/moon.pkg` | 修改 | 删 `native-stub` 字段 |
| `lib/zip/zip_wbtest.mbt` | 新增/扩展 | stored-only ZIP 创建/解析/CRC/往返互操作测试 |

### 不涉及文件

- `lib/agent/session_serializer.mbt`、`lib/web/handlers_publish.mbt`（消费方，API 不变）

## 实施计划 [必填]

### 任务包 1：纯 MoonBit stored ZIP（预估 0.5 天）
- 实现 CRC-32（IEEE 查表法）
- 实现 `create_zip`：写 Local File Header + 原始数据 + Central Directory + EOCD
- 实现 `extract_zip`：扫 EOCD → 解 Central Directory → 跳 Local File Header → 提取数据；若 method ≠ 0 返回错误
- 实现 `find_entry`：基于 `extract_zip` 的便捷查找
- 保留 `ZipEntry` 结构与原 API 签名
- 删 `miniz_zip.c` 与 native-stub
- 验证门：`moon check` + `moon test lib/zip`

### 任务包 2：互读写回归（预估 0.25 天）
- 用 `unzip` 解开迁移后生成的 ZIP；用项目代码解开 `zip` 命令生成的 stored-mode ZIP（`zip -0`）
- 校验 session 打包/解包往返一致（`moon test lib/agent` 不回归）
- 验证门：手动 `moon run cmd` 跑一次会话保存 + 恢复

## 验收标准 [必填]

- [ ] `moon check` 0 errors
- [ ] `moon test lib/zip` 通过
- [ ] `miniz_zip.c` 已删除，`lib/zip/moon.pkg` 不再含 `native-stub` 字段
- [ ] 迁移后生成的 ZIP 可被标准 `unzip` 解压（method 0 stored）
- [ ] 项目代码可解开 `zip -0` 命令生成的 stored ZIP
- [ ] 项目代码读 method 8 ZIP 时返回明确错误（而非崩溃或错数据）
- [ ] `moon test lib/agent` 不回归
- [ ] `moon fmt` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 历史 session 包若由未来支持 deflate 的版本生成，将无法解压 | 兼容性 | 现有 C 实现也是 stored-only，历史包必然 method 0；风险不存在 |
| 容器层字节布局写错 | ZIP 损坏 | 对照 APPNOTE.TXT；任务包 2 用 `unzip -t` 与 `zip -0` 双向互操作验证 |
| CRC-32 实现错误 | 数据校验失败 | 用已知向量（"123456789" → 0xCBF43926）测试 |
| 体积膨胀（无压缩） | session 文件变大 | 与现状一致，非回归；将来若需压缩再单独提 spec |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本（deflate 方案） | 依据 reduce-ffi-c-dependency-plan.md §4.4 |
| 2026-07-25 | 推翻 deflate 方案，改 stored-only | 对抗性审核发现 C 实现本就 stored-only（method 0），「deflate method 8」「复用 `@async/gzip`」均为错误前提 |
