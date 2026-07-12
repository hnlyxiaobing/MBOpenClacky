
---
name: mcp-manager
description: |
  Manage MCP (Model Context Protocol) servers for MBOpenClacky: add, list, probe, remove,
  reconfigure. Edits ~/.mbopenclacky/mcp.json so the user never writes JSON by hand.
  Trigger on: add mcp, install mcp, setup mcp, configure mcp, mcp list, mcp remove,
  mcp probe, mcp reconfigure.
user_invocable: true
category: management
allowed_tools:
  - Terminal
  - FileReader
  - Write
  - Edit
  - Grep
---

# MCP Manager Skill

Manage MCP servers for MBOpenClacky. The user's MCP configuration lives at
`~/.mbopenclacky/mcp.json` (the same format Claude Desktop and Cursor use). You never
ask the user to edit it by hand — you do it for them.

---

## Command Parsing

| User says | Subcommand |
|-----------|------------|
| `add mcp`, `install mcp`, `connect &lt;something&gt;`, "I want clacky to read my files / access github / query my db / search the web" | add |
| `mcp list`, `mcp status`, "what mcps do I have" | list |
| `mcp probe &lt;name&gt;`, "what tools does &lt;name&gt; have" | probe |
| `mcp remove &lt;name&gt;`, `mcp delete &lt;name&gt;` | remove |
| `mcp reconfigure &lt;name&gt;`, `mcp fix &lt;name&gt;` | reconfigure |

If the intent is unclear, default to **`add`** — it's the most common ask.

---

## Known-Good Server Catalog

When the user describes what they want, match it to one of these and propose it.
Each entry: package, what it does, required params, recommended description.

### 1. `filesystem` — read/write local files
- **When**: "read my files", "access my desktop", "browse my code"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-filesystem", "&lt;ABSOLUTE_PATH&gt;"]`
- **Required**: absolute directory path (ask user; default to `~/Documents`)
- **Tools**: read_file, write_file, list_directory, search_files, etc.

### 2. `github` — GitHub repos, issues, PRs
- **When**: "access github", "manage my repos", "read my issues"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-github"]`
- **Env**: `{ "GITHUB_PERSONAL_ACCESS_TOKEN": "&lt;TOKEN&gt;" }`
- **Required**: PAT from https://github.com/settings/tokens (recommend `repo` scope)

### 3. `fetch` — fetch HTTP URLs as markdown
- **When**: "fetch web pages", "read articles by url"
- **Command**: `npx` (or `uvx` if Python preferred)
- **Args**: `["-y", "@modelcontextprotocol/server-fetch"]`
- **Required**: nothing

### 4. `memory` — persistent knowledge graph
- **When**: "remember things across sessions", "give clacky long-term memory"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-memory"]`
- **Required**: nothing

### 5. `postgres` — query a Postgres database
- **When**: "query my database", "connect to postgres"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-postgres", "&lt;DATABASE_URL&gt;"]`
- **Required**: DATABASE_URL like `postgresql://user:pass@host:5432/dbname`

### 6. `slack` — Slack messages
- **When**: "read slack", "send slack messages"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-slack"]`
- **Env**: `{ "SLACK_BOT_TOKEN": "xoxb-...", "SLACK_TEAM_ID": "T..." }`
- **Required**: bot token and team id (Slack admin → app config)

### 7. `brave-search` — web search via Brave API
- **When**: "search the web", "give clacky search"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-brave-search"]`
- **Env**: `{ "BRAVE_API_KEY": "&lt;KEY&gt;" }`
- **Required**: free API key from https://api.search.brave.com/

### 8. `puppeteer` — browser automation
- **When**: "automate the browser", "scrape with js"
- **Command**: `npx`
- **Args**: `["-y", "@modelcontextprotocol/server-puppeteer"]`
- **Required**: nothing (downloads Chromium on first run)

### Custom (anything else)
If the user names a package or path you don't recognize, take the spec from them
verbatim and pass it through. Always confirm `command`, `args`, and `env` back
in plain language before saving.

### Remote / HTTP servers (streamable-http)
Some MCP servers are hosted services and don't ship as a CLI — you connect over
HTTPS instead. **Trigger when** the user gives you a URL ending in `/mcp`,
`/sse`, or hosted on `*.mcp.*` / `mcp.*.app`, or says "the server is at
https://...".

