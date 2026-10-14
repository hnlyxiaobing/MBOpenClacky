# 用户场景自动化测试方案 v1.0

> **状态说明（2026-10-14）**：这是设计草稿，不是当前测试事实。`test/web-e2e/` 已落地 21 个 Playwright spec（114 个测试），Journey 当前为 23 条（Web 9 / TUI 5 / CLI 9）。本文保留原始目标、风险和路线图，实施状态以 `docs/testing.md` 为准。


**日期**: 2026-10-10  
**目标**: 覆盖 90% 用户核心场景，发现现有问题，优化测试体系  
**状态**: 设计阶段

---

## 一、现有测试体系反思

### 1.1 当前测试金字塔

```
                    ┌─────────────────┐
                    │  Layer 9: 旅程   │  23 条 E2E 旅程（当前）
                    │  (真实二进制)    │  真实 LLM mock
                    ├─────────────────┤
                    │  Layer 6: 工具   │  确定性工具 eval
                    │  (离线 eval)     │
                    ├─────────────────┤
                    │  Layer 4: 界面   │  TUI 47 + Web 26
                    │  (headless eval) │  单步 UI 行为
                    ├─────────────────┤
                    │  Selftest: CLI   │  10 个契约探针
                    │  (合同测试)      │
                    ├─────────────────┤
                    │  Unit Tests      │  ~4000 测试用例
                    │  (白盒测试)      │
                    └─────────────────┘
```

### 1.2 问题分析

| 问题 | 症状 | 根因 |
|------|------|------|
| **层级职责不清** | Layer 4 和 Layer 9 有重叠（如 TUI 消息往返） | 缺少明确的分层标准 |
| **Web UI 覆盖不足** | 26 个 Web eval 只覆盖 API，未覆盖 UI 交互 | 缺少浏览器自动化能力 |
| **多轮对话缺失** | 仅 CLI 有 1 个多轮旅程，TUI/Web 无 | 旅程编写成本高 |
| **附件/图片未覆盖** | `--file`/`--image` 无任何测试 | 功能新，测试未跟进 |
| **进阶功能长尾** | 35 个核心场景中 20+ 个无覆盖 | 优先级不清晰 |
| **场景维护成本高** | 每个旅程需手写 MoonBit 代码 | 缺少 DSL 或配置化 |

### 1.3 测试金字塔应该是什么

```
                    ┌─────────────────────┐
                    │  E2E: 关键用户旅程    │  20-30 条（含多轮）
                    │  (真实二进制+浏览器)  │  覆盖第一梯队
                    ├─────────────────────┤
                    │  Integration: 功能流  │  50+ 场景
                    │  (API + UI 组件)      │  覆盖第二梯队
                    ├─────────────────────┤
                    │  Component: 单组件    │  100+ 场景
                    │  (对话框/面板/命令)   │  覆盖第三梯队
                    ├─────────────────────┤
                    │  Unit: 函数/方法      │  4000+ 用例
                    │  (白盒)               │
                    └─────────────────────┘
```

**关键改进点**:
1. **E2E 层引入浏览器自动化** — 真正测试 Web UI
2. **Integration 层独立出来** — API + UI 组件组合测试
3. **Component 层扩展** — 现有 Layer 4 eval 重新定位
4. **场景配置化** — 用 JSON/YAML 而非代码定义场景

---

## 二、自动化执行方案设计

### 2.1 分层策略

| 场景类型 | 测试层级 | 执行方式 | 频率 |
|---------|---------|---------|------|
| **CLI 主流程** (1-3, 8, 26-28) | E2E Journey | 真实二进制 + mock LLM | 每次提交 |
| **TUI 主流程** (4-5, 8-9, 14, 21-22, 35) | Component + E2E | eval + 真实 TUI | 每次提交 |
| **Web 主流程** (6-7, 8-9, 15-17, 19, 23-25, 29, 34) | Integration + E2E | API + 浏览器自动化 | 每次提交 |
| **附件/图片** (10-11) | Integration | API + 文件系统验证 | 每次提交 |
| **Skill 调用** (12) | Integration | eval + 真实执行 | 每次提交 |
| **错误恢复** (20) | E2E | 故障注入 + 恢复验证 | 每日 |
| **进阶功能** (30-33) | Integration | API + 组件测试 | 每周 |

