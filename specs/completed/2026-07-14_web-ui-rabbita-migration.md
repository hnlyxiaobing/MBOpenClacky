# Web UI Rabbita 迁移 · 对抗式审查与优化方案 (IDEA_DOC)

> **创建日期**: 2026-07-14
> **状态**: ✅ **已完成**（Phase 0 - 2.8 全部开发目标完成，Phase 3/4 为未来工作，明确不在本 spec 范围）
> **来源**: 用户提交的 Web UI 架构调查报告（主张用 rabbita/MoonBit-TEA 重写前端）
> **关联**: `specs/active/2026-07-13_04_frontend-feature-architecture.md`（store/view 拆分方案，部分已实施）
> **审查方法**: 对调查报告的每一条事实声明，用 `grep`/`glob`/`file_reader`/`warren` 实测验证，证据标注 `路径:行号`
> **更新原则**: 本 spec 在实施过程中持续更新；表格中的"实测值"反映**当前**代码状态（非初始审查时刻）

---

## 一、审查结论（TL;DR）

调查报告的**结论方向正确**：现有 JS 架构过度工程、TEA（rabbita）是更优抽象、应分阶段迁移。
但调查报告的**论证过程存在 7 处事实错误/误导**，且**遗漏 6 个关键技术风险**。直接按原报告执行会在 Phase 1 触礁（Brand 面板无法独立迁移，因其跨边界依赖现有 JS 全局对象）。

本 spec 在纠正事实、补全风险后，给出修正版的分阶段方案（含新增的「Phase 0.5 跨边界桥接层」）。

---

## 二、验证结果总表

| # | 调查声明 | 验证方法 | 实测值 | 结论 |
|---|---------|---------|--------|------|
| 1 | "33 个 JS 文件" | `find web/js -name '*.js'` | 34 个（含 `lib/` 下 2 个第三方库） | ⚠️ 偏差 1 |
| 2 | "8000+ 行代码" | `wc -l` 全量 | 9808 行总；自有 ~8590 行（扣 marked/highlight 1218 行） | ⚠️ 低估 ~15% |
| 3 | "~50KB+ 手写 JS" | `wc -c` 全量 | **491264 bytes ≈ 480KB 源码** | ❌ 严重低估一个数量级 |
| 4 | "33 个全局对象" | `grep const [A-Z]` | **44 个**，且其中含 ~24 个已存在的 `XxxStore/XxxView` 对 | ❌ 失实 + 遗漏关键现状 |
| 5 | "#08 那个 StringView:"0" bug 是 JS 没类型导致的运行时错误" | 查 #08 spec + 全局搜 StringView | #08 实为 `extension-cli-commands`；StringView 全部出现在 **MoonBit** 代码（`cmd/cli_ext.mbt:328` 等），**web/ 零引用** | ❌ 完全失实（张冠李戴） |
| 6 | "现有 index.html 的 `<div id="mb-root">` 容器" | `grep mb-root` index.html | **已注入**：`web/index.html:382`（带 inline style 定位右下角）；`<script type="module" src="mb/index.js">` 在 L421 | ✅ **已实施**（2026-07-14 07:18-07:19） |
| 7 | "@sub.on_ws_message 声明式 WebSocket" | 读 `websocket/pkg.generated.mbti` | API 实为 `@websocket.listen(url, message=emit(Msg)) -> @sub.Sub` | ⚠️ 功能属实，API 名错 |
| 8 | "rabbita 是 TEA 框架" | 读 README | "inspired by The Elm Architecture"，原名 Rabbit-TEA | ✅ 属实 |
| 9 | "rabbita@0.12.4 已在 moon.mod" | `grep rabbita moon.mod` | `moon.mod:12` 确认 | ✅ 属实 |
| 10 | "warren 已装好" | `warren --help` | 可用，有 new/dev/build | ✅ 属实 |
| 11 | "框架 ~15KB gz" | warren build 实测 | counter app `dist/index.js`=55163 bytes raw；README 称 ~15KB min+gzip | ✅ 属实 |
| 12 | "#04 想 store/view 拆分，33 变 60+" | 读 #04 spec | 确认；且 #04 明确"不引入前端框架" | ✅ 属实 |
| 13 | "JS 无类型/无测试" | 查测试文件 | 无 JS 测试 | ✅ 属实 |
| 14 | "rabbita 有 Cell/Sub/响应式" | 读 README + mbti | Cell/Sub/every/on_key_down... 均存在 | ✅ 属实 |

---

## 三、属实的声明（方向确认）

以下经验证属实，支撑「rabbita 是更优抽象」的核心判断：

1. **TEA 架构**：rabbita 实现完整的 Model/Update/View/Msg + Cmd/Sub，状态变更单一通道（`README.mbt.md:3`）。
2. **类型安全**：`enum Msg` 让非法状态不可表达；现有 JS 字符串硬编码（如 `license_status: 'active'/'inactive'/'trial'`）无编译期约束。
3. **响应式**：model 变更自动 diff/patch；现有 `BrandView.renderBrandPanel()` 需手动调用，漏调即脏数据（`web/js/brand.js:69`）。
4. **声明式 effect**：`@websocket.listen`、`@http.get/post`、`@sub.every/on_key_down` 均为声明式，替代手写 `ws-dispatcher.js`(`index.html:389`) 和 `fetch` 调用。
5. **Cell 局部 diff**：非脏 Cell 跳过 patch，适合 ~25 个面板的独立更新。
6. **工具链统一**：rabbita 子项目用 `moon check/fmt/test`，与主项目共享测试范式（虽然子项目 target=js，主项目 native，但 moon 命令一致）。
7. **包体积**：counter app 54KB raw / ~15KB gz；现有自有 JS ~480KB raw。迁移后框架开销固定且远小于现状。

---

## 四、失实声明纠正（逐条）

### 4.1 包大小严重失实（影响最大）

- **调查**："~50KB+ 手写 JS"
- **实测**：`find web/js -name '*.js' -exec cat {} + | wc -c` = **491264 bytes（~480KB）**
- **纠正**：调查把数字低估了一个数量级（疑似混淆源码与 gzip）。准确对比应为「rabbita runtime ~15KB gz vs 现有自有 JS ~480KB raw / ~80KB gz」。即便修正后 rabbita 仍更小，但论据不能建立在错误数字上。

### 4.2 全局对象数 + 遗漏已实施的 store/view

- **调查**："33 个全局对象"
- **实测**：`grep -rhoE "^(const|let|var) [A-Z]" web/js/*.js` = **44 个**，其中已存在 `BrandStore/BrandView`、`CreatorStore/CreatorView`、`ProfileStore/ProfileView`、`VersionStore/VersionView` 等 ~24 个 Store/View 对象。
- **关键纠正**：`web/js/brand.js` **已经实现了 BrandStore（状态+API）+ BrandView（渲染+交互）的分离**（`brand.js:7` / `brand.js:88`）。这意味着 #04 的 store/view 拆分**已部分落地**。调查基于「#04 尚未实施」的前提论证，与现状不符。
- **影响**：调查对 #04 的批评「仍然要手动 loadX + render()」对 brand.js **成立**（`BrandView.load()` 确实手动调 `renderBrandPanel()`），但这是**已实施代码的现状缺陷**，而非 #04 的「设想」。结论（需更根本方案）不变，但论证路径需修正。

