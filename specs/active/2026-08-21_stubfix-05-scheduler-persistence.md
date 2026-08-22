# 调度器持久化实装（schedules.yml + 任务文件 + 时间戳）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 对抗性审核通过，自 draft 移入 active）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告第四节表格 + 第五节建议 5）
> **关联历史 spec**: 无
> **来源差距**: 审计报告第四节「调度器持久化是 stub：不读 schedules.yml、任务不写盘、不删除任务文件--重启即丢；last_run_at 恒 0」
> **依赖**: 无（时间戳解法与 stubfix-04 决策 5 共用）
> **灰度 key**: 无

## 问题描述 [必填]

`lib/server/scheduler.mbt` 的调度器在内存中运行，持久化全部是 stub：

1. **不读 schedules.yml**（:24 `TODO: FFI - read and parse schedules.yml`）--启动时配置文件被忽略。
2. **任务不写盘**（:187 `TODO: FFI - write task file to tasks_dir`）--新建定时任务重启即丢。
3. **不删除任务文件**（:202 `TODO: FFI - delete task file`）--删除任务仅内存生效。
4. **配置不回写**（:210 `TODO: FFI - serialize and write config`）。
5. **last_run_at 恒 0**（:162 `schedule.last_run_at = Some(0) // TODO: actual timestamp`）--调度判断失真。

审计定级"高"（第四节表格）：cron-task-creator 技能创建的定时任务在 server 重启后全部丢失，属用户可感知的数据丢失。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "schedules.yml 不读" | `grep -n "schedules.yml\|TODO" lib/server/scheduler.mbt` | :24 `// TODO: FFI - read and parse schedules.yml` | 确认 |
| "任务不写盘/不删/配置不回写" | 同上 | :187 写任务 TODO、:202 删任务 TODO、:210 序列化写配置 TODO | 确认 |
| "last_run_at 恒 0" | 同上 | :162 `schedule.last_run_at = Some(0) // TODO: actual timestamp`；:123 cron 字段更新 TODO | 确认 |
| "文件读写能力已存在于项目" | 既有事实：`@fs.write_string_to_file`、`@fs.read_file_to_string`（write 工具/file_reader 在用） | @fs 包提供同步文件读写 | 确认无需新 FFI |
| "YAML 解析能力现状" | `grep -rln "yaml\|yml" lib/ --include="*.mbt"` 排除 wbtest 后逐文件甄别 | 无通用 YAML 解析器（匹配项均为 .yml 文件路径引用）；**已有两处手写行式解析先例**：`lib/agent/profile.mbt:50-57`（profile.yml）、`lib/extension/loader.mbt:113-116`（ext.yml/ext.yaml manifest） | **已复核（原"实施时复核"疑点关闭）**：决策 2 有先例可循 |
| "Ruby 原版持久化形态" | 实读 `openclacky/lib/clacky/server/scheduler.rb:23-24,160` | `SCHEDULES_FILE=~/.clacky/schedules.yml` + `TASKS_DIR=~/.clacky/tasks`；任务文件为 `.md`（`File.write(task_file_path(...))`）；MB `scheduler.mbt:188` 的 `name + ".md"` 已对齐 | 确认数据模型对齐（含任务文件扩展名） |
| "TokenCache 无真实时间" | 实读 `lib/channel/http_helper.mbt:23` | `// ... since we don't have real time in pure MoonBit`（TokenCache 区块内） | 确认（审计引用 :44-61 略偏，注释在 :23） |

### 详细分析

调度器核心循环（触发判断、任务执行分发）为真实现，缺的是持久化四件事（load/save/write/delete）与真实时间戳。Ruby 原版（openclacky）以 `schedules.yml` + tasks 目录文件形态持久化，MB 侧配置结构已在 `SchedulerConfig` 中描述了同样的路径约定（config_path/tasks_dir 字段存在），即**数据模型已对齐，仅 IO 缺失**。

时间戳问题与审计第四节 TokenCache（http_helper.mbt:44-61 "we don't have real time in pure MoonBit"）、MCP started_at（stubfix-04）同源：需要选定一个统一时钟源。项目 native 目标下 `@client` FFI 或 async 运行时已提供毫秒时钟的可行来源（llm_caller 的退避延迟在用 async sleep；具体时钟函数实施时以 `moon ide doc` 查证选定，若需新增共享工具则落 lib/utils 并回写本 spec）。

## 决策 [必填 - 含为什么]

1. **决策 1（IO 用既有 @fs）**：读写/删除文件直接用 @fs 既有函数（同步），不引新 FFI。
   - **为什么**：write 工具与 file_reader 已验证该路径；调度器操作低频（任务创建/删除/加载），同步 IO 无性能顾虑。
2. **决策 2（YAML 子集而非通用 YAML）**：schedules.yml 的读写限定为调度器自身的扁平结构（cron 表达式 + prompt + id + enabled 等标量字段），手写行式序列化/解析（`key: value` 逐行），不引入通用 YAML 库。
   - **为什么**：项目无 YAML 依赖，为单一配置文件引入通用解析器不成比例；调度器结构受控（自身 schema），行式子集足够；与 Ruby 原版文件保持肉眼可读兼容（同 key 命名）。若实施中发现结构嵌套超预期，升级为 JSON 文件并保持 .yml 读取兼容（迁移读取），在 spec 变更记录留痕。