### 2.2 具体场景自动化方案

#### Phase 1: 补齐第一梯队（1-2 周）

##### 场景 8: 多轮对话上下文保持

**目标**: 验证连续 3+ 轮对话中 Agent 记住上下文

**CLI 实现** (扩展现有 `cli_session_save_and_continue`):
```moonbit
// test/journey/scenarios/cli_multi_turn_context.mbt
fn main() {
  // Turn 1: 告诉 Agent 用户名
  run_cli("--message", "我的名字是 Alice")
  assert_exit_code(0)
  
  // Turn 2: 继续会话，问名字
  run_cli("--continue", "--message", "我叫什么名字？")
  assert_exit_code(0)
  assert_stdout_contains("Alice")
  
  // Turn 3: 再问一次，确认记忆持久
  run_cli("--continue", "--message", "再重复一次我的名字")
  assert_exit_code(0)
  assert_stdout_contains("Alice")
}
```

**TUI 实现** (扩展 journey):
```moonbit
// test/journey/scenarios/tui_multi_turn_context.mbt
fn main() {
  start_tui()
  
  // Turn 1
  type_text("我喜欢蓝色")
  press_enter()
  wait_for_idle()
  
  // Turn 2
  type_text("我最喜欢的颜色是什么？")
  press_enter()
  wait_for_idle()
  assert_output_contains("蓝色")
  
  // Turn 3
  type_text("再问一次")
  press_enter()
  wait_for_idle()
  assert_output_contains("蓝色")
}
```

**Web 实现** (浏览器自动化):
```javascript
// test/journey/scenarios/web_multi_turn_context.js
const { chromium } = require('playwright');

test('multi-turn conversation maintains context', async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('http://localhost:7071');
  
  // Turn 1
  await page.fill('[data-testid="composer"]', '我的项目叫 Phoenix');
  await page.press('[data-testid="composer"]', 'Enter');
  await page.waitForSelector('.message.assistant');
  
  // Turn 2
  await page.fill('[data-testid="composer"]', '我的项目叫什么？');
  await page.press('[data-testid="composer"]', 'Enter');
  await page.waitForSelector('.message.assistant:nth-child(2)');
  
  const lastMessage = await page.textContent('.message.assistant:last-child');
  expect(lastMessage).toContain('Phoenix');
  
  await browser.close();
});
```

##### 场景 9: 模型切换

**CLI**:
```moonbit
// test/journey/scenarios/cli_model_switch.mbt
fn main() {
  // 默认模型
  run_cli("--message", "hello")
  assert_exit_code(0)
  
  // 切换到 gpt-4
  run_cli("--model", "gpt-4", "--message", "hello")
  assert_exit_code(0)
  
  // 切换到不存在的模型，应报错
  run_cli("--model", "nonexistent-model", "--message", "hello")
  assert_exit_code(1)
  assert_stderr_contains("model not found")
}
```

**Web** (浏览器自动化):
```javascript
// test/journey/scenarios/web_model_switch.js
test('switch model in settings', async () => {
  await page.goto('http://localhost:7071/settings');
  
  // 打开模型选择器
  await page.click('[data-testid="primary-model-selector"]');
  
  // 选择 gpt-4
  await page.click('[data-testid="model-option-gpt-4"]');
  
  // 验证保存
  await page.waitForSelector('[data-testid="save-success"]');
  
  // 新建会话，验证使用新模型
  await page.goto('http://localhost:7071/session/new');
  const modelBadge = await page.textContent('[data-testid="model-badge"]');
  expect(modelBadge).toContain('gpt-4');
});
```

##### 场景 10: 文件附件上传

**CLI**:
```moonbit
// test/journey/scenarios/cli_file_attachment.mbt
fn main() {
  // 创建测试文件
  write_file("test.txt", "Hello World")
  
  // 附带文件提问
  run_cli("--file", "test.txt", "--message", "这个文件的内容是什么？")
  assert_exit_code(0)
  assert_stdout_contains("Hello World")
  
  // 多个文件
  write_file("test2.txt", "Second file")
  run_cli("--file", "test.txt", "--file", "test2.txt", "--message", "有几个文件？")
  assert_exit_code(0)
  assert_stdout_contains("2")
}
```

