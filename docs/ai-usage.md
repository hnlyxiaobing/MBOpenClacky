# AI 使用声明与质量闸门（docs/ai-usage.md）

## 声明

本项目（MBOpenClacky 的「契约化」改造期，2026-09-11 – 09-24）在开发过程中使用了 AI
编程工具辅助实现。**目标、范围、验收标准与最终质量由维护者定义并负责**；AI 产出必须
通过下述机器闸门方可合入。

AI 不参与的部分：验收标准的定义、范围冻结（P0+P1 承诺 / P2 stretch / P3 验收包）、
需求取舍、对「未完成项」是否如实登记的判断。

## 三类机器闸门

任何改动合入前必须同时通过：

| 闸门 | 命令 | 拦住什么 |
|---|---|---|
| 类型与警告 | `moon check`（CI 以 `scripts/warn_count.sh 0 strict` 固定 0 警告预算） | 类型错误、新增编译警告 |
| 公共 API 冻结 | `moon info` 后 `git diff --exit-code -- '**/pkg.generated.mbti'` | 改了公共符号却不提交接口文件（接口文件入库，全仓 31 个） |
| 契约探针 | `moon build --target native --release cmd` 后 `<binary> selftest` | 退出码 / stdout 形状（empty/text/json/json-lines）/ stderr 干净度 / `Failure(`·`Panic(` 泄漏；并对比 `moon run cmd`，差异如实报告 |
| 真话台账 | `scripts/known_gaps.sh check` | 台账与代码不一致：扫描段过期、命中项缺少 curated 状态行、引用不存在的文件 |
| 测试 | `moon test --release`（debug 模式受编译器 ICE 影响，见 `docs/known-gaps.md`） | 回归；含协议往返测试与会话日志 DoD 测试 |

## AI 产出的可验证痕迹

- 协议往返测试：`lib/protocol/protocol_wbtest.mbt`（每个 Event/Command 变体的
  `parse(to_json(e)) == e`）
- 契约探针自检：`cmd/selftest.mbt` 的 `engine_cases`（23 条合成样本，含 live CLI 无法
  确定性产出的 empty / json-lines 形状）
- 会话日志 DoD：`lib/agent/session_log_wbtest.mbt`（截断恢复、压缩字节保持、锁与陈旧
  恢复、旧格式只读投影）
- 未完成项：`docs/known-gaps.md`（由脚本生成扫描段 + 人工 curated 状态 + 已知环境问题）

## 人类审查关注点

AI 产出中需要人工判断而非闸门保证的部分：

1. **范围**：是否夹带了范围外功能（本期范围冻结见 `docs/MBOpenClacky-改造开发计划.md`）
2. **真实性**：文档声明是否与实测一致（本期已修正 README 的 MCP HTTP 不实声明、
   `--version` 与 `moon.mod` 版本漂移、`moon install` 弃用命令等）
3. **取舍**：如 TUI 未绑定 wire 词表、P2 评测未实现——均登记在 `docs/known-gaps.md`
   而非隐去
