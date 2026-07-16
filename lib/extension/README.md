# Extension Framework

OpenClacky 扩展生命周期管理。扩展包含 `manifest.toml`、源码目录与可选的贡献声明（Skill / Panel / Agent / Api / Hook / Patch），由本包统一加载、校验、打包、上架，并注入运行时。

## 结构（`lib/extension/`）

| 文件 | 职责 |
|------|------|
| `types.mbt` | 核心类型与数据结构（`Extension`、`ExtensionManifest`、`ExtensionContribution` 等） |
| `mod.mbt` | `extension_id`、`source_dir` 等辅助函数 |
| `loader.mbt` | 三级源扫描（内置 / 用户目录 / 市场）加载扩展并解析 manifest |
| `verifier.mbt` | manifest 校验（字段、版本、依赖、贡献合法性） |
| `packager.mbt` | 扩展打包与签名，生成可分发产物 |
| `scaffold.mbt` | 脚手架生成，快速创建新扩展骨架 |
| `marketplace.mbt` | 扩展市场：列表、安装 / 卸载 / 发布、enable / disable |
| `patch_loader.mbt` | 将 `ExtensionContribution::Patch` 转换为 `@agent.PatchRule`（声明式 tool/block_pattern/allow_pattern + 命令式 shell 脚本，fail-open） |

## 运行时集成

- **API 路由分发**：贡献类型 `Api` 的扩展路由由 `lib/web/ext_dispatcher.mbt` / `ext_loader.mbt` 注册到 `/api/ext/<id>/`，含超时包裹与错误信封、热重载。
- **Patch 拦截**：`patch_loader.mbt` 将扩展声明的补丁规则挂入 Agent 的 `PatchChain`，在每次工具调用前后评估（`Allow` / `Block`）。
- **CLI 命令**：`moon run cmd -- ext <subcommand>` 提供扩展的安装 / 卸载 / 发布 / 列表等子命令。

## 完成状态

MVP 已完整实现：Loader / Verifier / Packager / Scaffold / Marketplace / PatchLoader 及 API 路由分发、热重载、CLI 命令均已就位。剩余方向为高级沙箱隔离。