**Web** (浏览器自动化):
```javascript
// test/journey/scenarios/web_file_attachment.js
test('upload file attachment', async () => {
  await page.goto('http://localhost:7071/session/new');
  
  // 上传文件
  const fileInput = await page.$('[data-testid="file-input"]');
  await fileInput.uploadFile('test.txt');
  
  // 验证附件显示
  const attachmentBadge = await page.textContent('[data-testid="attachment-badge"]');
  expect(attachmentBadge).toContain('test.txt');
  
  // 发送消息
  await page.fill('[data-testid="composer"]', '分析这个文件');
  await page.press('[data-testid="composer"]', 'Enter');
  
  // 验证 Agent 处理了文件
  await page.waitForSelector('.message.assistant');
  const response = await page.textContent('.message.assistant');
  expect(response.length).toBeGreaterThan(0);
});
```

##### 场景 11: 图片理解

**CLI**:
```moonbit
// test/journey/scenarios/cli_image_understanding.mbt
fn main() {
  // 准备测试图片（1x1 红色 PNG）
  copy_file("test/fixtures/red.png", "test.png")
  
  // 附带图片提问
  run_cli("--image", "test.png", "--message", "这张图片是什么颜色？")
  assert_exit_code(0)
  assert_stdout_contains("红色")
}
```

**Web** (浏览器自动化):
```javascript
// test/journey/scenarios/web_image_understanding.js
test('upload and analyze image', async () => {
  await page.goto('http://localhost:7071/session/new');
  
  // 上传图片
  const imageInput = await page.$('[data-testid="image-input"]');
  await imageInput.uploadFile('test/fixtures/red.png');
  
  // 验证预览
  await page.waitForSelector('[data-testid="image-preview"]');
  
  // 发送消息
  await page.fill('[data-testid="composer"]', '描述这张图片');
  await page.press('[data-testid="composer"]', 'Enter');
  
  // 验证 Agent 分析了图片
  await page.waitForSelector('.message.assistant');
  const response = await page.textContent('.message.assistant');
  expect(response).toContain('红色');
});
```

#### Phase 2: 补齐第二梯队（2-3 周）

##### 场景 12: Skill 调用

**TUI**:
```moonbit
// test/journey/scenarios/tui_skill_invocation.mbt
fn main() {
  start_tui()
  
  // 通过斜杠命令调用
  type_text("/skill commit-push")
  press_enter()
  wait_for_idle()
  assert_output_contains("commit")
  
  // 通过自然语言调用
  type_text("帮我提交代码")
  press_enter()
  wait_for_idle()
  // 验证触发了 commit-push skill
  assert_output_contains("git commit")
}
```

**Web** (浏览器自动化):
```javascript
// test/journey/scenarios/web_skill_panel.js
test('skill panel browse and invoke', async () => {
  await page.goto('http://localhost:7071/skills');
  
  // 验证技能列表加载
  await page.waitForSelector('[data-testid="skill-list"]');
  const skills = await page.$$('data-testid="skill-item"');
  expect(skills.length).toBeGreaterThan(0);
  
  // 搜索技能
  await page.fill('[data-testid="skill-search"]', 'commit');
  const filtered = await page.$$('[data-testid="skill-item"]');
  expect(filtered.length).toBeLessThan(skills.length);
  
  // 点击技能查看详情
  await page.click('[data-testid="skill-item"]:first-child');
  await page.waitForSelector('[data-testid="skill-detail"]');
});
```

##### 场景 14: TUI 撤销操作

```moonbit
// test/journey/scenarios/tui_undo_operation.mbt
fn main() {
  start_tui()
  
  // 让 Agent 创建文件
  type_text("创建文件 test.txt，内容是 Hello")
  press_enter()
  wait_for_idle()
  assert_file_exists("test.txt")
  assert_file_content("test.txt", "Hello")
  
  // 撤销
  type_text("/undo")
  press_enter()
  wait_for_idle()
  
  // 验证文件被删除或恢复原状
  assert_file_not_exists("test.txt")
}
```

