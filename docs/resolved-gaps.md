# Resolved Gaps Archive（已修复归档）

> 本节归档已从 `docs/known-gaps.md`（活跃缺口台账）移出的已修复条目。工作流：修复一条缺口 → 重跑 `scripts/known_gaps.sh generate` → 该条从扫描表消失 → 将对应 curated 行从 `known-gaps.md` 移至本文并标记为 `fixed`（保留修复记录）。
>
> 归档条目不参与 CI 校验（`scripts/known_gaps.sh check` 仅扫描 `known-gaps.md`）。

## 已解决的环境问题

| 问题 | 现象 | 影响与处置 |
|---|---|---|
| CI 自 2026-08-28 起为红 | **2026-09-21 已定位并修复。** 失败步骤是 `Run tests`：裸 `moon test --release` 按 `moon.work` 的工作区成员 `[".", "vendor/mbtpdf"]` **同时运行被 vendored 的依赖自身的内部测试**，而该测试驱动在当前工具链上 ICE（`Sys_error(".../core/_build/native/release/bundle/prelude/prelude.mi: No such file or directory")`）。其前的 type check / 警告预算 / 公共 API / 真话台账 / 构建 / 契约探针**全部 success**（步骤级证据取自公开 API） | **fixed（已复验）**：CI 的测试步骤改为只跑本模块自身的包（`lib cmd test`；`lib/mcp` 单列一步供 Linux 跑），与 `scripts/repo_stats.sh` 公布的用例数同口径；依赖的**库**代码仍被构建并由 `lib/parser` 的测试覆盖，只是不再运行其自带单测。定位手段：公开 API 的步骤级结论 + WSL 复现（`moon check` 绿、裸 `moon test --release` ICE、限定包列表跑完 3818/3818）。**复验**：commit `020ec26` 的 CI run `35565534593` 全部步骤 success，为 2026-08-28 以来首次绿 |
| Docker 工作流失败（`Build Docker image`） | **2026-09-21 已定位并修复。** 根因是产物路径写错，且**在 Dockerfile 中出现两处**：① 构建阶段的 `test -f /build/_build/native/release/build/cmd/cmd.exe` 断言；② 运行阶段的 `COPY --from=builder /build/_build/native/release/build/cmd/cmd.exe`。moon 的产物路径含模块命名空间，实际为 `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd`，两处**恒不成立**——`moon build` 本身成功，失败来自这两处引用。buildx 报文即指向 ②：`failed to compute cache key ... "\/build\/_build\/native\/release\/build\/cmd\/cmd.exe": not found`（**经 job 页面读到的真实报错**） | **fixed**：构建阶段把产物规范化为稳定路径 `/build/out/mbopenclacky`（`cmd`/`cmd.exe` 两种后缀在本地判别），运行阶段改为 `COPY --from=builder /build/out/mbopenclacky`；注释写明路径规则。**复验为绿**：commit `7770730` 的 `Docker` 工作流（run `35566838562`）全部步骤 success，含 `Build Docker image` 与 `Verify image`（后者 `docker run --rm mbopenclacky:latest --version` 实际执行了镜像内二进制）。本机无 Docker，本地无法复现；判据取自工作流步骤级结果 |

## 归档台账

<!-- BEGIN: archive -->

