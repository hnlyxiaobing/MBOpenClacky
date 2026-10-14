# MBOpenClacky 优化提升计划

> 更新日期：2026-10-14
> 对标上游 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky)。Web fork 基线为 v1.5.0，TUI 对齐 ui2 v1.5.4。
> 本文是当前工作约束和下一步方向；历史 WP 交付看 [CHANGELOG](CHANGELOG.md) 与 `specs/completed/`，逐行缺口看 [known-gaps](known-gaps.md)。

## 1. 当前状态

截至 2026-09-23，计划中的 17 个工作包已闭环（16 完成、1 作废）。渠道发送/接收、媒体生成、GEP 反思、旧会话投影、Web JSONL、MCP HTTP、benchmark 真执行等主路径已经落地。

后续不是继续补“已宣传但未实现”的功能，而是扩大验证覆盖、补产品级运行时原语，并保持每项声明可由代码和测试复核。

## 2. 开发约束

### 2.1 验证基线

```bash
moon check -d
moon build --target native --release cmd
BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
"$BIN" selftest --repo .
"$BIN" eval --offline --repo .
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
scripts/known_gaps.sh check && scripts/repo_stats.sh check
```

- CI 的主测试步排除 `lib/mcp` 并单独运行该包；不要把两个日志的数字混成一个未说明的总数。
- `moon fmt` 只格式化本次改动文件；`moon info` 用于核对公共接口。
- 任何接不通的路径返回可诊断错误，禁止静默假成功。

### 2.2 既有契约

改动以下面之前先看源码和对应测试：

1. **Web 查询参数**：路由参数与 query string 不是同一个字段，bridge 需要从 URL 提取 query。
2. **配置 overlay**：TOML、`MBOPENCLACKY_*`、`OPENCLACKY_*`/`CLACKY_*` 与 lite 模型按 type 合并；已有 default 模型时不要重复注入同 type。
3. **相对路径**：工具按进程 CWD 解析路径，隔离测试必须显式 chdir 或使用绝对路径。
4. **AOT 扩展**：运行期热加载扩展不能实现 trait，命令式行为使用 shell command。
5. **TUI 协议边界**：TUI 直接消费引擎 `HookEvent`，wire 词表保留给 Web/CLI；不要为了统一而丢掉工具原始状态。
6. **wasm-gc**：不是当前验收目标；native FFI 缺口保持在台账中，不用测试跳过掩盖。

## 3. 下一步方向

### 3.1 验证与评测

1. **Ruby/MoonBit 真模型对标**：同模型、同参数、同任务集，至少 5 次重复；记录 token、成本、工具序列和失败归因。
2. **任务集扩充**：`test/capability/tasks` 从 10 条扩到 20–30 条，覆盖长上下文、压缩、多文件重构、约束执行和错误恢复。
3. **浏览器 E2E 固化**：把 `test/web-e2e` 的本机路径改为可配置，并决定是否纳入 CI。
4. **性能门禁决策**：先在 `specs/draft/` 评估 benchmark 的噪声和阈值，再决定是否做趋势门禁。

### 3.2 运行时原语

按依赖顺序考虑：

1. 类型化、fail-closed 的审批链。
2. 子代理进程级隔离与预算。
3. 沙箱和写范围工具化。
4. `goal` / `plan` / `steer` / `job` 等更高层原语。
5. 前端契约测试和产品端点探针。

### 3.3 范围冻结

除非另有 spec，本期不：

- 新增 IM 渠道或 Provider；
- 重写前端；
- 实现 MCP `resources` / `prompts`；
- 将品牌服务端、遥测服务端或 wasm-gc 作为发布承诺；
- 把基准或真模型单次结果当作回归结论。

## 4. 工作流

1. 在 `specs/draft/` 用增量模板写 spec，填完所有必填项。
2. 对缺口声明做源码核对；不要把 gap 文档当事实。
3. 通过对抗性评审后进入 `specs/active/`。
4. 小步实现，编辑后跑 `moon check`，完成后跑相关测试 scope。
5. 修复台账条目时运行 `scripts/known_gaps.sh generate`，并把 curated 行移入 [resolved-gaps](resolved-gaps.md)。
6. 归档到 `specs/completed/`，在 [CHANGELOG](CHANGELOG.md) 记录行为变化和验证证据。

## 5. 事实来源

| 问题 | 事实来源 |
|---|---|
| 是否存在缺口 | `docs/known-gaps.md` + 对应源码 |
| 当前规模/版本 | `scripts/repo_stats.sh` |
| 交付历史 | `docs/CHANGELOG.md`、`specs/completed/` |
| 测试怎么跑 | `docs/testing.md` 与各 test 子目录 README |
| 上游差异 | `docs/project-status.md`、`web/UPSTREAM_SYNC.md` |
