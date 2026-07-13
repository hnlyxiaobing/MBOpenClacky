# MBOpenClacky 部署指南

MBOpenClacky 提供三种自托管部署方式。Web 服务默认监听 **7070** 端口。

> 前提：先构建原生二进制 `moon build --target native --release cmd`，产物位于
> `_build/native/release/build/cmd/cmd.exe`（在 Linux/macOS 上为 `cmd`）。以下用
> `mbopenclacky` 指代该二进制。

---

## 1. Docker Compose（推荐，最快上手）

编排文件：`deploy/docker-compose.yml`（基于仓库根目录已有的多阶段 `Dockerfile`）。

```bash
# 可选：覆盖端口与时区
export MBOPENCLACKY_WEB_PORT=8080
export TZ=Asia/Shanghai

docker compose up -d --build
curl http://localhost:${MBOPENCLACKY_WEB_PORT:-7070}/health
```

- 数据（配置/会话/技能/日志）持久化于命名卷 `mbopenclacky-data`（容器内 `/app`）。
- 内置健康检查：`curl -f http://localhost:7070/health`。
- 重启策略：`unless-stopped`。

## 2. systemd（裸机生产）

单元文件：`deploy/systemd/mbopenclacky.service`。

```bash
sudo cp mbopenclacky /opt/mbopenclacky/          # 放置二进制
sudo useradd -r -s /usr/sbin/nologin -d /opt/mbopenclacky mbopenclacky
sudo chown -R mbopenclacky:mbopenclacky /opt/mbopenclacky
sudo cp deploy/systemd/mbopenclacky.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mbopenclacky
sudo journalctl -u mbopenclacky -f
```

- 以非 root 用户 `mbopenclacky` 运行，`ProtectSystem=strict` + `NoNewPrivileges`。
- 崩溃自动重启（`Restart=on-failure`，间隔 5s）。
- 端口经环境变量 `MBOPENCLACKY_WEB_PORT` 注入。

## 3. 裸跑（开发 / 临时）

```bash
./mbopenclacky server &          # 后台常驻并配合 nohup/supervisor 亦可
# 或仅前端开发
./mbopenclacky --server
```

## 日志轮转

配置：`deploy/logrotate.d/mbopenclacky`。日志位于 `~/.mbopenclacky/logs/clacky-YYYY-MM-DD.log`，按周轮转、保留 12 份并压缩。

```bash
sudo cp deploy/logrotate.d/mbopenclacky /etc/logrotate.d/
sudo logrotate -d /etc/logrotate.d/mbopenclacky   # 预演
```

> 若通过 systemd 将 `HOME` 改为 `/opt/mbopenclacky`，日志路径变为
> `/opt/mbopenclacky/.mbopenclacky/logs/`，logrotate 配置已包含该路径。
