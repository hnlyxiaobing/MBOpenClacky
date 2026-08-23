# 基础设施模块文件操作补全（output_dir/backup/scripts/discover）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 对抗性审核通过，自 draft 移入 active）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 3.5 节 + 第五节建议 9）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 3.5「五个模块全 FFI TODO 零功能」中的四个文件系统类模块
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

四个模块的所有文件系统操作都是 TODO FFI，在当前 MoonBit 目标下完全不可用：

| 模块 | 文件 | TODO 数 | 影响 |
|------|------|---------|------|
| 媒体输出目录 | lib/media/output_dir.mbt | 8 | 创建目录、列出文件、清理、大小计算全不可用--**最关键**：media-gen 等技能生成媒体后无法写入输出目录 |
| 备份管理器 | lib/server/backup_manager.mbt | 7 | 读配置、列文件、创建归档、删除旧备份全不可用 |
| 脚本管理器 | lib/utils/scripts_manager.mbt | 4 | 列出脚本、验证文件存在都是 TODO |
| 服务发现 | lib/server/discover.mbt | 4 | PID 文件读/写/删、进程存活检查都是 TODO |

审计定级 P3 但指出实现模式简单（读/写文件 + 目录列表），可批量处理。其中 output_dir 因被媒体生成链路依赖，实际价值最高。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "output_dir 8 处 TODO 全文件操作" | 审计 3.5 节表格（lib/media/output_dir.mbt） | 创建/列出/清理/大小计算全 TODO | 确认（审计行号佐证，实施时逐条复核） |
| "backup_manager 7 处" | 审计 3.5 节 | 读配置/列文件/归档/删除旧备份 | 确认同上 |
| "scripts_manager 4 处 / discover 4 处" | 审计 3.5 节 | 列脚本/验证存在；PID 读写删/存活检查 | 确认同上 |
| "@fs 已有所需原语" | 实读 `.mooncakes/moonbitlang/x/fs/pkg.generated.mbti`（项目 @fs 即此包，各 moon.pkg 已 import） | `read_file_to_string`/`write_string_to_file`/`create_dir`/`is_dir`/`is_file`/`path_exists` + **`read_dir(String) -> Array[String]`、`remove_file`、`remove_dir` 均原生存在** | **已复核（关闭"目录列举/删除需查证"疑点）**：全部原语现成，无需从 glob 抽取 |
| "目录列举能力参照" | ~~glob 工具实现~~ | **审核修正：不需要**--@fs.read_dir 原生提供目录列举 | 决策 2 条件分支已关闭（走 @fs 直用） |
| "递归建目录已有" | `lib/utils/path.mbt:67-83 ensure_dir`（write spec 决策 4 引用） | 递归创建 + Windows 分隔符规范化 | 确认复用 |

### 详细分析

四个模块的 TODO 均为"纯文件系统操作"（无网络/无子进程/无协议），且 @fs（moonbitlang/x/fs）原语全覆盖：
- 文件读写/存在/目录判定：@fs 直接可用。
- 递归建目录：`@utils.ensure_dir` 现成。
- 目录列举：`@fs.read_dir` 原生（审核确认，无需从 glob 抽取）。
- 文件删除：`@fs.remove_file`/`remove_dir` 原生（审核确认；永久删除语义，不走 safe_rm 回收站）。
- 进程存活（discover）：@process 先例（browser_process 的进程管理）可参照；PID 数值 + kill(pid, 0) 语义在 Windows 下需等效方案（实施时以 @process 能力为准）。
- 归档（backup_manager 的"创建归档"）：`lib/zip` create_zip 现成（stored-only 对备份场景足够，见决策 4）。

时间戳类 TODO（如备份的"删除旧备份"按时间判断）复用 stubfix-04/05 的时钟解法（决策 3 of stubfix-05 已声明共享）。

## 决策 [必填 - 含为什么]

1. **决策 1（一批四模块，逐包任务包）**：一个 spec 承载四个模块（每个模块改动小且模式相同），按 output_dir -> scripts_manager -> discover -> backup_manager 顺序排任务包。
   - **为什么**：四者合计改动量约等于一个中型 spec；单独成 spec 会让 draft 目录充斥四个微型文档；顺序按用户价值排（媒体生成链路最优先）。
2. **决策 2（原语复用优先，审核后收敛）**：文件操作全部走 @fs/@utils 既有函数；目录列举直接用 `@fs.read_dir`（审核确认原生存在，不从 glob 抽取共享函数）。
   - **为什么**：审计建议 9 明示"实现模式简单，可批量处理"；@fs 能力面实读全覆盖，零新增抽象。