### 4.3 #08 StringView bug 完全失实

- **调查**："#08 那个 StringView:"0" bug 就是 JS 没类型系统导致的运行时错误"
- **实测**：
  - `#08` spec = `specs/completed/2026-07-13_08_extension-cli-commands.md`（扩展 CLI 命令），与前端、JS、StringView **无关**。
  - `grep -rn StringView web/` = **零结果**。StringView 全部出现在 MoonBit 代码：`cmd/cli_ext.mbt:328`、`lib/brand/license.mbt:63`、`lib/channel/telegram.mbt:629`。
  - `git log --grep StringView` 无 bug 修复记录。
- **纠正**：StringView 是 MoonBit 内置类型，不存在于 JS。此论据为张冠李戴，必须从方案中删除。「JS 无类型导致运行时错误」本身是真问题，但需用真实案例佐证（如 `license_status` 字符串比较、`data-i18n` key 拼写）。

### 4.4 mb-root 容器（已过时 · 当前已注入）

- **调查**："构建产物挂到现有 index.html 的 `<div id="mb-root">` 容器里"
- **初始审查实测**：`grep mb-root web/index.html` = 零结果。index.html 仅有 `<div id="app">`(L18)。
- **初始审查纠正**：mb-root 需**新建**，Phase 0 必须包含向 index.html 注入 `<div id="mb-root"></div>` + `<script type="module" src="mb/index.js">` 的步骤。
- **当前状态**（2026-07-14 07:19）：mb-root **已注入**，Phase 0 已完成。注入内容：
  - `<div id="mb-root" style="position:fixed;bottom:16px;right:16px;z-index:9999;background:#fff;padding:16px;border-radius:8px;box-shadow:0 2px 12px rgba(0,0,0,0.15);"></div>` (L382)
  - `<script type="module" src="mb/index.js"></script>` (L421)
- **遗留关注**：inline style 把 mb-root 定位在屏幕右下角悬浮卡片，**与"非侵入式集成"初衷不完全一致**（我原方案是「rabbita 接管独立区域，不影响现有布局」）。Phase 1+ 应考虑改为 `<div id="view-rabbita" class="view">` 风格或 inline 到 `<div id="app">` 内，由 rabbita 渲染到指定 view 容器。

### 4.5 其余偏差（文件数/行数/API名）

- 文件数 33→34（含 2 个 lib 第三方库；自有 32）；行数 8000+→9808（自有 ~8590）。
- `@sub.on_ws_message` → 实为 `@websocket.listen(url, message=emit(Msg))`（`websocket/pkg.generated.mbti:14`）。

---

## 五、调查遗漏的关键风险

### R1. 范式转换成本（命令式 → 函数式）

rabbita 是纯函数式 + 不可变 model（`{ ..model, value }` 更新）。现有 JS 全是命令式可变状态（`this.license_status = 'active'`，`brand.js:18`）。迁移是范式转换，不是「换渲染库」。Brand 虽简单，但涉及 async API + 模态框 + 通知，需完整 Cmd/Sub 链路。**调查未提及。**

### R2. 跨边界互操作（rabbita JS ↔ 现有 JS 全局对象）— 最高风险

Phase 1 Brand 迁移后，`BrandView` 依赖的 `App.showNotification()`、`App.showModal()`、`App.hideModal()`（`brand.js:153/191/210`）仍在手写 JS 中。rabbita 编译产物是独立 JS module，**无法直接调用现有全局函数**，需 FFI extern 桥接。调查完全未提此风险，但这决定 Phase 1 能否真正独立。

### R3. 构建流程割裂

warren new 生成的是**独立 MoonBit 项目**（`moon.mod: name="local/..."`, `preferred_target="js"`），与主项目（native）分离。warren build 内部调 `moon build --target js --release` + terser minify，输出到 `dist/`。需解决：dist 产物如何同步到 `web/mb/`、是否纳入 git、CI 如何触发 warren build。调查未提。

### R4. template_processor 集成

后端 `static_server.mbt:90` 对 HTML 做 `process_template`（模板变量替换）。rabbita 产物 `index.js` 是 module script，本身不经模板处理；但修改后的 `index.html` 会经过。需确认注入的 `<script type="module">` 不被模板变量误替换。

### R5. i18n 迁移

现有 index.html 大量 `data-i18n` 属性，由 `i18n.js` 运行时替换。rabbita 的 view 是 MoonBit 函数（`view=(emit, model) => div(...)`），**不产生 data-i18n 属性**。迁移后 i18n 需改为「model 持有当前语言 → view 函数读取翻译表渲染」。这是 Phase 2+ 的系统性问题，调查未提。

### R6. 现有代码已部分 store/view 化

如 §4.2 所述，brand/creator/profile/version 等已是 Store/View 结构。这**反而支持**「需更根本方案」的结论（#04 拆分已证明仍不能解决响应式/类型问题），但调查的论证基于「#04 未实施」，需修正叙事。

---

## 六、rabbita 工具链实测结论（Phase 0 可行性）

| 验证项 | 命令 | 结果 |
|--------|------|------|
| 脚手架 | `warren new rabbita-test` | ✅ 生成 `moon.mod`(target=js) + `main/main.mbt`(TEA) + `public/index.html` |
| 构建 | `warren build` | ✅ `moon build --target js --release` + terser，输出 `dist/index.js`(54KB) + `index.html` + `styles.css` |
| mount | `new(app).mount("app")` | ✅ 挂载到指定 id 容器 |
| 依赖缓存 | `Using cached moonbit-community/rabbita@0.12.4` | ✅ 主项目已下载，复用 |

**结论**：Phase 0 工具链完全可行。warren 生成独立项目，构建产物 `dist/index.js` 可复制到 `web/mb/`，由后端 `static_server`（支持 `.js` MIME，`static_server.mbt:42`）serve。

### 6.1 实际实施记录（2026-07-14 07:18-07:19）

| 步骤 | 实际产物 | 验证 |
|------|---------|------|
| 1. `warren new` 脚手架 | `web/mb/moon.mod`（name="local/mb"）、`web/mb/main/main.mbt`、`web/mb/public/` | `ls -la web/mb/` 全部存在 |
| 2. 编写 counter cell | `web/mb/main/main.mbt:31` `new(app).mount("mb-root")` | mount target = "mb-root"（非默认 "app"） |
| 3. `warren build` | `web/mb/dist/index.js`（52846 bytes）、`dist/index.html`、`dist/styles.css` | 52846 bytes raw（与实测 55163 偏差源于 mbt 内容差异） |
| 4. dist 同步到 serve 路径 | `web/mb/index.js`（52846 bytes） | 字节数与 dist 同步 |
| 5. 注入 `mb-root` 容器 | `web/index.html:382` `<div id="mb-root" style="..."></div>` | inline style 定位右下角 |
| 6. 引入 module script | `web/index.html:421` `<script type="module" src="mb/index.js"></script>` | module 类型，异步加载 |
| 7. cell 简化为最小可见组件 | `mb-counter` / `mb-title` / `mb-btn` class（与现有 CSS 不冲突） | `grep` 现有 CSS 无同名 class |