##### 场景 15: Web 设置面板

```javascript
// test/journey/scenarios/web_settings_panel.js
test('settings panel change language', async () => {
  await page.goto('http://localhost:7071/settings');
  
  // 切换到 UI 标签
  await page.click('[data-testid="tab-ui"]');
  
  // 修改语言为中文
  await page.selectOption('[data-testid="language-select"]', 'zh');
  
  // 验证保存成功
  await page.waitForSelector('[data-testid="save-success"]');
  
  // 刷新页面，验证持久化
  await page.reload();
  const language = await page.$eval('[data-testid="language-select"]', el => el.value);
  expect(language).toBe('zh');
  
  // 验证界面变成中文
  const header = await page.textContent('[data-testid="header"]');
  expect(header).toContain('会话');
});

test('settings panel change theme', async () => {
  await page.goto('http://localhost:7071/settings');
  await page.click('[data-testid="tab-ui"]');
  
  // 选择暖色主题
  await page.click('[data-testid="theme-warm"]');
  
  // 验证 CSS 变量变化
  const bgColor = await page.evaluate(() => {
    return getComputedStyle(document.body).backgroundColor;
  });
  expect(bgColor).toContain('rgb(255, 250, 245)'); // 暖色背景
});
```

##### 场景 16: Web 技能管理

```javascript
// test/journey/scenarios/web_skill_management.js
test('import skill from zip', async () => {
  await page.goto('http://localhost:7071/skills');
  
  // 点击导入按钮
  await page.click('[data-testid="import-skill-btn"]');
  
  // 上传 ZIP
  const fileInput = await page.$('[data-testid="skill-zip-input"]');
  await fileInput.uploadFile('test/fixtures/sample-skill.zip');
  
  // 验证导入成功
  await page.waitForSelector('[data-testid="import-success"]');
  
  // 验证技能出现在列表中
  const skillNames = await page.$$eval('[data-testid="skill-item"]', 
    els => els.map(el => el.textContent));
  expect(skillNames).toContain('sample-skill');
});

test('create new skill', async () => {
  await page.goto('http://localhost:7071/skills');
  
  // 点击创建按钮
  await page.click('[data-testid="create-skill-btn"]');
  
  // 填写表单
  await page.fill('[data-testid="skill-name"]', 'my-custom-skill');
  await page.fill('[data-testid="skill-description"]', 'A test skill');
  await page.fill('[data-testid="skill-content"]', '## Instructions\nDo something');
  
  // 提交
  await page.click('[data-testid="submit-btn"]');
  
  // 验证创建成功
  await page.waitForSelector('[data-testid="create-success"]');
});
```

##### 场景 17: Web 扩展市场

```javascript
// test/journey/scenarios/web_extension_market.js
test('browse and install extension', async () => {
  await page.goto('http://localhost:7071/extensions');
  
  // 验证扩展列表加载
  await page.waitForSelector('[data-testid="extension-list"]');
  
  // 搜索扩展
  await page.fill('[data-testid="extension-search"]', 'theme');
  
  // 点击扩展查看详情
  await page.click('[data-testid="extension-item"]:first-child');
  await page.waitForSelector('[data-testid="extension-detail"]');
  
  // 安装扩展
  await page.click('[data-testid="install-btn"]');
  await page.waitForSelector('[data-testid="install-success"]');
  
  // 验证扩展出现在已安装列表
  await page.click('[data-testid="filter-installed"]');
  const installed = await page.$$('[data-testid="extension-item"]');
  expect(installed.length).toBeGreaterThan(0);
});
```

##### 场景 19: Web 文件回收站

