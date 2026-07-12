
---
name: extend-openclacky
description: |
  Customize, fix, override or extend MBOpenClacky itself — change a built-in tool's behavior, intercept/audit/block tool calls,
  plug in a new IM channel, or add UI to the Web UI.
  Trigger on "patch openclacky", "block dangerous commands", "audit tool use", "add slack channel", "extend the web ui",
  "改 openclacky 内置", "拦截工具调用", "扩展 web 界面".
  Do NOT trigger for ordinary feature work in the user's own project that doesn't touch MBOpenClacky.
user_invocable: true
category: development
allowed_tools:
  - FileReader
  - Write
  - Edit
  - Grep
  - Terminal
---

# Extending MBOpenClacky

MBOpenClacky provides several extension points for customization.

---

## Extension Mechanisms

### 1. Custom Skills (Easiest)

Create new skills in:
- Project-level: `.mbopenclacky/skills/&lt;skill-name&gt;/SKILL.md`
- User-level: `~/.mbopenclacky/skills/&lt;skill-name&gt;/SKILL.md`

This is the recommended way to extend functionality for most use cases.

---

### 2. Custom Tools (Advanced)

MBOpenClacky's tool system is built in MoonBit. To add a new tool:

1. Create a new `.mbt` file in `lib/tool/`
2. Implement the `Tool` trait
3. Register it in the tool registry
4. Recompile MBOpenClacky

Tool trait structure:
- `name: String` — unique identifier
- `description: String` — what it does
- `execute(params: Json) -> Result&lt;Json, Error&gt;` — the implementation

---

### 3. Web UI Customization

The Web UI is in `assets/web/`. Customize by:

1. **Adding new panels**: Create new components in `assets/web/components/`
2. **Adding API endpoints**: Implement handlers in `lib/web/handlers/`
3. **Custom styling**: Modify `assets/web/css/` or add new CSS files

The Web UI uses a simple component system with server-side rendering.

---

### 4. Channel Adapters (IM Platforms)

Add support for a new IM platform:

1. Create a new file in `lib/channel/adapters/`
2. Implement the `ChannelAdapter` trait
3. Add it to the `AnyChannelAdapter` enum
4. Update the channel manager

Required methods:
- `name() -> String`
- `start(config: Json) -> Result&lt;(), Error&gt;`
- `send_message(chat_id: String, text: String) -> Result&lt;(), Error&gt;`
- `receive_messages(callback: fn(msg: Message) -> ()) -> ()`

---

### 5. Hook System (Event Interception)

MBOpenClacky has a hook system for intercepting events:

Create hooks in:
- Project-level: `.mbopenclacky/hooks/`
- User-level: `~/.mbopenclacky/hooks/`

Hook types:
- `pre-tool-call` — before a tool executes
- `post-tool-call` — after a tool executes
- `pre-llm-call` — before calling the LLM
- `post-llm-call` — after calling the LLM
- `on-message` — when a message is received
- `on-startup` — when the agent starts

Example hook structure:
```yaml
name: "my-hook"
description: "What this hook does"
events: ["pre-tool-call"]
enabled: true
```

---

## Flow for Creating an Extension

1. **Identify** what the user wants to do and pick the right extension mechanism
2. **Explore** the relevant code files in the MBOpenClacky repository
3. **Create** the extension file(s) in the appropriate location
4. **Test** the extension works as expected
5. **Document** what was done and how to use it

---

## Common Extension Use Cases

### Use Case 1: Block Dangerous Tools

Create a `pre-tool-call` hook that checks the tool name and parameters, and blocks execution if it matches a dangerous pattern.

### Use Case 2: Audit All Tool Usage

Create a `pre-tool-call` and `post-tool-call` hook that logs every tool execution to a file or external service.

### Use Case 3: Add a New IM Platform

Implement a new `ChannelAdapter` for the platform.

### Use Case 4: Custom Web UI Panel

Add a new API endpoint and a corresponding Web UI component.

---

## Important Notes

- **Backward compatibility**: Try to maintain compatibility when extending
- **Documentation**: Always document what your extension does
- **Testing**: Test your extension thoroughly before using in production
- **MoonBit knowledge**: Building custom tools/channels requires familiarity with MoonBit
