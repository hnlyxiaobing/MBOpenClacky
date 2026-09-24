# benchmark-gate: 性能基准升级为 CI 门禁规格

> 状态：`draft`（2026-09-23 创建）
> 来源：[development-plan-2026-09-23.md](../../docs/development-plan-2026-09-23.md) #17
> 前置：`test/benchmark/` 已落地（runner/scenario/stats/comparator/timer/persistence + wbtest），`cmd benchmark` 真执行默认 registry 工具并计时（WP-3.4）

## 1. 背景与动机

`test/benchmark/` 当前以里程碑方式手动运行，不进 CI。原因：
- 计时噪声大（同一二进制在同机器连续跑两次，p95 可浮动 30%+）
- 历史基线混了模拟驱动（0ms）与真实执行结果，`compare_with_history` 会误报回归
- 无规格依据拒绝"抖动卡 PR"——若有人拿噪声当回归，无法反驳

若要升级为门禁（CI 红/绿判定），须先定义：阈值、基线管理、噪声处理、失败处置。

## 2. 目标

1. 定义可机器校验的回归判定规则（p95 阈值 + 基线同代约束）
2. 给出噪声处理策略（采样数、离群值、重试）
3. 明确门禁失败后的人工处置流程
4. 保持当前手动运行方式不变（门禁为可选增强，不替换）

## 3. 非目标

- 不替换现有 `cmd benchmark` 的 CLI 接口
- 不引入新依赖（纯 MoonBit 统计 + JSON 基线文件）
- 不覆盖模型调用延迟（层 8 的 `cmd eval --live` 负责）
- 不处理跨机器基线可比性（CI runner 同代即可）

## 4. 规格

### 4.1 采样与统计

| 参数 | 值 | 理由 |
|------|-----|------|
| warmup | ≥ 3 | 冷启动（页面缓存、JIT 等效的 native page fault）前 3 次不计入样本 |
| iterations | ≥ 10 | 低于 10 次 p95 无统计意义 |
| 离群值处理 | 无自动剔除 | 诚实反映分布；离群值本身是信号（GC、磁盘抖动） |
| 统计量 | min/max/avg/p50/p95/p99 | p95 为主判定指标，其余为诊断 |

### 4.2 回归判定

回归判定基于 **p95 同代基线比较**：

```
regression_ratio = current_p95 / baseline_p95
is_regression = regression_ratio > (1.0 + threshold_pct / 100.0)
```

- `threshold_pct` 默认 15.0（现有 `--threshold` 默认 10.0 偏紧，实测噪声可超 10%）
- 基线来源：`_build/benchmark/results/<scenario>/baseline.json`（手动 `--save-baseline` 生成）
- **不使用历史中位数**：当前 `compare_with_history` 的历史中位数会混入旧口径数据，改为显式基线文件

### 4.3 基线管理

- **基线同代约束**：基线文件记录生成时的 `git commit` + `moon version` + 机器 OS；加载基线时校验 commit 是否在当前分支的祖先链上（`git merge-base --is-ancestor`）
- **基线过期**：若基线 commit 不在祖先链上（如跨分支比较），拒绝比较并提示 `--save-baseline` 重建
- **基线更新**：仅允许在以下情况更新基线文件并提交：
  - 已确认的性能优化（`perf:` 提交）
  - 工具实现变更导致语义等价但耗时不同（需在 PR 描述中说明）
  - 禁止仅因"CI 红了"而更新基线

### 4.4 噪声处理

- **CI 环境锁定**：CI runner 须固定实例类型（不混用 shared/dedicated），减少调度噪声
- **重试策略**：单次判定为回归时，自动追加 5 次迭代重新计算 p95；若二次判定仍回归才报红
- **诊断输出**：回归时打印 top-3 最慢迭代的绝对耗时，便于判断是噪声还是真退化

### 4.5 门禁集成

```yaml
# .github/workflows/ci.yml 新增步骤（在 test 之后）
- name: Benchmark gate (optional, allow-failure)
  run: |
    moon build --target native --release cmd
    ./cmd.exe benchmark --threshold 15.0 --check-baseline
  continue-on-error: true  # 第一阶段：只告警不阻断
```

阶段推进：
1. **Phase 1（当前）**：`continue-on-error: true`，只产生 annotation
2. **Phase 2（积累 2 周数据后）**：去掉 `continue-on-error`，正式阻断
3. **Phase 3（稳定后）**：收紧 threshold 至 10.0

## 5. 验证

- [ ] `cmd benchmark --save-baseline` 生成可校验的基线文件
- [ ] `cmd benchmark --check-baseline` 在基线过期时返回非零退出码并打印诊断
- [ ] 同二进制连续跑 5 次，p95 波动 < 15%（验证阈值合理性）
- [ ] 注入人为退化（在工具执行前 `sleep 100ms`），回归判定为红
- [ ] 注入人为优化（删除冗余遍历），回归判定为绿（无反报）

## 6. 风险

| 风险 | 缓解 |
|------|------|
| CI runner 噪声仍超 15% | Phase 1 只告警不阻断，积累数据后调阈值 |
| 基线文件成为 PR 冲突热点 | 基线按场景分文件（`<scenario>/baseline.json`），减少冲突面 |
| 跨平台基线不可比 | 基线文件含 OS 字段，不同 OS 各自维护基线 |

## 7. 与现有代码的关系

- `benchmark_comparator.mbt`：`compare_with_history` 改为 `compare_with_baseline`，接收显式基线路径
- `benchmark_persistence.mbt`：新增 `save_baseline` / `load_baseline` 函数
- `benchmark_stats.mbt`：统计逻辑不变，p95 计算已正确
- `cmd benchmark`：新增 `--save-baseline` 与 `--check-baseline` 参数
