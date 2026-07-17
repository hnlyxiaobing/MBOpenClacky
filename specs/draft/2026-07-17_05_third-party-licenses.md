# 第三方许可与来源说明 · 增量 Spec

> **创建日期**: 2026-07-17
> **状态**: 讨论中
> **关联总览**: 大赛验收反馈 #7 - marked/highlight 第三方许可与来源说明
> **来源差距**: highlight.js 和 marked.js 缺少 LICENSE 文件和版本标注
> **依赖**: 无

## 问题描述 [必填]

`web/js/lib/README.md` 中 highlight.js 和 marked.js 的版本列为 `-`，且 `web/js/lib/` 目录下没有任何 LICENSE 文件。

| 库 | 版本 | LICENSE 文件 | README 版本标注 |
|----|------|-------------|----------------|
| highlight.js | v11.9.0 | ❌ 缺失 | ❌ 标注为 `-` |
| marked.js | v12.0.2 | ❌ 缺失 | ❌ 标注为 `-` |
| KaTeX | 0.16.11 | 需确认 | ✅ 已标注 |
| QRCode | 1.5.4 | 需确认 | ✅ 已标注 |
| CodeMirror | 6.0.1 | 需确认 | ✅ 已标注 |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "web/js/lib/ 无 LICENSE 文件" | `find web/js/lib/ -name "LICENSE*"` | 0 结果 | 确认缺失 |
| "README 版本列为 -" | `cat web/js/lib/README.md` | highlight.js 和 marked.js 版本为 `-` | 确认 |
| "highlight.js 版本 11.9.0" | `grep -m1 "version" web/js/lib/highlight.min.js` | 从源码注释提取 | 确认 |
| "marked.js 版本 12.0.2" | `grep -m1 "version" web/js/lib/marked.min.js` | 从源码注释提取 | 确认 |

### 详细分析

**highlight.js**：BSD-3-Clause 许可证。官方仓库 https://github.com/highlightjs/highlight.js/blob/main/LICENSE

**marked.js**：MIT 许可证。官方仓库 https://github.com/markedjs/marked/blob/master/LICENSE.md

**其他库**（KaTeX、QRCode、CodeMirror）：README 已标注版本，但需确认是否有 LICENSE 文件。

## 决策 [必填 - 含为什么]

1. **下载官方 LICENSE 文件**：从 GitHub 官方仓库下载原始 LICENSE 文件，保持内容不变。
2. **更新 README.md**：填入正确的版本号，添加 LICENSE 文件名列。
3. **可选创建汇总文件**：在项目根目录创建 `THIRD_PARTY_LICENSES.md` 汇总所有第三方库许可信息。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/js/lib/LICENSE-highlightjs` | 新建 | 从官方仓库下载的 BSD-3-Clause 许可证 |
| `web/js/lib/LICENSE-marked` | 新建 | 从官方仓库下载的 MIT 许可证 |
| `web/js/lib/README.md` | 修改 | 填入版本号，添加 LICENSE 文件名列 |
| `THIRD_PARTY_LICENSES.md` | 新建（可选） | 汇总所有第三方库许可信息 |

### 不涉及文件

- `web/js/lib/highlight.min.js` - 源文件不修改
- `web/js/lib/marked.min.js` - 源文件不修改
- 其他库文件 - 已标注版本

## 实施计划 [必填]

### 任务包 1：下载 LICENSE 文件（预估 0.5 天）
- 从 GitHub 下载 highlight.js 的 LICENSE 文件（BSD-3-Clause）
- 从 GitHub 下载 marked.js 的 LICENSE 文件（MIT）
- 保存到 `web/js/lib/` 目录
- 确认其他库（KaTeX、QRCode、CodeMirror）的 LICENSE 状态

### 任务包 2：更新 README（预估 0.5 天）
- 更新 `web/js/lib/README.md`，填入 highlight.js 版本 `11.9.0`
- 更新 `web/js/lib/README.md`，填入 marked.js 版本 `12.0.2`
- 添加 LICENSE 文件名列
- 可选：创建 `THIRD_PARTY_LICENSES.md` 汇总文件

## 验收标准 [必填]

- [ ] `web/js/lib/LICENSE-highlightjs` 存在且内容为 BSD-3-Clause
- [ ] `web/js/lib/LICENSE-marked` 存在且内容为 MIT
- [ ] `web/js/lib/README.md` 中 highlight.js 版本为 `11.9.0`
- [ ] `web/js/lib/README.md` 中 marked.js 版本为 `12.0.2`
- [ ] `web/js/lib/README.md` 包含 LICENSE 文件名列
- [ ] Web UI 功能不受影响（纯文档修改）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| LICENSE 文件内容被修改 | 低 | 从官方仓库直接下载原始文件 |
| 版本号不准确 | 低 | 从源码注释中提取版本号 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈 #7 |
