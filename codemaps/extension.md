# extension - 扩展系统 · 脚手架 · 打包 · 验证 · 市场

> 路径: `lib/extension/` · 16 mbt（8 源 + 8 测试）+ README.md + moon.pkg/.mbti · OpenClacky 扩展生命周期管理

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `load_all_extensions()` | `loader.mbt` | 加载所有来源的扩展 |
| `load_extensions_from_source(source)` | `loader.mbt` | 从指定来源加载扩展 |
| `load_single_extension(ext_dir)` | `loader.mbt` | 加载单个扩展目录 |
| `create_extension_scaffold(...)` | `scaffold.mbt` | 创建扩展骨架 |
| `package_extension(...)` | `packager.mbt` | 打包扩展为 zip |
| `unpack_extension(...)` | `packager.mbt` | 解包扩展 zip |
| `validate_extension(ext)` | `verifier.mbt` | 验证扩展完整性 |
| `validate_manifest(...)` | `verifier.mbt` | 验证 manifest.json |
| `list_marketplace_extensions()` | `marketplace.mbt` | 列出市场扩展 |
| `install_extension_from_path(path)` | `marketplace.mbt` | 从本地路径安装 |
| `publish_extension(ext_path)` | `marketplace.mbt` | 发布扩展到市场 |
| `patch_rule_from_contribution(ext, contrib)` | `patch_loader.mbt` | 将 `ExtensionContribution::Patch` 转换为 `@agent.PatchRule` |

## 关键类型

### 核心 Struct
- **`Extension`** - 扩展实体（manifest, source, enabled, directory）
- **`ExtensionManifest`** - 清单（id, name, version, description, author, contributes, min_app_version）
- **`ExtensionContribution`** - 贡献项（type, name, handler/path）
- **`ExtensionSource`** - 来源枚举（`Builtin | Local | Installed | Dev`）

### 脚手架
- **`ExtensionTemplate`** - 扩展模板（id, name, description, contributions）

### 验证
- **`ValidationResult`** - 验证结果（valid, errors, warnings）
- **`ValidationError`** - 验证错误枚举（MissingField, InvalidValue, FileNotFound, Conflict...）
- **`ExtensionContributionType`** - 贡献类型（`Panel | Skill | Agent | Api | Hook | Patch`）

### 市场
- **`RegistryEntry`** - 市场注册条目（id, name, version, description, author, download_url）

## 核心调用链

```
# 扩展加载
load_all_extensions()
  └─ load_extensions_from_source(Builtin/Local/Installed/Dev)
      └─ load_single_extension(dir)
          ├─ 读取 manifest.json -> ExtensionManifest
          ├─ validate_manifest(manifest) -> ValidationResult
          └─ 构建 Extension

# 扩展开发流程
create_extension_scaffold(template)
  └─ 生成目录结构 + manifest.json + 初始文件

package_extension(ext_dir)
  └─ zip 打包 -> .clackyext 文件

publish_extension(ext_path)
  └─ package + 上传到市场 Registry
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 类型定义 | `types.mbt` | Extension、ExtensionManifest、ExtensionContribution、ValidationError、RegistryEntry |
| 加载 | `loader.mbt`, `loader_wbtest.mbt` | 扩展加载、来源目录解析、enabled_extensions |
| 脚手架 | `scaffold.mbt` | create_extension_scaffold、default_template |
| 打包 | `packager.mbt` | package_extension、unpack_extension、list_packaged_extensions |
| 验证 | `verifier.mbt` | validate_extension、validate_manifest、validate_all_extensions |
| 市场 | `marketplace.mbt` | 市场列表、安装/卸载/发布、enable/disable |
| 补丁加载 | `patch_loader.mbt` | Patch 贡献→`@agent.PatchRule`（声明式 tool/block_pattern/allow_pattern + 命令式 shell 脚本，fail-open） |
| 辅助 | `mod.mbt` | extension_id、source_dir 辅助函数 |

## 外部依赖

- `lib/web` - ExtensionDispatcher 注册扩展路由
- `lib/skill` - 扩展技能贡献
- `lib/agent` - Patch 贡献转换为 PatchRule（`patch_loader.mbt`）
- `moonbitlang/x/fs` - 文件系统操作
- `moonbitlang/core/json` - manifest.json 解析

## 风险点

1. **路径遍历** - `install_extension_from_path` 需验证路径安全
2. **Manifest 注入** - manifest.json 中的 handler/path 需校验，防注入
3. **版本兼容** - `min_app_version` 检查可能被绕过
4. **并发安装** - 多个安装/卸载操作并发可能导致状态不一致
5. **扩展代码执行** - 扩展的 skill/agent 贡献在 Agent 上下文中执行，需沙箱隔离
