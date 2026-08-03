# working_dir 用户输入规范化 · 增量 Spec

> **创建日期**: 2026-08-03
> **状态**: 已完成
> **关联总览**: `docs/2026-08-03-web-ui-fix-adversarial-review.md`（遗留问题 3）
> **关联历史 spec**: `specs/completed/2026-07-29_working-dir-normalization.md`
> **来源差距**: 2026-08-03 对抗性审查（Issue 3 同类残留）
> **依赖**: 无

## 问题描述 [必填]

2026-07-29 的修复只规范化了**系统构造**的默认工作目录（home 分支，2026-08-03 又补了 config 分支），但两个**用户可控输入入口**仍未规范化，Windows 上用户手输/粘贴 `C:\Users\foo\proj` 或混合分隔符路径会原样入库并展示，与同 session 其他路径展示风格不一致：

1. `POST /api/sessions` 请求体的 `working_dir`（`lib/web/handlers.mbt:233`：原样 `=> wd`）
2. `PATCH /api/sessions/:id/working_dir` 的 `new_dir`（`lib/web/handlers_session_ext.mbt:288`：原样入库）

本 spec 的定位是**一致性/展示规范化 + 防御性纵深**：经审核确认，`wd_is_within_dir`（`handlers_session_ext.mbt:345-356`）函数体首行已对 `dir`/`target` 双双调用 `wd_normalize_sep` 内部归一，且 `validate_path`（handlers_files.mbt:10-19，PATCH :255 先于一切执行）拒绝任何含 `..` 的输入——**当前不存在"混合分隔符削弱校验"的现存安全弱点**（初稿该声称未经读码验证，审核予以纠正）。让校验与落盘作用于同一个规范形式仍是更稳的结构（校验语义不依赖每个校验点各自归一的自觉）。另注：`POST /api/sessions` 的 `working_dir` 没有 `validate_path`/越界校验，与 PATCH 不对称，属既有缺口，另案处理，不在本 spec 范围。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "POST body working_dir 未规范化" | 读 `lib/web/handlers.mbt:230-237` | `Some(String(wd)) if !wd.is_empty() => wd` 原样返回 | 确认 |
| "PATCH new_dir 未规范化" | 读 `lib/web/handlers_session_ext.mbt:283-288` | `working_dir: new_dir` 原样入库 | 确认 |
| "PATCH 校验对原始输入直接比较" | 读 `lib/web/handlers_session_ext.mbt:260-280` + `wd_is_within_dir` 实现 :345-356 | 调用点传原始 `new_dir`，但函数内部首行 `wd_normalize_sep` 双向归一；`validate_path`（:255）先行拒绝 `..` | **初稿"校验被削弱"声称不成立**；现状安全，改进定位为一体化/纵深 |
| "规范化函数已存在且幂等" | 读 `lib/web/handlers_dirs.mbt:17-31` | `dirs_fwd_slashes`：`\`→`/`、折叠重复 `//`、保留 UNC 前导 `//` | 确认可复用 |
| "wd_is_absolute 已识别两种分隔符" | 读 `lib/web/handlers_session_ext.mbt:332-339` | 同时识别 `/` 与 `\` | 确认规范化不破坏绝对路径判定 |
| "前端 picker 路径已规范" | 2026-07-29 分析文档 Bug 3 章节 | `/api/dirs` 输出经 `dirs_fwd_slashes` | 仅手输/粘贴路径受影响，影响面低 |

### 详细分析

`dirs_fwd_slashes` 是本代码库既定的路径展示规范化（正斜杠在 Windows API 全有效，2026-07-29 spec 已论证）。信任边界原则：外部输入应在入口规范化一次，下游所有消费者（持久化、展示、校验）都面对规范形式。当前两个入口漏网。

## 决策 [必填 - 含为什么]

1. **两个入口统一在解析后立即 `dirs_fwd_slashes`**。为什么：与 2026-07-29/2026-08-03 已确立的规范化策略一致；幂等，对已规范输入无影响；Linux/WSL 常见输入不含 `\`，实践中是恒等变换（极端例外见风险表）。
2. **PATCH 中规范化先于 `wd_is_within_dir` 校验**（校验实现见 `handlers_session_ext.mbt:345-356`）。为什么：该校验内部虽已自行归一分隔符，现状无安全弱点；但"校验作用于落盘所用的同一规范形式"是更稳的纵深结构——校验正确性不再依赖每个校验点各自记得归一。审核已双向推演：`dirs_fwd_slashes`（比内部归一多做 `//` 折叠）不会把原本接受的变成拒绝；唯一判定变化是 `C://base/sub` 类从拒绝变接受，而 Windows 上 `C://base` 本就等价 `C:\base`，新判定反而更正确；UNC 前导 `//` 被显式保留，不受影响；`..` 输入在 `validate_path` 阶段即被拒，与规范化无交互。
3. **不做平台风格输出（Windows 反斜杠）**。为什么：与既定决策一致（全平台统一正斜杠展示），避免来回摇摆。

