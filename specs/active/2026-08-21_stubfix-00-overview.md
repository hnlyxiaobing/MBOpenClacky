# Stub 实装修复批次总览（stubfix 01-08）· 总览文档

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 全部 8 份子 spec 对抗性审核通过，自 draft 移入 active）
> **来源**: 《Stub 实装状态审计报告》（2026-08-21，全仓库 grep + 逐文件精读，四大领域 + 断链分析）
> **批次命名**: stubfix
> **依赖**: 无（批次内 spec 相对独立，个别软依赖见依赖链）

## 一、批次目标

把审计报告确认的"未实装/断链/假成功"问题转化为可审查、可独立实施的小型 spec 集。本批次共 8 份增量 spec，已全部通过对抗性审查（2026-08-22）并位于 `specs/active/`，逐个实施后归档至 `specs/completed/`。

**审计结论速览**（全部经本批次 spec 创建时的代码复核）：

| 领域 | 审计结论 | 复核结果 |
|------|---------|---------|
| 渠道发送 | 部分实装但断链（ChannelManager 孤儿、webhook 断链、web API 假成功） | 属实（ChannelManager 零引用、WebhookRegistry 生产零注册、send 端点假成功均已验证） |
| Discord 网关 | 协议层完整、连接层全 TODO | 属实（discord.mbt 10 TODO / gateway 0 TODO） |
| MCP stdio | transport 全 placeholder、send_request 必抛错 | 属实（is_alive 假标志、ignore(message)、"async runtime" 必抛） |
| 办公文档解析 | 6 格式全 placeholder | 属实，且有**新增发现**：lib/parser 整体为孤儿代码（ParserManager 全仓库零引用）；自带 lib/zip 仅支持 stored，真实 Office 文档（Deflate）不可解 |

## 二、Spec 清单

| # | 文件 | 来源（审计章节） | 优先级 | 核心问题 | 核心方案 |
|---|------|----------------|--------|---------|---------|
| 01 | `2026-08-21_stubfix-01-channel-wiring.md` | 3.1/3.2/3.3 + 建议 1 | P0 | ChannelManager 孤儿 + webhook 断链 + send API 假成功 | server 生命周期挂载 + WebhookRegistry 接线 + send/test API 真调用 |
| 02 | `2026-08-21_stubfix-02-honest-send-errors.md` | 2.1 风险提示 + 建议 2 | P0 | Telegram/WeCom/Weixin send_text 假成功（静默丢消息）；**审核扩围**：飞书 update_message、Discord edit_message/delete_message/get_current_user/upload_file 同为假成功 | 翻转为诚实 Err + wbtest 期望翻转 + 假成功闸门（扩围六处一并翻转） |
| 03 | `2026-08-21_stubfix-03-doc-parser-moonbitmark.md`（已完成 2026-08-22，移入 completed） | 2.4 + 建议 4 | P1 | 文档解析 6 格式全 placeholder + parser 孤儿 + read 工具不解析 | MoonBitMark 新增 OLE2/CFB + Word 二进制能力并发布 0.4.0（任务包 0/1）→ MB 引入；六格式白名单 + 薄适配层（删六个 XxxParser）+ read 工具接线 |
| 04 | `2026-08-21_stubfix-04-mcp-stdio-transport.md` | 2.3 + 建议 3 | P1 | MCP stdio transport 空壳、请求响应无关联 | 复用 browser_process 的 @process spawn 模式 + JSON-RPC id 关联 + initialize 握手 |
| 05 | `2026-08-21_stubfix-05-scheduler-persistence.md` | 第四节 scheduler 条目 + 建议 5 | P1 | 调度器不持久化（重启全丢）、时间戳恒 0 | @fs 读写 + yml 子集解析 + write-through + 共享时钟 |
| 06 | `2026-08-21_stubfix-06-telegram-send.md` | 2.1 + 建议 7 | P2 | Telegram 发送假成功（02 翻转后待实装） | 复用 http_post_json 同构实现 + 错误映射 |
| 07 | `2026-08-21_stubfix-07-ws-gateway.md` | 2.2/3.6 + 建议 6 | P2 | WebSocket 客户端缺失（Discord/钉钉 Stream/WeCom 三平台共用） | WsClient 薄封装（**审核裁决：@async.websocket 随既有 async@0.21.0 依赖树内，零新增依赖，TLS/wss 内置**）+ Discord 网关连接层 + ISO 8601 解析 |
| 08 | `2026-08-21_stubfix-08-infra-fs-modules.md` | 3.5 + 建议 9 | P3 | output_dir/backup/scripts/discover 四模块文件操作全 TODO | @fs/@utils 原语复用 + lib/zip 归档 + 按价值排序任务包 |

