# 路径处理补全：~user 解析 + 绝对路径行为核实（BUG-0005/0008/0007）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0005、BUG-0008、BUG-0007（needs-investigation）；`reports/p5_fix_unit_clustering.md` FU-11  
> **关联历史 spec**: 无（BUG-0004 相对路径修复已完成，commit d4efa4e，本 spec 在其基线上续做）  
> **来源差距**: P2 单元层（path-003/004；BUG-0007 台账证据矛盾待核实）  
> **依赖**: 无（批次 4 工具/安全簇）  
> **灰度 key**: 无

> **B 类冻结标注**：BUG-0005/0007/0008 为 P2.5 冻结的 B 类根因，**复现证据基于 P2.5 前基线，修复前需在当前基线重新验证**（本 spec 已对核心证据完成当前基线源码级核实，见验证记录；fuzz/用例级复跑仍列入任务包）。

## 问题描述 [必填]

1. **BUG-0005/0008（同根因）**：`expand_path` 不解析 `~user`。MB（`lib/tool/security.mbt:225-253`）对 `~user` 原样返回、对 `~\foo` 展开为 `home + "\foo"`；Ruby `File.expand_path("~user")` 尝试解析用户主目录，用户不存在时报错（ruby_results.json 实测：path-003 `~\foo` → "user \foo doesn't exist"，path-004 `~user` → "user user doesn't exist"）。
2. **BUG-0007（needs-investigation，2026-08-14 修订）**：台账称"file_edit 不拒绝绝对路径（ruby 拒绝）"，证据指向 path-016~021；但现行 test_cases.json 仅 18 例，且 ruby_results.json 中 edit-005/006、path-011 均显示 Ruby **未**拒绝绝对路径。**原始结论与实测证据矛盾，必须先核实 Ruby 源码的绝对路径处理真实行为，再定修复方案**——在核实结论落地前不得给 MB 加任何绝对路径拒绝逻辑（若 Ruby 不拒绝而 MB 拒绝，反而制造新分歧）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB expand_path 不解析 ~user" | 读 `lib/tool/security.mbt:225-253` | `~` 后跟非 `/`、非 `\` 时走 else 分支原样返回（行 235-237）；`~\foo` 因行 232-233 的 `\` 前缀检查被展开为 home+`\foo` | 确认 BUG-0005/0008 根因 |
| "Ruby 对 ~user/~\foo 报错（实测）" | 读 `cases/path_handling/ruby_results.json` path-003/004 | path-003：`"error":"user \\foo doesn't exist"`；path-004：`"error":"user user doesn't exist"` | 实测确认参照行为（WSL，File.expand_path 将 `~\foo` 按 ~user 形态解析） |
| "Ruby 工具层 expand_path 语义" | 读 openclacky `lib/clacky/tools/base.rb:36-45` | `~` 开头即 `File.expand_path(path)`（含 ~user 语义）；相对路径一律解析为绝对 | 参照确认 |
| "MB 相对路径分支已修复（BUG-0004 基线）" | 读 `lib/tool/security.mbt:243-252` | 相对路径经 `resolve_path(cwd, path)` 解析为绝对 | 当前基线确认，本 spec 不动此分支 |
| "openclacky 全 lib 无绝对路径拒绝逻辑" | `grep -rn "not allowed\|must be relative\|Absolute paths" D:/MoonBit/openclacky/lib/` | 无任何工具层/安全层绝对路径拒绝命中（仅 terminal 注释、web 前端等无关命中） | BUG-0007 台账"ruby 拒绝绝对路径"初步证伪 |
| "Ruby 文件工具均接受绝对路径" | 读 openclacky `tools/edit.rb:15,34-36`、`tools/write.rb:14,32`、`tools/file_reader.rb:17,49` | 参数描述均为 "absolute or relative"；execute 首步 expand_path 后直接操作，无绝对路径检查 | 初步证伪（任务包 1 补完核对） |
| "安全层只拦凭据路径，不拦绝对路径" | 读 openclacky `tools/security.rb:273-297` | `validate_secret_write` 仅匹配 `.ssh/`、`.aws/` 模式 | 初步证伪 |
| "BUG-0007 无用例可挂闸门" | 读 `test/diff/path_handling_cases_wbtest.mbt:21-26` | 注释自述"没有可挂 known_failure(\"BUG-0007\") 的用例，台账描述与实测证据不符" | 确认 needs-investigation 处置前提 |
| "path_003/004 回归用例挂 BUG-0005 闸门" | 读 `test/diff/path_handling_cases_wbtest.mbt:46-74` | 两处 `known_failure("BUG-0005")`；且注释指出 expand_path 为包内私有函数，test/diff 只能断言 is_secret 公开面 | 修复后需在同包白盒补精确断言 |

