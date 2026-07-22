# 前端资产移植（87 文件整体拷贝） · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §五 P0  
> **关联历史 spec**: `specs/completed/2026-07-21_web-parity-01-assets-static-server.md`（骨架阶段）  
> **来源差距**: 当前 web/ 仅 4 功能文件骨架，原前端 87 文件 ~39700 行未移植  
> **依赖**: `web-replication-01`（二进制静态服务）  
> **优先级**: P0

## 问题描述 [必填]

当前 `web/` 目录是手写骨架（55 行 HTML + 121 行 JS + 269 行 CSS），原项目前端 87 文件（含 15 feature 模块、vendor 库、i18n.js 2123 行、WS 客户端）未移植。浏览器渲染结果与原项目差距极大，前端完成度仅 3-5%。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前 web/ 仅 4 功能文件 | `ls web/` | index.html(55L) / app.js(121L) / app.css(269L) / favicon.svg | 确认骨架 |
| 原项目 87 文件 | `find D:/MoonBit/openclacky/lib/clacky/web -type f` | 87 文件 | 确认完整源 |
| 模板占位符 | `grep "{{BRAND_NAME}}\|{{EXT_SCRIPTS}}" web/index.html` | L6,L13,L20,L21,L40 含 BRAND_NAME；L53 含 EXT_SCRIPTS | 替换点明确 |
| 原 index.html 有 55 个 script 标签 | `grep -c "<script" 原index.html` | 55 | 加载顺序需保持 |
| web/dist/ 为空目录 | `ls web/dist/` | 0 items | 无需清理 |

### 详细分析

原前端为纯静态 vanilla JS/CSS/HTML（MIT 许可），无构建步骤。拷贝后由 StaticServer 直接服务。模板替换（{{BRAND_NAME}}、{{EXT_SCRIPTS}}）已由 lib/web/template_processor.mbt 的 process_template() 实现，TemplateConfig::default() 在无 brand 配置时回退为 "MBOpenClacky"、在无 ext_ui 资产时注入空串——无需额外代码改动。

## 决策 [必填 - 含为什么]

1. **整集拷贝 87 文件，不挑拣**：零修改纪律要求保持上游完整性；ext_ui 面板文件在盘上无害（由 `{{EXT_SCRIPTS}}` 控制是否注入）。
2. **覆盖现有骨架文件**：`web/index.html`、`web/app.js`、`web/app.css` 被原文件覆盖。
3. **`{{BRAND_NAME}}` 回退 "MBOpenClacky"**：`resolve_brand_name()` 已从配置读取，无配置时回退为 "MBOpenClacky"。brand 配置系统完善属后续 spec 范围。
4. **`{{EXT_SCRIPTS}}` 注入空串**：`build_official_panel_script_tags()` 检查 ext_ui 资产文件，当前不存在则注入空串。扩展面板注入属 spec-11。
5. **保留 `web/PATCHES.md` 和 `web/UPSTREAM_SYNC.md`**：更新内容记录本次拷贝。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/**`（87 文件） | 拷贝覆盖 | 源：`D:/MoonBit/openclacky/lib/clacky/web/` |
| `web/PATCHES.md` | 修改 | 登记 P0-002 状态为已完成 |
| `web/UPSTREAM_SYNC.md` | 修改 | 更新同步记录（日期、文件数） |

### 不涉及文件

- `lib/web/` 后端代码（spec-01 已处理静态服务）
- 品牌资产设计（P4 范围）

## 实施计划 [必填]

### 任务包 1：资产拷贝（0.5 天）
cp -r /mnt/d/MoonBit/openclacky/lib/clacky/web/* web/  # 从原项目整集拷贝 87 文件
# 保留 PATCHES.md 和 UPSTREAM_SYNC.md（不会被覆盖，原项目无同名文件）
- 删除不再需要的旧骨架残留（若有）

### 任务包 2：模板替换验证（0.25 天）
- 启动 server，`curl http://localhost:7071/` 验证：
  - 无 `{{BRAND_NAME}}` 残留
  - 无 `{{EXT_SCRIPTS}}` 残留
  - 含 `<script src="app.js">` 等 55 个标签
- `curl http://localhost:7071/vendor/marked/marked.min.js` 验证 200 + 正确 MIME

### 任务包 3：首屏视觉验证（0.25 天）
- 浏览器打开 7071，与原项目 7070 同视口对比
- console 无 404（除 `/api/ext/*` 和 `/ext_ui/*` 预期 404 外）

## 验收标准 [必填]

- [ ] `web/` 目录含 87+ 文件，与原项目一一对应
- [ ] 首页渲染与原项目视觉一致（顶栏/侧栏/主题/i18n）
- [ ] console 无非预期 404
- [ ] 字体正常加载（KaTeX 公式渲染无方框）
- [ ] 主题切换（dark/light）正常
- [ ] `moon check` 0 errors

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| script 加载顺序依赖 | 中 | 保持原 index.html 顺序不变 |
| 品牌资产法律风险 | 低 | PATCHES.md 登记待替换，P4 前完成 |
| 原前端调用未实现 API 报错 | 低 | 前端有容错（空态降级），不阻塞首屏 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-01`（二进制静态服务）
- **后置依赖**：所有后续 spec（03-12）均依赖本 spec 完成

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P0 资产移植 |
| 2026-07-22 | 对抗性审核修正：行数 56→55/122→121/270→269/2033→2123/~38000→~39700；占位符位置补 L20；script 标签数 56→55；PowerShell→WSL cp 命令；决策 #3/#4 措辞修正（非"硬编码"，现有 process_template() 已处理） | 事实核查纠正 |
