# AI 使用声明与质量闸门

## 声明

MBOpenClacky 的开发过程使用了 AI 编程工具辅助分析、实现和文档整理。目标、范围、验收标准、取舍和最终质量由维护者负责。AI 输出只有在通过仓库机器闸门、且与源码/实测一致时才可合入。

AI 不替代人工判断的部分包括：范围冻结、风险取舍、发布决策，以及对“未完成项”是否如实登记的判断。

## 合入闸门

| 闸门 | 命令 | 拦截内容 |
|---|---|---|
| 类型与警告 | `moon check -d`；CI 用 `scripts/warn_count.sh` 固定 0 警告 | 类型错误和新增警告 |
| 公共 API | `moon info`，再检查 `pkg.generated.mbti` diff | 公共符号变化未入库 |
| CLI 契约 | `moon build --target native --release cmd` 后 `<binary> selftest --repo .` | 退出码、stdout/stderr 形状、panic 泄漏、native/moon-run 差异 |
| 确定性评测 | `<binary> eval --offline --repo .` | 工具任务失败或不可重复 |
| 真话台账 | `scripts/known_gaps.sh check` | 扫描段过期、命中项缺 curated 状态、引用失效 |
| 数字一致性 | `scripts/repo_stats.sh check` | README/AGENTS/project-status 的生成数字过期 |
| 回归测试 | scoped `moon test`（完整命令见 [testing.md](testing.md)） | 单元、差分、链路、协议和 harness 回归 |
| 可选浏览器 E2E | `cd test/web-e2e && npm test` | 浏览器 UI/API 组合回归；不作为默认 CI 闸门 |

测试必须使用 scoped 命令，不能裸跑 `moon test`。CI 主步和 `lib/mcp` 分步的口径见 [testing.md](testing.md)。

## 可验证痕迹

- 协议往返测试：`lib/protocol/protocol_wbtest.mbt`。
- CLI 契约探针：`cmd/selftest.mbt` 的 23 个引擎样本和 10 个 native probes。
- 会话日志 DoD：`lib/agent/session_log_wbtest.mbt`，覆盖截断恢复、压缩投影、锁和旧格式只读兼容。
- 能力评测：`test/eval/tool_harness.mbt` + `test/eval/tasks/`，离线任务重复执行以计算可重复性。
- 真模型评测：`test/eval/live_harness.mbt` + `test/capability/tasks/`，报告写 `docs/eval/`。
- 未完成项：`docs/known-gaps.md` 的自动扫描段、人工 curated 表和环境说明。

## 人工审查重点

1. **真实性**：文档命令、端点、数量和状态是否能由当前源码或一次可重复命令证明。
2. **范围**：是否把 draft 设计、历史 spec 或单次实验误写成现时承诺。
3. **安全性**：Web 暴露、认证、加密、shell/PTY、扩展命令和浏览器自动化是否有明确边界。
4. **诚实性**：不可用路径必须返回错误或登记缺口，不能用占位响应伪装成功。
5. **可维护性**：新增数字优先进入 `scripts/repo_stats.sh` 的生成块；新增缺口优先进入 `scripts/known_gaps.sh` 的扫描/curated 流程。
