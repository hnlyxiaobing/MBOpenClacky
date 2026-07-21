# TUI 对齐批次 2：Welcome Banner 与状态栏 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 讨论中（draft，待对抗性审核）  
> **关联总览**: `docs/tui_feature_parity_plan.md`（功能差距矩阵）  
> **关联历史 spec**: `specs/active/2026-07-21_tui-parity-01-command-usability.md`（批次 1）  
> **来源差距**: W01 / W03 / W04 / W05 / W08 / S01 / S02（差距矩阵批次 2，P0——截图对比的核心视觉差异）  
> **依赖**: 无强制前置（批次 1 建议先行但非阻塞）  
> **灰度 key**: 无

## 问题描述 [必填]

用户截图对比显示两者启动观感差异显著：原版有 6 行 ASCII 大字 logo、tagline、TIPS、`AGENT MODE INITIALIZED` 分隔区、工作目录/权限/规则信息行；MBOpenClacky 只有一个 Boxed 标题框，启动后大面积空白。具体缺口：

| # | 缺口 | 原版参照 | 来源 ID |
|---|------|---------|---------|
| 1 | banner 无 tagline/Version/4 条 TIPS | `welcome_banner.rb:61-74` | W03 |
| 2 | 无 `AGENT MODE INITIALIZED` 分隔区 | `welcome_banner.rb:80-97` | W04 |
| 3 | 无启动信息行（Working Directory / Permission Mode / Project Rules ✓） | `welcome_banner.rb:87-92` | W05 |
| 4 | 无 logo 宽度退化（原版宽 <90 退化为纯文本） | `welcome_banner.rb:36` MIN_WIDTH_FOR_LOGO | W01 |
| 5 | 无 API key/模型缺失 warning | `ui_controller.rb:1295-1303` | W08 |
| 6 | 状态栏分段颜色已定义但渲染未按段上色；无 idle/working 动画区分 | `input_area.rb:1131-1179` | S01/S02 |

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| banner 仅渲染标题+副标题 | `lib/tui/banner.mbt:61 Banner::render` | 只输出 title + "v0.1.0" 副标题，三种风格均不含 tagline/TIPS/信息行 | 确认 |
| 版本号硬编码 | `tui_controller.mbt:21` | banner 追加为第一条 output entry（随滚动滚走） | 确认：新增区块应复用同一追加机制 |
| Project Rules 检测基础设施已存在 | `grep -n "find_main\|find_sub_projects" lib/utils/workspace_rules.mbt` | `workspace_rules.mbt:19 find_main`、`:45 find_sub_projects`、`:101 has_rules` | 确认：W05/W06 不需新检测逻辑，只需 UI 接入 |
| 权限模式/工作目录数据源已在状态 | `lib/tui/state.mbt` TuiState | working_dir、permission_mode、session_id、model 字段齐全 | 确认 |
| 状态栏分段颜色定义未应用 | `lib/tui/status_bar.mbt:12 SegmentColor` vs `tui_controller.mbt:233 redraw_status` | 定义了 SegmentColor 枚举，redraw_status 只加 bold、plain_text 拼接 | 确认 |
| API key 缺失的可判定信号 | `lib/agent/agent.mbt` client/config | `agent.client.api_key` 可判空；模型名在 config | 确认：banner 后可追加 warning entry |
| 原版 TIPS 文案 | 外部参照（原版 `welcome_banner.rb:28`，当前仓库无 `.repos/`，未验证） | 4 条：提问/具体描述/.clackyrules 或 AGENTS.md//help | 原版行号待复核；可直接复刻文案 |
| 原版 logo 宽度退化阈值 90 | 外部参照（原版 `welcome_banner.rb:36`，当前仓库无 `.repos/`，未验证） | MIN_WIDTH_FOR_LOGO = 90 | 原版行号待复核；MBOpenClacky Boxed banner 已有 adaptive_width（min(term-4,60)，下限 20），退化策略可在此基础上加纯文本分支 |
| 子项目规则列表（W06） | `workspace_rules.mbt:45 find_sub_projects` | 函数存在 | 确认基础设施在；本 spec 将 W06 列为可选项（见决策 4） |

## 决策 [必填 - 含为什么]