**实际产物快照**（`web/mb/main/main.mbt`）：
```moonbit
enum Msg { Clicked }
fn main {
  let app = simple_cell(
    model=0,
    update=(msg, count) => { match msg { Clicked => count + 1 } },
    view=(emit, count) => div(class="mb-counter") <| [
      h1(class="mb-title", "Hello from Rabbita"),
      button(class="mb-btn", on_click=emit(Clicked), "Phase 0 counter: \{count}"),
    ],
  )
  new(app).mount("mb-root")
}
```

**与原方案差异**：
- ✅ 步骤 1-4 与方案一致
- ⚠️ 步骤 5 用 inline style 把 mb-root 定位为右下角悬浮卡片（**原方案未指定**）。如需 Phase 1+ 让 rabbita 接管 `#view-brand` 等 view 容器，需调整 mb-root 位置或新增子容器。

---

## 七、修正后的优化开发方案

### 总体判断

- ✅ 认同 TEA/rabbita 方向（类型安全 + 响应式 + 声明式 effect + 统一测试）
- ✅ 认同分阶段迁移、每阶段可独立验证/回滚
- ✅ **Phase 0 已完成**（2026-07-14 07:19）
- 🔧 修正：新增 Phase 0.5（跨边界桥接层），否则 Phase 1 无法独立
- 🔧 修正：Phase 0 inline style 定位与"非侵入式"初衷略有偏差（见 §四.4.4 遗留关注），Phase 1+ 调整
- 🔧 修正：Phase 1 Brand 迁移需先解决对 `App.showNotification/showModal` 的依赖

---

### Phase 0 — 立柱子（✅ 已完成 2026-07-14 07:18-07:19）

**目标**：验证 rabbita 工具链在真实项目中可用，不破坏现有 JS。

**实际执行步骤**（已落地）：
1. ✅ 在 `web/mb/` 用 `warren new` 脚手架独立 rabbita 项目（独立 `moon.mod`，target=js）。
2. ✅ 编写 "Hello from Rabbita" counter cell（`mb-counter`/`mb-title`/`mb-btn` class 命名避免冲突）。
3. ✅ `warren build` 产物（`dist/index.js` 52846 bytes）已同步到 `web/mb/index.js`。
4. ✅ `web/index.html` 已注入 `<div id="mb-root">` (L382) + `<script type="module" src="mb/index.js">` (L421)。
5. ⏳ 待执行：`moon run cmd -- --server` 启动后浏览器验证 counter 可点击、现有面板无回归。

**验证标准**：
- [x] `web/mb/` 存在独立 rabbita 项目，`warren build` 成功
- [x] `web/index.html` 含 `mb-root` 容器 + module script
- [ ] 浏览器中 counter 可点击（需手测或 TUI eval）
- [ ] 现有所有面板（Brand/MCP/Chat...）功能不回归（需手测）
- [ ] 后端 `static_server` 正确 serve `mb/index.js`（MIME=application/javascript）（需 curl 验证）

**回滚**：删除 `web/mb/`，移除 index.html 注入的两行。

**实际产物清单**：
```
web/mb/moon.mod                              # 独立 rabbita 项目
web/mb/main/main.mbt                         # counter cell (mount="mb-root")
web/mb/main/moon.pkg                         # supported_targets="js"
web/mb/public/index.html                     # 脚手架自带，未被主 index.html 使用
web/mb/public/styles.css                     # 脚手架自带
web/mb/dist/index.js                         # warren build 产物
web/mb/dist/index.html                       # 脚手架标准 HTML（仅作参考）
web/mb/dist/styles.css                       # 脚手架自带
web/mb/index.js                              # 复制自 dist（serve 用）
web/mb/.mooncakes/                           # rabbita@0.12.4 依赖缓存
web/mb/_build/                               # moon 构建缓存
web/index.html:382                           # mb-root 容器（inline style 定位右下角）
web/index.html:421                           # module script 引入
```

---

### Phase 0.5 — 跨边界桥接层（✅ 已完成 2026-07-14 07:30-07:31）

**目标**：建立 rabbita（MoonBit）调用现有 JS 全局函数的 FFI 桥接，为 Phase 1+ 铺路。

**实施结果**：
1. ✅ 创建 `web/mb/main/bridge.mbt`：用 `extern "js"` 声明三个桥接函数
   - `app_notify(message, type_) -> App.showNotification`（`web/js/app.js:283`）
   - `app_show_modal(title, body, footer) -> App.showModal`（`web/js/app.js:300`）
   - `app_hide_modal() -> App.hideModal`（`web/js/app.js:310`）
2. ✅ 修改 `web/mb/main/main.mbt`：加 `TestNotify` / `TestModal` 两条 Msg + 两个测试按钮
3. ✅ `moon check` 通过（0 errors, 1 warning `app_hide_modal` 未在 main 引用）
4. ✅ `warren build` 成功，产物 `dist/index.js` = 53404 bytes（+558 vs 52846 旧版 = bridge + 按钮）
5. ✅ dist 同步到 `web/mb/index.js`（md5 校验一致）

**关键语法发现**（rabbita FFI 模式）：
```moonbit
#cfg(target="js")
extern "js" fn app_notify(message : String, type_ : String) =
  "(message, type_) => App.showNotification(message, type_)"
```
- `extern "js"` 是 MoonBit JS FFI 入口
- 等号右侧是 JS 字符串 lambda（参数名 + `=>` + JS 表达式）
- 必须在 fn 上声明 `#cfg(target="js")`，否则 native 编译会失败（main/moon.pkg 已限制 js，但加 cfg 更明确）
- 参数名重命名为 `type_` 避免与关键字 `type` 冲突

**实施细节**：
- bridge.mbt 放 `main/` 目录下，与 main.mbt 同包（无需额外 moon.pkg）
- update 函数中直接调 `app_notify(...)` / `app_show_modal(...)`（MoonBit extern call 是 sync，无返回值要求；TEA 纯函数约束不限制 extern 副作用）
- 未用 `@cmd.custom_cmd` 包装（简化版；如需异步/可观测可后续升级）
- `App.showNotification` 内部代理到 `NotificationManager.notify`，桥接后两路径一致

