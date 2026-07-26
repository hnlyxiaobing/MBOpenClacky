# 目录浏览路径规范化修复（Windows）· 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-12-dirs-endpoint-contract.md`（fix-12 已对齐 dirs 形状）  
> **来源差距**: BUG-009（P1）  
> **依赖**: 无  
> **优先级**: P1（Windows 文件树路径格式不一致，可能致后续请求失败）

## 问题描述 [必填]

`GET /api/dirs?path=C:/` 在原生 Windows 构建上返回的 entries path 为 `"C://$Recycle.Bin"`（双斜杠），`home` 为 `"C:/Users\\hnlyh"`（混合分隔符），`default` 为 `"C:/Users\\hnlyh/clacky_workspace"`。原项目 entries path 为 `"C:/$Recycle.Bin"`（单斜杠），home 为 `"C:/Users/hnlyh"`（统一正斜杠）。路径格式不一致可能导致文件树后续请求失败，且前端显示不美观。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-009 "Windows 双斜杠/混合分隔符" | 报告 native Windows curl | entries `C://$Recycle.Bin`、home `C:/Users\hnlyh` | 确认（报告观测，原生 Windows） |
| "dirs_fwd_slashes 仅替换反斜杠" | 读 `lib/web/handlers_dirs.mbt:15-17` | `fn dirs_fwd_slashes(path) { path.replace(old="\\", new="/") }`，不处理连续正斜杠去重 | 确认根因：无去重 |
| "entries 用 Path::join" | 读 `lib/web/handlers_dirs.mbt:153-168` | `full = @path.Path::join(@path.Path(target), @path.Path(name)).to_string()`（join 调用在 :153 与 :161）；target 以 `/` 结尾时 join 可能产生双斜杠 | 确认：Windows 上 `C:/` + join 产生 `C://name` |
| "WSL 无法复现" | `curl /api/dirs?path=/tmp/` | WSL 下 entries 为 `/tmp/_wbtest...`（单斜杠，正常） | 确认：双斜杠为 Windows 盘符路径特有；Linux 无此问题 |
| "home 混合分隔符疑点" | 读 handlers_dirs.mbt:101 `home=@utils.home_dir()` + :187 `dirs_fwd_slashes(home)`（default 在 :180） | home 经 dirs_fwd_slashes 应全转正斜杠；报告显示混合，疑为 `@utils.home_dir()` 返回已含正反混合或报告测试时点差异 | 待实施时在 Windows 实测确认 |
| "orig 契约" | 报告对照 orig | 单斜杠、统一正斜杠 | 以 orig 为基准 |

### 详细分析

`dirs_fwd_slashes`（handlers_dirs.mbt:15）只做反斜杠->正斜杠替换，不去重连续正斜杠。当 `@path.Path::join` 在 Windows 盘符路径（`C:/` 结尾）上产生双斜杠时，未被消除。home 字段经 dirs_fwd_slashes 应统一，报告的混合分隔符需在 Windows 实测复核（可能 `home_dir()` 返回值已混合）。

## 决策 [必填 - 含为什么]

1. **`dirs_fwd_slashes` 增加连续斜杠去重**：替换反斜杠后，再 collapse 连续 `/` 为单个 `/`（保留 `C:/` 开头的双斜杠情况除外——盘符 `C:/` 不应变成 `C:`）。需正确处理 Windows 盘符前缀（`X:` 后保留单个 `/`）。
2. **join 后统一规范化**：在 entries/home/default/parent 所有输出路径上统一过 `dirs_fwd_slashes`（多数已过），并保证 join 产生的双斜杠被去重。
3. **不依赖平台分支**：规范化逻辑跨平台一致（Linux 下 `/` 不会被误去重为空），Windows 盘符单独保留。
4. **MoonBit 约束检查**：纯字符串处理，无 AOT/FFI。
5. **需 Windows 实测复核 home 混合分隔符**：实施时在原生 Windows 构建上验证 home/default 也被正确规范化。

<!-- MoonBit 约束：无 AOT trait；无 FFI；纯字符串规范化。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_dirs.mbt` | 修改 | `dirs_fwd_slashes` 增加连续 `/` 去重（处理盘符前缀）；确保所有输出路径过规范化 |
| `lib/web/handlers_dirs_wbtest.mbt` | 修改 | `C://x` -> `C:/x`、`C:/Users\hnlyh` -> `C:/Users/hnlyh` 断言 |

### 不涉及文件

- 目录读取/遍历逻辑
- 路径校验（validate_path，已存在）
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：规范化增强（预估 0.3 天）
- `dirs_fwd_slashes`：先 replace `\`->`/`，再 collapse 连续 `/`（保留 `://` 或盘符 `X:/` 的单斜杠语义）。
- 白盒：`C://$Recycle.Bin` -> `C:/$Recycle.Bin`；`C:/Users\hnlyh` -> `C:/Users/hnlyh`；`/tmp//x` -> `/tmp/x`。

### 任务包 2：Windows 实测复核（预估 0.2 天）
- 原生 Windows 构建上 `curl /api/dirs?path=C:/`，确认 entries/home/default 均单斜杠统一。

## 验收标准 [必填]

- [ ] 白盒：`dirs_fwd_slashes` 正确去重连续斜杠并统一分隔符
- [ ] 原生 Windows `GET /api/dirs?path=C:/` entries path 为 `C:/$Recycle.Bin`（单斜杠）
- [ ] home/default 为 `C:/Users/hnlyh`（统一正斜杠）
- [ ] Linux 下 `/tmp/` 等路径行为不回归（白盒 + WSL curl）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 去重逻辑误伤 `//host` UNC 路径或 `://` 协议前缀 | 中 | 仅 collapse 路径中部连续 `/`，保留前缀 `//`/`://`；白盒覆盖 UNC |
| Windows 实测无法在本环境（WSL）执行 | 中 | 白盒覆盖规范化逻辑；标注需在原生 Windows 复核 home 混合分隔符疑点 |
| `home_dir()` 返回值本身混合需在源头修 | 低 | 若实测确认 home_dir 返回混合，则在 dirs_fwd_slashes 已能统一（无需改 home_dir） |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-009 起草。WSL 无法复现双斜杠（Linux 路径正常），根因为 dirs_fwd_slashes 无去重；home 混合分隔符需原生 Windows 实测复核，已在风险与验收中标注 |
| 2026-07-26 | 审核修正：`Path::join` :159-168 -> :153-168（join 在 :153/:161）；`dirs_fwd_slashes(home)` :200 -> :187（default 在 :180） | 对抗性审核 + 第一性原理校验 |
