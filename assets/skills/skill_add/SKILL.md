---
name: skill_add
description: "Install a skill from URL or local path"
version: "1.0.0"
user_invocable: true
category: utility
allowed_tools: [Terminal, FileReader, Write, WebFetch]
argument_hint: "<url-or-path>"
---

# Skill Add

## Purpose

Install a skill package from a GitHub repository URL or a local filesystem path. Validates the SKILL.md format, copies the skill to the user's skill directory, and confirms it is registered and available.

## Instructions

1. **Parse the Input**: Determine whether the argument is:
   - A **GitHub URL** (e.g., `https://github.com/user/repo` or `https://github.com/user/repo/tree/main/skills/my-skill`)
   - A **local path** (absolute or relative directory containing a SKILL.md)

2. **Download or Copy the Skill**:
   - For a GitHub URL:
     - Clone the repository to a temporary directory using `git clone --depth 1`
     - If a sub-path is specified, extract only that sub-directory
   - For a local path:
     - Verify the directory exists and contains a `SKILL.md` file

3. **Validate SKILL.md Format**:
   - Read the `SKILL.md` file
   - Parse the YAML frontmatter and verify required fields are present:
     - `name` (non-empty, kebab-case or snake_case)
     - `description` (non-empty string)
   - Report any validation errors and abort if critical fields are missing

4. **Install to Skill Directory**:
   - Determine the target path: `~/.mbopenclacky/skills/<skill-name>/`
   - If a skill with the same name already exists, ask the user whether to overwrite
   - Copy all files from the source directory to the target path
   - Clean up any temporary clone directories

5. **Confirm Registration**:
   - Read back the installed `SKILL.md` to verify integrity
   - Report the installed skill name, description, category, and allowed tools
   - Inform the user how to invoke it: `/<skill-name>`

## Output Format

- Source type (URL or local path)
- Validation results (fields found, any warnings)
- Installed path
- Skill metadata summary (name, description, category, allowed_tools)
- Invocation command: `/<skill-name>`
