# GET /api/dirs 目录浏览契约对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md` I-008、`docs/web-ui-gaps.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`（API 契约对齐同类先例）  
> **来源差距**: I-008 - GET /api/dirs 目录浏览结构不兼容（P1）  
> **依赖**: 前置 fix-06；后置 无  
> **优先级**: P1  
> **灰度 key**: 无

## 问题描述 [必填]

`GET /api/dirs`（新会话弹窗的工作目录选择器使用的无会话目录浏览端点）响应结构与前端期望完全不兼容，导致目录选择器无法导航：

- **期望（orig）**：`{root, path, parent, home, default, entries:[{name, path, type}]}`，entries 仅含目录、path 为绝对路径、按名称排序，并过滤隐藏文件与噪声目录。
- **实际（current）**：`{path, count, files:[{name, is_dir}]}`，files 同时含文件与目录、无绝对路径、无排序、无过滤；缺 `root`/`parent`/`home`/`default`/`entries` 全部导航字段。

前端 `fetchDirs` 的 sessionLess 分支读 `data.root`/`data.home`/`data.default`/`data.entries` 并过滤 `e.type === "dir"`，在当前响应下全部得到 undefined/空数组，工作目录选择器空白不可导航（`web/sessions.js:4613-4626`）；新会话 store 读 `data.home` 推导默认工作目录同样失败（`web/features/new-session/store.js:104-115`）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前 GET /api/dirs 返回 `{path, count, files:[{name,is_dir}]}` | 读 `lib/web/handlers_dirs.mbt:37-52` | 确认：items 为 `{name, is_dir}`，响应 `{path, files, count}`；默认 dir 为 `"."`；不存在直接 404；无排序无过滤 | 确认 I-008 的"实际"描述属实 |
| orig 返回 `{root, path, parent, home, default, entries:[{name,path,type}]}` | 读 `D:/MoonBit/openclacky/lib/clacky/server/http_server.rb:4508-4544`（`api_browse_dirs`） | 第 4541 行确认六键响应；entries 仅目录（4534 行 `next unless File.directory?`），path 为绝对路径（4535 行 `path: full`），按名称小写排序（4539 行） | 确认 I-008 的"期望"描述属实 |
| orig 空 path 默认 Dir.home；`~` 展开；不存在时向上找最近存在的祖先而非 404 | 读 `http_server.rb:4516-4527` | 确认三行为均存在（4516/4517/4522-4526） | 确认，需纳入对齐 |
| orig 过滤隐藏文件（除非 `show_hidden=true`）与 IGNORED_FILE_ENTRIES | 读 `http_server.rb:4445, 4529-4531` | 常量列表：`.git .svn .hg node_modules .DS_Store .bundle vendor/bundle tmp .sass-cache` | 确认，MoonBit 侧无此过滤（`grep "node_modules\|IGNORED" lib/web` 0 命中），需新增 |
| orig `default` = agent_config.default_working_dir \|\| `~/clacky_workspace` | 读 `http_server.rb:6705-6707` | 确认 `default_working_dir` helper 定义 | 确认 |
| 前端消费 `data.root/home/default/entries`、`e.type === "dir"`、`d.path` 绝对路径 | 读 `web/sessions.js:4613-4626` | 确认 fetchDirs sessionLess 分支逐字段依赖 orig 形状 | 确认：前端无需修改 |
| 前端新会话 store 消费 `data.home` | 读 `web/features/new-session/store.js:104-115` | 确认 `loadDefaultDirectory` 读 `data.home` 后拼 `/clacky_workspace` | 确认 |
| 前端不读 `data.parent` | `grep "data\.parent" web/sessions.js` | 0 命中（`homeDir`/`defaultDir` 有消费，`parent` 无直接消费） | parent 键按 orig 契约仍返回（保持形状一致），前端暂不消费 |
| 路由已注册 `GET /api/dirs` | 读 `lib/web/server.mbt:655-658` | `dr.get("", ...)` 指向 `handle_dirs_list`；crescent 空路径注册已有先例（fix-04 验证） | 确认：路由无需改，仅改 handler |
| MoonBit 侧可取 home 目录 | `grep "@utils.home_dir" lib/` | 多处在用（`lib/web/handlers_files.mbt:299`、`lib/web/ext_loader.mbt:191` 等） | 确认 `@utils.home_dir()` 可用 |
| MoonBit 侧可取配置的 default_working_dir | 读 `lib/config/agent.mbt:20`、`lib/web/handlers_session_ext.mbt:235` | `AgentConfig.default_working_dir : String?`；`server_ref.val.config.default_working_dir` 已有读取先例 | 确认可复用 |
| `~` 展开能力 | 读 `lib/web/ext_loader.mbt:189` | 存在私有 `expand_tilde`（同包可复用或仿写） | 确认可行 |
| 现有 dirs 测试仅覆盖 mkdir | 读 `lib/web/handlers_api_contract_wbtest.mbt:82-135` | 3 个测试均为 `handle_dirs_mkdir`，无 GET list 断言 | 确认：需新增 GET 形状白盒测试 |
| **偏差**：POST /api/dirs/mkdir 请求体键名也不兼容（前端发 `{parent, name}`，后端收 `{path, name}`） | 读 `web/sessions.js:4892-4896`（发 `parent`）vs `lib/web/handlers_dirs.mbt:67-73`（读 `path`）vs orig `http_server.rb:4562`（收 `parent`） | 确认存在第二处不兼容 | gap/issues 文档未记录此点；**按 scope 纪律不纳入本 spec**，记入"不涉及文件"并回报主 agent |

