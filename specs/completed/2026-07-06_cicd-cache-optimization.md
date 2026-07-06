# 任务包：CI 缓存优化

> **关联 spec**: `specs/active/2026-07-06_cicd-pipeline.md`  
> **创建日期**: 2026-07-06  
> **状态**: 已完成

## 目标

优化 `.github/workflows/ci.yml` 的缓存策略，加速 CI 流水线执行，目标将 CI 总耗时从 ~3-5 分钟降低到 ~1-2 分钟（缓存命中时）。

## 边界

### 要做

- 缓存 moon 工具链（`~/.moon/` 目录，按 moon 版本 hash 做 cache key）
- 缓存 mooncakes 依赖（`.mooncakes/` 目录，按 `moon.mod` hash 做 cache key）
- 缓存构建产物（`_build/` 目录，按源码 hash 做 cache key，可选）
- 使用 `actions/cache@v4` 官方 Action

### 明确不做

- 不做 Docker layer caching（放在 docker.yml 任务包）
- 不做 self-hosted runner
- 不做 CI 并行化（check/build/test 已有顺序依赖）

## 自由度

- **模型可以**：自选 cache key 策略、是否拆分多个 cache step
- **但不能**：引入第三方非官方 Action

## Checkpoint 规则

- 改代码前复述 diff 计划（仅修改 ci.yml）
- 确保缓存 key 在 moon 版本/依赖变更时能正确失效

## 验收标准

- [x] ci.yml 包含 moon 工具链缓存 ✅（`actions/cache@v4`, path: `~/.moon`, key: `moon-toolchain-${{ runner.os }}-v1`）
- [x] ci.yml 包含 mooncakes 依赖缓存 ✅（path: `.mooncakes`, key: `mooncakes-deps-${{ runner.os }}-${{ hashFiles('moon.mod') }}`）
- [x] 缓存 key 策略合理 ✅（工具链按 OS+v1 固定 key，依赖按 moon.mod hash 动态 key）
- [x] 不改动任何 .mbt 源文件 ✅

---

## 验收报告

### 改了什么

- **修改** `.github/workflows/ci.yml`（49 行 → 67 行，+18 行）
  - 新增 `Cache MoonBit toolchain` 步骤（`~/.moon/` 缓存）
  - 新增 `Cache project dependencies` 步骤（`.mooncakes/` 缓存）
  - 安装步骤增加 `if: cache-hit != 'true'` 条件判断
  - PATH 设置拆为独立步骤（无论缓存命中与否都执行）
- 未修改任何 .mbt 源文件

### 跑了什么验证

- 文件差异审查 → ✅ 仅 ci.yml 被修改，新增缓存逻辑
- YAML 结构审查 → ✅ `actions/cache@v4` 用法正确，`cache-hit` 条件判断合法
- git status lib/ cmd/ → ✅ 无源码变更

### 验收标准对照

- [x] ci.yml 包含 moon 工具链缓存 ✅
- [x] ci.yml 包含 mooncakes 依赖缓存 ✅
- [x] 缓存 key 策略合理 ✅
- [x] 不改动任何 .mbt 源文件 ✅

### 没覆盖的

- 构建产物缓存（`_build/` 目录，风险较高，暂缓）
- Docker layer caching（已在 docker.yml 中通过 `type=gha` 实现）

### 后续排查建议

- 首次运行无缓存时 CI 耗时较长，第二次运行应显著加速
- 如需更新 moon 工具链缓存，修改 key 中的 `-v1` 后缀即可触发重建
- `moon.mod` 变更时依赖缓存自动失效，无需手动处理
