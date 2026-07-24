# GET /api/media/types 语义对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中——待人工确认（进入开发前必须完成「人工确认是否有意重定义」硬性 gate，见风险评估）  
> **关联总览**: `docs/web-ui-gaps.md`、`docs/web-ui-issues.md` I-007  
> **关联历史 spec**: `specs/completed/2026-07-21_web-parity-04-secondary-panels.md`（当前实现的来源）、`specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`（同类 API 语义对齐先例）  
> **来源差距**: I-007 —— GET /api/media/types 语义被重定义（P1，需人工确认）  
> **依赖**: 前置 fix-06（web-ui-fix-06，并行撰写中，撰写本 spec 时其文件尚未存在于 specs/draft/）+ 人工确认；后置 无  
> **优先级**: P1  
> **灰度 key**: 无

## 问题描述 [必填]

`GET /api/media/types` 的响应语义与原项目（Ruby openclacky）完全不同：

- **期望（orig）**：按模态返回配置状态对象——`{image: {configured, model, base_url, source}, video: {...}, audio: {...}, stt: {...}, video_understanding: {...}}`，供调用方（orig 的 media-gen skill）判断"该模态是否已配置、用哪个模型、走哪个 base_url"。
- **实际（current）**：返回硬编码的文件扩展名列表——`{image: ["png","jpg","webp"], video: ["mp4","webm"], audio: ["mp3","wav","ogg"]}`，且不包含 `stt`、`video_understanding` 两个模态，完全不含 `configured/model/base_url/source` 任何配置信息。

`docs/web-ui-issues.md` I-007 判定"疑似遗漏而非有意"，**需人工确认**是否存在有意重定义（例如有未发现的扩展名列表消费者）。在确认前本 spec 不进入开发。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前实现返回扩展名列表 | 读 `lib/web/handlers_bridge.mbt:824-837`（grep `handle_media_types_bridge` 定位） | `handle_media_types_bridge` 返回硬编码 `{image:["png","jpg","webp"], video:["mp4","webm"], audio:["mp3","wav","ogg"]}` | 确认：语义为扩展名列表，无 configured/model/base_url/source，无 stt/video_understanding |
| 实现位置（gap 文档未指明文件） | `grep -rn "handle_media_types_bridge\|media/types" lib/` | 命中 `lib/web/handlers_bridge.mbt:826`，**不在** `lib/web/handlers_media.mbt`（该文件只含 image/video/speech/transcription/video-understand 处理器） | **与任务指派描述有偏差**：实现位于 web-parity-04 引入的 bridge 文件，而非 handlers_media.mbt |
| 路由注册 | `grep -n "media" lib/web/server.mbt` | `lib/web/server.mbt:738` `md.get("/types", event => handle_media_types_bridge(server_ref, event))`，位于 `api.group("/media", ...)`（server.mbt:724-739） | 确认：GET /api/media/types 已注册，指向 bridge handler |
| orig 语义为模态配置对象 | 读 `D:/MoonBit/openclacky/lib/clacky/server/http_server.rb:1709-1730` | `api_media_types` 遍历 `MEDIA_KINDS`，每项输出 `{configured:true, model, base_url, source}` 或 `{configured:false, source:"off"}` | 确认 orig 语义，与 I-007 描述一致 |
| orig 模态集合含 stt、video_understanding | `grep -n "MEDIA_KINDS\s*=" D:/MoonBit/openclacky/` | `providers.rb:509` `MEDIA_KINDS = %w[image video audio stt video_understanding]` | 确认：orig 五模态，current 只有三模态 |
| orig `configured` 语义（auto 是否算 configured） | 读 `D:/MoonBit/openclacky/lib/clacky/agent_config.rb:744-807`（`media_state`） | `"configured" => !entry.nil?`：派生（auto）条目也算 configured=true、`source="auto"`；disabled 时 configured=false、source="off" | 确认：orig 的 configured 含 auto 派生，不只是显式 custom 配置 |
| orig 消费者 | `grep -rn "media/types" D:/MoonBit/openclacky/` | 消费者为 `default_skills/media-gen/SKILL.md`（读 `image.model`、`video.configured`、`audio.configured` 决定是否暴露生成能力）+ RSpec 测试；无 orig 前端 JS 消费 | 确认：orig 语义的主要消费者是 agent skill，不是前端 |
| fork 前端是否消费 /api/media/types | `grep -rn "media/types" web/` | 0 命中 | 确认：当前前端无任何消费者 |
| fork 的 media-gen skill 是否消费 | 读 `assets/skills/media-gen/SKILL.md` | 该 SKILL.md 已重写，未引用 /api/media/types，也不含 configured/model 检查逻辑 | 确认：fork 内**当前无已知消费者**（这既是"重定义可能无害"的论据，也是"修复低风险"的论据） |
| 测试场景是否锁定扩展名形状 | 读 `test/scenarios/web/web_parity_04_secondary_panels.json` | 步骤含 GET /api/media/types（:23），断言仅 `status_not_eq 500/502/503` | 确认：场景不锁定响应体形状，改语义不破坏该场景 |
| 扩展名语义是否有意引入 | 读 `specs/completed/2026-07-21_web-parity-04-secondary-panels.md:33` | 计划栏写的是"补缺 + 形状核对"，spec 内无任何"改为扩展名列表"的决策记录 | 确认：扩展名形状是实现漂移，**无文档化决策**，支持 I-007"疑似遗漏"的判断 |
| 可复用的模态状态计算逻辑 | 读 `lib/web/handlers_configtest.mbt:671-704`（`handle_config_media_all`） | 已按相同五模态 `["image","video","audio","stt","video_understanding"]` 计算 `{source, model, base_url, configured}`，用 `config.find_model_by_type` / `config.derive_media_model` | 确认存在可复用逻辑；**但语义与 Ruby 有偏差**：派生（auto）时它输出 `configured:false`，Ruby 为 `configured:true`——直接复用会引入新的契约偏差，实现时需修正或独立实现 |
| crescent PATCH/PUT/DELETE 支持 | `grep -n "patch\(\|put\(\|delete\(" lib/web/server.mbt` | 大量命中（如 :180 delete、:198-212 patch、:275 put 等） | 确认：crescent 支持，本 spec 不声称"不支持" |
| fix-06 前置依赖是否已存在 | `ls specs/draft/ specs/active/` | draft/ 与 active/ 均为空；completed/ 只有 fix-01~05 | fix-06 为并行撰写中的 spec，撰写时文件尚不存在，依赖按指派记录 |