- **Type**: `http`
- **Required**: `url` (the streamable-http endpoint)
- **Optional**: `headers` — typically `{ "Authorization": "Bearer &lt;token&gt;" }`

When the user pastes a URL, ask:
1. What service is this? (so you can pick a `name` and `description`)
2. Does it need an authorization header? If yes, paste the token.

---

## Subcommand: `add` — the primary flow

Goal: the user describes what they want, you produce a working MCP entry +
confirm it works. Keep questions minimal.

### Step 1 — Identify intent

- If the user's first message already names a server (e.g. "add filesystem"),
  pick that catalog entry directly.
- Otherwise, ask **one** open question: "What would you like MBOpenClacky to
  be able to do? (e.g. read your files, access GitHub, search the web)"
- Match their answer to the catalog. If multiple match, present 2-3 options
  with one-line descriptions and let them pick.

### Step 2 — Environment preflight

Before asking for parameters, check the runtime is installed:

```bash
# For npx-based servers
which npx >/dev/null 2>&1 || echo "MISSING_NPX"

# For uvx-based servers
which uvx >/dev/null 2>&1 || echo "MISSING_UVX"
```

If missing, tell the user how to install (`brew install node` for npx,
`brew install uv` for uvx) and stop. Do not proceed.

### Step 3 — Collect parameters

Ask only for the **business-meaningful** params from the catalog entry:
- For `filesystem`: which directory? Default offer: `~/Documents`. Resolve `~`
  to an absolute path before saving.
- For `github`/`brave-search`/`slack`: tell them where to get the token, then
  ask them to paste it.
- For `postgres`: ask for the connection URL.

Never invent values. If you don't have a sensible default, ask.

### Step 4 — Confirm

Show the user the spec you're about to save, in plain language:

> I'll add a server called **filesystem** that runs `npx -y @modelcontextprotocol/server-filesystem /Users/me/Documents`. It'll let me read and write files in your Documents folder. OK?

For secrets (tokens, passwords), echo only the last 4 chars: `***...abcd`.

### Step 5 — Save to mcp.json

Write to `~/.mbopenclacky/mcp.json`:

For stdio:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"],
      "description": "Read/write files in ~/Documents"
    }
  }
}
```

For http:
```json
{
  "mcpServers": {
    "linear": {
      "url": "https://mcp.linear.app/sse",
      "headers": { "Authorization": "Bearer lin_api_xxx" },
      "description": "Linear issues and projects"
    }
  }
}
```

If the file already exists, read it first, add the new server, and write it back.

If the response has issues, show the error and ask the user how to proceed (retry, edit, abort).

### Step 6 — Probe

Immediately verify the server starts and exposes tools.

Tell the user: "Probing the server now — this may take a moment..."

Then tell them to test it via the normal agent flow or WebUI.

### Step 7 — Hint at next steps

End with a one-line nudge: how the user can use the new MCP next. Examples:
- filesystem: "Try: list the files in your Documents folder"
- github: "Try: show me my open PRs"
- fetch: "Try: fetch https://example.com and summarize"

---

## Subcommand: `list`

Read `~/.mbopenclacky/mcp.json` and show it in a clean list or table.

If no servers are configured: "No MCP servers configured yet. Run `mcp-manager add` to get started."

---

## Subcommand: `probe <name>

Tell the user that MCP probing is handled automatically by MBOpenClacky when it connects to the server. They can see available tools in the WebUI or just start using them in conversation.

---

## Subcommand: `remove <name>`

1. Confirm with the user first: "Remove **<name>**? Its tools will no longer be available to MBOpenClacky. (Y/n)"
2. On yes: read `~/.mbopenclacky/mcp.json`, remove the entry, write it back.
3. Confirm completion in one line.

---

## Subcommand: `reconfigure <name>`

1. Read current config from `~/.mbopenclacky/mcp.json` and show it back (mask secrets).
2. Ask which fields to change (path / token / args).
3. Update the entry and write back.
4. Confirm.

---

## General Rules

- **Never write directly to `~/.mbopenclacky/mcp.json` without reading it first** — always merge changes
- **Never echo full secrets** — mask all but last 4 chars of tokens/URLs
- **One question at a time** — don't dump a form on the user
- **Stop on errors** — don't proceed past a failed preflight
- **Quote real error messages** — don't paraphrase