```javascript
// test/journey/scenarios/web_trash_restore.js
test('restore deleted file from trash', async () => {
  // 先让 Agent 删除文件
  await page.goto('http://localhost:7071/session/new');
  await page.fill('[data-testid="composer"]', '删除文件 important.txt');
  await page.press('[data-testid="composer"]', 'Enter');
  await page.waitForSelector('.message.assistant');
  
  // 进入回收站
  await page.goto('http://localhost:7071/trash');
  await page.click('[data-testid="tab-file-trash"]');
  
  // 验证文件在回收站
  await page.waitForSelector('[data-testid="trash-item"]');
  const trashItems = await page.$$eval('[data-testid="trash-item"]', 
    els => els.map(el => el.textContent));
  expect(trashItems.some(item => item.includes('important.txt'))).toBe(true);
  
  // 恢复文件
  await page.click('[data-testid="restore-btn"]:first-child');
  await page.waitForSelector('[data-testid="restore-success"]');
  
  // 验证文件恢复
  const response = await fetch('http://localhost:7071/api/files/important.txt');
  expect(response.status).toBe(200);
});
```

#### Phase 3: 进阶功能（3-4 周）

##### 场景 21: TUI 主题切换

```moonbit
// test/journey/scenarios/tui_theme_switch.mbt
fn main() {
  start_tui()
  
  // 默认主题
  assert_background_color("dark")
  
  // 切换到亮色主题
  type_text("/theme light")
  press_enter()
  wait_for_idle()
  assert_background_color("light")
  
  // 切换到暖色主题
  type_text("/theme warm")
  press_enter()
  wait_for_idle()
  assert_background_color("warm")
}
```

##### 场景 23: Web 命令面板搜索

```javascript
// test/journey/scenarios/web_command_palette.js
test('command palette search sessions', async () => {
  await page.goto('http://localhost:7071');
  
  // 打开命令面板
  await page.keyboard.press('Control+k');
  await page.waitForSelector('[data-testid="command-palette"]');
  
  // 搜索会话
  await page.fill('[data-testid="command-input"]', 'project');
  
  // 验证搜索结果
  await page.waitForSelector('[data-testid="search-results"]');
  const results = await page.$$('[data-testid="search-result"]');
  expect(results.length).toBeGreaterThan(0);
  
  // 点击结果跳转
  await page.click('[data-testid="search-result"]:first-child');
  await page.waitForSelector('[data-testid="chat-panel"]');
});
```

##### 场景 27: CLI NDJSON 日志

```moonbit
// test/journey/scenarios/cli_ndjson_log.mbt
fn main() {
  // 使用 NDJSON 输出
  let output = run_cli("--ndjson", "--message", "hello")
  assert_exit_code(0)
  
  // 验证每行都是有效 JSON
  let lines = output.split("\n")
  for line in lines {
    if line.is_empty() { continue }
    let json = JSON.parse(line)
    assert(json.has("timestamp"))
    assert(json.has("level"))
    assert(json.has("message"))
  }
}
```

##### 场景 28: CLI Agent Profile 切换

```moonbit
// test/journey/scenarios/cli_agent_profile.mbt
fn main() {
  // 默认 coding agent
  run_cli("--message", "hello")
  assert_exit_code(0)
  
  // 切换到 custom agent
  run_cli("--agent", "creative", "--message", "hello")
  assert_exit_code(0)
  
  // 不存在的 agent，应报错
  run_cli("--agent", "nonexistent", "--message", "hello")
  assert_exit_code(1)
  assert_stderr_contains("agent profile not found")
}
```

##### 场景 30: MCP Server 模式

```moonbit
// test/journey/scenarios/cli_mcp_server.mbt
fn main() {
  // 启动 MCP server（stdio 模式）
  let process = spawn("cmd", ["mcp"])
  
  // 发送 initialize 请求
  let request = #"{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": { "name": "test", "version": "1.0" }
    }
  }#
  
  process.stdin.write(request + "\n")
  process.stdin.flush()
  
  // 读取响应
  let response = process.stdout.read_line()
  let json = JSON.parse(response)
  assert(json["id"] == 1)
  assert(json["result"].has("serverInfo"))
  
  process.kill()
}
```

##### 场景 31: Hook 执行

```moonbit
// test/journey/scenarios/cli_hook_execution.mbt
fn main() {
  // 创建自定义 hook
  write_file("hooks/pre-tool.json", #"{
    "event": "pre_tool",
    "command": "echo 'Hook triggered' >> hook.log"
  }"#)
  
  // 运行 CLI，指定 hooks 目录
  run_cli("--hooks-dir", "hooks", "--message", "创建文件 test.txt")
  assert_exit_code(0)
  
  // 验证 hook 被执行
  assert_file_exists("hook.log")
  assert_file_content_contains("hook.log", "Hook triggered")
}
```

