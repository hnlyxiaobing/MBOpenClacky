---
name: channel-manager
description: |
  Configure IM platform channels (Feishu, WeCom, Weixin, Discord, Telegram, DingTalk) for MBOpenClacky.
  Uses browser automation for navigation; guides the user to paste credentials and perform UI steps.
  Trigger on: "channel setup", "setup feishu", "setup wecom", "setup weixin", "setup wechat", "setup discord", "setup telegram", "setup dingtalk",
  "channel config", "channel status", "channel enable", "channel disable", "channel reconfigure", "channel doctor",
  "send message to weixin", "send message to feishu", "send message to wecom", "send message to discord", "send message to telegram", "send message to dingtalk".
  Subcommands: setup, status, enable &lt;platform&gt;, disable &lt;platform&gt;, reconfigure, doctor, send &lt;platform&gt; &lt;message&gt;.
argument_hint: "[setup | status | enable &lt;platform&gt; | disable &lt;platform&gt; | reconfigure | doctor | send &lt;platform&gt; &lt;message&gt;]"
allowed_tools:
  - Terminal
  - FileReader
  - Write
  - Edit
  - AskFollowupQuestion
  - Glob
  - browser
user_invocable: true
category: management
---

# Channel Manager Skill

Configure IM platform channels for MBOpenClacky.

## Configuration file (single source of truth)

All channel configuration lives in **one** file, read by the runtime at server
startup and re-applied whenever the web panel changes it:

```
~/.mbopenclacky/channels.json
```

Schema — platform credentials always go inside `settings`, as **strings**:

```json
{
  "channels": [
    {
      "platform": "feishu",
      "enabled": true,
      "settings": { "app_id": "cli_xxx", "app_secret": "xxx" }
    }
  ]
}
```

Rules:

- `platform` is one of `feishu`, `wecom`, `weixin`, `discord`, `telegram`, `dingtalk` (lowercase).
- `enabled` is a boolean. A disabled platform keeps its settings but is not started.
- `settings` values must be strings — numbers and booleans are ignored by the loader.
- There is **no** `channels.yml`; YAML is not parsed. Never write the YAML shape.
- Read the file, edit it, write the whole file back. Preserve other platforms.

After changing the file, the running server picks the change up when the web
panel applies it; a manually edited file takes effect on next server start.

---

## Command Parsing

| User says | Subcommand |
|-----------|------------|
| `channel setup`, `setup feishu`, `setup wecom`, `setup weixin`, `setup wechat`, `setup discord`, `setup telegram`, `setup dingtalk` | setup |
| `channel status` | status |
| `channel enable feishu/wecom/weixin/discord/telegram/dingtalk` | enable |
| `channel disable feishu/wecom/weixin/discord/telegram/dingtalk` | disable |
| `channel reconfigure` | reconfigure |
| `channel doctor` | doctor |
| `send &lt;message&gt; to weixin/feishu/wecom/discord/telegram/dingtalk` | send |

---

## `status`

Read `~/.mbopenclacky/channels.json`, or call `GET /api/channels` when a server
is running. The API returns one entry per platform:

```json
{"channels":[
  {"platform":"feishu","enabled":true,"running":true,"has_config":true,
   "has_token":true,"settings":{"app_id":"cli_xxx","has_app_secret":true}},
  {"platform":"wecom","enabled":false,"running":false,"has_config":false,
   "has_token":false,"settings":{}}
]}
```

- `has_config` — a config entry exists for the platform.
- `running` — the adapter is currently active.
- `has_token` — at least one credential is present.
- `settings` — non-secret keys verbatim; every credential key appears as
  `has_<key>` only. Credential values are **never** returned by the API.

Display the result:

```
Channel Status
─────────────────────────────────────────────────────
Platform   Enabled   Running   Details
feishu     ✅ yes    ✅ yes    app_id: cli_xxx...
wecom      ❌ no     ❌ no     (not configured)
weixin     ✅ yes    ✅ yes    has_token: true
discord    ✅ yes    ✅ yes    has_token: true
telegram   ✅ yes    ✅ yes    has_token: true
dingtalk   ✅ yes    ✅ yes    app_key: ding_xxx...
─────────────────────────────────────────────────────
```

