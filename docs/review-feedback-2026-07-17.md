# 大赛验收反馈核对报告

**核对日期**：2026-07-17
**核对范围**：官方反馈的 4 项问题
**当前状态**：`moon check` 0 errors / `moon test` 2769/2769 通过

---

## 反馈原文

> 申报的 SQLite 持久化未实现，成本计算和部分渠道/扩展仍为占位逻辑，精确包名未发布到 mooncakes.io。请先修复缺失 C 文件与 native 头文件，确保 README 命令及 CI 全部通过，完成申报核心功能，并补齐 marked/highlight 的第三方许可与来源说明后再申请复核。

---

## 逐项核对结果

### 1. SQLite 持久化未实现 — ✅ 依然有效

**验证方式**：`grep -rn "sqlite|SQLite" lib/ cmd/` 仅命中 1 处测试断言字符串，无任何实际 SQLite 绑定代码。

**当前实现**：会话持久化使用 JSON 文件（`lib/agent/session_store.mbt`），通过 `@fs.write_string_to_file` 写入 `~/.mbopenclacky/sessions/*.json`。计费持久化（`lib/billing/billing_store.mbt`）同样基于文件。

**结论**：申报中承诺的 SQLite 持久化确实未实现，当前为 JSON 文件存储。

**简洁解决方案**：

方案 A（最小工作量，推荐）：将申报描述从 "SQLite 持久化" 更正为 "JSON 文件持久化"，与实现保持一致。

方案 B（如必须保留 SQLite）：新增 `lib/db/` 包，通过 MoonBit native FFI 绑定 SQLite3 C API（参考 `lib/client/http_native.c` 的 FFI 模式），提供 `open/exec/query/close` 四个核心函数，替换 `session_store.mbt` 和 `billing_store.mbt` 的读写后端。预计工作量 2-3 天。

---

### 2. 成本计算为占位逻辑 — ✅ 依然有效

**验证方式**：`lib/agent/cost_tracker.mbt:86`：

```moonbit
fn calculate_model_cost(_model : String, _usage : @client.Usage) -> Double? {
  None
}
```

该函数是 stub，永远返回 `None`。`track_cost` 调用它后 cost 始终为 `0.0`，`CostSource` 始终为 `Estimated`。

**但注意**：`lib/pricing/cost_calculator.mbt` 中有完整的 `calculate_cost` 实现（含定价表查找、分级定价、缓存成本分解），只是未被 `cost_tracker.mbt` 调用。

**结论**：定价引擎已实现，但未接线到 Agent 的 cost tracker。

**简洁解决方案**：在 `cost_tracker.mbt` 中将 `calculate_model_cost` 替换为对 `@pricing.calculate_cost` 的调用（约 10 行改动），并在 `moon.pkg` 中添加对 `lib/pricing` 的依赖。预计工作量 0.5 天。

---

### 3. 部分渠道/扩展仍为占位逻辑 — ✅ 依然有效

**验证结果**：

| 位置 | 占位内容 |
|------|---------|
| `lib/channel/manager.mbt:35` | `load_config` 是空实现，注释 "Placeholder: In production this reads from self.config_path"，不读任何配置文件 |
| `lib/channel/weixin_api.mbt:306` | AES-128-ECB 加密/解密未实现，注释 "Placeholder for AES-128-ECB encryption" |
| `lib/channel/discord_api.mbt:72` | 某 API 返回 "placeholder success response" |
| `lib/channel/dingtalk.mbt:179` | `message_id: "dingtalk_msg_placeholder"` |
| `lib/channel/feishu.mbt:113` | `message_id: "feishu_msg_placeholder"` |

**结论**：渠道配置加载、微信 AES 加解密、以及多个渠道的消息发送返回均为占位实现。

**简洁解决方案**（按优先级）：

1. **`manager.mbt` 配置加载**（最高优先级）：使用已有的 `bobzhang/toml` 或 `@json` 读取 `channels.yml`，约 20 行代码。
2. **消息 ID 占位**：各渠道 API 发送消息后，从 HTTP 响应 JSON 中提取真实 `message_id` 字段，替换硬编码字符串。每个渠道约 5 行改动。
3. **微信 AES 加密**：引入 `moonbitlang/x/crypto` 的 AES 模块（如已有）或通过 FFI 调用 OpenSSL，替换 `weixin_api.mbt` 中的占位函数。

预计总工作量 2-3 天。

---

### 4. 精确包名未发布到 mooncakes.io — ✅ 依然有效

**验证方式**：访问 `https://mooncakes.io/hnlyxiaobing/MBOpenClacky` 返回 404。

