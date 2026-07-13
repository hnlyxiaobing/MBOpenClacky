# Harness 方法论 v2 升级方案

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **依据**: G01-G17 对抗性审核结果（15 处事实性错误、8 处文件名错误、3 处架构方向错误、3 处过度设计）
> **关联文档**: `specs/decisions/harness-methodology-application-plan.md`（v1.0）

## 一、问题诊断：v1 流程的系统性缺陷

### 1.1 G01-G17 审核数据

| 问题类型 | 数量 | 典型案例 |
|---------|------|---------|
| "缺失"声称未验证 | 15 处 | G10 restart 已实现、G13 thinking_view 不存在但声称已实现、G15 KaTeX/QRCode 已集成、G17 auto_creator 已存在 205 行 |
| 文件名猜测错误 | 8 处 | G14 `image_gen.mbt` 不存在、G16 `handlers_restart.mbt`/`session_serializer.mbt`/`identity.mbt` 均不存在 |
| 架构方向性错误 | 3 处 | G02/G07 提议 trait DSL（MoonBit AOT 不可行）、G10 声称 crescent 不支持 PATCH（实际支持） |
| 过度设计 | 3 处 | G09 10MB 分块、G10 8 端点（实际缺 1 个）、G15 3 库缺失（实际缺 1 个） |
| 缺少标准章节 | ~20 处 | 所有 spec 原始版本缺少改动范围/实施计划/风险评估/依赖关系/变更记录 |

### 1.2 根因分析

**根因 1：差距分析被当作 ground truth，而非待验证假设**

`docs/gap_analysis_and_development_plan.md`（799 行）是基于一次代码扫描生成的快照。spec 作者直接从 gap 文档中提取"缺失项"写 spec，没有回到代码库验证。

**根因 2：v1 的"读地形"步骤缺少强制验证**

v1 操作卡片步骤 1 是"读地形"，但仅描述为"读 specs/ + codemaps/ + AGENTS.md"。没有要求用 `grep`/`glob`/`file_reader` 验证 gap 文档的关键论断。codemap 也未覆盖所有包。

**根因 3：缺少 spec 级别的对抗性审核**

v1 的"他测"（第 3 层 safety net）针对的是代码 diff，不是 spec。spec 从创建到进入开发之间没有审核关卡。

**根因 4：模板有标准章节但无强制检查**

v1 的 incremental-spec-template 已包含改动范围/风险评估/变更记录，但 17 个 spec 中无一完整填写。模板是"建议"而非"强制"。

**根因 5：MoonBit 语言约束未系统化检查**

MoonBit AOT 编译意味着运行时动态加载的扩展不能实现 trait。这个约束在 CLAUDE.md 和 AGENTS.md 中有暗示但未作为 spec checklist 项。

### 1.3 v1 中已经有效的设计（保留）

- **No Spec, No Code** 原则有效
- **最小混沌单元**切分思路有效（按包/功能/文件/阶段）
- **checkpoint 6 种动作**模型有效
- **多层 safety net** 分层有效
- **"只产出 spec 不开发"**的批次模式有效（允许集中审核）
- **上下文三件套**（spec + codemap + new-chat）概念有效

## 二、升级方案：v2 新增流程

### 2.1 新增步骤：Pre-Spec 代码验证（Gap-to-Spec Gate）

在"读地形"和"切任务"之间插入强制验证关卡。

```
v1 流程:  读地形 -> 切任务 -> 做 spec -> [直接进入 active/]
v2 流程:  读地形 -> ★Gap 验证★ -> 切任务 -> 做 spec -> ★Spec 审核★ -> 进入 active/
```

**Gap 验证协议**：

对 gap 文档中的每一个"缺失/不完整"论断，必须执行以下验证：

| 论断类型 | 验证命令 | 通过标准 |
|---------|---------|---------|
| "X 功能缺失" | `grep -r "X" lib/ cmd/ web/` | grep 0 命中 = 确认缺失；有命中 = 需读取代码确认实现程度 |
| "X 文件不存在" | `glob "lib/**/X*"` | glob 0 结果 = 确认不存在；有结果 = 修正 spec |
| "X 端点缺失" | `grep "X" lib/web/server.mbt` | grep 0 命中 = 确认缺失；有命中 = 检查 handler 是否为 stub |
| "crescent 不支持 Y" | `grep "Y" lib/web/server.mbt` | 查找已有用法作为反证 |
| "完成度 N%" | `find + wc -l` 统计实际行数 | 与声称的百分比交叉验证 |