### 详细分析

**MB expand_path 现状**（security.mbt:225-253，BUG-0004 修复后版本）：

```
~          → home
~/foo ~\foo → home + 剩余部分        # ← ~\foo 与 ruby 分歧（ruby 按 ~user 报错）
~user      → 原样返回                 # ← BUG-0005/0008：ruby 解析用户主目录，失败报错
相对路径    → resolve_path(cwd, path) # BUG-0004 已修
绝对路径    → 原样返回
```

**Ruby `File.expand_path` 的 ~user 语义**：`~user` 查询该用户主目录（getpwnam），用户不存在抛 `ArgumentError: user X doesn't exist`；`~\foo` 在 POSIX 下 `\` 不是分隔符，同样按用户名 `\foo` 解析并报错。

**BUG-0007 核实进展（本 spec 已完成的初核）**：openclacky 全 lib grep 无绝对路径拒绝逻辑；edit/write/file_reader 参数描述均为 "absolute or relative"；安全层只拦凭据路径；ruby_results 实测 edit-005/006（绝对路径编辑）、path-011（"/foo" 原样保留）均未拒绝。**初步结论：台账"ruby 拒绝绝对路径"系误判**，疑似 P2 时期把 harness driver 的某种包装行为当作 ruby 工具行为。任务包 1 需补完核对（grep/glob/terminal 工具、agent/server 入口、WSL 探针实测）后正式结论。

**平台差异决策点**：`~user` 解析在 POSIX 可读本机 `/etc/passwd`（或 getent）；Windows 无此机制，Windows 版 Ruby 的 `File.expand_path("~user")` 行为需实测（预期 ArgumentError，Ruby Windows 不支持 ~user 展开）。diff-harness 的 ruby 基线全部在 WSL 采集，MB 运行在 Windows 原生——两侧对 `~user` 的"报错"对齐比"解析结果"对齐更现实。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0005/0008 修复形态）**：`expand_path` 的 `~` 分支重构——`~` 后非 `/` 的字符序列（含 `~\foo`，对齐 ruby POSIX 把 `\` 当用户名字符的实测行为）一律按 `~user` 处理：提取用户名 → 查 `/etc/passwd` 解析该用户主目录 → 找到则替换，找不到则使调用方报错（错误消息含 `user \{name} doesn't exist`，对齐 ruby ArgumentError 文案）。
   - **为什么**：与 ruby_results 实测逐条对齐（path-003/004）；读 `/etc/passwd` 文本解析即可覆盖 WSL/Linux 场景，不引入 getpwnam FFI（lib/tool 已 native-only，无 wasm 约束问题）。
2. **决策 2（Windows 语义）**：Windows 原生（无 /etc/passwd）下 `~user` 统一报错，消息同为 `user \{name} doesn't exist`。
   - **为什么**：diff-harness ruby 基线在 WSL 采集、其 ~user 用例全部以报错收场；MB 主运行平台是 Windows，"报错"是两侧唯一可对齐的公共语义。任务包 1 若在 WSL/Windows ruby 实测出其他行为，以实测修订本决策。
   - **存疑**：Windows ruby 的 `File.expand_path("~user")` 真实行为未经实测（无 Windows ruby 环境），列为裁决点。
3. **决策 3（BUG-0007 处置）**：**先核实、后定案**。任务包 1 完成 Ruby 源码全量核对 + WSL 探针实测；预期结论为"ruby 不拒绝绝对路径，台账误判"→ 将 BUG-0007 标记 invalid（证据矛盾证伪）回写 BUGS.md，MB 不加任何拒绝逻辑。若核实发现真实拒绝点（如 agent/server 入口层），再按判定总则对齐并补回归用例。
   - **为什么**：BUG-0007 被标高 severity 安全边界，但当前证据链矛盾；按总则第 6 条（诚实标注不确定性），证据矛盾时只能 needs-investigation，禁止按猜测实现"安全修复"。