## 三、依赖链与实施顺序

```
stubfix-02（假成功翻转）──┐
                          ├──> stubfix-01（渠道接线）──> stubfix-06（Telegram 真发送）
                          │         │
                          │         └──────────────────> stubfix-07（WS 基础设施 + Discord 网关）
                          │                                    │（后置：钉钉 Stream / WeCom WS 消费 WsClient）
stubfix-03（文档解析，独立）│
stubfix-04（MCP stdio，独立）
stubfix-05（调度器持久化，独立）<──共享时钟──> stubfix-04 ──> stubfix-08（backup 轮转复用时钟）
```

- **硬依赖**：仅 06 -> 02（Err 分支替换）、06 -> 01 软依赖（test 探测透传）。
- **共享资产**：时钟函数（04/05/08 三处消费，先落地者定实现并回写）；WsClient（07 交付，钉钉/WeCom 后置 spec 消费）。
- **建议实施顺序**：02 -> 01（同批次合入）-> 03（用户重点，独立可并行）-> 04 -> 05 -> 06 -> 07 -> 08。
- **并行性**：03/04/05 三者与 01/02 无任何耦合，可三线并行。

## 四、MoonBitMark 组件调研结论（stubfix-03 支撑材料）

用户指定调研组件：`hnlyxiaobing/moonbitmark@0.3.0`（本地 `/mnt/d/MoonBit/MoonBitMark/`）。

**结论：满足 DOCX/XLSX/PPTX/PDF 四种格式的解析要求，是本批次文档解析的最优路径；DOC/WPS（OLE2/Word 二进制）能力由 stubfix-03 任务包 0/1 新增进 MoonBitMark 0.4.0（.wps 与 .doc 同为 OLE2 容器 + WordDocument 流，单一提取器覆盖双格式，2026-08-22 修订）。**

| 评估项 | 结果 | 证据 |
|--------|------|------|
| DOCX/XLSX/PPTX 容器 | ✅ 纯 MoonBit libzip（ZIP + Deflate） | `src/libzip/pkg.generated.mbti`：ZipArchive::open / read_file_entry_decompressed / deflate_decompress；依赖仅 core |
| PDF 文本抽取 | ✅ 纯 MoonBit（bobzhang/mbtpdf 词距感知），**无需外部命令 pdftotext** | README 运行边界节；审计建议的外部命令路径可被替代 |
| XML 解析 | ✅ 纯 MoonBit parser | src/xml（tokenizer/types） |
| 输出形态 | ✅ Markdown（LLM 友好，对齐 Ruby 原版 preview markdown 语义） | ConvertResult.markdown |
| async 兼容 | ✅ 双方均 moonbitlang/async@0.21.0 | 两个 moon.mod 对比 |
| OCR | 默认 Off，零 Python 依赖 | OcrConfig::default() = mode Off |
| Windows native | ✅ 与 MB 同 MSVC 环境 | KNOWN_ISSUES.md |
| 许可证 | ✅ Apache-2.0（MIT 项目可依赖） | moon.mod |
| DOC/WPS（OLE2） | ❌ 0.3.0 不支持 -> ✅ 0.4.0 新增 | stubfix-03 任务包 0/1 在 MoonBitMark 内新增 `src/ole2` + `src/formats/doc`（.doc/.wps 共用 Word 二进制提取）；.et/.dps 维持诚实报错 |
| 已知残留 | PDF 词距 OpTm/OpTw/OpTc、密集表格、重复 object 丢页 | docs/KNOWN_ISSUES.md（对语义文本提取足够，写入 03 验收口径） |
| 发布状态 | ✅ 0.3.0 已在线验证（mooncakes.io docs 页可达，async@0.21.0 + mbtpdf@0.1.2） | 2026-08-22 审核补录；0.4.0 由 stubfix-03 任务包 1 发布 |