3. **决策 3（时间戳共享解法）**：时钟函数与 stubfix-04（MCP started_at）共用同一实现；本 spec 消费点为 last_run_at/next_run 计算。
   - **为什么**：审计三处时间戳 stub 同源；避免两个 spec 各自为政造出两个时钟。实施顺序上先落地者定方案，后者复用（两 spec 均已声明）。
4. **决策 4（写盘时机）**：任务创建/删除/启用禁用/cron 修改即刻写盘（write-through），不做定时批量落盘。
   - **为什么**：调度任务低频且丢失代价高；write-through 语义最简单、崩溃窗口最小。
5. **决策 5（加载容错）**：schedules.yml 缺失时正常空启动；单条任务解析失败跳过并日志告警，不阻塞其余任务。
   - **为什么**：与 stubfix-01 决策 6 同原则（增强能力不阻塞主服务）；脏数据只损失自身条目。

MoonBit 约束检查：不涉及 FFI 新增（@fs 既有）、不涉及 trait 动态加载。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/server/scheduler.mbt` | 修改 | load（yml 子集解析，决策 2/5）、save_config 回写、任务文件 write/delete（决策 4）、last_run_at 真实时间戳（决策 3）、cron 字段更新（:123 TODO 一并处置） |
| `lib/server/scheduler_wbtest.mbt`（新建或既有测试文件） | 修改/新建 | 持久化往返（创建->落盘->重载还原）、删除同步删文件、脏行容错、时间戳非 0 |
| `lib/utils/`（时钟工具，如 stubfix-04 未先行落地） | 修改 | 共享时钟函数（决策 3，两 spec 协调归属） |

### 不涉及文件

- cron 表达式解析与触发循环 -- 已实装，不动
- cron-task-creator 技能层 -- 消费调度器 API，持久化透明
- web 端 scheduler handler -- 接口不变

## 实施计划 [必填]

### 任务包 1：时钟 + yml 子集解析（预估 0.5 天）

1. 时钟函数落地（与 stubfix-04 协调归属，决策 3）。
2. yml 子集序列化/反序列化纯函数 + 单测（往返、脏行、空文件）。

### 任务包 2：调度器 IO 接线（预估 0.5 天）

1. load_config 真读 schedules.yml（决策 5 容错）；create/delete/toggle/cron 修改 write-through（决策 4）；last_run_at 真实化。
2. wbtest：内存态与磁盘态一致性（用临时目录）；重启模拟（新实例 load 还原）。
3. `moon check` 0 errors；`moon test lib/server` 通过。

### 任务包 3：回归验收（预估 0.25 天）

1. 手动冒烟：`moon run cmd -- server` 创建定时任务 -> 重启 server -> 任务仍在（文件系统断言）。
2. 全量 `moon test` 无回归；`moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] schedules.yml 存在时启动自动加载全部任务；缺失时空启动无报错
- [ ] 创建任务立即落盘（tasks_dir 出现任务文件 + schedules.yml 更新）；重启后任务还原（wbtest + 手动断言）
- [ ] 删除任务同步删除磁盘文件
- [ ] 单条脏数据不阻塞其余任务加载（日志告警）
- [ ] last_run_at 为真实时间戳（非 0），调度判断随时间推进
- [ ] `moon check` 0 errors（lib/server、lib/utils）
- [ ] `moon test lib/server` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| yml 子集解析与 Ruby 原版文件格式不完全兼容（原版字段超集） | 中 | 实施首步取 Ruby 原版 schedules.yml 真实样例对照字段；未知字段保留原样透传（round-trip 不丢） |
| 时钟函数归属两 spec 竞争（stubfix-04 同时声明） | 低 | 实施顺序协调：先动工者落地 lib/utils 并回写两 spec；均为同一作者批次可控 |
| 多实例并发写 schedules.yml（server + CLI 同时操作） | 低 | 现状单 server 进程为既定假设（discover 模块即为此设计）；写盘加原子替换（临时文件 + rename）防半写 |
| write-through 在慢磁盘上的延迟 | 低 | 低频操作；最大任务数护栏（如 1000）沿用既有配置 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：cron-task-creator 技能的持久化承诺兑现（技能文档如有"重启不丢"表述）；TokenCache 过期刷新（审计第四节，backlog，复用决策 3 时钟）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告第四节调度器条目 + P1 建议 5 |
| 2026-08-22 | 审核补强：全部 TODO 行号实读复核（:24/:123/:162/:187/:202/:210 精确命中）；关闭"YAML 能力"待复核疑点（无通用解析器，但 profile.mbt:50-57 与 extension/loader.mbt:113-116 已有行式解析先例，决策 2 可直接参照）；补录 Ruby 原版形态验证（scheduler.rb:23-24，任务文件为 .md，与 MB :188 约定一致）；TokenCache 注释行号修正为 http_helper.mbt:23 | 对抗性审核 + 第一性原理校验 |
