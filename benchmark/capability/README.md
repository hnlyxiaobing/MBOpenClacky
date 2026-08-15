# 端到端能力基准（capability benchmark）

> 手动触发的真模型能力基准。**不进 CI**（成本与不确定性高）。
> 本目录当前为骨架：diff-harness P4 阶段未执行，20~30 个 golden 任务集尚未建立。
> 本规程定义了运行方法与判分口径，任务集待扩充。

## 目的

在真实模型下统计对比 MBOpenClacky 与 Ruby openclacky 的能力表现：

- 成功率（任务完成判定）
- 平均轮数 / token 消耗
- 失败模式分布（死循环 / 幻觉工具调用 / 上下文溢出 / 解析失败）

## 任务集规范

每个任务一个 JSON 文件放 `tasks/` 下（待建）：

```json
{
  "id": "cap-001",
  "title": "读取并修改文件",
  "files": {"hello.txt": "..."},
  "prompt": "...",
  "acceptance": "自然语言判分标准（由判分脚本/人工核对）",
  "source": "派生自 diff-harness scenarios/001_read_edit_file.json"
}
```

初始任务种子（建议，派生自已验证的 P3 剧本）：001 read_edit、003 multi_turn、004 parallel、014 tool_failure_recovery。
扩充方向：长上下文压缩触发、多文件重构、错误恢复——每类 3~5 个，总量 20~30。

## 运行方法

1. 准备真实模型配置（两侧同一模型同一参数）：
   - MB 侧：`MBOPENCLACKY_API_KEY/BASE_URL/MODEL` 环境变量或 `~/.mbopenclacky/config.toml`
   - Ruby 侧：`CLACKY_API_KEY/CLACKY_BASE_URL/CLACKY_MODEL`
2. 每侧每任务跑 ≥ 5 次（模型有随机性，单次无统计意义）：
   ```bash
   # MB 侧（示例）
   cd <干净临时目录> && <MBOpenClacky>/_build/native/debug/build/cmd/cmd.exe \
     --message "<任务 prompt>" --mode auto_approve
   # Ruby 侧（WSL）
   wsl -e bash -c "cd <干净临时目录> && openclacky agent -m '<任务 prompt>'"
   ```
3. 每轮记录：transcript（stdout 全文）、请求序列（如走代理抓包）、退出码、最终文件状态、token 用量。
4. 判分：按任务 `acceptance` 人工或脚本核对最终文件状态与 transcript。

## 判分与归因

- 统计口径与失败模式分类遵循 diff-harness `AGENTS.md` P4 节定义。
- MB 侧成功率显著低的任务类别，用两侧 transcript 做失败归因，结论写回 diff-harness `reports/BUGS.md`（新编号或追加既有条目证据）。
- 基准结果写 `results/`（不入 git 或按仓库约定），报告格式：每任务成功率 + 均值 ± 方差。

## 纪律

- 禁止用本基准替代 mock 链路测试做回归判定（随机性太大）。
- 禁止把真实 API key 写入任务文件或结果文件。
- 任务集只增不减；修改任务必须新增版本号。