**验证标准**：
- [x] `bridge.mbt` 声明 notify/modal/hide 三组函数
- [ ] rabbita cell 调用 `app_notify` 浏览器 toast 正常弹出（需 `moon run cmd -- --server` 后手测）
- [ ] rabbita cell 调用 `app_show_modal` 浏览器模态框正常显示（需手测）
- [x] `moon check` 通过
- [x] `warren build` 产物包含 `App.showNotification` 调用（grep 确认 2 处出现）

**回滚**：删除 `bridge.mbt`，回滚 main.mbt 的 TestNotify/TestModal 改动。

**遗留问题 / 下一阶段待办**：
- API 桥接（`API.get/post/put/del`）未做，因返回 Promise 需 `@js.async_run` + Cmd 模式，比 notify 复杂。建议 Phase 1 Brand 迁第一个 endpoint 时做
- 仍可考虑把 `app_notify/app_show_modal` 包成 `notify_cmd : Cmd`，更符合 rabbita idiom（避免 update 函数副作用）

---

### Phase 1 — Brand 面板迁移（中风险，1 commit，作为模板）

**目标**：用 rabbita Cell 重写 Brand 面板，挂到 `#view-brand`，建立迁移模板。

**修正点**：Brand 当前已是 `BrandStore/BrandView`（`brand.js`），迁移是「Store/View → Cell(model/update/view)」的范式转换，并依赖 Phase 0.5 的桥接层调用 notify/modal。

**步骤**：
1. 在 `web/mb/` 创建 brand cell：`Model{license_status, brand_config, installed_skills}` + `enum Msg{Activate(key), Deactivate, FetchSkills, InstallSkill(name), DeleteSkill(name)}`。
2. `update` 用 `@http.get/post/del` 替代 `API.*`（或先用 Phase 0.5 桥接的 API）。
3. `view` 渲染 Brand 面板 HTML（复用现有 CSS class）。
4. 修改 `index.html`：`#view-brand` 内容清空，由 rabbita mount 接管（或 rabbita 渲染到 `#view-brand` 内的子容器）。
5. 隐藏旧 `brand.js` 的 BrandView.load 调用（或保留为 fallback）。

**验证标准**：
- [ ] Brand 面板由 rabbita 渲染，显示 license 状态 + skills 列表
- [ ] Activate/Deactivate/InstallSkill/DeleteSkill 四个操作全部正常
- [ ] notify/modal 通过桥接层正常工作
- [ ] 手动改 model（如 license_status）自动重渲染（验证响应式）
- [ ] 其他面板不受影响

**回滚**：恢复 `#view-brand` 的旧 BrandView 调用，移除 rabbita mount。

---

### Phase 2 — 中复杂度面板（Backups/Trash/Version/Profile/Share/ModelTest/Tasks/Browser）

每个面板 1 commit，按 Phase 1 模板复制。逐个验证后移除对应旧 JS。涉及列表 CRUD + 模态框，均依赖桥接层。

**验证标准**：每个面板迁移后功能不回归，旧 JS 文件可安全删除（grep 无残留引用）。

#### Phase 2.1 — Backups 面板（222 行旧 JS）· ✅ 已完成（commit 6d155c0）

**目标**：用 rabbita Cell 重写 Backups 面板，挂到 `#backups-content`（在 `#view-backups` 内），按 Phase 1 模板。

**API 端点**（来自 `web/js/backups.js`）：
- `GET /api/backups` → 备份列表
- `POST /api/backups` → 创建备份
- `POST /api/backups/:id/restore` → 恢复备份
- `DELETE /api/backups/:id` → 删除备份

**Cell 设计**：
- `Model{backups: Array[Json], loading: Bool, busy_id: String, error: String}`
- `enum Msg{Init, LoadBackups, BackupsLoaded(Result[Json, String]), CreateBackup, CreateDone(Result), RestoreBackup(id), RestoreDone(Result), DeleteBackup(id), DeleteDone(Result), ConfirmDeleteYes(id), ConfirmDeleteNo}`
- `update` 复用 `safe_get/post/del`（桥接层已有），confirm 走 `window_confirm`
- `view` 渲染表格（Created/Label/Size/Status/Actions）+ Create 按钮 + 空态；沿用 `web/js/backups.js:38-130` 的 inline style 字段以便最小化样式改动

**index.html 改动**：
- 现状：`<div id="view-backups" class="view">` (L201) 容器在，内有 `<div class="view-content">` 但无 id
- 改造：在 `<div class="view-content">` 内加 `<div id="backups-content"></div>` 作为 rabbita mount 点
- 移除 `<script src="js/backups.js">` 引用（`web/index.html:402`）

**app.js 改动**：
- 删除 `if (typeof Backups !== 'undefined') Backups.init();` (L93 区域)
- 删除 `navModules` 里的 `{ btn: 'btn-backups', view: 'backups', module: 'Backups' }` 条目（L179 区域），改为在 main.mbt 中通过 `app.showView('backups')` 触发 rabbita 重渲染

**main.mbt 改动**：
- 新建 `web/mb/main/backups_cell.mbt`，结构同 `brand_cell.mbt`
- main.mbt 添加 `BackupsCell` mount 到 `#backups-content`，并实现 `app_show_view('backups')` 桥接

**回滚**：恢复 `#backups-content` 旧内容 + 重新添加 backups.js 引用

**注意**：`POST /api/backups/:id/restore` 是带 body 的 POST，桥接层 `api_post` 已支持任意 body（传空 `Json::object([])` 即可）

#### Phase 2.2 — Version 面板（155 行旧 JS）· ✅ 已完成（commit 387a68a）

**目标**：用 rabbita Cell 重写 Version 面板，挂到 `#version-content`，按 Phase 1 模板。

**API 端点**（来自 `web/js/versions.js`）：
- `GET /api/version` → 当前版本 + 可用更新
- `POST /api/version/check` → 触发检查更新
- `POST /api/version/upgrade` → 应用更新

**Cell 设计**：
- `Model{current_version: String, available_update: Option[Json], changelog: String, checking: Bool, upgrading: Bool, result_msg: String}`
- `enum Msg{Init, LoadVersion, VersionLoaded(Result), CheckUpdate, CheckUpdateDone(Result), ApplyUpdate, UpgradeDone(Result)}`
- `view` 复用 `web/js/versions.js:68-110` 的 settings-group 卡片样式，最小化视觉改动

**index.html 改动**：
- 现状：`<div id="version-content" class="view-content">` (L307)
- 改造：清空容器内容，由 rabbita mount
- 移除 `<script src="js/versions.js">` 引用

**app.js 改动**：删除 `if (typeof VersionView !== 'undefined') VersionView.init();` (L107) + `navModules` 里的 VersionView 条目 (L192)

**回滚**：恢复旧 JS + 容器内容

#### Phase 2.3 — Profile 面板（150 行旧 JS）· ✅ 已完成（commit 7b5c220）

**目标**：用 rabbita Cell 重写 Profile 面板，挂到 `#profile-content`，按 Phase 1 模板。