### 详细分析

| 维度 | orig（Ruby） | current（MoonBit） | 差距 |
|------|-------------|-------------------|------|
| 响应顶层 | 五模态键：image/video/audio/stt/video_understanding | 三模态键：image/video/audio | 缺 stt、video_understanding |
| 每项形状 | `{configured, model, base_url, source}`（configured=false 时为 `{configured:false, source:"off"}`） | `["png","jpg",...]` 扩展名数组 | 完全不同 |
| configured 语义 | 显式 custom 或 auto 派生成功均为 true | 不适用（无此字段） | - |
| 数据来源 | `@agent_config.media_state(kind)` | 硬编码字面量 | 与配置完全脱钩——配置了图像模型也返回同样的扩展名列表 |
| 消费者 | orig media-gen skill（决定能力暴露） | 无已知消费者（前端 0 命中、fork skill 不引用、场景仅查非 5xx） | - |

当前实现在功能上是"死数据"：不读配置、不含能力信息，orig 语义下该端点的全部用途（skill 判断模态可用性、回显 model/base_url）均无法实现。

## 决策 [必填 - 含为什么]

1. **对齐 orig 语义：按五模态返回配置状态对象**。理由：(a) web-parity-04 spec 的原始计划就是"补缺 + 形状核对"，扩展名形状无任何文档化决策，判定为实现漂移；(b) fork 内 grep 不到任何扩展名列表的消费者，替换语义无已确认的破坏面；(c) orig 语义有明确消费者模型（media-gen skill），且是 G-001 前端/skill 同步的正确基线。
2. **`configured` 语义照抄 Ruby `media_state`**：显式配置（custom）或 auto 派生成功均 `configured:true`，分别标 `source:"custom"`/`source:"auto"`；两者皆无时 `{configured:false, source:"off"}`。理由：orig skill 依赖 `configured` 判断能力可用性，auto 派生成功就是"可用"，若照抄 `handle_config_media_all` 的 `configured:false`（auto 时）会让 skill 误判能力缺失。注意 `handle_config_media_all` 的该项偏差属于 I-017（/api/config/media）范畴，**本 spec 不修改它**，只在本端点内实现正确语义。
3. **扩展名列表不单设新端点，直接替换**：grep 证实 fork 前端、fork skill、测试场景均无扩展名形状消费者，"另设端点或并留"没有受益方，徒增 API 面。若人工确认环节发现确实存在消费者，回退方案为并留：扩展名列表迁至 `GET /api/media/extensions`（crescent 加路由即可，已验证 group 内加 `md.get` 无约束）。
4. **输出字段严格对齐 orig 四键**：configured/model/base_url/source，未配置时 model/base_url 键省略（orig 的 else 分支只输出 configured+source 两键），不额外加 provider/available 等 /api/config/media 专属字段。理由：I-007 的对齐基线是 orig `api_media_types`，不是 `api_get_media_config`，混入后者字段属于范围蔓延。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及（纯 HTTP handler 同步逻辑，无动态加载 trait）
- crescent 路由：已验证 PATCH/PUT/DELETE 均有既有用法（server.mbt:180/198/275 等）；本 spec 仅改 GET 响应体
- FFI：不涉及（media_state 等价逻辑复用 @config 的 find_model_by_type / derive_media_model，纯 MoonBit）
- mooncakes 依赖：不涉及
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_bridge.mbt` | 修改 | `handle_media_types_bridge`（:826-837）重写：遍历五模态，用 `server_ref.val.config.find_model_by_type` / `derive_media_model` 计算 `{configured, model, base_url, source}`，对齐 orig `api_media_types` 输出形状 |
| `lib/web/handlers_bridge_wbtest.mbt`（或就近的 `*_wbtest.mbt`） | 修改/新增 | 白盒测试：无媒体模型时五模态均 `{configured:false, source:"off"}`；配置 image 模型后 image 项 `{configured:true, model, base_url, source:"custom"}`；auto 派生场景 `configured:true, source:"auto"` |
| `lib/web/server.mbt` | 不改 | 路由 `md.get("/types", ...)`（:738）已存在，无需变动（仅列出以明确边界） |

### 不涉及文件

- `lib/web/handlers_media.mbt`：只含 image/video/speech/transcription/video-understand 处理器，与 /types 无关（任务指派描述中的定位偏差，实际无需触碰）
- `lib/web/handlers_configtest.mbt` 的 `handle_config_media_all`：其 auto 时 `configured:false` 的偏差属 I-017（/api/config/media 缺 per-模态详情），相邻问题，本 spec 明确不碰
- 前端 `web/`：无消费者，零修改
- `assets/skills/media-gen/SKILL.md`：fork skill 是否回引 /api/media/types 属 skill 内容对齐议题，不在本 spec
- `test/scenarios/web/web_parity_04_secondary_panels.json`：断言仅查非 5xx，改语义后仍通过，无需修改
- I-008（/api/dirs）、I-009（billing/summary）、I-010（trash）等相邻 P1 问题：均不在本 spec 范围
- POST /api/media/image 等 501 端点：媒体生成本身的实现与本 issue 无关

## 实施计划 [必填]

### 任务包 0：人工确认 gate（硬性前置，估时不计入开发）
- 向项目维护者确认：`GET /api/media/types` 从"模态配置对象"改为"扩展名列表"是否为有意重定义
- 若确认无意（预期结果，依据：web-parity-04 spec 无此决策记录 + 无消费者）→ 按本 spec 进入开发
- 若确认有意 → 记录消费者身份，本 spec 降级为"并留方案"（新增 /api/media/extensions 迁移扩展名语义，/types 恢复 orig 语义），修订 spec 后再进入开发
- **确认结论必须写入变更记录后方可移入 specs/active/**

### 任务包 1：handler 重写（0.5 天）
- 重写 `handle_media_types_bridge`：遍历 `["image","video","audio","stt","video_understanding"]`
- 每模态：`find_model_by_type(kind)` 命中 → `{configured:true, model, base_url, source:"custom"}`；否则 `derive_media_model(kind)` 命中 → `{configured:true, model, base_url, source:"auto"}`；否则 `{configured:false, source:"off"}`
- 与 orig `api_media_types` 输出逐键比对（含未配置分支只输出两键）

### 任务包 2：测试与验证（0.5 天）
- 白盒测试覆盖三分支（off / custom / auto）
- 起服务实测：`GET /api/media/types` 在无配置与有图像模型配置两种状态下形状与 orig RSpec 用例（`http_server_media_spec.rb:27-67`）等价
- `moon check` + `moon test lib/web`

## 验收标准 [必填]

- [ ] 人工确认 gate 完成，结论已写入本 spec 变更记录（否则不得进入开发，更不得验收）
- [ ] 无媒体模型配置时，`GET /api/media/types` 返回五模态键（image/video/audio/stt/video_understanding），每项 `{configured:false, source:"off"}`（对齐 orig spec 用例 1）
- [ ] 配置 image 类型模型后，image 项为 `{configured:true, model, base_url, source:"custom"}`，其余模态不变（对齐 orig spec 用例 2）
- [ ] auto 派生成功场景输出 `configured:true, source:"auto"`（白盒测试覆盖）
- [ ] 响应中不再出现扩展名数组；响应不含 api_key 等敏感字段
- [ ] `test/scenarios/web/web_parity_04_secondary_panels.json` 场景仍通过（非 5xx）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| **扩展名语义实为有意重定义，直接替换破坏未知消费者** | 高 | **硬性 gate：人工确认是进入开发的前置条件**，未确认前本 spec 停留在 draft、不进入 active；确认有意则走并留方案（新增 /api/media/extensions） |
| 与 `handle_config_media_all` 的 configured 语义不一致（auto 时本端点 true、config 端点 false）造成表面矛盾 | 低 | 两者对齐的基线不同：/api/media/types 对齐 orig `api_media_types`（auto=true），/api/config/media 的偏差属 I-017 另行修复；spec 中明确记录不在本范围 |
| derive_media_model 对某些 kind 派生行为与 Ruby `derive_media_model` 不完全等价（如模型清单差异） | 中 | 实现时以 MoonBit `derive_media_model` 实际返回为准（fork 配置体系的 ground truth），只保证响应形状与 configured 布尔语义对齐 orig，不保证具体模型名与 Ruby provider 清单一致 |
| 修复后 fork media-gen skill 仍不消费该端点，修复"无即时用户" | 低 | 修复目标是契约对齐（G-001 同步基线），非即时功能；测试场景已含该端点非 5xx 探针 |
| fix-06 内容与本 spec 存在未知交集（如 fix-06 也触碰 handlers_bridge.mbt） | 低 | 前置依赖已声明 fix-06；fix-06 完成/定稿后核对其涉及文件清单，若有交集在本 spec 进入 active 前解决合并顺序 |

## 依赖关系 [必填]

- **前置依赖**：fix-06（web-ui-fix-06，并行撰写中——撰写本 spec 时 specs/draft/、specs/active/ 下尚无其文件）+ **人工确认**（是否有意重定义，硬性 gate）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本（讨论中——待人工确认） | I-007 P1：GET /api/media/types 语义对齐 orig；含 13 项验证记录，定位偏差（实现实际位于 handlers_bridge.mbt 而非 handlers_media.mbt）、configured 语义加深（orig auto 也算 configured）、消费者面确认（fork 内 0 消费者） |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_media_types_bridge@handlers_bridge.mbt:824-837 确认硬编码 {image:[png,jpg,webp],video:[mp4,webm],audio:[mp3,wav,ogg]} 无 stt/video_understanding/configured/model/base_url/source；路由@server.mbt:738 确认；fork 前端 grep "media/types" web/ 为 0 命中确认无消费者；实现位置偏差（在 handlers_bridge.mbt 非 handlers_media.mbt）正确识别。orig Ruby 逐行验证：api_media_types@http_server.rb:1713-1730 确认遍历 MEDIA_KINDS@providers.rb:509（五模态）输出 {configured,model,base_url,source}；configured 语义 auto 也为 true（与 handle_config_media_all 的 configured:false 偏差正确归为 I-017）。人工确认 gate 已标注。交叉引用 secondary-panels.md + api-response-wrappers.md 均存在。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
