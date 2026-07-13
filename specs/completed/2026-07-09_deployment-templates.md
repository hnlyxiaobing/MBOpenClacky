# 部署模板 · 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-09  
> **状态**: 已完成（2026-07-13 实施）  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P2-1）  
> **负责人**: Agent-E（部署运维）

## 核心目标

补齐生产部署所需的编排与守护模板：`docker-compose.yml`、systemd unit、日志轮转（logrotate），让 MBOpenClacky 可一键编排部署、以服务形式常驻、日志不撑爆磁盘。Dockerfile 已较完善（多阶段、非 root、健康检查），本轮在其上层补编排与守护。

## 关键能力

- **docker-compose**：单文件起 Web 服务 + 持久化卷 + 健康检查 + 重启策略；可扩展挂载配置/数据目录。
- **systemd unit**：服务定义、自动重启、日志归属、`User=` 非 root。
- **logrotate**：按大小/时间轮转 `~/.clacky/logs`，保留份数与压缩。
- **环境变量化**：端口、数据目录、配置路径通过 env 注入，模板可复用。

## 明确不做

- 不做 K8s/Helm（原因：超出当前规模）。
- 不做多节点集群编排（原因：单机自托管为主）。
- 不改 Dockerfile 本体（原因：已完善，仅编排层）。

## 关键决策（含为什么）

1. **compose 作为默认快速部署**：降低上手门槛，对齐自托管场景。
2. **systemd 供裸机生产**：很多用户不用 Docker，需原生守护方案。
3. **logrotate 必备**：JSON 会话日志增长快，必须轮转。
4. **配置外置**：所有可变项走 env，模板零硬编码路径。

## 验收维度

- [ ] `docker-compose up` 可起服务且健康检查通过
- [ ] systemd unit 可 `enable/start`，崩溃自动重启
- [ ] logrotate 配置生效，日志按策略轮转
- [ ] 端口/数据目录可经 env 覆盖
- [ ] 文档说明三种部署方式（Docker / systemd / 裸跑）

## 待后续推进时补充

- 环境变量完整清单
- 备份卷策略
- 反向代理（nginx）示例

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P2-1 |
| 2026-07-13 | 实施完成：新增 `deploy/docker-compose.yml`、`deploy/systemd/mbopenclacky.service`、`deploy/logrotate.d/mbopenclacky`、`deploy/README.md`；三种部署方式齐备，端口/数据目录经 env 可覆盖 | 闭环实施 |