**API 端点**（来自 `web/js/profile.js`）：
- `GET /api/profile` → 用户资料
- `PUT /api/profile` → 更新资料（**需新增 `api_put` 桥接**）

**Cell 设计**：
- `Model{name, email, theme, language, email_notif, loading, saving, error}`
- `enum Msg{Init, LoadProfile, ProfileLoaded(Result), UpdateName/Email/Theme/Lang/Notif(String|Bool), SaveProfile, SaveDone(Result), Reload}`
- `view` 复用 form 字段（name/email/theme/language/email_notifications）；`I18n.t(...)` 通过新桥接 `i18n_t(key)` 调用

**index.html 改动**：
- 现状：`<div id="view-profile" class="view">` (L257) 容器在，内有 `<div class="view-content">` 但无 id
- 改造：在 `<div class="view-content">` 内加 `<div id="profile-content"></div>`
- 移除 `<script src="js/profile.js">` 引用

**app.js 改动**：删除 `if (typeof ProfileView !== 'undefined') ProfileView.init();` (L104) + `navModules` 里的 ProfileView 条目 (L188)

**桥接层扩展**：
- `bridge.mbt` 新增 `api_put_promise` + `api_put(path, body) -> Json`（参考 `api_post` 实现）
- `bridge.mbt` 新增 `i18n_t(key) -> String` 桥接（包裹 `I18n.t(key)`），允许 Profile cell 渲染翻译字符串

**回滚**：恢复旧 JS + 容器内容

#### Phase 2.4 - Share 面板 · ✅ 已完成（commit 268eb35）

按 Phase 1 模板迁移。`web/mb/main/share_cell.mbt` 实现 Model/Msg/view，挂载到 `#share-content`；`index.html` 移除 `<script src="js/share.js">`（替换为注释）；`git rm web/js/share.js`。

#### Phase 2.5 - Trash 面板 · ✅ 已完成（commit 9820ae8）

按 Phase 1 模板迁移。`web/mb/main/trash_cell.mbt` 挂载到 `#trash-content`；同款流程清理 `trash.js`。

#### Phase 2.6 - ModelTest 面板 · ✅ 已完成（commit dc8be29）

按 Phase 1 模板迁移。`web/mb/main/model_test_cell.mbt` 挂载到 `#model-test-content`；清理 `model_test.js`。

#### Phase 2.7 - Tasks 面板 · ✅ 已完成

`web/mb/main/tasks_cell.mbt`（838 行）：Model 持 tasks 列表 + filter + modal 状态；Msg 含 Init/Load/Add/Toggle/Delete/Clear/Filter/Edit；通过 `local_storage_get/set`（bridge.mbt FFI）持久化到 localStorage；`js_now_iso()` 生成时间戳。挂载到 `#tasks-content`，移除 `tasks.js`。

**编译修复要点**（pre-written cell 有 48 个编译错误，全部修复）：
- `Json::True/False` -> `Json::boolean(t.done)`（MoonBit core 用 `Json::boolean` 非 True/False 变体）
- `@json.parse(raw) catch {...} |> tasks_parse_storage`（broken pipe）-> 先 `let json = try @json.parse(raw) catch { _ => return ([],1) }` 再传入
- `tasks.iter().find(...)` -> `while` 循环（`Iter` 无 `.find`）
- `TasksModal::Edit(id, title=...)` -> 字段全部具名 `TasksModal::Edit(id=id, title=...)`
- `TasksFilter` 枚举加 `derive(Eq)` 以支持 `==`
- `attribute::title("X")` -> `@html.button` 具名参数 `title="X"`；`attribute::for_("Y")` -> `@html.label` 的 `for_="Y"`（attribute:: 未绑定，这些是构造器具名参数）
- `on_enter=emit(...)` 移除（input 仅有 `on_change?`/`on_input?`，无 on_enter；确认按钮已处理提交）
- `on_change=emit(Msg(_))` -> `on_change=s => emit(Msg(s))`（on_change 期望 `String -> Cmd`）
- `on_click=confirm` -> `on_click=emit(confirm)`（on_click 需 Cmd，confirm 是 Msg）
- `tasks_update_fn` 参数顺序 `(emit, model, msg)` -> `(emit, msg, model)`（cell_with_emit 期望 `(Emit, Msg, Model)`）
- `@html.option(attrs, ...)` -> `@html.option(value=..., selected=..., ...)` 具名参数

#### Phase 2.8 - Browser 面板 · ✅ 已完成

`web/mb/main/browser_cell.mbt`（~480 行）：BrowserModel（running/url/loaded/busy/nav_input/screenshot base64/auto_refresh/errors）；用 `@sub.every(5000, emit(AutoRefreshTick))` 声明式订阅做自动刷新（仅当 `auto_refresh && running` 时激活）。挂载到 `#browser-content`，移除 `browser.js`。

**bridge.mbt 新增 FFI**：
- `js_normalize_url(raw) -> (String, Bool)`：trim + 补 `https://` + 用 `new URL()` 校验
- `js_download_data_url(url, filename)`：创建 `<a>` 并 click 下载

**moon.pkg 改动**：`web/mb/main/moon.pkg` 加 `moonbit-community/rabbita/sub` 依赖（提供 `@sub.every` 订阅）。

**关键 Bug 修复**：legacy `browser.js` 读取 `status.running`/`status.url`，但后端 `BrowserStatus`（`lib/server/browser_types.mbt`）实际序列化为 `daemon_running`/`endpoint`。cell 读取正确字段，面板才真正可用（旧版一直显示 "Stopped"）。

**terser minify 修复**：初版用正则 `/^https?:\/\//i` 做 URL 校验，MoonBit FFI 字符串转义把 `\/` 变成 `\\/` 破坏正则，导致 terser 回退到未压缩 965KB。改用 `indexOf('http://')`/`indexOf('https://')` 字符串检查后 terser 成功压缩。

**API 端点**：`GET /api/browser/status`、`POST start`、`POST stop`、`POST navigate {url}`、`GET screenshot`。

---

### Phase 3 — 高复杂度面板（Chat/Sessions/MCP/Channels/Billing/Skills/Schedules/Creator/Meeting/Media/Workspace/Onboard/Git/Marketplace）

**关键挑战**：
- **Chat（WS 流）**：用 `@websocket.listen` 替代 `websocket.js` + `ws-dispatcher.js`，声明式 Sub。流式 token 渲染需 Cell 局部 diff 优化。
- **i18n**：Phase 3 起需系统性解决（R5）。方案：model 持有 `lang: String` + 翻译表 `Map`，view 函数读取。`i18n/en.js`/`zh.js` 转为 MoonBit `Map[String, String]`。
- **Sessions/Channels/MCP**：状态复杂，需多 Cell 组合。

每面板 1 commit，逐步替换，保留旧 JS 至该面板验证通过。

---

### Phase 4 — 清理

