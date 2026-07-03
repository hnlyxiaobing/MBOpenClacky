---
name: skill-creator
description: Create new custom skills with guided workflow
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [Write, FileReader, Edit]
---

# Skill Creator

## Purpose
Guide the user through creating a new custom skill with proper structure, metadata, and instructions.

## Instructions
1. Ask for or identify:
   - Skill name (kebab-case, e.g., "my-skill")
   - Purpose and description
   - Required tools
   - Category (development, utility, memory, management)
2. Generate SKILL.md with proper YAML frontmatter
3. Write clear step-by-step instructions for the agent
4. Define expected output format
5. Save to assets/skills/<name>/SKILL.md
6. Verify the file is properly formatted
7. Confirm creation and explain how to invoke it

## Output Format
- Created file path
- Skill metadata summary (name, category, tools)
- Invocation command (e.g., /my-skill)
- Suggestions for testing the new skill
