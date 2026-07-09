# Extension 框架 MVP · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P1-1）  
> **关联历史**: `specs/completed/2026-07-07_extension-runtime-activation.md`（已激活运行时调度）  
> **负责人**: Agent-C

## 核心目标

在已激活的扩展运行时（`lib/web/ext_loader.mbt`、`ext_dispatcher.mbt`、`cmd/*_loader.mbt`）之上，补齐原项目 `lib/clacky/extension/` 的完整能力：Loader、Verifier、Packager、Scaffold、Publish、Marketplace 后端，以及 `ext.yml` 三层源发现（builtin/installed/local），使扩展可被创建、校验、打包、发布、安装、启用/禁用。

## 关键能力

- **Loader**：`ext.yml` 三层源扫描（内置 `assets/extensions`、已安装 `~/.clacky/extensions`、本地项目），合并优先级，产出扩展清单。
- **Verifier**：校验 `ext.yml` 结构、贡献类型合法性、依赖与版本约束、资源完整性。
- **Packager**：将扩展目录打包为可分发的 zip（含签名/校验和）。
- **Scaffold**：从模板生成新扩展骨架（manifest + 各贡献类型文件）。
- **Publish/Marketplace**：发布到扩展市场、列表、安装、启用/禁用、卸载的 REST API 与存储。
- **贡献类型承载**：panel / skill / agent / api / hook / patch（对齐已完成运行时已注册的 7 种）。

## 明确不做

- 不做远程市场服务端（原因：MBOpenClacky 自托管，市场先做本地/文件存储 + 可选远端拉取）。
- 不做扩展热加载的沙箱隔离（原因：MoonBit 静态编译，扩展通过 API/Hook/Patch 接入，非动态代码执行；沙箱超出 MVP）。
- 不迁移默认扩展内容（原因：P1-2 独立 spec 处理）。
- 不做前端市场 UI（原因：P1-4 处理）。

## 关键决策（含为什么）

1. **扩展为声明式（manifest + 静态资源）而非动态代码**：MoonBit AOT 编译，无法像 Ruby 动态加载 `.rb`；扩展通过 API handler 注册、Hook 事件订阅、Patch 配置生效，这已是已完成运行时的模型，MVP 沿用。
2. **三层源合并**：对齐原项目 `ext.yml` 发现机制，builtin 不可卸载、installed 可管理、local 优先调试。
3. **Packager 输出 zip + SHA256**：简单可移植，先不做复杂签名体系。
4. **Marketplace 存储**：扩展元数据存 `~/.clacky/extensions/registry.json`，发布即写入；远端拉取作为可选增强。
5. **Verifier 必须在 install/publish 前强制运行**：防止坏扩展污染运行时。

## 验收维度

- [ ] `ext.yml` 三层源扫描可产出合并清单
- [ ] Verifier 能拒绝非法 manifest（缺字段/非法贡献类型/资源缺失）
- [ ] Packager 可产出 zip + 校验和，且可被 Loader 重新加载
- [ ] Scaffold 可生成合规扩展骨架
- [ ] Marketplace API：list / install / enable / disable / uninstall / publish 可用且配 wbtest
- [ ] 与已完成运行时调度器联调：一个最小扩展可被加载并触发 panel/hook
- [ ] `moon check` 0 errors，`moon test` 相关包通过

## 待后续推进时补充

- 扩展版本升级与迁移策略
- 远端市场协议（若需要对接原 Clacky 云市场）
- 扩展权限粒度（哪些 hook 可订阅、哪些 API 可调用）

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P1-1，最大单一缺口 |