**被否决的备选**：shell 调 unzip/pdftotext（Windows 外部依赖）、自研 inflate 进 lib/zip（工作量+PDF 仍无解）、复制 libzip/xml 源码（维护双份、丢转换管线）。

## 五、本轮未立项项（backlog，按审计章节归档）

| 项 | 审计位置 | 处置说明 |
|----|---------|---------|
| 钉钉 Stream Mode / WeCom WebSocket 连接层 | 2.1/3.6 | 依赖 stubfix-07 的 WsClient，后置独立 spec |
| 各平台 API 层补全（飞书 multipart 上传/附件下载、Discord edit_message/媒体、钉钉文件 URL、微信 AES-128-ECB） | 2.1 建议 8 | 诚实报错型 stub 无数据完整性风险；随各平台流式输出/媒体需求排期 |
| web `/api/upload` 文档解析 | 新发现（stubfix-03 调研） | stubfix-03 完成后零成本扩展 |
| Telegram/Weixin 接收侧长轮询、weixin 限流重试 | 2.1/第四节 | 与连接层议题合并统筹 |
| license activate/deactivate/heartbeat HTTP stub | 第四节 | 白标授权体系联网验证，独立排期 |
| telemetry 上报 placeholder + 匿名 ID 哈希 | 第四节 | 遥测合规议题 |
| TokenCache 过期刷新（时间戳同源） | 第四节 | 共享时钟落地后（04/05）顺带修复 |
| channel_scaffold 模板 stub 注释 | 3.4 | 设计如此，生成代码属脚手架语义 |
| skill reflector placeholder / 进化引擎 stub | 3.7 | 技能体系演进议题，非本批次 |
| channels_store 与 ChannelConfig 模型合并 | 3.3（stubfix-01 决策 5） | 数据迁移级改动，接线先行 |
| MCP HTTP transport 实装 | 2.3 | stubfix-04 决策 4 范围控制，stdio 主流先行 |

## 六、批次验收（整体）

- [x] 8 份 spec 全部通过对抗性审查（每份的验证记录表被复核、决策被质询）后移入 `specs/active/`（2026-08-22 完成；审查要点：02 同族假成功扩围、03 DOC/WPS 方案落 MoonBitMark 0.4.0、07 裁决 @async.websocket、08 关闭 @fs 能力疑点）
- [ ] 各 spec 独立实施、独立归档（`specs/completed/`），本总览随批次推进更新状态
- [ ] 批次全部归档后：全仓库假成功型 stub 清零（grep `success.*placeholder` / `tg_msg_` / `weixin_msg_pending` 断言）；审计报告第五节建议 1-9 对应项全部关闭或显式入 backlog

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本：8 份子 spec + MoonBitMark 调研结论 + backlog 归档 | stub 审计报告驱动的 Harness v2 批次起草 |
| 2026-08-22 | 批次对抗性审核完成：02 行同步同族假成功扩围；07 行同步 @async.websocket 前置裁决；03 行维持 DOC/WPS 修订结论；08 行 @fs 能力疑点关闭（read_dir/remove_file/remove_dir 原生具备）；状态改"实施中"并随批次移入 active | 8 份子 spec 逐份审核（详见各 spec 变更记录） |