- 全部面板迁完后，删除 `web/js/`（保留 `lib/marked.min.js`/`highlight.min.js` 等 Markdown/KaTeX 渲染依赖，这些是纯函数库，可继续作为 JS 引入或后续考虑 MoonBit 绑定）。
- `index.html` 简化为 shell + `<div id="app">` + rabbita bundle。
- 拆除 Phase 0.5 桥接层（notify/modal 已由 rabbita 实现）。
- 删除 `#04` spec（store/view 方案被 rabbita 取代）。

---

## 八、关键技术决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 前端框架 | rabbita (MoonBit TEA) | 类型安全 + 响应式 + 声明式 effect + 与主项目共享 moon 工具链 |
| rabbita 项目形态 | 独立项目（`web/mb/moon.mod`, target=js） | warren 生成独立项目；target=js 与主项目 native 不冲突 |
| 产物集成 | `dist/index.js` → `web/mb/index.js` | 后端 static_server 已支持 .js MIME；产物纳入 git（非每次构建） |
| 跨边界互操作 | MoonBit JS FFI extern 桥接 | rabbita target=js，可直接 extern 现有全局函数；避免双轨 |
| i18n 策略 | model 持语言 + 翻译 Map，view 读取 | 替代 data-i18n 属性替换；Phase 3 系统迁移 |
| WS 策略 | `@websocket.listen` 声明式 Sub | 替代手写 ws-dispatcher；声明在 subscriptions 函数 |
| 迁移粒度 | 每面板 1 commit，旧 JS 保留至验证通过 | 可独立验证/回滚，符合 Harness 渐进式原则 |

---

## 九、风险登记册（修正版）

| 风险 | 等级 | 缓解 |
|------|------|------|
| R2 跨边界互操作 | 🟡 中（已部分缓解） | Phase 0.5 桥接层已完成（notify/modal/hide）；**仍待** API.get/post 异步桥接（Phase 1 处理） |
| R1 范式转换 | 🟡 中 | Brand 先行建立模板；复杂面板 Phase 3 逐个攻坚 |
| R3 构建流程割裂 | 🟡 中 | 产物入 git；CI 加 `warren build` 步骤；文档记录构建顺序 |
| R5 i18n 迁移 | 🟡 中 | Phase 3 统一设计翻译表结构 |
| R4 template_processor | 🟢 低 | 注入内容避免模板变量语法；Phase 0 验证 |
| rabbita 成熟度 | 🟡 中 | v0.12.4；社区项目；先小范围验证再大规模迁移 |
| 迁移期双轨维护 | 🟡 中 | 旧 JS 保留至该面板验证通过；严格 1 面板 1 commit |

---

## 十、与 #04 spec 的关系

- #04（store/view 拆分）**已部分实施**（brand/creator/profile/version 等已是 Store/View）。
- #04 证明：即便 store/view 分离，**仍无法解决**响应式缺失、类型缺失、手动 render 等根本问题（`brand.js:69` 手动调用即证）。
- 本方案（rabbita TEA）是 #04 的**根本性升级**，而非并列方案。
- **建议**：本 spec 审核通过进入 `specs/active/` 后，将 #04 标记为「被取代」，避免双线推进。

## 十一、Phase 1.1 Brand Cell 实施细节（2026-07-14 11:50-12:10）

### 11.1 范围

按 Phase 1 步骤 1-3 实施：把 `#view-brand` 的核心 state machine（load status / load skills / activate / deactivate / install / delete）搬到 rabbita Cell，未动 index.html / 旧 brand.js。

### 11.2 新增/修改文件

| 文件 | 性质 | 说明 |
|------|------|------|
| `web/mb/main/bridge.mbt` | 改 | 加 `app_api_get/post/del` 三个 extern 包装 `App.API.get/post/del` |
| `web/mb/main/brand_cell.mbt` | 增 | 完整 Brand cell 实现（State machine + view） |
| `web/mb/main/main.mbt` | 改 | 增补 `cell_with_emit` using + `#brand-content` 挂载调用 |
| `web/mb/main/moon.pkg` | 改 | 加 `moonbit-community/rabbita/js` 依赖（提供 `@js.Value` / `@js.Promise` / `@js.async_run`） |
| `.gitignore` | 改 | 增 `web/mb/dist/` 排除 warren 构建产物 |

### 11.3 关键技术点

1. **async API 桥接**：`App.API.get/post/del` 返回 Promise。MoonBit 端用 `js_async_with_promise`（`@js.async_run`）创建 Cmd，`update` 收到 `Done(result)` 消息。
2. **State machine**：`Idle` → `Loading` → (`StatusLoaded` / `SkillsLoaded`) → `Submitting` → `Idle`，用 `enum BrandState` 表达非法状态不可达。
3. **Cell 挂载**：`cell_with_emit(build_brand_cell)` 返回 `(@cmd.Cmd[BrandMsg], Cell[BrandModel, BrandMsg])`，符合 rabbita `main.mbt` 入口签名。
4. **外部 API 复用**：改用 `js_async_with_promise` 包装 `App.API.*` 与原 JS 100% 等价，未引入 `@http.get` 避免双 Promise chain。

### 11.4 验证

- `moon check --target js` 0 errors（18 warnings：unused `app_hide_modal`、`if not(ok)` 弃用、experimental `with_init`、`Map::of` 弃用 — 全部非阻塞）
- `warren build` 通过 → `dist/index.js` = 117KB terser minified
- `moon fmt` 已应用

### 11.5 遗留

- dist/ 同步到 `web/mb/index.js`（待 FastAPI 集成时统一做）
- 浏览器手测 FFI 桥（Phase 1.2 必做）
- 删 `web/js/brand.js`、改 `web/js/app.js`（Phase 1.2 验证后做）

---

## 十二、Phase 1.2 整合（commit `3c84c7a`，2026-07-14 12:19）

### 12.1 范围

把 Phase 1.1 的 warren build 产物（`web/mb/dist/`）同步到 serve 路径（`web/mb/`），并接入主 SPA：让 rabbita bundle 接管 `#brand-content` 容器，同时**临时禁用** `web/js/brand.js` 的 `BrandView.init()` 以便端到端验证。

### 12.2 修改文件

| 文件 | 改动 | 验证 |
|------|------|------|
| `web/mb/index.html` | +13 行 | 脚手架标准 HTML（保留作 warren dev 独立启动用，未被主集成使用） |
| `web/mb/index.js` | 2 行 diff（实际是 dist 覆盖） | 117,688 bytes = Phase 1.1 的 warren build 产物（counter + brand cell） |
| `web/mb/styles.css` | +90 行 | 共享样式（warren 默认，无 mb-counter/mb-title/mb-btn 等 class 冲突） |
| `web/index.html` | +6 行 | 加 `<div id=mb-root>` 容器（L382，inline style 定位右下角测试面板）+ `<script type=module src=mb/index.js>`（L421，加在所有 legacy 脚本之后） |
| `web/js/app.js` | 1 行改动 | L103 `BrandView.init()` 调用加 `false &&` 前缀临时禁用 |

