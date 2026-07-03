---
name: channel_manager
description: "Manage IM channel connections (Feishu/WeCom/Telegram/Discord/DingTalk/WeChat)"
version: "1.0.0"
user_invocable: true
category: management
allowed_tools: [Terminal, FileReader, Write, Edit]
argument_hint: "list | add <platform> | remove <name> | test <name>"
---

# Channel Manager

## Purpose

Manage IM channel integrations for MBOpenClacky, supporting six platforms: Feishu, WeCom (企业微信), Telegram, Discord, DingTalk, and WeChat. Allows listing, adding, testing, and removing channel connections.

## Instructions

1. **Parse the Sub-command**: Determine which operation to perform based on the argument:
   - `list` — show all configured channels
   - `add <platform>` — add a new channel for the given platform
   - `remove <name>` — remove a channel by its configured name
   - `test <name>` — test connectivity for a specific channel

2. **List Channels** (`list`):
   - Read the channel configuration from `~/.mbopenclacky/channels.yml` or the project config
   - Display each channel: name, platform, enabled status, last connected time
   - If no channels are configured, report that and suggest `add`

3. **Add a Channel** (`add <platform>`):
   - Validate the platform name against supported platforms: feishu, wecom, telegram, discord, dingtalk, wechat
   - Prompt for platform-specific credentials:
     - **Feishu**: App ID, App Secret, Verification Token, Encrypt Key
     - **WeCom**: Corp ID, Agent ID, Secret, Token, EncodingAESKey
     - **Telegram**: Bot Token (from @BotFather)
     - **Discord**: Bot Token, Application ID
     - **DingTalk**: AppKey, AppSecret, Robot Code
     - **WeChat**: AppID, AppSecret, Token, EncodingAESKey
   - Write the new channel entry to the configuration file
   - Confirm the channel was added

4. **Test a Channel** (`test <name>`):
   - Look up the channel by name in the configuration
   - Attempt a connection/ping using the platform's API:
     - Feishu/WeCom: call the token endpoint to validate credentials
     - Telegram: call `getMe` API
     - Discord: call the gateway bot endpoint
     - DingTalk: call the access token endpoint
     - WeChat: call the access token endpoint
   - Report success or failure with error details

5. **Remove a Channel** (`remove <name>`):
   - Look up the channel by name
   - Confirm removal with the user
   - Remove the entry from the configuration file
   - Report the channel was removed

## Output Format

- For `list`: table of channels (name, platform, enabled, status)
- For `add`: confirmation message with channel name and platform
- For `test`: connection result (OK/FAIL) with latency or error details
- For `remove`: confirmation of deletion
