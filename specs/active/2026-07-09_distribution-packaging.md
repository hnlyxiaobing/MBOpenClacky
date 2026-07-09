# 分发打包 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P2-2）  
> **负责人**: Agent-E（部署运维）

## 核心目标

补齐原项目已有但 MBOpenClacky 缺失的分发与安装生态：Homebrew 公式、卸载脚本、完整安装脚本（浏览器/系统依赖）、Windows 安装包。当前仅有基础 `install.sh/ps1` 与 `setup_yoga.sh`。

## 关键能力

- **Homebrew 公式**：`brew install` 可装，支持版本更新。
- **完整安装脚本**：检测并安装系统依赖（libcurl-dev、libssl 等）、拉取二进制、初始化配置目录。
- **浏览器安装脚本**：对齐原项目 `install_browser.sh`，配置 Chrome/Edge 远程调试。
- **卸载脚本**：清理二进制、配置、数据（可选保留用户数据）。
- **Windows 安装包**：MSI 或脚本化安装，含依赖声明。

## 明确不做

- 不做 Snap/Flatpak（原因：需求未明确）。
- 不做自动签名公证（macOS notarization）（原因：先功能后签名）。
- 不做应用商店上架。

## 关键决策（含为什么）

1. **Homebrew tap 仓库**：公式放独立 tap，`brew tap ... && brew install mbopenclacky`。
2. **安装脚本幂等**：重复运行不破坏已有配置。
3. **卸载分级**：默认保留用户数据，`--purge` 才全删。
4. **依赖前置检测**：安装前检查 libcurl/libssl，缺失则提示安装命令。

## 验收维度

- [ ] `brew install` 可装可升级
- [ ] 安装脚本幂等且检测依赖
- [ ] 卸载脚本分级清理（默认保留数据）
- [ ] 浏览器安装脚本可用
- [ ] Windows 安装路径可用（脚本或 MSI）
- [ ] 文档与 CI 发布物对应

## 待后续推进时补充

- GitHub Release 自动化发布物（含 checksum）
- 版本号与公式同步机制
- macOS notarization（后续）

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P2-2 |