### 详细分析

| 维度 | 当前（`lib/web/handlers_dirs.mbt:5-52`） | orig（`http_server.rb:4512-4544`） | 修复方式 |
|------|------|------|------|
| 顶层键 | `{path, files, count}` | `{root, path, parent, home, default, entries}` | 改为六键 |
| 条目 | `{name, is_dir}`，含文件+目录 | `{name, path(绝对), type:"dir"}`，仅目录 | 仅保留目录，补绝对 path 与 type |
| 排序 | 无（read_dir 原始顺序） | 名称小写排序 | 排序 |
| 过滤 | 无 | 隐藏文件（除非 show_hidden）+ IGNORED_FILE_ENTRIES 9 项 | 新增过滤，支持 `show_hidden` query |
| 空 path | `"."`（相对 cwd） | `Dir.home` | 改 home |
| `~` 前缀 | 不支持 | 展开为 home | 支持 |
| 目录不存在 | 404 | 向上找最近存在的祖先 | 对齐为祖先回退（前端选择器要求可用） |
| `default` 字段 | 无 | config.default_working_dir \|\| `~/clacky_workspace` | 读 `server_ref.val.config.default_working_dir`，fallback `home + /clacky_workspace` |
| 路径校验 | `validate_path`（拒 `..`） | 无显式校验（绝对模式天然安全） | **保留** `validate_path`（fix-05 安全基线不回退；前端只传绝对路径不受影响） |

前端两处消费点（sessions.js picker、new-session store）均已按 orig 形状编写，**前端零修改**。

## 决策 [必填 - 含为什么]

1. **响应形状全量对齐 orig 六键，不保留 `files`/`count` 旧键**：前端两个消费点都只读 orig 键（已验证），旧键无消费者；保留双形状只会留下永远无人读的字段。`entries` 项只含 `{name, path, type:"dir"}`（orig 在 browse 端点不返回 size）。

2. **仅目录 + 排序 + 过滤语义对齐 orig**：目录选择器只展示目录；隐藏文件与 9 项 IGNORED 目录（`.git`/`node_modules` 等）默认过滤，`show_hidden=true` 时放行隐藏文件（IGNORED 列表 orig 恒过滤，保持恒过滤）。过滤逻辑放在 handler 内联常量，不新建模块——仅此一处消费。

3. **空 path 默认 home、`~` 展开、不存在目录向上回退祖先**：三个行为都是选择器可用性前提（orig 注释明确说明"picker stays usable"）。MoonBit 用 `@utils.home_dir()` 与仿写 `expand_tilde`（`ext_loader.mbt:189` 有先例）实现。`home` 取不到时回退 `"."`（与现有代码风格一致）。

4. **`default` 字段：优先 `config.default_working_dir`，fallback `home + "/clacky_workspace"`**：与 orig `default_working_dir` helper（http_server.rb:6705-6707）语义一致；MoonBit 侧读取先例见 `handlers_session_ext.mbt:235`。

5. **保留 `validate_path` 拒绝 `..`**：fix-05 确立的安全基线不因对齐 orig 而回退；前端只传绝对路径（sessions.js:4616 用 `encodeURIComponent(relPath)`，relPath 来自服务端返回的绝对 path），合法导航不触发拒绝。

6. **scope 仅 GET /api/dirs**：POST /api/dirs/mkdir 的 body 键名（`parent` vs `path`）不兼容是新发现的相邻问题，按 scope 纪律不纳入，另报主 agent 立项。