| 位置 | 状态 | 交付物 | 说明 |
|---|---|---|---|
| cmd/cli_mcp.mbt:9 | fixed | 计划 #10 | cli_mcp stdio MCP server 已接线（2026-09-23）：server 侧 JSON-RPC 协议面（initialize/tools/list/tools/call）实现，读自身进程 stdin |
| cmd/cli_mcp.mbt:11 | fixed | 计划 #10 | 同上（2026-09-23） |
| cmd/cli_mcp.mbt:18 | fixed | 计划 #10 | 同上（2026-09-23） |
| cmd/cli_mcp.mbt:24 | fixed | 计划 #10 | 同上（2026-09-23） |
| lib/channel/dingtalk.mbt:95 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/dingtalk.mbt:112 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/dingtalk_api.mbt:362 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/dingtalk_api.mbt:382 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/dingtalk_api.mbt:408 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/dingtalk_api.mbt:424 | fixed | WP-1.2 | 钉钉 Stream/gateway 与文件下载接线（2026-09-22）：open_stream_connection/download_file_url 走真实 HTTP POST，双 token 缓存复用；start/stop 的 TODO 改为如实描述（webhook 接收由 ChannelManager 承担） |
| lib/channel/discord_api.mbt:85 | fixed | WP-1.6 | Discord 编辑接线（2026-09-22）：`edit_message` 走 PATCH，`supports_message_updates=true` 与实现一致 |
| lib/channel/discord_api.mbt:101 | fixed | WP-1.6 | Discord 撤回接线（2026-09-22）：`delete_message` 走 DELETE（204 仅看状态）；`Adapter` trait 新增 `delete_message`/`supports_message_deletion` 并由 `AnyAdapter` 分发 |
| lib/channel/discord_api.mbt:114 | fixed | WP-1.6 | Discord 用户信息接线（2026-09-22）：`get_current_user` 走 GET /users/@me；web 连通性探针改走该方法（不再手工拼 URL 绕开 stub） |
| lib/channel/discord_api.mbt:136 | fixed | WP-1.6 | Discord 上传接线（2026-09-22）：`upload_file` 走 multipart POST + `build_discord_upload_body` |
| lib/channel/discord_api.mbt:150 | fixed | WP-1.6 | Discord 下载接线（2026-09-22）：`download_attachment` 走真实 GET；原实现不发请求即返回 `Ok("")`（静默假成功）已消除 |
| lib/channel/feishu.mbt:76 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu.mbt:153 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:178 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:188 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:227 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:230 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:250 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:254 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:273 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:276 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:301 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:305 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:327 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/feishu_api.mbt:331 | fixed | WP-1.1 | 飞书 send/update/upload/download/history 已接线（2026-09-22）：PATCH 传输支持、multipart 二进制上传、content 契约修正，业务 code 检查防假成功；webhook 接收已由 stubfix-01 承担 |
| lib/channel/telegram.mbt:250 | fixed | 计划 #7 | Telegram getUpdates 长轮询接收侧已接线（2026-09-23）：`start()` 进入 `poll_loop`（HTTP POST getUpdates + timeout=30），入站消息经 ChannelManager 投递；编辑/撤回由 WP-1.6 接线 |
| lib/channel/telegram.mbt:291 | fixed | WP-1.6 | Telegram 编辑/撤回接线（2026-09-22）：`update_message` 走 editMessageText（纯文本不带 parse_mode，与发送侧 R3 决策一致）、`delete_message` 走 deleteMessage；`supports_message_updates=true` 与实现一致 |
| lib/channel/wecom.mbt:93 | fixed | WP-1.3 | 企微 send 接线（2026-09-22）：新增 WeComApiClient（gettoken 缓存 + message/send），errcode!=0 一律报错；adapter 改持 api_client，start 注释如实化 |
| lib/channel/wecom.mbt:123 | fixed | WP-1.3 | 企微 send 接线（2026-09-22）：新增 WeComApiClient（gettoken 缓存 + message/send），errcode!=0 一律报错；adapter 改持 api_client，start 注释如实化 |
| lib/channel/wecom.mbt:141 | fixed | WP-1.3 | 企微 send 接线（2026-09-22）：新增 WeComApiClient（gettoken 缓存 + message/send），errcode!=0 一律报错；adapter 改持 api_client，start 注释如实化 |
| lib/channel/weixin.mbt:191 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin.mbt:215 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin.mbt:230 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:312 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:339 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:346 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:352 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:360 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:367 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| lib/channel/weixin_api.mbt:373 | fixed | WP-1.4 | 微信 send 与 AES-128-ECB 接线（2026-09-22）：AES-128-ECB 加 PKCS#7 由 moonbitlang/x/crypto 承载并有 FIPS-197 向量测试；send_text 走真实 sendmessage 并处理 ret 与限流；start 注释如实化 |
| cmd/hook_loader.mbt:27 | fixed | 计划 #18 | 死代码清理（2026-09-23）：`lib/hook/shell_loader.mbt`（`ShellHookLoader`）已删除——生产代码零调用且 `execute_hook` 无条件 `Allow` 是静默放行陷阱；真实加载路径 `cmd/hook_loader.mbt:27 load_shell_hooks` 由 `cmd/hook_loader_wbtest.mbt`（4 例）覆盖 |
| cmd/hook_loader.mbt:48 | fixed | 计划 #18 | 同上（2026-09-23）；原 `shell_loader.mbt:48` 的 STDIN 传递 TODO 随文件删除一并清除 |
| lib/mcp/http_transport.mbt:58 | fixed | WP-3.3 | MCP Streamable HTTP 已接线（2026-09-22）：`start` 校验 url 并置为可用（无连接可建），`send_request` 走 `@async/http` POST，`application/json` 与 `text/event-stream` 两种应答都可解析，服务端 `Mcp-Session-Id` 被捕获并在后续请求回带；行号随重写漂移 |
| lib/media/dashscope.mbt:12 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/dashscope.mbt:19 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/gemini.mbt:12 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/gemini.mbt:17 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/gemini.mbt:34 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/gemini.mbt:39 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/openai_compat.mbt:13 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/openai_compat.mbt:19 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/openai_compat.mbt:36 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/media/openai_compat.mbt:40 | fixed | WP-1.5 | 媒体生成已接线（2026-09-21）：OpenAI 兼容网关承载图/语音/视频，DashScope 同步多模态接口，Gemini 直连重定向网关 |
| lib/server/browser_manager.mbt:36 | fixed | 计划 #20 | browser_manager 运维 TODO 已修（2026-09-23）：`browser.yml` 经 `simple_yml` 解析、`started_at` 由 `@env.now()` 填充、uptime 真实计算、配置写回 |
| lib/server/browser_manager.mbt:80 | fixed | 计划 #20 | 同上（2026-09-23） |
| lib/server/browser_manager.mbt:125 | fixed | 计划 #20 | 同上（2026-09-23） |
| lib/server/browser_manager.mbt:150 | fixed | 计划 #20 | 同上（2026-09-23） |
| lib/skill/reflector.mbt:111 | fixed | WP-2.1 | 占位 `apply_improvements` 已删除，替换为 LLM 反思的 prompt 构建与响应解析纯函数（2026-09-22） |
| lib/skill/reflector.mbt:116 | fixed | WP-2.1 | 同上（2026-09-22） |
| lib/skill/reflector.mbt:124 | fixed | WP-2.1 | 同上（2026-09-22） |
| lib/tool/browser.mbt:234 | fixed | 计划 #19 | browser 截图尺寸约束与配置检测已修（2026-09-23）：`max_width`/`max_height` 在 schema 中标注为 enforced；`browser_config_path` 存在性与 `enabled` 检测已实现 |
| lib/tool/browser.mbt:237 | fixed | 计划 #19 | 同上（2026-09-23） |
| lib/tool/browser.mbt:241 | fixed | 计划 #19 | 同上（2026-09-23） |
| lib/tool/browser.mbt:427 | fixed | 计划 #19 | 同上（2026-09-23） |
| lib/tool/browser.mbt:439 | fixed | 计划 #19 | 同上（2026-09-23） |
| lib/tool/browser.mbt:448 | fixed | 计划 #19 | 同上（2026-09-23）；行号随 #19 编辑漂移，原 "stub" 标记移至 :476 |
| lib/web/handlers_backup.mbt:649 | fixed | 计划 #11 | 备份快照 ZIP 下载已接线（2026-09-23）：`build_backup_zip` 经 `lib/zip` 打包快照目录，成功返回 `application/zip` + `body_bytes`，失败走 `HttpResponse::json_status(500, …)` 诊断体；原 501 占位与 `not_found(Json::object().stringify())` 的双层嵌套隐患一并清除 |
| lib/web/handlers_backup.mbt:670 | fixed | 计划 #11 | 同上（2026-09-23）；行号随重写漂移，文件仍存在 |
| lib/web/handlers_bridge.mbt:838 | fixed | WP-1.5 | 视频生成已接线（2026-09-21），status 端点如实报告同步执行模型 |
| lib/web/handlers_bridge.mbt:845 | fixed | WP-1.5 | 视频生成已接线（2026-09-21），status 端点如实报告同步执行模型 |
| lib/web/handlers_channels.mbt:336 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:387 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:389 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:391 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:393 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:448 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:472 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_channels.mbt:718 | fixed | 连通性探针 | 四平台连通性探针真实化（telegram getMe / 企微 gettoken / 微信 1s getupdates / 钉钉 token），并删除不可达且伪造 success 的同步 test/send 处理器（2026-09-22） |
| lib/web/handlers_media.mbt:2 | fixed | WP-1.5 | 媒体 REST 端点已接线（2026-09-21），无配置或非法输入返回诊断 400 |
| lib/web/handlers_media.mbt:27 | fixed | WP-1.5 | 媒体 REST 端点已接线（2026-09-21），无配置或非法输入返回诊断 400 |
| lib/web/handlers_media.mbt:41 | fixed | WP-1.5 | 媒体 REST 端点已接线（2026-09-21），无配置或非法输入返回诊断 400 |
| lib/web/handlers_media.mbt:55 | fixed | WP-1.5 | 媒体 REST 端点已接线（2026-09-21），无配置或非法输入返回诊断 400 |
| lib/web/handlers_media.mbt:69 | fixed | WP-1.5 | 媒体 REST 端点已接线（2026-09-21），无配置或非法输入返回诊断 400 |
| lib/web/handlers_skills.mbt:639 | fixed | WP-2.1 | 进化端点已接线：真实 LLM 反思 + 进化日志持久化 + 历史查询端点（2026-09-22） |
| lib/web/handlers_skills.mbt:648 | fixed | WP-2.1 | 同上（2026-09-22） |
| lib/web/handlers_skills.mbt:659 | fixed | WP-2.1 | 同上（2026-09-22） |
| lib/web/handlers_trash.mbt:365 | fixed | 计划 #13 | trash 已接真实数据面（2026-09-23，注释标 `fix-13`）：软删除会话保留磁盘负载（`@utils.get_trash_dir()`），`trash_add_session` 由会话删除流程调用，使 `GET /api/trash/sessions` 反映真实回收站内容并以 `remove_trash_item` 做恢复/清理 |
| lib/web/handlers_ws.mbt:283 | fixed | 计划 #4 | WS 会话摘要改由共享助手 `session_updated_at(sd)` 提供真实活跃时间（2026-09-23），与 REST 侧投影（`handlers.mbt:33`）同源；旧会话缺该字段时回落 `created_at`，故不破坏旧文件兼容 |
| cmd/eval.mbt:77 | fixed | WP-2.2 | `--live` 已接线（2026-09-22）：`test/capability/tasks/` 任务集 + 真 ReAct 运行器（工具面限定为 file_reader/write/edit/grep/glob）+ 评分向量与报告落盘；无 key 时仍诚实 exit 1 |
| cmd/main.mbt:198 | fixed | WP-2.2 | `--live` 帮助文本改为如实描述「需配置模型」（2026-09-22） |
| cmd/selftest.mbt:520 | fixed | WP-2.2 | 契约探针改为与 key 无关的确定性失败路径（缺任务集→exit 1、模式互斥→exit 2），避免探针继承环境后触发真实计费调用（2026-09-22） |

<!-- END: archive -->