3. **决策 3（output_dir 语义对齐 media-gen 链路）**：目录创建用 ensure_dir（递归）；输出文件写入后返回绝对路径；列出/清理/大小计算为管理接口（清理需保留近期文件策略参数）。
   - **为什么**：media-gen 技能的落盘契约是本模块存在理由；清理策略可配置防止误删全部产物。
4. **决策 4（backup 归档用 lib/zip）**：备份归档走既有 `create_zip`（stored-only），不做压缩算法升级。
   - **为什么**：备份场景文件多为文本/配置，stored zip 已满足打包+完整性（CRC）诉求；Deflate 升级与 stubfix-03 决策 1 的否决理由一致（不为备份引入 inflate）。
5. **决策 5（删除语义分级，审核后收敛）**：备份轮转删除、output_dir 清理为**永久删除**，直接用 `@fs.remove_file`/`remove_dir`（审核确认原生存在），不走 safe_rm 回收站路径。
   - **为什么**：回收站语义适合用户文件误删保护，不适合自动轮转（会把回收站当垃圾场）；@fs 删除原语现成，无需引入 safe_rm 依赖。
6. **决策 6（discover 存活检查）**：PID 文件 + 进程存在性探测以 @process 能力为准（native）；不可得时降级为"PID 文件存在 + 端口探测"（HTTP GET localhost，复用 @client）。
   - **为什么**：Windows 下信号探测语义受限；端口探测与服务发现目的一致（确认 server 可达）且实现无歧义。

