---
name: search-skills
description: Search for available skills by name, description, or capability
version: "1.0.0"
user_invocable: true
category: utility
allowed_tools: [FileReader, Glob, WebSearch]
---

# Search Skills

## Purpose
Find available skills by name, capability, or description. Helps users discover what the agent can do.

## Instructions
1. Search local skill definitions in assets/skills/ directory
2. Parse each SKILL.md for metadata (name, description, category)
3. Match against user's query using name, description, or category
4. Optionally search online skill repositories for community skills
5. Sort results by relevance to the query
6. Present results with invocation instructions

## Output Format
- Skill name and short description
- Category (development, utility, memory, management)
- Whether it's built-in or user-created
- How to invoke it (slash command format)
- Required tools summary