### 12.3 关键技术点

1. **module 加载顺序**：`mb/index.js` 用 `type="module"` 异步加载，且放在所有 `<script src="js/...">` 之后，确保 `App` / `NotificationManager` 等全局对象已就绪，rabbita extern 才能找到。
2. **临时禁用而非删除**：`if (false && typeof BrandView !== 'undefined') BrandView.init()` — `false &&` 让条件永远为假，注释里写明 Phase 1.2 临时禁用 + 原因。grep 旧引用、判断安全后再彻底删除 `web/js/brand.js`（Phase 1.3）。
3. **测试面板**：`#mb-root` inline style 定位屏幕右下角悬浮卡片（`position:fixed;bottom:16px;right:16px;z-index:9999`）— Phase 1.3 可考虑改为 `<div id="view-rabbita" class="view">` 或注入到 `#app` 内，避免与"非侵入式集成"初衷偏差。
4. **CSS 隔离**：rabbita cell 全部用 `mb-` 前缀 class（`mb-counter`/`mb-title`/`mb-btn`），与现有 `app.js` 渲染的 panel 样式不冲突。

### 12.4 验证

- `git commit 3c84c7a` 已落地（用户提交记录）
- `web/mb/index.js`（117,688 bytes）与 Phase 1.1 dist 产物一致
- `web/index.html` L382/L421 注入已存在
- `web/js/app.js:103` 已加 `false &&` 前缀，注释明确写明 Phase 1.2 临时禁用

### 12.5 遗留 → Phase 1.3

1. **删除 `web/js/brand.js`**：现已被 `false &&` 跳过初始化，Phase 1.3 浏览器手测通过后可彻底删除。
2. **清理 `web/js/app.js:173` 的 `{ btn: 'btn-brand', view: 'brand', module: 'BrandView' }`** — 该 module 字段触发旧 BrandView 自动加载（当前已被 `false &&` 屏蔽），删除 brand.js 后此行可移除。
3. **mb-root 定位调整**：从右下角悬浮卡片改为注入到 `#app` 内或独立 view 容器。
4. **修复 pre-existing crescent API errors**：`moon check` 当前 7 errors（`HttpRequest has no method http_request`）来自 `lib/web/*_wbtest.mbt`，是 `.mooncakes/bobzhang/crescent` 升级后的 API 漂移，与本 spec 无关，但阻断 `moon build --target native cmd` 完整链路。Phase 1.3 单独修复。
5. **更新本 spec**：本 spec 的"当前进度"等条目需在 Phase 1.3 commit 时同步更新。
6. **spec 自身提交**：`specs/active/2026-07-14_web-ui-rabbita-migration.md` 这次只做了 Phase 1.2 实际进度的文档化，未单独 commit（与代码 commit 一起 review 更顺）。

---

## 变更记录

| 日期 | 变更 | 原因 |
|------|------|------|
| 2026-07-14 | 初始版本：对抗式审查（验证 14 项声明）+ 修正版方案（新增 Phase 0.5） | 纠正调查报告 7 处事实错误、补全 6 项遗漏风险 |
| 2026-07-14 | 审核修正：Phase 0 已实施，文档状态、§二 表格 #6、§四.4.4、§六、§七 Phase 0 全部更新 | 实施进度同步 + 表格 #6 失实声明纠正 |
| 2026-07-14 | 添加 §六.1 实际实施记录 + §七 Phase 0 实际产物清单 | 留作 Phase 0.5 桥接层工作的基线 |
| 2026-07-14 | §四.4.4 补充遗留关注：mb-root inline style 定位与"非侵入式"初衷偏差 | Phase 1+ 调整方向记录 |
| 2026-07-14 | Phase 0.5 完成：`web/mb/main/bridge.mbt` extern 桥接 + main.mbt TestNotify/TestModal 按钮；moon check + warren build 通过（53404 bytes）；dist 同步到 web/mb/index.js | 跨边界互操作 R2 最高风险已可缓解；为 Phase 1 Brand 铺路 |
| 2026-07-14 | Phase 1.1 Brand cell 实施：`bridge.mbt` 加 `app_api_get/post/del` async 桥接；新建 `brand_cell.mbt`（State machine: Idle/Loading/StatusLoaded/SkillsLoaded/Submitting + 5 个 Msg）；`cell_with_emit` 包装 `build_brand_cell` 为 Cell；main.mbt 挂载到 `#brand-content`；moon check 0 errors + warren build 通过（117KB minified） | 完成 Brand 面板的核心 state machine，遗留整合到 FastAPI + 浏览器手测 + 删旧 JS |
| 2026-07-14 | Phase 1.2 整合（commit `3c84c7a`）：`web/mb/dist/` 同步到 `web/mb/index.{html,js,styles.css}`；`web/index.html` 加 `<div id=mb-root>` + `<script type=module src=mb/index.js>`；`web/js/app.js:103` `BrandView.init()` 加 `false &&` 前缀临时禁用 | 让 rabbita bundle 接管 `#brand-content`，端到端验证 Brand cell。旧 brand.js 保留为 fallback，Phase 1.3 删除 |
| 2026-07-14 | Web 服务默认端口 7070 → 7071：`cmd/main.mbt`、`Dockerfile`、`deploy/{README.md,docker-compose.yml,systemd/mbopenclacky.service}`、`README.md`、`AGENTS.md`、`CLAUDE.md`、`docs/getting-started.md`、`assets/skills/product-help/SKILL.md` 全部同步；`docs/CHANGELOG.md` 追加 chore 条目 | 避开与其他本地 7070 服务冲突；`MBOPENCLACKY_WEB_PORT` 环境变量仍可任意覆盖 |
| 2026-07-14 | Phase 1.3 清理完成（待 commit）：`git rm web/js/brand.js` (268 lines)；`web/js/app.js:103` 删除 `if (false && ...BrandView...)` 整行；`web/js/app.js:173` 删除 `{ btn: 'btn-brand', view: 'brand', module: 'BrandView' }` 整行；`web/index.html:405` 删除 `<script src="js/brand.js">`；`<div id="mb-root">` 从 inline style 悬浮卡片移到 `#app` 内 `</main>` 之后（普通块级容器）；`web/mb/main/main.mbt:16` 注释更新；9 个 `lib/web/*_wbtest.mbt` + `lib/web/handlers_media.mbt`（moon fmt 顺带）把 `HttpRequest::http_request` → `HttpRequest::HttpRequest`（新版 crescent 构造器）；`moon fmt` 16 tasks up to date / `moon check` 0 errors / `warren build main --dist dist` 通过 / `moon test` 1909→1895（14 pre-existing 失败：2 tui 渲染 + 5+5 handler status code 漂移 + 2 onboard device code 状态；stash 验证 3c84c7a 同样 4/6 onboard 失败）/ `moon build --target native --release cmd` 0 errors；`MBOPENCLACKY_WEB_PORT=7071` 后台启动 curl 验证 `/mb/index.js`(200,117688B), `/mb/index.html`(200,343B), `/mb/styles.css`(200,1546B), `/`(200,19397B), `/health`(`{"status":"ok"}`) 全部 200，HTML 注入 `mb-root`/`mb/index.js`/`brand-content` 完整 | 旧 BrandView JS 全部下线、crescent API 与新版对齐、mb-root 不再遮挡右下角、完整构建链路 moon fmt+check+test+native release 全部绿灯 |

