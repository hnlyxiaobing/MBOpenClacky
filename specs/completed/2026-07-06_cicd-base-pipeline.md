# 任务包：基础 CI 流水线（moon check + build + test）

> **关联 spec**: `specs/active/2026-07-06_cicd-pipeline.md`  
> **创建日期**: 2026-07-06  
> **状态**: 已完成

## 目标

创建 `.github/workflows/ci.yml`，实现 PR 和 main 分支的基础 CI 流水线，包含 moon check（类型检查）、moon build（构建）、moon test（测试）三个步骤，确保每次代码变更自动验证。

## 边界

### 要做

- 创建 `.github/workflows/ci.yml` GitHub Actions 配置文件
- CI 在 PR 创建/更新 和 main 分支 push 时触发
- 使用 Ubuntu 22.04 runner（与 Dockerfile builder 一致）
- 安装 moon 工具链、libssl-dev 等构建依赖
- 执行 `moon update && moon install` 安装项目依赖
- 执行 `moon check`（类型检查）
- 执行 `moon build --target native --release cmd`（构建，显式指定 cmd 包避免 #1488）
- 执行 `moon test`（运行测试）
- 设置合理的 job 超时（15 分钟）

### 明确不做

- 不做 Docker 镜像构建（放在任务包 2）
- 不做缓存优化（放在任务包 3）
- 不做 Windows/macOS 矩阵
- 不做代码质量门禁/安全扫描

## 自由度

- **模型可以**：自选 YAML 结构风格、step 命名方式、条件判断写法
- **但不能**：改动任何现有源码、引入新的外部 Action（除非 GitHub 官方 action）、修改 Dockerfile

## Checkpoint 规则

- 改代码前复述 diff 计划（创建哪些文件、内容结构）
- 发现"想做但不应做"的事情立刻暂停汇报
- 不改动任何 `.mbt` 源文件

## 验收标准

- [x] `.github/workflows/ci.yml` 文件存在且语法合法
- [x] CI 触发条件覆盖 PR + main push
- [x] CI 包含 moon check 步骤
- [x] CI 包含 moon build --target native --release cmd 步骤
- [x] CI 包含 moon test 步骤
- [x] CI 有合理的超时设置（15 分钟）
- [x] 不改动任何现有源码文件

---

## 验收报告

### 改了什么

- **新建** `.github/workflows/ci.yml`（49 行）— GitHub Actions CI 工作流
- 未修改任何现有文件

### 跑了什么验证

- 文件存在性检查 → ✅ `.github/workflows/ci.yml` 已创建
- YAML 语法检查 → ✅ 人工审查结构合法
- git status --short lib/ cmd/ → ✅ 无本任务引入的源码变更
  （`cmd/moon.pkg` 和 `lib/tui/moon.pkg` 的 M 状态为本次任务之前的既有变更）

### 验收标准对照

- [x] `.github/workflows/ci.yml` 文件存在且语法合法 ✅
- [x] CI 触发条件覆盖 PR + main push ✅（`on: push: branches: [main]` + `pull_request: branches: [main]`）
- [x] CI 包含 moon check 步骤 ✅（step: Type check）
- [x] CI 包含 moon build --target native --release cmd 步骤 ✅
- [x] CI 包含 moon test 步骤 ✅
- [x] CI 有合理的超时设置 ✅（timeout-minutes: 15）
- [x] 不改动任何现有源码文件 ✅

### 没覆盖的

- 缓存优化（任务包 3）
- Docker 镜像自动化（任务包 2）
- 实际 CI 运行验证（需推送到 GitHub 后触发）

### 后续排查建议

- 首次 CI 运行可能因 moon 工具链安装耗时较长而接近 15 分钟超时，建议在任务包 3 中加入缓存优化
- 如 `moon test` 因 libcurl 依赖未启用而跳过，需确认 CI 环境中 `lib/client/moon.pkg` 的 link 配置
- 确认 GitHub runner 的 Ubuntu 22.04 镜像中 `libssl-dev` 包名可用