**简洁解决方案**：在项目根目录执行：

```bash
moon publish
```

如首次发布需先 `moon login`。发布后包地址为 `https://mooncakes.io/hnlyxiaobing/MBOpenClacky`。

---

### 5. 缺失 C 文件与 native 头文件 — ⚠️ 部分有效

**验证结果**：

| 文件 | 状态 |
|------|------|
| `lib/client/http_native.c` (391 行） | ✅ 存在 |
| `lib/client/http_thread.c` (405 行） | ✅ 存在 |
| `lib/client/mb_stubs.c` (21 行） | ✅ 存在 |
| `lib/billing/time_stub.c` | ✅ 存在 |
| 任何 `.h` 头文件 | ❌ 不存在 |

**结论**：C 源文件已存在，`moon check` 和 `moon test` 均通过（链接 `-lcurl` 正常）。但项目内确实没有 `.h` 头文件。如果反馈指的是 FFI 声明头文件（如 `moonbit.h`），该文件由 MoonBit 工具链提供，不需要项目自带。如果指的是 C 源文件配套头文件，当前 `http_native.c` 和 `http_thread.c` 是自包含的（所有声明在文件内部），不依赖外部头文件。

**简洁解决方案**：

- 如果复核要求提供头文件：将 `http_native.c` 中的函数声明提取到 `lib/client/http_native.h`，在 `.c` 文件中 `#include "http_native.h"`，约 10 分钟工作量。
- 如果仅要求编译通过：当前已满足，无需额外操作。

---

### 6. README 命令及 CI 通过 — ✅ 已通过

**验证结果**：

| 项目 | 状态 |
|------|------|
| `moon check` | ✅ 0 errors, 847 warnings |
| `moon test` | ✅ 2769/2769 通过 |
| `moon build --target native --release cmd` | ✅ CI 中执行 |
| CI workflow (`.github/workflows/ci.yml`) | ✅ 包含 check/build/test 完整流程 |
| Docker build (`.github/workflows/docker.yml`) | ✅ 存在 |

README 中的命令与 CI 一致，均可正常执行。

---

### 7. marked/highlight 第三方许可与来源说明 — ✅ 依然有效

**验证结果**：

| 库 | 版本 | LICENSE 文件 | README 版本标注 |
|----|------|-------------|----------------|
| highlight.js | v11.9.0（从源码注释提取） | ❌ 缺失 | ❌ 标注为 `-` |
| marked.js | v12.0.2（从源码注释提取） | ❌ 缺失 | ❌ 标注为 `-` |
| KaTeX | 0.16.11 | 需确认 | ✅ 已标注 |
| QRCode | 1.5.4 | 需确认 | ✅ 已标注 |
| CodeMirror | 6.0.1 | 需确认 | ✅ 已标注 |

`web/js/lib/README.md` 中 highlight.js 和 marked.js 的版本列为 `-`，且 `web/js/lib/` 目录下没有任何 LICENSE 文件。

**简洁解决方案**：

1. 从官方仓库下载 LICENSE 文件放入 `web/js/lib/`：
   - highlight.js: https://github.com/highlightjs/highlight.js/blob/main/LICENSE (BSD-3-Clause)
   - marked.js: https://github.com/markedjs/marked/blob/master/LICENSE.md (MIT)
2. 更新 `web/js/lib/README.md`，填入版本号 `11.9.0` 和 `12.0.2`，并添加 LICENSE 文件名列。
3. 可选：在项目根目录创建 `THIRD_PARTY_LICENSES.md` 汇总所有第三方库许可。

预计工作量 0.5 天。

---

## 汇总

| # | 反馈项 | 是否依然有效 | 预估修复工作量 |
|---|--------|-------------|---------------|
| 1 | SQLite 持久化未实现 | ✅ 有效 | 0.5 天（改描述）或 2-3 天（实现 SQLite） |
| 2 | 成本计算占位逻辑 | ✅ 有效 | 0.5 天（接线 pricing 模块） |
| 3 | 渠道/扩展占位逻辑 | ✅ 有效 | 2-3 天 |
| 4 | 未发布 mooncakes.io | ✅ 有效 | 10 分钟（`moon publish`） |
| 5 | C 文件/头文件缺失 | ⚠️ C 文件已修复，头文件可选 | 0-10 分钟 |
| 6 | README/CI 通过 | ✅ 已通过 | — |
| 7 | marked/highlight 许可 | ✅ 有效 | 0.5 天 |

**建议修复顺序**：4 → 7 → 2 → 5 → 1 → 3（先快速修复低成本项，再处理核心功能）。