1. **banner 结构改为多区块追加**：ASCII logo（现有 Boxed 或新增 6 行大字，宽度不足退化纯文本）→ tagline+version+TIPS 区块 → AGENT MODE 分隔区 → 信息行区块，各为独立 output entry，自然滚入 scrollback。理由：复用现有"banner 即首条 output"机制，不引入新渲染通道；与原版"滚走的历史"语义一致。
2. **logo 形态：复刻原版 6 行 OPENCLACKY 字样还是沿用 MBOpenClacky 品牌字，属产品决策，本 spec 默认沿用 MBOpenClacky 名称 + Block 风格大字**（`lib/utils/block_font.mbt` 的 `@utils.BlockFont` 已有 5x5 字形，banner.mbt Block 风格实际调用者；`lib/tui/block_font.mbt` 为其 TUI 伴生渲染器），宽度 <90 退化纯文本 "Welcome, MBOpenClacky is here"。理由：对齐的是"有大字 logo + 退化逻辑"的行为，不是复刻竞对产品名；如需改回 OPENCLACKY 字样只换字形表。
3. **状态栏位置保持顶部，不迁到底部（显式偏离原版）**。理由：MBOpenClacky 布局已稳定（layout 三区 + eval 断言顶部状态栏），迁移成本高且无功能收益；但分段上色与 idle/working 视觉区分（spinner 字符动画替代原版雪花 ❄❅❆，因盲文与现有 spinner 体系一致）必须落地，解决"状态不可感知"问题。
4. **W06 子项目规则列表列为可选实现项**：`find_sub_projects` 已存在，接入成本低，但若首轮验证发现其输出格式不适合 banner 则降级为后续 spec，不阻塞本批验收。
5. **W08 warning 触发条件为 `api_key` 为空或模型未配置**，追加在 banner 末尾（黄色 [warning] entry）。理由：与原版"启动后检查"语义一致；实现零依赖。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent 路由：不涉及。
- FFI：不涉及（纯 MoonBit + 既有 workspace_rules）。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/banner.mbt` | 修改 | 新增 tagline/TIPS 常量与渲染、AGENT MODE 分隔区、信息行渲染；logo 宽度 <90 退化纯文本 |
| `lib/tui/tui_controller.mbt` | 修改 | 启动序列按区块追加 banner；追加 API key warning（W08）；版本号改从统一来源取 |
| `lib/tui/status_bar.mbt` | 修改 | 分段上色渲染落地（替代 plain_text 拼接）；status 字段 idle `●`/working 动画帧 |
| `lib/tui/tui_controller.mbt` redraw_status | 修改 | 按 SegmentColor 逐段输出 ANSI 颜色 |
| `lib/tui/banner_wbtest.mbt`（新建或补充） | 新建 | 区块内容单测（含宽度退化分支） |
| `test/tui/tui_eval_adapter.mbt` | 修改 | 适配器启动 banner 同步新区块（eval 才能断言） |
| `test/scenarios/tui/basic_startup.json` | 修改 | 断言 tagline/TIPS/AGENT MODE/信息行 |
| `test/scenarios/tui/banner_narrow.json` | 新建 | 窄终端（<90 宽）退化纯文本断言 |
| `test/scenarios/tui/status_bar_colors.json` | 新建 | 状态栏分段 ANSI 颜色码断言 |

### 不涉及文件

- `lib/utils/workspace_rules.mbt`（只调用，不修改）
- `lib/tui/output_buffer.mbt`、`layout_manager.mbt`（渲染管线不动）
- `lib/agent/`、`lib/config/`（数据源只读）

## 实施计划 [必填]

1. banner 区块化重构 + tagline/TIPS/AGENT MODE/信息行（1 天）。
2. logo 宽度退化 + 窄终端 eval 场景（0.5 天）。
3. W08 API key warning（0.5h）。
4. 状态栏分段上色 + idle/working 动画（1 天）。
5. eval 适配器同步 + 3 个 eval 场景 + 全量验证 + 人工 TTY 对照截图（0.5 天）。

## 验收标准 [必填]

- [ ] 启动后依次显示：大字 logo（或窄终端纯文本）→ tagline/version/TIPS → AGENT MODE 分隔区 → 信息行（Dir/Mode/Rules）
- [ ] 终端宽 <90 时 logo 退化为纯文本欢迎行（eval `banner_narrow`）
- [ ] Project Rules 存在时信息行显示 `AGENTS.md ✓`（本仓库根目录有 AGENTS.md，可直接人工验证）
- [ ] 未配置 API key 时 banner 末尾出现 [warning] 提示
- [ ] 状态栏各段按 SegmentColor 上色（eval 断言 ANSI 码）；agent 运行时状态字段有动画
- [ ] `moon check` 0 errors（lib/tui）；`moon test lib/tui` 通过
- [ ] `--tui-eval` 全量 PASS；人工 TTY 与原版截图逐区块对照

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| banner 区块增多导致启动首屏超高（窄终端） | 中 | 各区块合计 ≤12 行；窄终端除 logo 退化外，TIPS 可压缩为 1 行 |
| 信息行依赖 cwd/permission 在 TuiState 初始化时序 | 中 | banner 追加在 hooks 注册与 from_agent 之后，启动序列内顺序保证 |
| 状态栏上色在 VirtualScreen 与真实终端 ANSI 处理差异 | 中 | eval 断言颜色码存在性；人工 TTY 验证观感 |
| working 动画增加 Tick 重绘频率 | 低 | 沿用现有 200ms Tick 与 dirty 机制，无新定时器 |

## 依赖关系 [必填]

- **前置依赖**：无强制前置；批次 1 建议先行（命令框架），但本批可独立开发
- **后置依赖**：批次 3-5 的启动后交互默认 banner 已就位

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：9 项声称经 grep 验证（含 workspace_rules 基础设施已存在、SegmentColor 未应用两项关键事实）；状态栏位置、logo 品牌字两处显式决策；W06 降级为可选项 | 差距矩阵批次 2（P0）落实 |
| 2026-07-21 | 审核修正：TuiState `cwd` 字段名纠正为 `working_dir`；`block_font.mbt` 引用精确化（`lib/utils` BlockFont 为实际调用者，`lib/tui` 为伴生渲染器）；原版 `welcome_banner.rb` 行号标注为未验证外部参照；交叉引用 parity-01 draft->active | 对抗性审核 + 第一性原理校验 |
