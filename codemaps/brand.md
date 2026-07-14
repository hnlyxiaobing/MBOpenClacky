# brand - 白标定制 · 许可证管理 · 加密 · 设备绑定

> 路径: `lib/brand/` · 12 文件（src=8, test=4）· 品牌定制、许可证、设备绑定与身份持久化

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `BrandConfig::load(config_dir)` | `config.mbt` | 从配置目录加载品牌配置 |
| `BrandConfig::default_config()` | `config.mbt` | 默认（未品牌化）配置 |
| `BrandConfig::is_branded()` | `config.mbt` | 判断是否已品牌化 |
| `LicenseValidator::new(config)` | `license.mbt` | 创建许可证验证器 |
| `LicenseValidator::validate(key)` | `license.mbt` | 验证许可证密钥格式 |
| `LicenseValidator::activate(key)` | `license.mbt` | 激活许可证 |
| `LicenseValidator::heartbeat()` | `license.mbt` | 心跳上报（保持激活状态） |
| `generate_device_id()` | `device.mbt` | 生成设备唯一标识 |
| `DeviceAuthStore::new()` | `device_auth.mbt` | 创建设备授权会话存储 |
| `DeviceAuthStore::start_flow(...)` | `device_auth.mbt` | 启动 RFC 8628 设备授权流 |
| `DeviceAuthStore::poll(...)` | `device_auth.mbt` | 轮询设备授权结果 |
| `load_identity()` | `identity.mbt` | 从磁盘加载已绑定身份 |
| `create_identity(...)` | `identity.mbt` | 从授权结果创建 Identity |
| `encrypt_aes256gcm(...)` / `decrypt_aes256gcm(...)` | `crypto.mbt` | AES-256-GCM 加解密 |
| `derive_key(password, salt)` | `crypto.mbt` | PBKDF2 密钥派生 |
| `BrandSkillManager::new(config)` | `skill_manager.mbt` | 品牌技能管理器 |

## 关键类型

### 品牌配置
- **`BrandConfig`** - 品牌配置（brand_name, display_name, activated, license_key, device_id, distribution, expires_at...）
- **`DeviceInfo`** - 设备信息（device_id, platform, hostname）
- **`DeviceAuthSession`** - RFC 8628 授权会话（device_code, user_code, verification_uri, expires_at, approved）
- **`PollResult`** - 轮询结果：`Pending | Approved(String) | Expired | SlowDown`
- **`DeviceAuthStore`** - 线程安全的内存会话存储
- **`Identity`** - 已绑定身份（device_token, user_id, bound_at, device_info）

### 许可证
- **`LicenseValidator`** - 许可证验证器（config, status, last_heartbeat, activated_at）
- **`LicenseStatus`** - `Inactive | Active | Expired | GracePeriod`

### 加密
- **`EncryptedData`** - 加密数据（ciphertext, nonce, salt）
- 函数: `hmac_sha256`, `sha256_hex`, `secure_compare`, `generate_nonce`, `brand_http_get`

### 品牌技能
- **`BrandSkillInfo`** - 品牌技能信息（name, description, enabled）
- **`BrandSkillManager`** - 品牌技能管理器

## 核心调用链

```
cmd/main.mbt
  └─ BrandConfig::load(config_dir)
      └─ LicenseValidator::new(config)
          ├─ LicenseValidator::validate(key) -> 格式校验
          ├─ LicenseValidator::activate(key) -> 远程激活
          └─ LicenseValidator::heartbeat() -> 定期心跳

品牌化分发
  └─ BrandConfig::refresh_distribution()
      └─ BrandConfig::apply_distribution()
          └─ 替换品牌名称/技能列表/系统提示
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 配置 | `config.mbt` | BrandConfig、加载/保存/品牌判定/分发刷新 |
| 许可证 | `license.mbt` | LicenseValidator、激活/验证/心跳/宽限期 |
| 加密 | `crypto.mbt`, `crypto_native.c` | AES-256-GCM、HMAC-SHA256、PBKDF2、secure_compare |
| 设备 | `device.mbt` | DeviceInfo、generate_device_id、ensure_device_id |
| 设备授权 | `device_auth.mbt`, `device_auth_wbtest.mbt` | RFC 8628 设备授权流、会话存储与轮询 |
| 身份绑定 | `identity.mbt`, `identity_wbtest.mbt` | Identity 持久化、加载、解析 |
| 技能 | `skill_manager.mbt` | BrandSkillManager、品牌技能管理 |
| Stubs | `brand_stubs.c` | C FFI stubs（wasm 兼容） |

## 外部依赖

- `lib/skill` - 品牌技能加载
- **C FFI** - 加密原语（`crypto_native.c`）
- HTTP - 远程许可证激活/心跳（`brand_http_get`）

## 风险点

1. **密钥安全** - `license_key` 明文存储在配置文件中
2. **宽限期逻辑** - `grace_period_exceeded()` 依赖心跳时间戳，时钟回拨可能导致误判
3. **加密实现** - AES-256-GCM 通过 C FFI 实现，需确保 nonce 唯一性
4. **设备绑定** - `generate_device_id()` 基于平台信息，虚拟化环境可能不稳定
5. **分发覆盖** - `apply_distribution()` 直接修改运行时配置，可能覆盖用户自定义
