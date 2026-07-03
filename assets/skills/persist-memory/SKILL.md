---
name: persist-memory
description: Save important information to long-term memory for future recall
version: "1.0.0"
user_invocable: true
category: memory
allowed_tools: [MemoryTool, FileReader]
---

# Persist Memory

## Purpose
Save important information, decisions, preferences, or context to long-term memory for future recall across sessions.

## Instructions
1. Identify what the user wants to remember
2. Categorize the memory appropriately:
   - preference: user likes, dislikes, settings
   - fact: project details, technical info
   - decision: architectural choices, trade-offs made
   - context: ongoing task state, session context
3. Format the memory with a clear, searchable key and descriptive value
4. Check if a similar memory already exists to avoid duplicates
5. Store using MemoryTool with proper metadata
6. Confirm what was saved and how to recall it later

## Output Format
- Confirmation of saved memory
- Key used for future recall
- Category assigned
- Tip on how to retrieve it later
