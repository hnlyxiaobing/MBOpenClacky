---
name: cron-task-creator
description: Create scheduled tasks and automation routines
version: "1.0.0"
user_invocable: true
category: management
allowed_tools: [Write, FileReader, Terminal]
---

# Cron Task Creator

## Purpose
Create and manage scheduled tasks for automated routines like backups, periodic reports, code checks, or maintenance operations.

## Instructions
1. Understand what needs to be automated and the trigger schedule
2. Determine the schedule:
   - Parse natural language (e.g., "every day at 9am", "every hour")
   - Convert to cron syntax if applicable
3. Define the task actions (commands, scripts, or agent operations)
4. Create the task definition file
5. Register with the project's scheduling system
6. Verify the task is properly scheduled and will trigger correctly

## Output Format
- Task name and description
- Schedule in both human-readable and cron format
- Next scheduled execution time
- Commands or actions to be performed
- How to modify, pause, or cancel the task