MoonBit 约束检查：不涉及。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | :233 `=> dirs_fwd_slashes(wd)` |
| `lib/web/handlers_session_ext.mbt` | 修改 | PATCH 解析 `new_dir` 后立即规范化，再做绝对性/包含性校验 |
| `lib/web/handlers_session_ext_wbtest.mbt` | 修改 | 混合分隔符输入用例：入库值为正斜杠规范形式；`..\` 类相对路径行为不变 |

### 不涉及文件

- `lib/web/handlers_dirs.mbt`（`dirs_fwd_slashes` 本身不动；`handle_dirs_mkdir` 响应的 `@path.Path::join` 反斜杠问题另案，不在本 spec）
- `lib/agent/session_serializer.mbt` 的 import 入口（`handle_session_import`/`import_sessions_zip`）：ZIP 内 `working_dir` 指向**导出机器**的路径，分隔符规范化之外还涉及跨机路径是否重写的问题，属另案；本 spec 仅处理本机用户直接输入的两个入口（审核确认这是第三个用户可控入口，显式排除）
- 前端（仅展示后端返回值）

## 实施计划 [必填]

### 任务包 1：两个入口规范化 + 测试（预估 0.5 天）
1. 改 `handlers.mbt:233`。
2. 改 PATCH：读 `wd_is_within_dir` 实现 → 规范化置于校验前 → 改 `new_dir` 入库值。
3. 白盒测试：POST/PATCH 传 `C:\Users\foo/proj` → 响应与落盘均为 `C:/Users/foo/proj`；PATCH 越界路径（如 `C:/other` 超出配置目录）仍被拒绝。
4. `moon check` + `moon test lib/web`。

## 验收标准 [必填]

- [ ] POST body 带混合分隔符 `working_dir` → session 落盘与响应为规范形式
- [ ] PATCH 带混合分隔符 `new_dir` → 入库为规范形式，且 `wd_is_within_dir` 校验对规范形式执行
- [ ] 相对路径（如 `sub/dir`）行为不变
- [ ] Linux/WSL 路径行为不变（恒等）
- [ ] `moon check` 0 errors；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 规范化改变用户意图（极少数依赖 `\` 的场景） | 低 | 正斜杠在 Windows API 全有效（2026-07-29 spec 已论证） |
| Linux 合法文件名含 `\`（如目录 `foo\bar`）会被改写为正斜杠路径 | 低 | 实践中罕见；审核确认该边缘场景存在并予以接受，措辞从"零回归"修正为"实践中恒等" |
| 先规范化影响既有校验通过率（原本拒绝的变成接受） | 低 | 审核已双向推演：唯一判定变化（`C://base` 类）方向更正确；越界用例仍纳入任务包回归测试 |
| 与正在进行的其他 session 字段改造冲突 | 低 | 改动仅两行量级 |

## 依赖关系 [必填]

- **前置依赖**：`specs/completed/2026-07-29_working-dir-normalization.md`（已落地，含 2026-08-03 config 分支补丁）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-03 | 初始版本 | 对抗性审查发现用户输入入口未规范化 |
| 2026-08-03 | 对抗性审核修订：纠正事实错误——`wd_is_within_dir` 内部已归一分隔符且 `validate_path` 先行拒绝 `..`，"校验被削弱"声称不成立，定位改为一致性/纵深；import 入口（session_serializer）显式排除并注明理由；"零回归"软化并补 Linux 反斜杠文件名风险行；行号 :341+ 修正为 :345-356 | Spec Review Gate（PASS-WITH-FIXES，高×1/中×1/低×2） |
| 2026-08-03 | 实施完成：POST/PATCH 两个入口 dirs_fwd_slashes（PATCH 规范化先于校验）；3 个新白盒测试；moon test lib/web 446/446。 从 specs/active/ 归档至 specs/completed/ | 开发验收通过（Harness 步骤 9-10） |
