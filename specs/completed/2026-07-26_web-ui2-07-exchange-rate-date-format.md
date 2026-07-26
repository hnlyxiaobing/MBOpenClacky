# 汇率日期格式修复 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: 无  
> **来源差距**: BUG-004（P1）  
> **依赖**: 无  
> **优先级**: P1（前端"获取最新汇率"日期不可读）

## 问题描述 [必填]

`GET /api/exchange-rate` 的 `date` 返回 `"day-20660"`（epoch 天数占位符），`updated_at` 返回 `"1785061103"`（原始 epoch 秒字符串）。原项目 `date` 为 `"2026-07-26"`（YYYY-MM-DD），`updated_at` 为 RFC2822 形如 `"Sun, 26 Jul 2026 00:02:32 +0000"`。前端汇率面板日期信息不可读。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-004 "date=day-N" | `curl /api/exchange-rate` | `"date":"day-20660","updated_at":"1785061103"` | 确认 |
| "format_iso8601_date 占位" | 读 `lib/web/handlers_exchange_rate.mbt:143-149` | `format_iso8601_date(ts)` 返回 `"day-" + days.to_string()`，注释自承"epoch day to YYYY-MM-DD is not needed" | 确认根因（开发时主动跳过格式化） |
| "format_iso8601_ms 原始秒" | 读 `lib/web/handlers_exchange_rate.mbt:135-139` | `format_iso8601_ms(ts)` 返回 `secs.to_string()`，注释"seconds since epoch is sufficient" | 确认根因 |
| "已有时间格式化能力" | grep `lib/agent` `current_timestamp_iso` | `@agent.current_timestamp_iso()` 等已存在 ISO 格式化 | 确认：可复用或参照实现 epoch->日期 |
| "orig 契约" | 报告对照 orig | date=`YYYY-MM-DD`，updated_at=RFC2822 | 以 orig 为基准 |

### 详细分析

`build_exchange_rate_response`（handlers_exchange_rate.mbt:121）用 `current_time_ms()` 构造 `date`/`updated_at`，但两个 format 函数均返回占位/原始值。需实现 epoch(ms) -> YYYY-MM-DD 与 epoch(ms) -> RFC2822。

## 决策 [必填 - 含为什么]

1. **实现 `format_iso8601_date` 为 YYYY-MM-DD**：基于 epoch 秒做日历换算（考虑闰年/月份天数），输出 `2026-07-26`。UTC。
2. **`format_iso8601_ms` 改为 RFC2822**：输出 `Sun, 26 Jul 2026 00:02:32 +0000`，与 orig 一致。需 weekday 与月份名映射表。
3. **优先复用已有时间工具**：若 `lib/agent` 或 `lib/utils` 已有 epoch->date 换算则复用；否则在 handlers_exchange_rate.mbt 内实现最小日历换算（不引入 C time 库，避免 FFI）。
4. **MoonBit 约束检查**：纯 MoonBit 整数运算 + 字符串，无 FFI。闰年/月份天数手算即可。

<!-- MoonBit 约束：无 AOT trait；无 FFI；手写 epoch->日历换算，不依赖 C time.h。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_exchange_rate.mbt` | 修改 | `format_iso8601_date` 输出 YYYY-MM-DD；`format_iso8601_ms` 输出 RFC2822（weekday/月份名表） |
| `lib/web/handlers_exchange_rate_wbtest.mbt` | 修改 | 固定时间戳断言输出 `2026-07-26` 与 RFC2822 形状 |

### 不涉及文件

- 汇率获取/缓存/回退逻辑
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：日期换算实现（预估 0.3 天）
- 实现 epoch_ms -> (year,month,day,weekday,hour,min,sec) UTC 换算（含闰年）。
- `format_iso8601_date` -> YYYY-MM-DD；`format_iso8601_ms` -> RFC2822。
- 白盒：固定 ts 断言（如 ts 对应 2026-07-26 00:02:32 UTC）。

## 验收标准 [必填]

- [ ] `GET /api/exchange-rate` `date` 形如 `2026-07-26`（YYYY-MM-DD）
- [ ] `updated_at` 形如 `Sun, 26 Jul 2026 00:02:32 +0000`（RFC2822）
- [ ] 闰年/跨月边界正确（白盒覆盖 2/29、12/31->1/1）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| epoch->日历换算边界错误（闰年/时区） | 中 | 用已知时间戳交叉验证（如在线 epoch converter）；固定 UTC，不做时区转换 |
| RFC2822 weekday 算错 | 低 | 用参考日期（1970-01-01 周四）反推；白盒覆盖 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-004 起草，已 curl + 读 handlers_exchange_rate.mbt:121-149 验证（开发主动跳过格式化，注释自承） |
| 2026-07-26 | 审核修正：`build_exchange_rate_response` :123 -> :121；`format_iso8601_date` :141-148 -> :143-149；`format_iso8601_ms` :136-139 -> :135-139 | 对抗性审核 + 第一性原理校验 |