<!--
MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。
- crescent 路由：不新增路由；`get("")` 已有用法（server.mbt:656）。
- FFI：不涉及新 C stub；仅用已有 @fs/@path/@sys API。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_dirs.mbt` | 修改 | `handle_dirs_list` 重写为 orig 契约：六键响应、仅目录条目（绝对 path + type）、排序、IGNORED/隐藏过滤、show_hidden、home 默认、`~` 展开、祖先回退、`default` 字段 |
| `lib/web/handlers_dirs_wbtest.mbt` | 新建 | GET list 白盒测试：六键齐全、仅目录、排序、隐藏过滤、show_hidden 放行、不存在目录回退祖先、`~` 展开（USERPROFILE 重定向到 `_build` 保持 hermetic，参照 handlers_api_contract_wbtest.mbt 先例） |

### 不涉及文件

- `web/` 前端全部文件（两个消费点已按 orig 形状编写，零修改）
- `lib/web/handlers_dirs.mbt` 的 `handle_dirs_mkdir`（body 键名 `parent` vs `path` 不兼容为相邻问题，不在本 spec 范围）
- `lib/web/server.mbt`（路由已注册，无需改）
- `lib/web/handlers_files.mbt`（session 内 files API 为另一端点，不属于 I-008）
- `lib/config/`（只读复用 `default_working_dir`，不改配置结构）
- WS 协议层、`lib/agent/` 层（不涉及）

## 实施计划 [必填]

### 任务包 1：handler 重写（0.5 天）
- `handle_dirs_list`：path 解析（空→home、`~` 展开、validate_path 保留）、祖先回退、read_dir 后过滤（IGNORED 常量 + 隐藏/show_hidden）、仅目录条目（`is_directory` 复用 handlers_files.mbt:332）、绝对 path（`@path.Path::join`）、名称小写排序
- 响应组装 `{root, path, parent, home, default, entries}`；`parent` 取目标目录父级（根目录时等于自身）
- `default`：`server_ref.val.config.default_working_dir` 优先，fallback `home + "/clacky_workspace"`

### 任务包 2：白盒测试（0.5 天）
- 新建 `handlers_dirs_wbtest.mbt`，覆盖上表各行为；USERPROFILE 重定向 hermetic 模式参照 `handlers_api_contract_wbtest.mbt:58-72`
- `moon check` + `moon test lib/web` 全绿

## 验收标准 [必填]

- [ ] `GET /api/dirs`（无 query）返回 200 + `{root, path, parent, home, default, entries}` 六键，root=path=home
- [ ] `GET /api/dirs?path=<abs>` 的 entries 仅含目录，每项 `{name, path(绝对), type:"dir"}`，按名称小写排序
- [ ] 隐藏文件默认不出现，`show_hidden=true` 出现；`.git`/`node_modules` 等 IGNORED 项恒不出现
- [ ] `path` 指向不存在目录时返回最近存在祖先的列表而非 404
- [ ] `path=~/...` 正确展开为 home 下路径
- [ ] `default` 字段：配置存在时为配置值，否则为 `<home>/clacky_workspace`
- [ ] 含 `..` 的 path 仍返回 400（validate_path 安全基线不回退）
- [ ] Playwright 复测：新会话弹窗目录选择器可展开/进入/返回导航（对应 issues 表 I-008 行可标记 Fixed）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Windows 下 `@path.Path::join` 产出反斜杠路径，前端按 `/` 拼接预设路径 | 中 | 响应的 path/home/default 统一将 `\` 归一为 `/`（前端 store.js:111 用 `/` 拼接，orig 在 Windows 同样输出正斜杠风格）；白盒测试在 Windows 断言归一后形态 |
| home 目录取不到（HOME/USERPROFILE 均未设） | 低 | 回退 `"."`（现有代码风格），entries 仍可列出 cwd |
| 祖先回退改变 404 语义，影响其他调用方 | 低 | grep 确认 GET /api/dirs 仅前端 picker 与 new-session store 两个消费者（见验证记录），均期望可导航而非 404 |
| 排序/过滤使空目录 entries 为空数组 | 低 | 前端 `(data.entries \|\| [])` 有兜底（sessions.js:4624），显示空态即可 |

## 依赖关系 [必填]

- **前置依赖**：fix-06（按任务指派；fix-06 spec 文件当前尚未出现在 `specs/` 下，应为同批次并行起草中）。功能上本 spec 不依赖 fix-06 的代码产出，实施顺序服从指派。
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-008（P1）GET /api/dirs 契约对齐；验证中发现 mkdir body 键名相邻问题，按 scope 纪律排除并上报 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_dirs_list@:5-52 确认输出 {path,files,count}+{name,is_dir}；路由@server.mbt:655-656 确认；无 IGNORED 过滤确认（0 命中）；expand_tilde@ext_loader.mbt:189 确认可复用；@utils.home_dir() 多处使用确认；handle_dirs_mkdir@:67 读 path 确认 body 键名不兼容（正确排除为相邻问题）。orig Ruby 源码逐行验证：api_browse_dirs@http_server.rb:4512-4545 确认六键响应（root/path/parent/home/default/entries）+仅目录+绝对 path+名称排序+IGNORED/隐藏过滤+祖先回退+home 默认+~展开全部属实；default_working_dir@:6705-6706 确认。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
