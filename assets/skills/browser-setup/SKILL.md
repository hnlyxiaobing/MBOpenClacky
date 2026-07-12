
---
name: browser-setup
description: |
  Configure the browser tool for MBOpenClacky. Guides the user through Chrome or Edge setup,
  verifies the connection, and writes ~/.mbopenclacky/browser.yml.
  Supports macOS, Linux, and Windows (Chrome/Edge via remote debugging).
  Trigger on: "browser setup", "setup browser", "配置浏览器", "browser config",
  "browser doctor".
  Subcommands: setup, doctor.
argument_hint: "[setup | doctor]"
allowed_tools:
  - Terminal
  - FileReader
  - Write
  - browser
user_invocable: true
category: management
---

# Browser Setup Skill

Configure the browser tool for MBOpenClacky. Config is stored at `~/.mbopenclacky/browser.yml`.

## Region-Aware Download Links

Whenever you show the user a link to download or upgrade Chrome/Edge, pick the right one for their region instead of always using google.com.

Treat the user as **in China** when any of these are true:
- The user is talking to you in Chinese
- The system locale is Chinese
- The user is on Windows with Chinese region settings

Use these links accordingly:

| Region | Chrome | Edge |
|--------|--------|------|
| China | https://www.google.cn/chrome/ | https://www.microsoft.com/zh-cn/edge |
| Global | https://www.google.com/chrome/ | https://www.microsoft.com/edge |

When in doubt, show **both** lines (label them "China:" and "Global:") so the user can pick.

## Command Parsing

| User says | Subcommand |
|-----------|------------|
| `browser setup`, `配置浏览器`, `setup browser` | setup |
| `browser doctor` | doctor |

If no subcommand is clear, default to `setup`.

---

## `setup`

**Core Strategy**: Progressive validation with clear next steps at each failure point.

### Step 1 — Ensure Node.js is installed

Check Node.js version:
```bash
node --version 2>/dev/null
```

Parse the version. If Node.js is missing or version &lt; 20:

Tell the user to install Node.js from https://nodejs.org

If Node.js is available, proceed to Step 2.

### Step 2 — Ensure chrome-devtools-mcp is installed

Check if installed:
```bash
chrome-devtools-mcp --version 2>/dev/null
```

If found and exits 0 → skip to Step 3.

If missing, tell the user to install it:
```bash
npm install -g chrome-devtools-mcp@latest
```

Wait for user confirmation, then verify installation.

### Step 3 — Verify Chrome/Edge is running with remote debugging

First check if any browser is running with remote debugging by testing the CDP port:
- Try `http://localhost:9222/json/version` first

If that's reachable, great! If not:

Guide the user to enable remote debugging:

**On Windows**:
- Tell user to open Chrome/Edge with the flag: `--remote-debugging-port=9222`
- Or create a shortcut with that flag added
- Example: `chrome.exe --remote-debugging-port=9222`

**On macOS**:
```bash
open -a "Google Chrome" --args --remote-debugging-port=9222
```

**On Linux**:
```bash
google-chrome --remote-debugging-port=9222 &
```

Then tell the user:
- Visit `chrome://inspect/#remote-debugging` or `edge://inspect/#remote-debugging`
- Click "Allow remote debugging for this browser instance"

Wait for user confirmation, then retry the connection.

### Step 4 — Get and verify browser version

Now that connection is established, get the version via CDP:

Fetch `http://localhost:9222/json/version` and parse the user agent string.

Parse the version number:
- **version &gt;= 120** → Excellent, proceed
- **version 100-119** → Show warning but proceed:
  &gt; ⚠️ Your browser version is v${VERSION}. Version 120+ is recommended for best compatibility.
  &gt; Continuing anyway...
- **version &lt; 100 or "unknown"** → Stop:
  &gt; ❌ Browser version v${VERSION} is too old. Please upgrade Chrome or Edge to v120+.
  &gt;
  &gt; Use the download link from the **Region-Aware Download Links** section above
  &gt; (pick `China` or `Global` based on the user's region).
  &gt;
  &gt; After upgrading, run `browser-setup` again.

### Step 5 — Save configuration file

Write `~/.mbopenclacky/browser.yml`:

```yaml
browser:
  path: "<detected_browser_path>"
  debugging_port: 9222
  headless: false
  user_data_dir: "~/.mbopenclacky/browser-profile"
```

If the file already exists, read it first and merge changes.

### Step 6 — Done

&gt; ✅ Browser setup complete!
&gt;
&gt; **Chrome/Edge v${VERSION}** is connected and ready to use.
&gt;
&gt; You can now use browser automation features. Try asking me to:
&gt; - "Open google.com in the browser"
&gt; - "Take a screenshot"
&gt; - "Fill out a form on this page"

---

## `doctor`

**Core Strategy**: Diagnose don't fix. Check each component and report status.

This is a **diagnostic tool**, not a repair tool. It will check each component and tell you what's wrong, but won't automatically fix things.

### Diagnostic Steps

Run all checks **before** showing results. Then show a summary report.

#### 1. Check Config File

Check if `~/.mbopenclacky/browser.yml` exists:
```bash
test -f ~/.mbopenclacky/browser.yml && cat ~/.mbopenclacky/browser.yml
```

Parse the result:
- **File missing** → ❌ Not configured
- **File exists, `enabled: false`** → ⏸️ Disabled
- **File exists, `enabled: true`** → ✅ Enabled

#### 2. Check Node.js

```bash
node --version 2>/dev/null
```

- **Not found** → ❌ Node.js not installed
- **Version &lt; 20** → ❌ Node.js too old (need 20+)
- **Version &gt;= 20** → ✅ Node.js OK

#### 3. Check chrome-devtools-mcp

```bash
chrome-devtools-mcp --version 2>/dev/null
```

- **Not found** → ❌ Not installed
- **Found** → ✅ Installed (version: ...)

#### 4. Check CDP Port

```bash
curl -s http://localhost:9222/json/version
```

- **Failed** → ❌ Browser remote debugging not available on port 9222
- **Success** → ✅ CDP port is accessible

#### 5. Check Chrome Version

Only if step 4 succeeded, extract browser version from CDP response.

- **version &gt;= 120** → ✅ Excellent
- **version 100-119** → ⚠️ Acceptable but upgrade recommended
- **version &lt; 100 or unknown** → ❌ Too old

### Report Format

Show results in a clean table:

```
Browser Doctor — Diagnostic Report
═══════════════════════════════════════════════════════════════

Configuration
  [✅] Config file found (~/.mbopenclacky/browser.yml)
  [✅] Browser tool enabled

Dependencies
  [✅] Node.js v22.1.0
  [✅] chrome-devtools-mcp installed (v1.2.3)

Connection
  [✅] CDP port 9222 accessible
  [✅] Chrome connected (3 tabs open)
  [✅] Chrome v125

═══════════════════════════════════════════════════════════════
✅ All systems operational!
```

If there are any ❌ or ⚠️ items, show them first in a **Problems Found** section, followed by specific **Recommended Actions**.