### 2.3 测试数据管理

**策略**: 每个旅程独立沙箱，测试数据按需生成

```
test/
├── fixtures/              # 静态测试数据
│   ├── red.png           # 1x1 红色 PNG
│   ├── sample-skill.zip  # 示例技能包
│   └── test-documents/   # 测试文档
├── journey/
│   └── scenarios/        # 旅程场景代码
└── sandbox/              # 运行时沙箱（gitignore）
    └── <journey-id>/     # 每个旅程独立工作目录
        ├── .mbopenclacky/
        ├── sessions/
        └── workspace/
```

### 2.4 断言库扩展

当前 journey 框架已有基础断言，需扩展：

```moonbit
// test/journey/assertions.mbt

// 文件断言
fn assert_file_exists(path: String)
fn assert_file_not_exists(path: String)
fn assert_file_content(path: String, expected: String)
fn assert_file_content_contains(path: String, substring: String)

// UI 断言（TUI）
fn assert_background_color(theme: String)
fn assert_output_contains(text: String)
fn assert_status_bar_contains(text: String)

// Web 断言（浏览器自动化）
fn assert_element_visible(selector: String)
fn assert_element_text(selector: String, expected: String)
fn assert_css_variable(name: String, value: String)

// 网络断言
fn assert_http_status(url: String, status: Int)
fn assert_http_body_contains(url: String, substring: String)
```

---

## 三、测试体系优化方案

### 3.1 引入浏览器自动化

**现状**: Web eval 只测试 API，不测试 UI 交互  
**问题**: 无法发现前端 bug（如按钮不工作、样式错乱）  
**方案**: 引入 Playwright 驱动真实浏览器

**实施步骤**:
1. 安装 Playwright (`npm install -D @playwright/test`)
2. 创建 `test/web-e2e/` 目录
3. 编写测试脚本（见上述 Phase 1-3）
4. 集成到 CI（GitHub Actions 已支持 Playwright）

**目录结构**:
```
test/
├── web-e2e/
│   ├── playwright.config.ts
│   ├── scenarios/
│   │   ├── multi-turn.spec.ts
│   │   ├── model-switch.spec.ts
│   │   └── ...
│   └── fixtures/
│       └── test-data.ts
```

**CI 集成**:
```yaml
# .github/workflows/web-e2e.yml
name: Web E2E Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: moonbitlang/setup@v1
      - uses: actions/setup-node@v4
      
      - name: Build binary
        run: moon build --target native --release cmd
        
      - name: Install Playwright
        run: npm ci
        working-directory: test/web-e2e
        
      - name: Start server
        run: |
          ./cmd.exe server --port 7071 &
          echo $! > server.pid
          
      - name: Run E2E tests
        run: npm test
        working-directory: test/web-e2e
        
      - name: Stop server
        if: always()
        run: kill $(cat server.pid)
```

### 3.2 场景配置化（DSL）

**现状**: 每个旅程需手写 MoonBit 代码  
**问题**: 编写成本高，非开发者难以上手  
**方案**: 引入 JSON/YAML DSL 定义场景

**DSL 示例**:
```yaml
# test/scenarios/dsl/multi-turn.yaml
name: multi-turn-conversation
description: "Verify agent maintains context across 3 turns"
interface: cli
setup:
  - message: "我的名字是 Alice"
    expect:
      exit_code: 0
  - message: "我叫什么名字？"
    continue: true
    expect:
      exit_code: 0
      stdout_contains: "Alice"
  - message: "再重复一次"
    continue: true
    expect:
      exit_code: 0
      stdout_contains: "Alice"
```

**执行器**:
```moonbit
// test/scenarios/dsl_runner.mbt
fn run_scenario(path: String) -> Result[Unit, Error] {
  let yaml = read_file(path)?
  let scenario = YAML.parse(yaml)?
  
  for step in scenario.setup {
    let args = if step.continue {
      ["--continue", "--message", step.message]
    } else {
      ["--message", step.message]
    }
    
    let result = run_cli(args)?
    
    if let Some(code) = step.expect.exit_code {
      assert_eq(result.exit_code, code)?
    }
    
    if let Some(text) = step.expect.stdout_contains {
      assert_contains(result.stdout, text)?
    }
  }
  
  Ok(())
}
```