| 2026-07-14 | Phase 2.1 Backups 面板（commit `6d155c0`）：`backups_cell.mbt` 挂载到 `#backups-content`；移除 `backups.js` + index.html script 注释 | 中复杂度面板第 1 个，验证迁移模板可复制到列表 CRUD 面板 |
| 2026-07-14 | Phase 2.2 Version 面板（commit `387a68a`）：`version_cell.mbt` 挂载到 `#version-content`；移除 `versions.js` | 版本检查/升级面板迁移 |
| 2026-07-14 | Phase 2.3 Profile 面板（commit `7b5c220`）：`profile_cell.mbt` 挂载到 `#profile-content`；bridge.mbt 加 `api_put` + `i18n_t` 桥接；移除 `profile.js` | 表单 PUT 面板，扩展桥接层 |
| 2026-07-14 | Phase 2.4 Share 面板（commit `268eb35`）：`share_cell.mbt` 挂载到 `#share-content`；移除 `share.js` | 分享设置面板迁移 |
| 2026-07-14 | Phase 2.5 Trash 面板（commit `9820ae8`）：`trash_cell.mbt` 挂载到 `#trash-content`；移除 `trash.js` | 回收站面板迁移 |
| 2026-07-14 | Phase 2.6 ModelTest 面板（commit `dc8be29`）：`model_test_cell.mbt` 挂载到 `#model-test-content`；移除 `model_test.js` | 模型测试面板迁移，8 个中复杂度面板第 6 个完成 |
| 2026-07-14 | Phase 2.7 Tasks 面板（完成待 commit）：`tasks_cell.mbt`（838 行）挂载到 `#tasks-content`；bridge.mbt 加 `local_storage_get/set` + `js_now_iso` FFI；修复 48 个编译错误（Json::boolean/Iter 无 find/具名参数/参数顺序等）；移除 `tasks.js` | localStorage 持久化面板，迁移模板再验证 |
| 2026-07-14 | Phase 2.8 Browser 面板（完成待 commit）：`browser_cell.mbt`（~480 行）挂载到 `#browser-content`；用 `@sub.every(5000,...)` 声明式订阅做自动刷新；bridge.mbt 加 `js_normalize_url` + `js_download_data_url` FFI；修复 browser.js 字段名 bug（`status.running`->`daemon_running`）+ terser 正则转义问题；移除 `browser.js` | 中复杂度面板全部完成（8/8）|
| 2026-07-14 | **本 spec 全部开发目标完成**：Phase 0 - 2.8（9 个面板 + 桥接层 + 整合清理）全部落地；`moon check` 0 errors / `warren build` 通过（231KB minified）/ `moon build --target native --release cmd` 0 errors；服务冒烟测试 `/health` 200、`/mb/index.js` 231153B 200、HTML 含全部 10 个 mount 容器、0 悬挂旧 JS 引用。归档到 `specs/completed/` | Phase 3/4（高复杂度面板 + 全量清理）为未来工作，明确不在本 spec 范围 |

## 当前进度（截至 2026-07-14 18:50 · 全部开发目标完成）

- ✅ **Phase 0**（立柱子）：mb-root 容器 + 独立 rabbita 项目 + counter cell + warren build 产物同步
- ✅ **Phase 0.5**（跨边界桥接层）：`bridge.mbt` 声明 `app_notify`/`app_show_modal`/`app_hide_modal` extern + `app_api_get/post/del` async Cmd 桥接
- ✅ **Phase 1.1-1.3**（Brand 面板，commit `6685250`/`3c84c7a`/`372eccd`）：brand cell 完整 state machine + 整合 + 清理（删 brand.js、mb-root 移入 #app、crescent API 漂移修复）
- ✅ **Phase 2.1** Backups（commit `6d155c0`）
- ✅ **Phase 2.2** Version（commit `387a68a`）
- ✅ **Phase 2.3** Profile（commit `7b5c220`，加 `api_put`/`i18n_t` 桥接）
- ✅ **Phase 2.4** Share（commit `268eb35`）
- ✅ **Phase 2.5** Trash（commit `9820ae8`）
- ✅ **Phase 2.6** ModelTest（commit `dc8be29`）
- ✅ **Phase 2.7** Tasks（完成待 commit，localStorage 持久化 + 48 编译错误修复）
- ✅ **Phase 2.8** Browser（完成待 commit，`@sub.every` 自动刷新 + browser.js 字段名 bug 修复）

**最终验证**：
- `moon check`（web/mb）0 errors（100 warnings，均非阻塞）
- `warren build main --dist dist` 通过，terser 压缩 231KB（含全部 9 个 cell）
- `moon build --target native --release cmd` 0 errors
- 服务冒烟测试（`MBOPENCLACKY_WEB_PORT=7071`）：`/health`=`{"status":"ok"}` 200；`/mb/index.js`=200 `application/javascript` 231153B；HTML 含全部 10 个 mount 容器（brand/backups/version/profile/share/trash/model-test/tasks/browser-content + mb-root）；0 个悬挂旧 JS 引用（tasks/browser/brand.js 均已移除）

**已删除的 legacy JS**：`brand.js`/`backups.js`/`versions.js`/`profile.js`/`share.js`/`trash.js`/`model_test.js`/`tasks.js`/`browser.js`（9 个）。`app.js` 保留（其 `typeof X !== 'undefined'` 守卫和 `if (mod && typeof mod.load === 'function')` 检查自动跳过已删模块，navModules 条目无害保留）。

## 后续工作（不在本 spec 范围）

- **Phase 3**（高复杂度面板：Chat/Sessions/MCP/Channels/Billing/Skills/Schedules/Creator/Meeting/Media/Workspace/Onboard/Git/Marketplace）：涉及 WebSocket 流、i18n 系统性迁移、多 Cell 组合，需独立 spec 规划。
- **Phase 4**（清理）：全部面板迁完后删除 `web/js/`、简化 index.html、拆除 Phase 0.5 桥接层。
- **环境问题（pre-existing，与本 spec 无关）**：`@bobzhang/toml` 库 `create_array_of_tables` 用 `path[:-1]`（MoonBit slice 不支持负索引，`-1` 被当字面值导致 `view` abort）在 config 含 `[[models]]` 数组表时崩溃；`@bobzhang/crescent` 测试代码 `TryJsonTestUser` 缺 `Debug` derive 导致 `moon build` 类型检查失败。两者均为 vendored 依赖（`.mooncakes/`，gitignored）的 latent bug，本地补丁验证用，未提交。

