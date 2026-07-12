
---
name: cron-task-creator
description: |
  Create, manage, and run scheduled automated tasks (cron jobs) in MBOpenClacky. Use this skill whenever the user wants to create a new automated task or cron job, set up recurring automation, schedule something to run daily/weekly/hourly, view all scheduled tasks, edit an existing task prompt or cron schedule, enable or disable a task, delete a task, check task run history or logs, or run a task immediately.
  Trigger on phrases like cron, scheduled task, run every day, automate this; 定时任务, 每天自动, 定时执行.
disable-model-invocation: false
user_invocable: true
category: management
allowed_tools:
  - Write
  - FileReader
  - Terminal
---

# Cron Task Creator

A skill for creating, managing, and running scheduled automated tasks in MBOpenClacky.

## Architecture Overview

```
Storage:
  ~/.mbopenclacky/tasks/&lt;name&gt;.md      # Task prompt file (self-contained AI instruction)
  ~/.mbopenclacky/schedules.yml       # All scheduled plans (YAML list)
  ~/.mbopenclacky/logs/               # Execution logs (daily rotation)
```

## Cron Expression Quick Reference

| Expression       | Meaning                    |
|-----------------|----------------------------|
| `0 9 * * 1-5`  | Weekdays at 09:00         |
| `0 9 * * *`    | Every day at 09:00        |
| `0 */2 * * *`  | Every 2 hours             |
| `*/30 * * * *` | Every 30 minutes          |
| `0 19 * * *`   | Every day at 19:00        |
| `0 8 * * 1`    | Every Monday at 08:00     |
| `0 0 1 * *`    | First day of every month  |

Field order: `minute hour day-of-month month day-of-week`

---

## Operations

### 1. LIST — Show all tasks

Read `~/.mbopenclacky/schedules.yml` and display each task: name, cron schedule, enabled status, content preview.

If no tasks exist, inform the user and offer to create one or show templates.

**Key tip**: Remind the user that the MBOpenClacky WebUI Task Panel also shows all tasks and supports direct management.

---

### 2. CREATE — New task

**Step 1: Gather required info** (only ask for what's missing):
- What should the task DO? (goal, behavior, output format)
- How often should it run? (or is it manual-only without a schedule?)
- Any specific parameters? (URLs, file paths, output location, language)

**Step 2: Generate task name**:
- Rule: only `[a-z0-9_-]`, lowercase, no spaces
- Examples: `daily_report`, `price_monitor`, `weekly_summary`

**Step 3: Write the task prompt file**

Create `~/.mbopenclacky/tasks/&lt;name&gt;.md`. The prompt must be:
- **Self-contained**: the agent running it has zero prior context — include everything needed
- **Written as direct instructions** to an AI agent (imperative, not conversational)
- **Detailed**: include URLs, file paths, output format, language, expected output location

Good task prompt example:
```markdown
You are a price monitoring assistant. Complete the following task:

## Goal
Check the current BTC price on CoinGecko, compare with yesterday's price, and log an alert if the change exceeds 5%.

## Steps
1. Fetch https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true
2. Parse the JSON response to get current price and 24hr change
3. If |change| > 5%, write an alert to ~/price_alerts/alert_YYYY-MM-DD.txt
4. Print the current price and change percentage

Execute immediately.
```

**Step 4: Create or update schedules.yml**

Write to `~/.mbopenclacky/schedules.yml`:
```yaml
tasks:
  - name: "&lt;task_name&gt;"
    cron: "&lt;cron_expression&gt;"
    enabled: true
    created_at: "&lt;timestamp&gt;"
```

If no schedule is needed (manual-only), omit the `cron` field.

**Step 5: Confirm creation**

```
✅ Task created successfully!

📋 Task name: daily_standup
⏰ Schedule: Weekdays at 09:00 (cron: 0 9 * * 1-5)

View and manage this task in the MBOpenClacky WebUI → Tasks panel. Click ▶ Run to execute immediately.
```

---

### 3. EDIT — Modify an existing task

**Step 1**: Identify the task (if unclear, LIST first and ask)

**Step 2**: Show current state and ask what to update

**Step 3**: Update the task prompt file and/or schedules.yml

**Step 4**: Confirm changes

```
✅ Task updated!
📋 daily_standup
  Schedule: 0 9 * * 1-5 → 0 8 * * 1-5 (now weekdays at 08:00)
```

---

### 4. ENABLE / DISABLE — Toggle a task

Update `~/.mbopenclacky/schedules.yml`, set `enabled: true/false` for the task.

Confirm:
```
✅ daily_standup has been disabled.
  To re-enable: say "enable daily_standup"
```

---

### 5. DELETE — Remove a task

Always confirm before deleting (unless the user has explicitly said to delete).

Then:
- Delete the task file: `~/.mbopenclacky/tasks/&lt;name&gt;.md`
- Remove the entry from `~/.mbopenclacky/schedules.yml`

---

### 6. HISTORY — View run history

Check the log files in `~/.mbopenclacky/logs/`.

Display format:
```
📊 Run History: ai_news_x_daily

Mar 10  19:00  ❌ Failed  — JSON::ParserError: unexpected end of input
Mar 09  19:00  ✅ Success — took 1m 42s
Mar 08  19:00  ✅ Success — took 2m 10s
```

---

### 7. RUN NOW — Execute immediately

Tell the user how to run it via the WebUI or CLI.

---

### 8. TEMPLATES — Browse common task templates

When user says "what templates are there" or "what can I automate":

```
📚 Common Task Templates — pick one to get started:

1. 📰 Daily Report — Generate a summary of daily activity
2. 💰 Price Monitor — Check prices on a schedule, log alerts on anomalies
3. 📊 Weekly Summary — Every week, summarize the past week's work
4. 🌤 Weather Reminder — Fetch weather every morning and save to file
5. 🔍 Competitor Monitor — Periodically check competitor sites for changes
6. 📝 Journal Prompt — Evening reminder to journal with daily reflection
7. 🔗 Link Health Check — Periodically verify specified URLs are accessible
8. 📂 File Backup — Regularly back up a specified directory to another location

Tell me which one interests you, or describe your own use case!
```

---

## Important Notes

- Task names: only `[a-z0-9_-]`, no spaces, no uppercase
- Task prompt files must be **self-contained** — the executing agent has no prior memory
- The MBOpenClacky server must be running for cron to trigger automatically (checked every minute)
- The WebUI Task Panel is the preferred interface for managing tasks — always remind the user to check it after changes