MoonBit 约束检查：无新增 FFI；全部复用既有 @fs/@process/@client/@utils。wasm 目标如有文件操作需 stub 降级对齐（moon check 必须过）。✅

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/media/output_dir.mbt` | 修改 | 8 处 TODO -> ensure_dir/@fs 实现（决策 3） |
| `lib/utils/scripts_manager.mbt` | 修改 | 4 处 TODO -> @fs/path_exists 实现 |
| `lib/server/discover.mbt` | 修改 | PID 读写删 + 存活检查（决策 6） |
| `lib/server/backup_manager.mbt` | 修改 | 7 处 TODO -> @fs + create_zip + 时钟（决策 4 + 共享时钟） |
| `lib/utils/` | 不动 | ~~从 glob 抽出 list_dir 共享函数~~（审核确认 @fs.read_dir 原生存在，无需抽取） |
| 四模块对应 wbtest | 修改/新建 | 每模块：正常路径 + 容错（缺失目录/权限/脏数据） |

### 不涉及文件

- `lib/tool/glob.mbt` -- 只抽共享函数不改行为
- `lib/tool/safe_rm.mbt` -- 只查证复用边界（决策 5），不改其回收站语义
- media-gen 技能层 -- 消费 output_dir 接口，透明受益
- 审计 3.5 表格之外的模块（brand/telemetry 的 HTTP stub 等）-- 各自 backlog

## 实施计划 [必填]

### 任务包 1：output_dir（预估 0.5 天）

1. 8 处 TODO 实装（决策 3 语义）；wbtest 全覆盖（临时目录）。
2. media-gen 冒烟：生成一个媒体文件落盘成功（若 media-gen 可本地触发）。

### 任务包 2：scripts_manager + discover（预估 0.5 天）

1. scripts_manager 4 处实装 + wbtest。
2. discover PID/存活（决策 6）+ wbtest（真 server 冒烟：启动 server -> discover 找到 -> 停止 -> 探测失败）。

### 任务包 3：backup_manager（预估 0.5 天）

1. 读配置/列文件/归档（create_zip）/按时间轮转删除（共享时钟）+ wbtest。
2. 备份->恢复往返单测（zip 提取用既有 extract_zip）。

### 任务包 4：回归（预估 0.25 天）

1. `moon check` 0 errors；`moon test lib/media`、`lib/utils`、`lib/server` 通过；全量 `moon test` 无回归。
2. `moon fmt`、`moon info`。

## 验收标准 [必填]

- [ ] output_dir：目录自动创建（含多级）、文件落盘返回路径、列出/大小计算正确、清理保留策略生效（wbtest 断言）
- [ ] media-gen 生成产物成功写入输出目录（手动或集成冒烟）
- [ ] scripts_manager：列脚本/验证存在真实化，wbtest 通过
- [ ] discover：PID 写/读/删 + 存活探测（进程或端口路径），server 启停冒烟通过
- [ ] backup_manager：配置读取、归档创建（可被 extract_zip 还原）、旧备份轮转删除按时间生效
- [ ] 四模块 grep 无残留 "TODO: FFI" 标记
- [ ] `moon check` 0 errors（lib/media、lib/utils、lib/server）
- [ ] 相关 `moon test` 范围通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~@fs 无目录列举/删除原语~~ | ~~中~~ -> 已消除 | 审核确认 @fs（moonbitlang/x/fs）原生具备 `read_dir`/`remove_file`/`remove_dir`，无需新增或抽取 |
| Windows 权限/路径语义差异（如清理误删） | 中 | wbtest 用临时目录隔离；清理保留策略参数化 + 默认保守（保留最近 N 个） |
| 时钟依赖（backup 轮转）与 stubfix-04/05 协调 | 低 | 共享时钟已声明（stubfix-05 决策 3）；后实施者复用 |
| backup 归档大文件内存压力（Bytes 全量载入） | 低 | 备份对象为配置/会话文件（MB 级）；超大文件跳过并告警的护栏 |
| discover 误报（PID 复用） | 低 | 端口探测降级路径（决策 6）双保险 |

## 依赖关系 [必填]

- **前置依赖**：无（时钟依赖与 stubfix-04/05 共享解法，先落地者定实现）
- **后置依赖**：media-gen 媒体落盘链路可用性兑现；cron-task 等技能的备份/脚本管理可用性（backlog 相关 handler 接线如有）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 3.5 节 + P3 建议 9 |
| 2026-08-22 | 审核补强：四模块 TODO 计数实读精确命中（output_dir 8/backup_manager 7/scripts_manager 4/discover 4，discover 行号 :48/:65/:75/:103）；**关闭两大待查证疑点**--@fs（moonbitlang/x/fs）原生具备 read_dir/remove_file/remove_dir，目录列举无需从 glob 抽取、删除无需经 safe_rm；决策 2/5 相应收敛（remove 直用 @fs）；lib/zip create_zip(:92)/extract_zip(:179)、ensure_dir(path.mbt:67+) 实存确认 | 对抗性审核 + @fs mbti 实读 |
| 2026-08-23 | 实施完成并验收：四模块真实现——output_dir（ensure_exists 用 @utils.ensure_dir、list_files @fs.read_dir + 后缀过滤、cleanup、total_size）；scripts_manager（list_scripts 目录枚举 + 扩展名过滤、validate_script 真实存在检查）；discover（find_all_local 扫 PID 目录、write_pid_file/remove_pid_file @fs 写删）；backup_manager（load_config 行式 yml 解析、run 文件枚举 + @zip.create_zip + @fs.write_bytes_to_file + apply_retention 按名排序轮转、list、update_config 回写）；lib/media、lib/server moon.pkg 增 @fs/@utils/@zip/@utf8。utils_p3_wbtest validate_script 测试改为临时目录真实验证。**偏差记录**：(a) cleanup 改基于数量上限的保留策略（@fs 无文件 mtime 能力，已在代码注释说明）；(b) is_process_alive 无平台级进程探测，保守返回 true（决策 6 端口探测降级路径未启用，注释标明）；(c) BackupEntry.created_at 暂为空串（无 mtime）。验收：四模块目标文件 grep 无残留 TODO；moon check 0 errors；moon test lib/media 76/76、lib/utils 306/306、lib/server 120/120；全量 3837/3845（8 个失败均为环境缺 python3，与本批无关，重跑确认 013 熔断场景为时序抖动）；fmt/info 已跑 | 实施完毕，归档 |
| 2026-08-23 | 对抗性审查修订（代码级，4 项 C 级 + 4 项 W 级）：backup_manager：1) generate_archive_name 原 .tar.gz 撒谎（实际 @zip ZIP 格式）改 .zip；2) list() 原字符串读 ZIP 二进制必抛错被 catch 吞掉，列表永远空（静默假数据）——改 read_file_to_bytes；3) run() 原字符串读源文件，二进制（媒体/压缩包）必跳过且无告警（违背风险表跳过并告警承诺）——改 read_file_to_bytes 并 println 告警；4) include_sessions=false 落地 is_heavy_exclude（sessions/snapshots，对齐 Ruby HEAVY_EXCLUDE；原读取配置但不消费）；5) dest_dir 后置 is_dir 验证、retention 失败 println 告警。discover：6) is_process_alive 原恒 true（崩溃残留 PID 文件被当活 server）——/proc/pid 探测（非 Linux 退化 true）+ 新增 is_server_reachable HTTP /health 探测（2s 超时），find_all_local 双重校验，find_local/find_all_local 相应改 async。output_dir：7) cleanup(max_age_hours) 参数语义欺诈（被当 max_count 用）——改签名 cleanup(max_files) 并按文件名排序删除；8) total_size 原字符数统计（二进制必错）改字节读取；ensure_exists 后置 is_dir 验证（原恒 Ok）。新增 backup_wbtest.mbt 5 例（ZIP 往返含二进制/retention/禁用诚实 Err/重目录排除/heavy 单元）与 output_dir_wbtest.mbt 4 例。验收：moon check 0 errors；moon test lib/server 136/136、lib/media 80/80 | 实施后对抗性审查发现 backup 三连假成功（扩展名/列表/跳文件）与 discover 假活进程 |
