---
name: extend-openclacky
description: Extend OpenClacky with custom skills, tools, and integrations
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [Write, FileReader, Edit, Terminal]
---

# Extend OpenClacky

## Purpose
Guide the user through creating custom extensions for MBOpenClacky — a MoonBit implementation of the openclacky AI Agent CLI. OpenClacky supports extension through SKILL.md files, custom tool implementations, and MCP (Model Context Protocol) server integrations. This skill helps you create any of these extension types.

## Instructions
1. Determine the extension type:
   - **Custom Skill**: A new SKILL.md-based skill the agent can invoke
   - **Custom Tool**: A native MoonBit tool implementing the Tool trait
   - **MCP Integration**: An external MCP server connection for additional capabilities

2. For a **Custom Skill**:
   - Create directory `assets/skills/<skill-name>/` (kebab-case name)
   - Write `SKILL.md` with proper YAML frontmatter (see format reference below)
   - Write clear Markdown instructions with Purpose, Instructions, and Output Format sections
   - List only the tools the skill actually needs in `allowed_tools`
   - Save and verify the file is properly formatted

3. For a **Custom Tool**:
   - Implement the Tool trait in `lib/tool/`
   - Register the tool in the tool registry
   - Add the tool to `moon.pkg` dependencies if needed
   - Run `moon check` to verify compilation
   - Run `moon test` to validate behavior

4. For an **MCP Integration**:
   - Verify the MCP server package is available and prerequisites are met
   - Add server configuration to the project config file
   - Test the connection and verify available tools
   - Document the integration in the skill or tool that uses it

5. Verify the extension:
   - For skills: confirm SKILL.md parses correctly with valid frontmatter
   - For tools: run `moon check` and `moon test` with no errors
   - For MCP: ping the server and confirm tool count

6. Provide testing suggestions:
   - Invoke the skill via `/skill-name` in an agent session
   - Test the tool with edge cases and error scenarios
   - Verify MCP server reconnection after restart

## Skill Directory Structure
```
assets/skills/
├── skill-creator/
│   └── SKILL.md
├── extend-openclacky/
│   └── SKILL.md
└── your-custom-skill/
    └── SKILL.md
```

Each skill lives in its own directory under `assets/skills/` and must contain a `SKILL.md` file.

## SKILL.md Format Reference
| Field | Required | Description |
|---|---|---|
| `name` | Yes | Kebab-case skill name (e.g., `my-skill`) |
| `description` | Yes | Short description of the skill's purpose |
| `version` | No | Semantic version string (e.g., `"1.0.0"`) |
| `user_invocable` | No | Whether the user can invoke via `/skill-name` |
| `category` | No | One of: `development`, `utility`, `memory`, `management` |
| `allowed_tools` | No | List of tools the skill may use (e.g., `[Write, FileReader, Edit]`) |

## Output Format
- Extension file path (e.g., `assets/skills/my-skill/SKILL.md`)
- Extension type and metadata summary (name, category, tools)
- Invocation command (e.g., `/my-skill`)
- Verification result (frontmatter valid, compilation passed, or connection OK)
- Testing suggestions for the new extension
