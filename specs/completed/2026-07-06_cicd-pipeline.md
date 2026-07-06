# CI/CD 流水线建设 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-06  
> **状态**: 实施中  
> **负责人**: AI + 开发者

## 核心目标

为 MBOpenClacky 项目建立自动化 CI/CD 流水线，使每次 PR 和主分支合并都能自动完成类型检查、构建、测试验证，为 Harness 方法论的多层 Safety Net 提供第 4 层（CI/CD 自动化回归）能力，同时建设 Docker 镜像自动化构建与发布流程。

## 关键能力

- PR 自动触发 `moon check` + `moon build` + `moon test` 并报告结果
- Docker 多阶段构建自动化（main 分支合并触发）
- 构建产物缓存优化（mooncakes 依赖缓存、moon 工具链缓存）
- CI 结果可观测（PR 状态徽标、构建日志）

## 明确不做

- **不做 CD 自动部署到生产环境**（原因：项目当前无灰度/金丝雀基础设施，自动部署风险过高）
- **不做 Windows/macOS 矩阵构建**（原因：当前 `preferred_target = native` 且 C FFI 依赖 libssl，先确保 Linux CI 稳定）
- **不做代码覆盖率报告**（原因：moon test 暂无内置覆盖率工具，后续可补充）
- **不做安全扫描/依赖检查**（原因：放在后续增量 spec 中，本轮聚焦基础流水线）

## 关键决策（含为什么）

1. **使用 GitHub Actions**：项目托管在 GitHub（`https://github.com/hnlyxiaobing/MBOpenClacky`），GitHub Actions 是最自然的选择，无需额外集成
2. **Ubuntu 22.04 runner**：与 Dockerfile 的 builder stage 保持一致，确保 CI 环境与生产构建环境一致
3. **缓存 moon 工具链 + mooncakes 依赖**：moon 工具链安装耗时 30s+，依赖下载耗时 10s+，缓存可显著加速 CI
4. **显式指定 `moon build --target native --release cmd`**：避免 moon #1488 bug（plain build 会尝试链接 lib/brand 为独立可执行文件）
5. **Docker 构建仅在 main 分支触发**：避免每次 PR 都构建镜像（耗时长、镜像仓库污染），PR 阶段仅做代码验证

## 验收维度

- [ ] PR 创建/更新时自动触发 CI 流水线
- [ ] CI 包含 `moon check`（类型检查）
- [ ] CI 包含 `moon build --target native --release cmd`（构建）
- [ ] CI 包含 `moon test`（测试）
- [ ] Docker 镜像在 main 分支合并后自动构建
- [ ] CI 配置有合理的缓存策略
- [ ] CI 配置有合理的超时设置

## 待后续推进时补充

- Windows/macOS 矩阵构建（依赖 libssl 跨平台适配）
- 安全扫描（CodeQL / Trivy）
- 代码质量门禁（lint 规则、覆盖率阈值）
- CD 自动部署（待灰度基础设施就绪后）

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-06 | 初始版本 | 基于 harness-methodology-application-plan.md 阶段 1 规划 |
