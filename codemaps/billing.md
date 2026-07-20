# billing - 计费记录 · 用量统计 · 持久化

> 路径: `lib/billing/` · 3 mbt（2 源 + 1 测试）+ 1 C · Token 用量与成本记录

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `BillingStore::new(billing_dir)` | `billing_store.mbt` | 创建计费存储（指定目录） |
| `BillingStore::default()` | `billing_store.mbt` | 默认存储（`~/.mbopenclacky/billing/`） |
| `BillingStore::append(record)` | `billing_store.mbt` | 追加计费记录到 NDJSON |
| `BillingStore::query(...)` | `billing_store.mbt` | 按条件查询记录 |
| `BillingStore::summary(...)` | `billing_store.mbt` | 汇总统计（总 tokens/费用/模型分布） |
| `BillingStore::daily_breakdown(...)` | `billing_store.mbt` | 按日统计明细 |
| `BillingStore::cleanup(before_ms)` | `billing_store.mbt` | 清理旧记录 |

## 关键类型

### 核心 Struct
- **`BillingStore`** - 计费存储（billing_dir, cache）
- **`BillingRecord`** - 计费记录（timestamp, model, input_tokens, output_tokens, cache_read, cache_creation, cost_usd, session_id, agent_source）
- **`Summary`** - 汇总（total_input, total_output, total_cost, model_summaries, records_count）
- **`ModelSummary`** - 单模型统计
- **`DaySummary`** - 单日统计

### 辅助函数
- `generate_id()` - 生成记录 ID
- `filter_records(...)` - 记录过滤
- `aggregate_summary(records)` - 聚合统计

## 核心调用链

```
Agent::run() 完成
  └─ BillingStore::append(BillingRecord::new(...))
      └─ 写入 NDJSON 文件（追加模式）

Web API /api/billing/*
  └─ BillingStore::summary(period) -> Summary
  └─ BillingStore::daily_breakdown(period) -> Array[DaySummary]
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `billing_record.mbt` | BillingRecord 结构、generate_id、total_tokens |
| `billing_store.mbt` | BillingStore、CRUD、查询/汇总/清理、filter_records、aggregate_summary |
| `time_stub.c` | 时间函数 C FFI stub（测试用） |

## 外部依赖

- `lib/pricing` - calculate_cost 计算
- `moonbitlang/core/json` - JSON 序列化
- `moonbitlang/x/fs` - 文件 I/O

## 风险点

1. **内存持久化** - BillingStore 数据存储在文件中，并发写入可能冲突
2. **NDJSON 追加** - 追加模式不保证原子性，崩溃可能产生不完整行
3. **无索引** - 查询需全量扫描，大量记录时性能下降
4. **时间戳精度** - 依赖 `time_stub.c` 的 C FFI 时间获取