**输出**：每个 spec 的"现状分析"章节必须包含"经代码验证"标记，列出实际执行的验证命令和结果。

### 2.2 新增步骤：Spec 对抗性审核（Spec Review Gate）

spec 写完后、进入 `active/` 前，必须通过对抗性审核。

**审核三原则**：

1. **对抗性提问**：对每个"缺失"声称追问"真的不存在吗？"，对每个"已有"声称追问"真的实现了吗还是 stub？"
2. **第一性原理校验**：验证技术决策是否符合 MoonBit 语言约束（AOT、trait 限制、FFI 限制）
3. **交叉引用**：spec 中提到的每个文件名、函数名、字段名必须与代码库实际匹配

**审核检查清单**：

```
□ 所有"缺失"声称已用 grep/glob 验证
□ 所有文件名引用已用 glob 确认存在
□ 所有函数名/字段名引用已用 grep 确认存在
□ 技术决策符合 MoonBit AOT 约束（动态加载不能用 trait）
□ crescent API 能力已验证（PATCH/PUT/POST 实际支持情况）
□ 无过度设计（最简可行方案？）
□ 改动范围章节完整（涉及文件 + 不涉及文件）
□ 实施计划章节完整（任务包切分）
□ 风险评估章节完整
□ 依赖关系章节完整
□ 变更记录章节存在
```

### 2.3 模板升级：强制必填章节

将模板中的以下章节从"建议"升级为"必填"，缺少任意一项的 spec 不允许进入 `active/`：

| 章节 | v1 状态 | v2 状态 | 说明 |
|------|---------|---------|------|
| 问题描述 | 必填 | 必填 | 不变 |
| 现状分析 | 必填 | **必填 + 验证标记** | 必须包含"经代码验证"和实际执行的验证命令 |
| 决策（含为什么） | 必填 | 必填 | 不变 |
| 改动范围 | 建议 | **必填** | 涉及文件 + 不涉及文件 |
| 实施计划 | 无 | **必填（新增）** | 任务包切分 |
| 验收标准 | 必填 | 必填 | 不变 |
| 风险评估 | 建议 | **必填** | 风险表 |
| 依赖关系 | 无 | **必填（新增）** | 前置/后置依赖 |
| 变更记录 | 建议 | **必填** | 审核修正记录 |

### 2.4 新增：MoonBit 语言约束检查表

以下约束在 spec 决策阶段必须检查：

| 约束 | 检查方法 | 违反后果 |
|------|---------|---------|
| AOT 编译：运行时动态加载的代码不能实现 trait | 决策中如出现"扩展实现 trait"需标注不可行 | spec 打回重写 |
| crescent 路由方法支持：GET/POST/PUT/PATCH/DELETE | `grep "\.patch\|\.put\|\.delete" lib/web/server.mbt` 确认已有用法 | 不能以"crescent 不支持 X"为由回避 |
| wasm-gc 不可用：tty/crescent 有 FFI 依赖 | 不影响 spec 设计，但测试策略需标注 native-only | 测试验收标准需注明 |
| extern "C" FFI：需要 native-stub + link.native 配置 | 涉及 FFI 的 spec 需在改动范围中列出 C 文件和 moon.pkg 配置 | FFI spec 不完整 |
| mooncakes 依赖：需检查是否已有现成包 | `grep "import" moon.pkg` 查看已有依赖 | 避免重复造轮子 |

### 2.5 新增：Spec 生命周期管理

```
draft/          -> 新建 spec 先放此处，未通过审核
active/         -> 通过对抗性审核后移入，可进入开发
completed/      -> 开发完成并验收后归档
deprecated/     -> 因技术方向变更废弃的 spec（保留供回顾）
```

**v1 问题**：17 个 spec 直接进入 `active/`，未经过审核。
**v2 修正**：新增 `draft/` 目录，spec 先在 draft 中编写和审核，通过后才移入 active。

### 2.6 升级操作卡片

