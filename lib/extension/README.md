# Extension Framework

`lib/extension/` 管理扩展生命周期：加载、校验、打包、脚手架、市场、Patch/API 贡献和运行时分发。

## 结构

| 文件 | 职责 |
|---|---|
| `types.mbt` | Extension、Manifest、Contribution 等核心类型 |
| `loader.mbt` | 扫描内置/用户/市场扩展并解析 `manifest.toml` |
| `verifier.mbt` | manifest、版本、依赖和贡献校验 |
| `packager.mbt` | 打包、签名和分发产物 |
| `scaffold.mbt` | 新扩展骨架 |
| `marketplace.mbt` | 列表、安装、卸载、启用、禁用、发布 |
| `patch_loader.mbt` | 将 Patch contribution 转成 `@agent.PatchRule` |

## 运行时集成

- `Api` contribution 注册到 `/api/ext/<id>/`，由 `lib/web/ext_dispatcher.mbt` / `ext_loader.mbt` 分发。
- `Patch` contribution 进入 Agent 的 `PatchChain`，按 Allow/Block 评估工具调用。
- `Skill` contribution 在扩展启用时进入 Skill registry；关闭扩展不会向用户广告其 Skill。
- CLI：`cmd ext <list|install|uninstall|enable|disable|info|search|create|verify|pack|publish>`。

## 边界

当前可用的是生命周期和声明式贡献面。以下事项在 [known-gaps](../../docs/known-gaps.md) 登记：

- 依赖自动解析只警告，不自动补齐；
- 远程扩展下载未实现，需本地安装；
- 无 command 的 API 路由返回文档化的回退响应；
- 运行期热加载扩展不能实现 MoonBit trait，命令式行为走 shell command。

扩展包示例在 `assets/extensions/`，其 Skill/Panel/Agent/Hook/Patch 贡献可在 Web、Skill registry 和 Agent 运行时按启用状态加载。
