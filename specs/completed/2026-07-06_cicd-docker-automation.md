# 任务包：Docker 镜像自动化构建

> **关联 spec**: `specs/active/2026-07-06_cicd-pipeline.md`  
> **创建日期**: 2026-07-06  
> **状态**: 已完成

## 目标

创建 `.github/workflows/docker.yml`，在 main 分支合并时自动构建 Docker 多阶段镜像，确保镜像可用并可拉取。

## 边界

### 要做

- 创建 `.github/workflows/docker.yml` GitHub Actions 配置文件
- 仅在 main 分支 push 时触发（PR 不触发 Docker 构建）
- 使用现有 Dockerfile 的多阶段构建
- 构建产物打 tag（commit SHA + latest）
- 构建日志可观测

### 明确不做

- 不做镜像推送到 Docker Hub / GHCR（需配置 secrets，本轮不处理）
- 不做镜像安全扫描
- 不做多架构构建（arm64 等）

## 自由度

- **模型可以**：自选 tag 策略、是否使用 buildx
- **但不能**：修改现有 Dockerfile、引入需要 secrets 的步骤

## Checkpoint 规则

- 改代码前复述 diff 计划
- 不改动 Dockerfile 或任何 .mbt 源文件

## 验收标准

- [x] `.github/workflows/docker.yml` 文件存在且语法合法 ✅
- [x] 仅在 main push 时触发 ✅（`on: push: branches: [main]`，无 pull_request）
- [x] 使用现有 Dockerfile 构建 ✅（`docker/build-push-action@v6` + `file: ./Dockerfile`）
- [x] 构建产物有合理 tag ✅（commit SHA + latest，via metadata-action）
- [x] 不改动任何现有文件 ✅

---

## 验收报告

### 改了什么

- **新建** `.github/workflows/docker.yml`（45 行）— Docker 镜像构建工作流
- 未修改任何现有文件

### 跑了什么验证

- 文件存在性检查 → ✅ 已创建
- YAML 结构审查 → ✅ 语法合法，使用了 Docker 官方 Actions（setup-buildx / metadata / build-push）
- git status lib/ cmd/ → ✅ 无源码变更

### 验收标准对照

- [x] `.github/workflows/docker.yml` 文件存在且语法合法 ✅
- [x] 仅在 main push 时触发 ✅
- [x] 使用现有 Dockerfile 构建 ✅
- [x] 构建产物有合理 tag ✅（SHA + latest）
- [x] 不改动任何现有文件 ✅

### 没覆盖的

- 镜像推送到 Docker Hub / GHCR（需配置 secrets）
- 多架构构建（arm64）
- 镜像安全扫描

### 后续排查建议

- 如需推送镜像，添加 `push: true` 并配置 `docker/login-action@v3` + secrets
- Docker 构建耗时较长（moon 工具链安装 + 依赖下载），20 分钟超时应足够
- GHA cache (`type=gha`) 可加速重复构建
