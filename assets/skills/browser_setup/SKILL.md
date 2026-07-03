---
name: browser_setup
description: "Guide user through browser automation setup"
version: "1.0.0"
user_invocable: true
category: management
allowed_tools: [Terminal, FileReader, Write]
argument_hint: "[--auto]"
---

# Browser Setup

## Purpose

Detect installed browsers, configure remote debugging on port 9222, generate the `~/.mbopenclacky/browser.yml` configuration file, verify CDP (Chrome DevTools Protocol) connectivity, and handle headless mode settings.

## Instructions

1. **Detect Installed Browsers**: Check whether Google Chrome or Microsoft Edge is installed on the system.
   - On Windows, check registry paths and common install locations (`C:\Program Files\Google\Chrome\Application\chrome.exe`, `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`)
   - Report which browsers were found and their versions

2. **Configure Remote Debugging Port**: Set up the browser to launch with remote debugging enabled on port 9222.
   - Generate the launch command: `<browser_path> --remote-debugging-port=9222`
   - If `--auto` flag is provided, skip interactive prompts and use defaults (prefer Chrome, fall back to Edge)

3. **Generate Configuration File**: Write `~/.mbopenclacky/browser.yml` with the following structure:
   ```yaml
   browser:
     path: "<detected_browser_path>"
     debugging_port: 9222
     headless: false
     user_data_dir: "~/.mbopenclacky/browser-profile"
   ```
   - If the file already exists, read it first and merge changes

4. **Verify CDP Connection**: Launch the browser with debugging enabled and test the CDP endpoint.
   - Fetch `http://localhost:9222/json/version` to confirm connectivity
   - Report the browser version and WebSocket debugger URL

5. **Configure Headless Mode**: Ask the user whether to enable headless mode.
   - If headless is chosen, update the config with `headless: true` and add `--headless=new` to the launch flags

## Output Format

- Detected browsers list with paths and versions
- Configuration file path and contents
- CDP connection status (success/failure with details)
- Final launch command for the selected browser