4. **决策 4（不做）**：path-016 空串、path-017 纯空白（BUG-0055）、Windows 盘符 `C:\x` 均不动。
   - **为什么**：空串/盘符是 BUG-0004 修复时明示的冻结边界；BUG-0055 已单独立项归 FU-16。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI（/etc/passwd 文本解析用既有 @fs）、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/security.mbt` | 修改 | `expand_path`（行 225-253）`~` 分支重构：`~\` 前缀归入 ~user 处理；新增 ~user → /etc/passwd 解析 + 失败报错路径 |
| `lib/tool/p2_edit_write_wbtest.mbt`（或 `security_wbtest.mbt`） | 修改 | 新增同包白盒：`~user` 不存在用户报错（消息含 "user X doesn't exist"）；`~\foo` 报错；`~root` 等存在用户解析为 /root（POSIX 条件执行） |
| `test/diff/path_handling_cases_wbtest.mbt` | 修改 | path_003（行 52）/path_004（行 68）移除 `known_failure("BUG-0005")`；按可见性限制补公开面断言或改写为引用同包白盒结论 |
| `test/diff/known_failure.mbt` | 修改 | 在册数组移除 BUG-0005、BUG-0008（同根因同修）；BUG-0007 视核实结论移除或保留 |
| `reports/BUGS.md`（diff-harness 侧） | 修改 | BUG-0007 核实结论回写（invalid 或重定义）；BUG-0005/0008 修复记录 |

### 不涉及文件

- `lib/tool/edit.mbt` / `file_reader.mbt` / `write.mbt` — 工具层绝对路径策略待 BUG-0007 核实结论，本 spec 不加任何拒绝逻辑
- `resolve_path`（security.mbt:272-301）— BUG-0004 已修复，不动
- path-016/017/018 边界 — 冻结边界或另案（BUG-0055/FU-16）

## 实施计划 [必填]

### 任务包 1：BUG-0007 核实 + 平台语义实测（预估 0.5 天）

1. 补完 openclacky 核对：grep/glob/terminal 工具、agent.rb/server 入口是否在任何层拒绝绝对路径。
2. WSL ruby 探针：`File.expand_path("~user")`、`File.expand_path("~nosuchuser")`、edit 工具对 `/tmp/...` 绝对路径的实际行为，固化证据。
3. 结论回写 BUGS.md BUG-0007（预期 invalid）；如有意外发现，修订本 spec 决策 3 后再进任务包 2。

### 任务包 2：~user 解析实现（预估 0.5 天）

1. security.mbt `expand_path` `~` 分支重构（决策 1/2）。
2. 同包白盒新增用例；`moon check` 0 errors。

### 任务包 3：闸门移除与回归（预估 0.5 天）

1. path_003/004 移除 BUG-0005 闸门转绿；known_failure.mbt 移除 BUG-0005/0008。
2. `moon test lib/tool`、`moon test test/diff`、全量 `moon test` 无回归。
3. diff-harness 侧复跑 path_handling 用例集比对（path-003/004 两侧一致报错）。

## 验收标准 [必填]

- [ ] `~user`（不存在用户）与 `~\foo` 报错，消息含 "user X doesn't exist"（同包白盒 + path_003/path_004 移除 BUG-0005 闸门转绿）
- [ ] POSIX 下存在用户（如 `~root`）正确解析为主目录（条件性白盒用例）
- [ ] BUG-0007 核实结论回写 BUGS.md（预期 invalid：ruby 不拒绝绝对路径）；核实前 MB 无任何绝对路径拒绝逻辑落地
- [ ] `test/diff/known_failure.mbt` 在册数组移除 BUG-0005、BUG-0008（BUG-0007 按结论处置）
- [ ] `moon check` 0 errors（lib/tool、test/diff）
- [ ] `moon test lib/tool`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| BUG-0007 核实结论推翻"安全边界"认知，后续被质疑放任绝对路径 | 中 | 任务包 1 证据链完整回写 BUGS.md；若业务上仍需安全边界，单独立项为 MB 增强（非对齐项），不走差分修复通道 |
| /etc/passwd 解析在容器/minimal 系统缺条目 | 低 | 找不到条目即报错，与 ruby getpwnam 失败语义一致；不崩溃 |
| Windows 下 ruby ~user 真实行为未知（无实测环境） | 低 | 决策 2 按"报错"对齐 diff-harness WSL 基线；若后续有 Windows ruby 实测再修订 |
| expand_path 调用方（is_secret_path 等）未预期错误路径 | 中 | 现状 expand_path 返回 String 无错误通道；报错需改签名（String raise）或返回原样+日志。实施时核查全部调用点（is_secret_path:115、validate_secret_write），选最小侵入方案并在实施记录说明 |
| path_003/004 受包可见性限制无法精确断言 | 低 | 精确断言放 lib/tool 同包白盒；test/diff 保持公开面断言 + 注释引用 |

## 依赖关系 [必填]

- **前置依赖**：BUG-0004（fixed，commit d4efa4e）——expand_path 相对路径分支是本 spec 的改动基础
- **后置依赖**：FU-10 决策 5 留白（write 是否接 expand_path）依赖本 spec 任务包 1 的核实结论

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-11 |
| 2026-08-14 | BUG-0007 改为"先核实后定案"，任务包 1 前置 | BUGS.md 2026-08-14 修订：台账描述与实测证据矛盾，status 转 needs-investigation |