```
┌─────────────────────────────────────────────────────────────┐
│            MBOpenClacky Harness v2 操作卡片                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 读地形                                                  │
│     -> 0->1: 和模型讨论收敛目标                                 │
│     -> 1->N: 读 specs/ + codemaps/ + AGENTS.md                │
│                                                             │
│  ★2. Gap 验证（v2 新增）★                                   │
│     -> 对 gap 文档每个"缺失"论断执行 grep/glob 验证            │
│     -> 记录验证命令和结果到 spec 的"现状分析"章节               │
│     -> gap 文档是假设，不是 ground truth                      │
│                                                             │
│  3. 切任务                                                  │
│     -> 最小混沌单元：小到可检查，大到可自治                       │
│                                                             │
│  4. 做 spec（先放 draft/）                                   │
│     -> 必填章节：问题描述/现状分析(含验证)/决策/改动范围/          │
│        实施计划/验收标准/风险评估/依赖关系/变更记录              │
│     -> MoonBit 约束检查表逐项过                               │
│                                                             │
│  ★5. Spec 对抗性审核（v2 新增）★                              │
│     -> 三原则：对抗性提问/第一性原理/交叉引用                    │
│     -> 审核检查清单逐项过                                      │
│     -> 通过 -> 移入 active/；未通过 -> 留 draft/ 修改           │
│                                                             │
│  6. 做任务包                                                │
│     -> 目标 / 边界 / 自由度 / checkpoint / 验收                │
│                                                             │
│  7. 让模型推进 -> do it                                     │
│                                                             │
│  8. checkpoint                                             │
│     -> 6 种动作：放行/阻止/绕道/回炉/追问/加料                 │
│                                                             │
│  9. 证据验收                                                │
│     -> 多层 safety net：自验->自测->他测->CI->灰度              │
│                                                             │
│  10. 回写归档                                               │
│     -> spec 从 active/ 移到 completed/                       │
│     -> checkpoint 新发现回写 spec 和 codemap                  │
│                                                             │
│  验证命令速查                                               │
│  ├─ moon check                    # 类型检查（必跑）          │
│  ├─ moon test lib/<pkg>           # 目标包测试                │
│  ├─ moon build --target native --release cmd  # 构建         │
│  ├─ moon fmt --check              # 格式检查                 │
│  ├─ moon info                     # API 变更检查              │
│  ├─ grep -r "keyword" lib/ cmd/   # ★代码验证（v2 新增）★    │
│  └─ glob "lib/**/*.mbt"          # ★文件验证（v2 新增）★    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 三、实施计划

### 3.1 立即可做（今天）

| 步骤 | 动作 | 产出 |
|------|------|------|
| 3.1.1 | 创建 `specs/draft/` 目录 | 目录存在 |
| 3.1.2 | 更新 incremental-spec-template 加入必填标记 | 模板标注必填章节 |
| 3.1.3 | 更新 AGENTS.md Agent Instructions 段落 | 加入 v2 流程引用 |

### 3.2 本周完成

| 步骤 | 动作 | 产出 |
|------|------|------|
| 3.2.1 | 将 G01-G17 审核经验写入 codemap 更新指南 | 审核发现的文件名映射表 |
| 3.2.2 | 为核心包补充 codemap（至少 web/agent/tui/extension） | 4 个 CODEMAP.md |
| 3.2.3 | 更新 harness-methodology-application-plan.md 引用 v2 | v1 标注为历史版本 |

### 3.3 持续执行

| 步骤 | 动作 | 频率 |
|------|------|------|
| 3.3.1 | 每个新 spec 走 draft -> 审核 -> active 流程 | 每次 |
| 3.3.2 | 月度回顾 spec 质量（错误率趋势） | 每月 |
| 3.3.3 | codemap 时效性检查 | 每 2 周 |

## 四、v1 vs v2 对比总结

| 维度 | v1 | v2 |
|------|-----|-----|
| gap 文档定位 | ground truth | 待验证假设 |
| 读地形 | 读 spec/codemap/docs | 读 + **grep/glob 验证** |
| spec 质量关卡 | 无 | **对抗性审核 + 检查清单** |
| 模板章节 | 建议填写 | **必填，缺少则打回** |
| MoonBit 约束 | 隐含在 AGENTS.md | **显式检查表** |
| spec 目录 | active/completed | **draft/active/completed/deprecated** |
| 错误防范 | 靠开发者自觉 | **流程强制** |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | G01-G17 对抗性审核发现 v1 流程系统性缺陷 |

