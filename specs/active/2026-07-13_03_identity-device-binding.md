# Identity / 设备绑定系统 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G3（P0 阻塞性差距）
> **来源差距**: G3 - Identity / 设备绑定系统
> **负责人**: TBD
> **依赖**: 与 G10 存在交叉（G10 列出 `device/start` 和 `device/poll` 为缺失端点，实际已存在 mock 实现，本 spec 将其升级为真实实现）

## 核心目标

实现原项目 `Identity` 类（管理客户端平台账号绑定）的完整等效功能：RFC 8628 设备授权流、设备令牌持久化、Identity 生命周期管理。当前 `lib/web/handlers_onboard.mbt` 中 `handle_onboard_device_start` 和 `handle_onboard_device_poll` 为模拟实现（返回 `DEV-` 前缀的假 code，`DEV-APPROVED-` 前缀触发 approved），没有任何真实的设备绑定逻辑。

## 现状分析（经代码验证）

### `lib/web/handlers_onboard.mbt`（310 行）
- `handle_onboard_device_start`：返回 `DEV-` 前缀的 device_code + 8 字符 user_code，`verification_uri` 指向 `mbopenclacky.example.com/activate`（占位 URL）
- `handle_onboard_device_poll`：检查 `DEV-APPROVED-` 前缀返回 `approved`，否则返回 `pending`。无过期机制，无 `device_token` 返回。
- `onboard.json`：onboarding 状态持久化使用 **JSON 格式**（非 YAML）

### `lib/brand/device.mbt`（76 行，已存在）
- `DeviceInfo` 结构体：`device_id`、`hostname`、`username`、`platform`
- `generate_device_id()`：基于 hostname + username + platform 生成 SHA256 截断哈希
- `ensure_device_id()`：确保 BrandConfig 中有 device_id
- 注意：这是**许可证绑定**用的设备标识，与 RFC 8628 设备授权流不同，但可复用 `DeviceInfo` 作为设备指纹基础

### `lib/brand/config.mbt`（471 行）
- `BrandConfig::save` 持久化到 **`brand.toml`**（TOML 格式，非 YAML）
- 项目中无 YAML 序列化器；`ext.yml` 实际按 JSON 解析（见 `types.mbt` 注释）

### `lib/brand/skill_manager.mbt` + `lib/extension/marketplace.mbt`
- 技能/扩展发布到市场时**无任何身份验证**--不检查 device_token 或 Identity

## 关键能力

- **Identity 数据结构**：`device_token`（RFC 8628 设备授权流颁发的长期令牌）、`user_id`（绑定的用户 ID）、`bound_at`（绑定时间）、`device_info`（复用已有 `DeviceInfo`）。
- **设备授权启动**：`POST /api/onboard/device/start` 返回 `device_code` + `user_code` + `verification_uri` + `interval` + `expires_in`，对齐 RFC 8628。
- **设备授权轮询**：`GET /api/onboard/device/poll` 返回 `pending` / `success` / `expired` / `slow_down` 状态，成功后返回 `device_token`。
- **持久化**：`~/.clacky/identity.json` 存储（JSON 格式，权限 0o600），与 `onboard.json`、`skills.json` 等现有配置文件格式一致。
- **身份验证链**：发布技能/扩展到市场时验证设备令牌，防止未授权发布。
- **CLI 集成**：`clacky onboard` 命令触发设备授权流程（交互式显示 user_code 和 verification_uri）。

## 明确不做

- 不做 OAuth 2.0 服务端（原因：MBOpenClacky 自托管，授权由平台 OAuth 端点处理，本 spec 只做客户端设备授权流）。
- 不做多设备/多用户绑定（原因：原项目单设备单用户，超出范围）。
- 不做身份吊销/解绑（原因：原项目无此功能，后续按需添加）。
- 不引入 YAML 序列化器（原因：项目中无 YAML 序列化能力，`ext.yml` 实际按 JSON 解析；Identity 使用 JSON 格式保持一致性）。

## 关键决策（含为什么）