- Feishu: show `app_id` (truncated to 12 chars)
- WeCom: show `corp_id` (truncated) when present
- Weixin / Discord / Telegram / DingTalk: show `has_token: true/false` only

If no channels are configured yet: "No channels configured yet. Run `channel-manager setup` to get started."

---

## `setup`

Ask:
&gt; Which platform would you like to connect?
&gt;
&gt; 1. Feishu (飞书)
&gt; 2. WeCom (企业微信)
&gt; 3. Weixin (微信)
&gt; 4. Discord
&gt; 5. Telegram
&gt; 6. DingTalk (钉钉)

---

### Feishu setup

#### Step 1 — Create Feishu App

1. Tell user to visit https://open.feishu.cn/
2. Go to "App Console" → "Create App"
3. Fill in app name and description
4. Click "Create"

#### Step 2 — Get Credentials

1. In the app settings, go to "Credentials &amp; Basic Info"
2. Copy the **App ID** and **App Secret**
3. Ask user to paste them here

#### Step 3 — Configure Permissions

1. Go to "Permissions"
2. Add necessary scopes:
   - `im:message` (send/receive messages)
   - `im:chat` (manage chats)
   - `contact:user.base` (read user info)
3. Click "Apply for Permissions"

#### Step 4 — Enable Features

1. Go to "Features"
2. Enable "Bot"
3. Configure bot name and avatar

#### Step 5 — Publish App

1. Go to "Release"
2. Click "Create Version"
3. Fill in version info
4. Submit for review (or use "Test Version" for personal use)

#### Step 6 — Save Configuration

Add this entry to `~/.mbopenclacky/channels.json`:

```json
{
  "platform": "feishu",
  "enabled": true,
  "settings": { "app_id": "<app_id>", "app_secret": "<app_secret>" }
}
```

`bot_id` + `bot_secret` are accepted instead of `app_id` + `app_secret`.
`webhook_url` is optional.

On success: "✅ Feishu channel configured! You can now chat with the assistant via Feishu."

---

### WeCom setup

1. Guide user to visit https://work.weixin.qq.com/wework_admin/frame
2. Go to "App Management" → "Create App"
3. Fill in app name and description, upload avatar
4. Click "Create"
5. In the app settings, copy the **AgentId**, **Secret**, and **CorpID**
6. Ask user to paste them here
7. Under "Developer Interface", configure the receiving server if needed
8. Save the entry:

```json
{
  "platform": "wecom",
  "enabled": true,
  "settings": {
    "corp_id": "<corp_id>",
    "agent_id": "<agent_id>",
    "secret": "<secret>",
    "token": "<token>",
    "encoding_aes_key": "<encoding_aes_key>"
  }
}
```

`token` and `encoding_aes_key` are required only for receiving messages.
`api_base` is an optional override.

On success: "✅ WeCom channel configured! You can now chat with the assistant via WeCom."

---

### Weixin setup (Personal WeChat via iLink or similar)

Weixin setup varies by the integration method. Guide user through their chosen method:

1. Ask which integration method they want to use:
   - iLink (personal WeChat bot)
   - WxBot
   - Other custom method

2. Follow the instructions for their chosen method
3. Typically involves scanning a QR code or logging in via web
4. Save the entry (`uin` is the account identifier sent as the `X-WECHAT-UIN` header):

```json
{
  "platform": "weixin",
  "enabled": true,
  "settings": {
    "token": "<token>",
    "uin": "<uin>",
    "token_updated_at": "<epoch-milliseconds-as-a-string>"
  }
}
```

`app_id`, `app_secret`, `encoding_aes_key` and `api_base` are optional.
Write `token_updated_at` when the token is (re)issued: the web QR pairing page
polls for it to confirm the pairing completed.

On success: "✅ Weixin channel configured! You can now chat with the assistant via WeChat."

---

### Discord setup

