# telemetry - 匿名遥测 · 事件上报

> 路径: `lib/telemetry/` · 5 mbt（3 源 + 2 测试）+ moon.pkg/.mbti · 使用统计与事件追踪

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `Telemetry::new(device_id)` | `telemetry.mbt` | 创建遥测实例 |
| `Telemetry::startup(brand)` | `telemetry.mbt` | 上报启动事件 |
| `Telemetry::task(...)` | `telemetry.mbt` | 上报任务完成事件 |
| `Telemetry::share(...)` | `telemetry.mbt` | 上报分享事件 |
| `is_telemetry_enabled()` | `telemetry.mbt` | 检查遥测是否启用（环境变量/配置） |
| `generate_anonymous_id()` | `telemetry.mbt` | 生成匿名设备 ID |

## 关键类型

### 核心 Struct
- **`Telemetry`** - 遥测实例（device_id, events_sent）

### 事件类型
- **`TelemetryEvent`** - 事件枚举（`Startup | Task | Share`）
- **`TelemetryEventType`** - 事件类型字符串映射
- **`StartupPayload`** / **`TaskPayload`** / **`SharePayload`** - 各事件载荷

## 核心调用链

```
cmd/main.mbt
  └─ Telemetry::new(device_id)
      └─ Telemetry::startup(brand)
          └─ get_event_path(event) -> POST /api/telemetry/{event}

Agent::run() 完成
  └─ Telemetry::task(task_type, duration, success)
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `telemetry.mbt` | Telemetry 主体、事件上报、is_telemetry_enabled、generate_anonymous_id |
| `types.mbt` | TelemetryEvent、TelemetryEventType、各 Payload 类型 |

## 外部依赖

- `lib/brand` - device_id 生成
- HTTP 上报（通过 lib/client）

## 风险点

1. **隐私** - 遥测数据含设备 ID，需确保匿名性
2. **网络失败静默** - 上报失败不阻塞主流程，但可能导致数据丢失
3. **开关粒度** - `is_telemetry_enabled()` 为全局开关，无法按事件类型控制
