# pricing - 模型定价表 · 成本计算

> 路径: `lib/pricing/` · 4 mbt（2 源 + 2 测试）+ moon.pkg/.mbti · LLM 调用费用计算

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `calculate_cost(model, input_tokens, output_tokens)` | `cost_calculator.mbt` | 计算单次调用成本（美元） |
| `get_pricing(model)` | `model_pricing.mbt` | 查询模型定价（返回 ModelPricing?） |
| `pricing_table()` | `model_pricing.mbt` | 返回完整定价表（Map[String, ModelPricing]） |
| `normalize_model_name(model)` | `model_pricing.mbt` | 模型名归一化（别名->规范名） |

## 关键类型

- **`ModelPricing`** - 模型定价（input_price_per_million, output_price_per_million, cache_read_price_per_million, cache_creation_price_per_million）
- **`CostResult`** - 成本计算结果（input_cost, output_cost, cache_read_cost, cache_creation_cost, total_cost）
- **`CostSource`** - 成本来源（`Actual | Estimated`）

## 核心调用链

```
Agent::call_llm() -> 返回 Usage
  └─ calculate_cost(model, input_tokens, output_tokens)
      ├─ get_pricing(model) -> ModelPricing?
      │   └─ normalize_model_name(model) -> 规范名
      └─ tokens * price_per_million / 1_000_000
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `cost_calculator.mbt` | CostResult、calculate_cost 成本计算逻辑 |
| `model_pricing.mbt` | ModelPricing、pricing_table（约 40 模型定价）、get_pricing、normalize_model_name |

## 外部依赖

- 无外部包依赖

## 风险点

1. **定价表过时** - 模型定价硬编码在源码中，需定期更新
2. **模型名归一化** - `normalize_model_name()` 别名映射可能遗漏新模型变体
3. **精度** - 使用浮点运算，累积误差可能导致微小偏差