1. **持久化用 JSON 而非 YAML**：项目中 `onboard.json`、`skills.json` 均使用 JSON，`brand.toml` 使用 TOML。无 YAML 序列化器。使用 JSON 格式（`identity.json`）与现有配置文件约定一致。原项目 `identity.yml` 的 YAML 格式在 MoonBit 项目中不适用。
2. **设备授权流用轮询而非 WebSocket**：RFC 8628 标准轮询模式，简单可靠，无需长连接。
3. **设备令牌用随机生成 + SHA256 哈希**：`device_token = SHA256(random_bytes + device_code + timestamp)`，使用 `lib/brand/crypto.mbt` 中已有的 SHA256 实现。不依赖外部 "secret"（原 spec 中 `SHA256(device_code + secret)` 的 secret 来源未定义，此处修正为自包含方案）。
4. **`device_code` 有时效性**：默认 15 分钟过期（`expires_in = 900`），过期后轮询返回 `expired`。使用内存 Map 存储进行中的授权流（`device_code -> DeviceAuthSession`），服务重启后清空。
5. **模拟轮询状态切换**：当前平台 OAuth 端点未就绪，先实现本地模拟（`DEV-APPROVED-` 前缀触发 approved，保留向后兼容），架构上预留真实 OAuth 集成点（`exchange_device_code` 函数可替换为真实 OAuth 调用）。
6. **复用 `DeviceInfo` 作为设备指纹**：`lib/brand/device.mbt` 中已有的 `generate_device_id()` 可作为 Identity 的设备指纹，无需重复实现。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/brand/identity.mbt` | 新建 | `Identity` 结构体 + 加载/保存/验证逻辑 |
| `lib/brand/device_auth.mbt` | 新建 | RFC 8628 设备授权流状态机 + `DeviceAuthSession` 内存存储 |
| `lib/web/handlers_onboard.mbt` | 修改 | 升级 `handle_onboard_device_start` / `handle_onboard_device_poll` 为真实实现 |
| `lib/brand/skill_manager.mbt` | 修改 | 发布技能时验证 device_token |
| `lib/extension/marketplace.mbt` | 修改 | 发布扩展时验证 device_token |
| `cmd/` | 修改 | 增加 `clacky onboard` 子命令 |
| 对应 `*_wbtest.mbt` | 新增 | 覆盖 Identity 持久化、设备授权流、令牌验证 |

### 不涉及文件

- `lib/brand/config.mbt`（BrandConfig 保持不变，Identity 独立存储）
- `lib/brand/crypto.mbt`（SHA256 已实现，直接复用）
- `lib/brand/device.mbt`（DeviceInfo 直接复用，不修改）
- `lib/brand/license.mbt`（许可证验证独立于 Identity）

## 实施计划（任务包切分）

### 任务包 1：Identity 数据结构 + 持久化（0.5 天）
- 定义 `Identity` 结构体（`device_token`、`user_id`、`bound_at`、`device_info`）
- 实现 `load_identity()` / `save_identity()` （`~/.clacky/identity.json`，权限 0o600）
- 实现 `is_bound()` / `verify_token()` 验证方法

### 任务包 2：RFC 8628 设备授权流（1 天）
- 定义 `DeviceAuthSession`（`device_code`、`user_code`、`verification_uri`、`expires_at`、`interval`）
- 实现 `start_device_flow()`：生成 device_code + user_code，存入内存 Map
- 实现 `poll_device_flow()`：检查过期、返回 pending/approved/expired
- 实现 `exchange_device_code()`：approved 后生成 device_token 并持久化 Identity
- 保留 `DEV-APPROVED-` 模拟模式

### 任务包 3：Handler 升级（0.5 天）
- 升级 `handle_onboard_device_start`：调用 `start_device_flow()`，返回 RFC 8628 响应（含 `expires_in`、`interval`）
- 升级 `handle_onboard_device_poll`：调用 `poll_device_flow()`，approved 时返回 `device_token`

### 任务包 4：身份验证链（0.5 天）
- 在 `skill_manager.mbt` 发布技能前调用 `Identity::verify_token()`
- 在 `marketplace.mbt` 发布扩展前调用 `Identity::verify_token()`
- 未绑定时返回 403 + 错误信封

### 任务包 5：CLI 集成 + 测试（1 天）
- `clacky onboard` 子命令：交互式显示 user_code 和 verification_uri，轮询直到完成
- 白盒测试：Identity 持久化、设备授权流状态转换、令牌验证、过期处理

## 验收标准

- [ ] `POST /api/onboard/device/start` 返回符合 RFC 8628 的响应（含 `device_code`、`user_code`、`verification_uri`、`expires_in`、`interval`）
- [ ] `GET /api/onboard/device/poll?device_code=...` 正确返回 `pending` / `approved`（含 `device_token`）/ `expired`
- [ ] `device_code` 超过 15 分钟后轮询返回 `expired`
- [ ] `~/.clacky/identity.json` 正确持久化 Identity 数据（JSON 格式，权限 0o600）
- [ ] 发布技能/扩展时未绑定 Identity 返回 403
- [ ] `clacky onboard` CLI 命令可交互式完成设备授权
- [ ] `DEV-APPROVED-` 前缀的模拟模式仍可工作（向后兼容）
- [ ] `moon check` 0 errors（`lib/brand` + `lib/web` + `cmd`）
- [ ] `moon test lib/brand` 通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 内存 Map 存储授权流，服务重启后丢失进行中的授权 | 中 | 接受：用户重新发起即可；持久化到磁盘增加复杂度不值得 |
| 模拟模式可能被误用于绕过身份验证 | 高 | 模拟模式仅在非生产环境启用（通过环境变量 `CLACKY_DEV_MODE` 控制） |
| `device_token` 泄露后无法吊销 | 中 | 接受：原项目无吊销功能；后续可增加 `revoke_identity` 端点 |
| 文件权限 0o600 在 Windows 上不生效 | 低 | Windows 使用 ACL，`write_string_to_file` 默认权限已限制；非关键风险 |
| 身份验证链可能影响现有发布流程 | 中 | 验证失败时返回明确错误，引导用户执行 `clacky onboard` |

## 待后续推进时补充

- 真实平台 OAuth 端点对接（当平台 OAuth 服务就绪时）
- 设备令牌刷新机制
- 多设备场景支持
- 身份吊销/解绑端点

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G3，P0 阻塞性 |
| 2026-07-13 | 审核修正：修正"brand.yml 已使用 YAML 持久化"为 brand.toml（TOML 格式）；identity 存储格式从 YAML 改为 JSON（项目无 YAML 序列化器）；修正 device_token 生成方案（原 `SHA256(device_code + secret)` 的 secret 来源未定义）；补充已有 `lib/brand/device.mbt` 的 `DeviceInfo` 复用；补充"身份验证链"当前不存在的现状；补充改动范围、实施计划、风险评估；标注与 G10 的交叉依赖；增加模拟模式安全风险 | 对抗性审核 + 第一性原理校验 |
