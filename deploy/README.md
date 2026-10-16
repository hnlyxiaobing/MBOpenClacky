# MBOpenClacky 部署指南

MBOpenClacky 提供三种自托管部署方式。Web 服务默认监听 **7071** 端口。

> **安全提示**：自 v0.2 起，服务器默认仅绑定 `127.0.0.1`（回环地址）。
> 需要公网或局域网访问时，设置 `MBOPENCLACKY_WEB_HOST=0.0.0.0` 并**必须**
> 同时设置 `MBOPENCLACKY_WEB_API_KEY`，否则服务器拒绝启动。

> 前提：先构建原生二进制 `moon build --target native --release cmd`，产物位于
> `_build/native/release/build/cmd/cmd.exe`（`moon.work` 只含当前模块，发布树按
> workspace 相对路径分层；Linux/macOS 上为 `cmd`，无 `.exe`）。脚本里定位产物请统一
> 用 `scripts/release_binary.sh`，它按当前布局优先、找不到就大声失败。以下用
> `mbopenclacky` 指代该二进制。

---

## 1. Docker Compose（推荐，最快上手）

编排文件：`deploy/docker-compose.yml`（基于仓库根目录已有的多阶段 `Dockerfile`）。

```bash
# 必须设置 API key（公网绑定的安全闸门）
export MBOPENCLACKY_WEB_API_KEY="$(openssl rand -hex 32)"
# 同样必须：Web 服务器要求至少配置一个 LLM 模型，否则容器起来就退出
export MBOPENCLACKY_API_KEY="sk-..."
# 可选：覆盖端口与时区
export MBOPENCLACKY_WEB_PORT=8080
export TZ=Asia/Shanghai

docker compose up -d --build
curl http://localhost:${MBOPENCLACKY_WEB_PORT:-7071}/health
```

- 两个 key 缺一不可，这是 2026-10-15 用真实构建出的镜像实测出来的：只给 `MBOPENCLACKY_WEB_API_KEY` 时
  容器以退出码 1 报 `No API key configured … needs at least one LLM model configured`；把
  `MBOPENCLACKY_API_KEY` 设成空串同样被拒绝（不构成闸门绕过）。补上 LLM key 后 `--version` 报
  `MBOpenClacky v0.3.0`、`/health` 返回 `{"status":"ok","version":"0.3.0"}`。
- 因为重启策略是 `unless-stopped`，漏掉 LLM key 的表现不是「报错退出」而是**无限重启**，健康检查永远不过。
- 不想用环境变量的替代路径：`HOME` 被钉在 `/app`，把 `~/.mbopenclacky/config.toml` 写进命名卷同样有效。
- `docker compose config` 渲染需要 compose v2 插件；本机 WSL 的 docker 29.1.3 没有该插件（也没有 buildx），
  所以这一段只在有插件的环境复验，本轮证据来自直接 `docker run` 同一镜像。

- 数据（配置/会话/技能/日志）持久化于命名卷 `mbopenclacky-data`（容器内 `/app`）。
- 内置健康检查：`curl -f http://localhost:7071/health`。
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
./mbopenclacky server
```

## 日志轮转

配置：`deploy/logrotate.d/mbopenclacky`。日志位于 `~/.mbopenclacky/logs/clacky-YYYY-MM-DD.log`，按周轮转、保留 12 份并压缩。

```bash
sudo cp deploy/logrotate.d/mbopenclacky /etc/logrotate.d/
sudo logrotate -d /etc/logrotate.d/mbopenclacky   # 预演
```

> 若通过 systemd 将 `HOME` 改为 `/opt/mbopenclacky`，日志路径变为
> `/opt/mbopenclacky/.mbopenclacky/logs/`，logrotate 配置已包含该路径。