**优势**:
- 非开发者可编写场景
- 场景可读性高
- 易于批量生成

**劣势**:
- 需要实现 DSL 解析器
- 复杂场景表达力不足

**建议**: 先用 MoonBit 代码实现 Phase 1-2，验证价值后再考虑 DSL。

### 3.3 测试覆盖率可视化

**现状**: 不知道哪些功能已测试、哪些未测试  
**方案**: 生成覆盖率报告

**实现**:
```bash
# 生成场景覆盖矩阵
./cmd.exe eval --offline --repo . --format json | \
  jq '.scenarios[] | {name, status}' > coverage.json

# 生成 HTML 报告
python scripts/coverage_report.py coverage.json
```

**报告示例**:
```
┌─────────────────────────┬────────┬────────┬────────┐
│ 功能模块                │ 总场景 │ 已覆盖 │ 覆盖率 │
├─────────────────────────┼────────┼────────┼────────┤
│ CLI 主流程              │      6 │      5 │    83% │
│ TUI 主流程              │      6 │      3 │    50% │
│ Web 主流程              │      8 │      4 │    50% │
│ 附件/图片               │      2 │      0 │     0% │
│ Skill 调用              │      1 │      0 │     0% │
│ 错误恢复                │      1 │      1 │   100% │
│ 进阶功能                │     15 │      2 │    13% │
└─────────────────────────┴────────┴────────┴────────┘
```

### 3.4 失败分析与自动修复建议

**现状**: 旅程失败后需人工分析原因  
**方案**: AI 辅助分析失败日志，提供修复建议

**实现**:
```moonbit
// test/journey/failure_analyzer.mbt
fn analyze_failure(journey_id: String, evidence: Evidence) -> String {
  let log = read_file(evidence.log_path)
  let screenshot = evidence.screenshot_path
  
  // 调用 LLM 分析
  let prompt = #"""
  你是一个测试专家。以下是一个 E2E 测试失败的日志：
  
  旅程 ID: {{journey_id}}
  日志内容:
  {{log}}
  
  请分析：
  1. 失败的根本原因
  2. 是产品 bug 还是测试脚本问题
  3. 建议的修复方案
  """#
  
  let response = call_llm(prompt, images=[screenshot])
  response
}
```

**集成**:
```bash
# 旅程失败后自动分析
./cmd.exe journey --repo . 2>&1 | \
  ./cmd.exe analyze-failures --input -
```

### 3.5 性能基线与回归检测

**现状**: 不关注性能，只关注功能正确性  
**方案**: 记录关键指标，检测性能回归

**指标**:
- 启动时间（CLI/TUI/Web）
- 首次响应时间（TTFT）
- 内存占用
- 会话文件大小

**实现**:
```moonbit
// test/journey/performance_baseline.mbt
fn measure_startup() -> Duration {
  let start = sys.now()
  run_cli("--version")
  sys.now() - start
}

fn measure_ttft() -> Duration {
  let start = sys.now()
  run_cli("--message", "hello")
  // 解析 NDJSON 日志，找到第一个 token
  let log = read_file("session.jsonl")
  let first_token = log.lines()
    .find(|l| l.contains("token_delta"))
  sys.now() - start
}
```

**基线文件**:
```json
// test/journey/performance_baseline.json
{
  "cli_startup_ms": 150,
  "tui_startup_ms": 300,
  "web_startup_ms": 500,
  "ttft_ms": 1000,
  "memory_mb": 50
}
```

**CI 集成**:
```yaml
- name: Performance regression check
  run: |
    ./cmd.exe journey --repo . --measure-performance
    python scripts/check_performance.py
```

---

## 四、实施路线图

### Phase 0: 基础设施准备（1 周）

- [ ] 安装 Playwright，创建 `test/web-e2e/` 目录
- [ ] 扩展断言库（文件断言、UI 断言）
- [ ] 创建测试数据目录 `test/fixtures/`
- [ ] 编写 DSL 原型（可选）