1. Guide user to visit https://discord.com/developers/applications
2. Click "New Application", give it a name, click "Create"
3. Go to "Bot" in the left sidebar
4. Click "Add Bot" → "Yes, do it!"
5. Under "Privileged Gateway Intents", enable "Message Content Intent"
6. Click "Reset Token", copy the bot token (only shown once!)
7. Go to "OAuth2" → "URL Generator"
8. Check "bot" in scopes
9. Check permissions: "Send Messages", "Read Message History", "Read Messages/View Channels"
10. Copy the generated URL, open it in a browser, add the bot to your server
11. Ask user to paste the bot token and application ID here

Save the entry:

```json
{
  "platform": "discord",
  "enabled": true,
  "settings": { "bot_token": "<bot_token>", "application_id": "<application_id>" }
}
```

On success: "✅ Discord channel configured! You can now chat with the assistant on your Discord server."

---

### Telegram setup (Bot API)

1. Tell user to open Telegram and search for "@BotFather"
2. Start a chat, send `/newbot`
3. Follow the instructions: choose display name and username ending in `bot`
4. BotFather will give you a **bot token**
5. Ask user to paste the token here

Save the entry:

```json
{
  "platform": "telegram",
  "enabled": true,
  "settings": { "bot_token": "<bot_token>" }
}
```

The API endpoint is fixed (`https://api.telegram.org`); there is no setting for it.

Important notes:
- **Group chats**: The user must disable Privacy Mode in @BotFather first: `/mybots` → select bot → "Bot Settings" → "Group Privacy" → "Turn off"
- Then remove and re-add the bot to the group

On success: "✅ Telegram channel configured! You can now chat with the assistant on Telegram."

---

### DingTalk setup

1. Guide user to visit https://open-dingtalk.com/
2. Go to "Application Development" → "Enterprise Internal Development"
3. Click "Create Application"
4. Fill in app name and description
5. Click "Confirm"
6. In the app settings, go to "Credentials and Basic Information"
7. Copy the **AppKey** and **AppSecret**
8. Ask user to paste them here
9. Under "Development Management", configure the robot if needed

Save the entry:

```json
{
  "platform": "dingtalk",
  "enabled": true,
  "settings": { "app_key": "<app_key>", "app_secret": "<app_secret>" }
}
```

`access_token`, `secret`, `webhook_url` and `robot_code` are optional.

On success: "✅ DingTalk channel configured! You can now chat with the assistant via DingTalk."

---

## `enable`

Read `~/.mbopenclacky/channels.json`, set `"enabled": true` for the specified
platform, save the file.

Say: "✅ &lt;platform&gt; channel enabled."

---

## `disable`

Read `~/.mbopenclacky/channels.json`, set `"enabled": false` for the specified
platform, save the file.

Say: "❌ &lt;platform&gt; channel disabled."

---

## `reconfigure`

1. Show current config (mask secrets)
2. Ask which fields to update
3. Update the configuration
4. Say: "Channel reconfigured."

---

## `doctor`

Check each item and report ✅/❌ with remediation:

1. **Config file**: does `~/.mbopenclacky/channels.json` exist and parse as JSON?
2. **Schema**: is the root an object with a `channels` array, and is every entry
   `{platform, enabled, settings}` with string-valued settings? A YAML file or a
   platform-keyed map is a configuration that the runtime will not read.
3. **Required keys**: for each enabled platform, check the keys from the setup
   section above are present.
4. **Platform connectivity**: call `POST /api/channels/&lt;platform&gt;/test` when a
   server is running — it probes the real API with the stored credentials and
   returns `test_result`, `latency_ms` and the platform's own error message.
   Without a server, report that connectivity was not verified.

---

## `send`

Proactively send a message to a user via an IM channel.

### Parse the request

Extract platform and message from the user's instruction.

### Check configuration

Verify the specified platform is configured and enabled in
`~/.mbopenclacky/channels.json`.

### Send the message

Call `POST /api/channels/&lt;platform&gt;/send` with
`{"message": "...", "chat_id": "..."}`; it dispatches through the running
adapter.

### Output

- "✅ Message sent to &lt;platform&gt;." on success
- Error message with details on failure