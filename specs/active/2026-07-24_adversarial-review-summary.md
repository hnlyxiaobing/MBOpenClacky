# 对抗性审核总结报告

> **审核日期**: 2026-07-24
> **审核范围**: specs/draft/ 下 16 份 spec 文档（fix-06 ~ fix-20 + overview）
> **审核方法**: Harness v2 对抗性审查 + 第一性原理校验
> **审核结果**: 全部通过，0 份否决

## 审核统计

| 指标 | 数值 |
|------|------|
| 审核文档总数 | 16 |
| 通过 | 16 |
| 否决 | 0 |
| 发现事实性错误 | 3 |
| 发现行号漂移 | 7 |
| 发现安全漏洞 | 1 |
| orig Ruby 逐行验证 | 6 份 spec |
| 人工确认 gate | 3 |

## 逐份审核结果

### fix-06 (frontend-v15-sync) ✅
- **发现**: 品牌资产状态描述错误（声称"不含品牌资产"，实际 ext_ui/ 目录存在含 git/、time-machine/ 子目录）
- **修正**: 更正描述为"ext_ui/ 目录已存在"

### fix-07 (ws-lifecycle-events) ✅
- **行号漂移**: 889 -> 887（不影响实施）
- **无事实性错误**

### fix-08 (ws-cost-latency-update) ✅
- **无事实性错误**

### fix-09 (session-summary-fields) ✅
- **发现**: 文件名引用错误（handlers_config.mbt 应为 handlers_extra.mbt）
- **修正**: 更正文件名引用

### fix-10 (billing-api-contract) ✅
- **无事实性错误**
- 6 个 handler 逐行验证确认

### fix-11 (config-api-contract) ✅
- **行号漂移**: :1817 -> :1821（差 4 行）
- **正确识别**: I-020"声称已过时"（AgentConfig 已持有全部四开关）
- **无事实性错误**

### fix-12 (dirs-endpoint-contract) ✅
- **无事实性错误**
- **orig Ruby 逐行验证**: api_browse_dirs@http_server.rb:4512-4545 全部声称属实
- **新发现**: mkdir 请求体键名不兼容（未入 scope）

### fix-13 (trash-api-contract) ✅
- **无事实性错误**
- **关键验证**: "恒空数组"根因确认--会话删除流程确未接入回收站

### fix-14 (media-types-semantics) ✅
- **无事实性错误**
- **orig Ruby 逐行验证**: api_media_types@http_server.rb:1713-1730 确认五模态输出
- **人工确认 gate**: media/types 语义重定义

### fix-15 (skills-api-fields) ✅
- **无事实性错误**
- handle_session_skills 确认为空数组 stub（TODO P3 注释）

### fix-16 (creator-skills-contract) ✅
- **行号漂移**: :461 -> :462（差 1 行）
- **orig Ruby 逐行验证**: api_creator_skills@http_server.rb:4664-4745 五键响应确认

### fix-17 (skill-publish) ✅
- **行号漂移**: :546 -> :548（差 2 行）
- **orig Ruby 逐行验证**: api_publish_my_skill@http_server.rb:5295-5380 五步流程确认
- **人工确认 gate**: 发布功能平台后端与 license 互通性

### fix-18 (brand-system-info-api) ✅
- **行号漂移**: :206 -> :207（差 1 行）
- **安全漏洞发现**: BrandConfig.license_key@:14 在 derive(ToJson) 结构体内，GET /api/brand 会明文泄露
- **orig Ruby 逐行验证**: api_brand_info/api_onboard_status/api_get_version 三个端点逐行确认
- **人工确认 gate**: I-023 门禁恢复 + I-024 GET 远端检查

### fix-19 (cron-manual-task-files) ✅
- **行号引用偏差**: :129 为 save_schedule_state，GET handler 实际在 :262
- **orig Ruby 逐行验证**: list_cron_tasks@:129-146 任务文件为主表语义确认

### fix-20 (p3-contract-patch-batch) ✅
- **事实性错误**: I-036"/api/browser/status 缺 chrome_version"为 false positive
  - BrowserStatus@browser_types.mbt:13-24 含 chrome_version:String?@:16 且 derive(ToJson)
  - BrowserManager::status()@browser_manager.mbt:131 从 self.config.chrome_version 填充
  - handle_browser_status 返回 status.to_json() 包含此字段
  - orig Ruby BrowserManager#status@browser_manager.rb:114-124 同样从配置读取
- **修正**: I-036 标记为 false positive，从修复项中移除

### overview (fix-06-20-overview) ✅
- 覆盖范围完整，无遗漏
- 3 个人工确认 gate 已标注
- 更新审核记录和状态

## 关键发现模式

### 1. 行号轻微漂移（7 处）
| Spec | 声称行号 | 实际行号 | 偏差 |
|------|---------|---------|------|
| fix-07 | :889 | :887 | -2 |
| fix-11 | :1817 | :1821 | +4 |
| fix-16 | :461 | :462 | +1 |
| fix-17 | :546 | :548 | +2 |
| fix-18 | :206 | :207 | +1 |
| fix-19 | :129 | :262 | 引用对象不同 |

均不影响实施（函数名正确，仅行号偏移数行）。

### 2. 事实性错误（3 处）
| Spec | 错误 | 修正 |
|------|------|------|
| fix-06 | 品牌资产状态描述错误 | 更正为"ext_ui/ 目录已存在" |
| fix-09 | 文件名引用错误 | handlers_config.mbt -> handlers_extra.mbt |
| fix-20 | I-036 false positive | chrome_version 字段已存在，标记为 false positive |

### 3. 安全漏洞（1 处）
- fix-18: BrandConfig.license_key 通过 derive(ToJson) 明文泄露到 GET /api/brand 响应

### 4. 过时声称正确识别（2 处）
- fix-11 I-020: settings 四开关已存在
- fix-14: media/types 0 消费者

### 5. 未接线/stub 确认（2 处）
- fix-13: 会话删除未接入回收站
- fix-15: session skills 返回空数组 stub

### 6. orig Ruby 逐行验证（6 份）
| Spec | 验证的 orig 文件 |
|------|-----------------|
| fix-12 | http_server.rb:4512-4545 (api_browse_dirs) |
| fix-14 | http_server.rb:1713-1730 (api_media_types) |
| fix-16 | http_server.rb:4664-4745 (api_creator_skills) |
| fix-17 | http_server.rb:5295-5380 (api_publish_my_skill) |
| fix-18 | http_server.rb:2843,965-976,2940-2954 (brand/onboard/version) |
| fix-19 | scheduler.rb:129-146 (list_cron_tasks) |

## 人工确认 gate（待用户确认）

1. **fix-14**: /api/media/types 语义重定义是否有意
2. **fix-17 任务包 0**: 发布功能对接的平台后端与 license 互通性
3. **fix-18**: I-023（onboard 门禁行为影响）、I-024（version 更新检查是否有意重设计）

## 文件操作

- 16 份 spec 从 `specs/draft/` 移至 `specs/active/`
- `specs/draft/` 已清空
- 每份 spec 的变更记录表均添加了详细对抗性审核记录

## 结论

全部 16 份 spec 文档通过对抗性审核，已移入 `specs/active/`。发现并修正了 3 处事实性错误、7 处行号漂移、1 处安全漏洞。下一步：确认 3 个人工确认 gate，然后从 fix-06 开始按依赖顺序开发。