### Phase 1: 补齐第一梯队（2 周）

**Week 1**:
- [ ] 场景 8: 多轮对话（CLI + TUI + Web）
- [ ] 场景 9: 模型切换（CLI + Web）
- [ ] 场景 10: 文件附件（CLI + Web）

**Week 2**:
- [ ] 场景 11: 图片理解（CLI + Web）
- [ ] 验证所有新场景通过
- [ ] 生成覆盖率报告，验证达到 80%+

### Phase 2: 补齐第二梯队（3 周）

**Week 3**:
- [ ] 场景 12: Skill 调用（TUI + Web）
- [ ] 场景 14: TUI 撤销
- [ ] 场景 15: Web 设置面板

**Week 4**:
- [ ] 场景 16: Web 技能管理
- [ ] 场景 17: Web 扩展市场
- [ ] 场景 19: Web 文件回收站

**Week 5**:
- [ ] 场景 20: 错误恢复（全接口）
- [ ] 集成到 CI
- [ ] 编写文档

### Phase 3: 进阶功能（4 周）

**Week 6-7**:
- [ ] 场景 21-25: TUI 主题、多行输入、Web 搜索、Profile、Billing

**Week 8-9**:
- [ ] 场景 26-33: CLI NDJSON、Agent Profile、MCP、Hook、Patch

**Week 10**:
- [ ] 场景 34-35: Web 会话重命名、TUI 长输出滚动
- [ ] 性能基线建立
- [ ] 失败分析工具原型

### Phase 4: 优化与自动化（持续）

- [ ] 场景配置化 DSL（如验证有价值）
- [ ] 覆盖率可视化仪表板
- [ ] AI 辅助失败分析
- [ ] 性能回归自动检测
- [ ] 测试数据自动生成

---

## 五、预期成果

### 量化指标

| 指标 | 当前 | 目标 | 提升 |
|------|------|------|------|
| **核心场景覆盖率** | 40% (14/35) | 90%+ (32/35) | +50% |
| **Web UI 覆盖率** | 15% (4/26) | 85%+ (22/26) | +70% |
| **TUI 覆盖率** | 50% (3/6) | 100% (6/6) | +50% |
| **多轮对话覆盖** | 1/3 接口 | 3/3 接口 | +200% |
| **缺陷发现率** | ~5 bugs/月 | ~15 bugs/月 | +200% |

### 质量收益

1. **早期发现问题** — 每次提交自动运行，bug 在 24h 内发现
2. **回归保护** — 修复的 bug 不会再次出现
3. **文档价值** — 测试场景即活文档，展示系统能力
4. **重构信心** — 大规模重构后有测试保障

### 技术债务清理

通过测试发现并修复的潜在问题：
- 多轮对话上下文丢失
- 模型切换后状态不一致
- 文件附件处理异常
- Web UI 交互失败
- 错误恢复不完整

---

## 六、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **浏览器自动化不稳定** | Web 测试失败率高 | 使用 Playwright 最佳实践，添加重试逻辑 |
| **测试执行时间长** | CI 变慢，开发者体验差 | 分层执行：关键路径每次提交，完整套件每日 |
| **测试数据管理复杂** | 测试间相互干扰 | 每个旅程独立沙箱，测试后清理 |
| **维护成本高** | 测试代码成为负担 | 场景配置化，抽象通用断言 |
| **Mock LLM 不真实** | 测试通过但真实环境失败 | 定期运行真实 LLM 集成测试 |

---

## 七、附录

### A. 相关文档

- [Journey E2E Runner Spec](../../specs/draft/2026-09-23_journey-e2e-runner.md)
- [测试体系（TUI/Web 层）](../../docs/testing.md)
- [Playwright 文档](https://playwright.dev/)

### B. 工具清单

- **Playwright** — Web 浏览器自动化
- **MoonBit Test** — 单元测试和集成测试
- **Journey Runner** — E2E 旅程测试
- **Eval Framework** — 界面组件测试

### C. 联系方式

如有问题或建议，请联系测试团队。

---

**文档版本**: 1.0  
**最后更新**: 2026-10-10  
**维护者**: AI Agent