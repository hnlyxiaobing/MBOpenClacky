
---
name: skill-add
description: |
  Install skills from a zip URL or local zip file path, or copy from a directory.
  Use this skill whenever the user wants to install a skill from a zip link or a local file,
  or uses commands like /skill-add with a URL or file path.
  Trigger on phrases like: install skill, install from zip, skill from zip, skill from url,
  add skill from zip, 安装skill, 从zip安装skill, 从本地安装skill.
user_invocable: true
argument_hint: "&lt;url-or-path&gt; [--name &lt;skill-name&gt;]"
category: utility
allowed_tools:
  - Terminal
  - FileReader
  - Write
  - Glob
  - WebFetch
---

# Skill Add — Installer

Installs a skill from:
- A remote `.zip` URL
- A local `.zip` file path
- A local directory with a `SKILL.md`

---

## Step 1 — Parse the input

Determine what the user provided:
- A URL starting with `http://` or `https://` → remote zip
- A local file path ending with `.zip` → local zip
- A directory path → local directory

If the input is ambiguous, ask for clarification.

---

## Step 2 — Fetch/Copy the skill

### Option A: Remote zip URL

1. Download the zip file to a temporary location
2. Extract it
3. Find the `SKILL.md` file(s) inside
4. Copy the skill directory to the destination

### Option B: Local zip file

1. Extract the zip file
2. Find the `SKILL.md` file(s) inside
3. Copy the skill directory to the destination

### Option C: Local directory

1. Verify the directory has a `SKILL.md`
2. Copy the entire directory to the destination

---

## Step 3 — Choose the destination

Ask the user where to install:
1. **User-level** (recommended) → `~/.mbopenclacky/skills/` (available everywhere)
2. **Project-level** → `./.mbopenclacky/skills/` (only in this project)

If not specified, default to user-level.

---

## Step 4 — Validate SKILL.md

Read and validate the `SKILL.md`:
- Must have YAML frontmatter
- Must have `name` field
- Should have `description` field

If validation fails:
- Show the errors to the user
- Offer to try to fix simple issues
- Or abort if it's too broken

---

## Step 5 — Install

Copy the skill directory to the destination:

For user-level:
```
~/.mbopenclacky/skills/<skill-name>/SKILL.md
```

For project-level:
```
./.mbopenclacky/skills/<skill-name>/SKILL.md
```

If a skill with the same name already exists:
- Ask the user if they want to overwrite
- If yes, rename the old one to `<name>.backup` first, then install
- If no, abort

---

## Step 6 — Confirm installation

Show the user:
- What skill was installed (name, description)
- Where it was installed to
- How to invoke it (if `user_invocable: true`)

Example:
```
✅ Skill installed successfully!

📦 Name: my-skill
📝 Description: What this skill does
📍 Location: ~/.mbopenclacky/skills/my-skill/
🚀 Invoke with: /my-skill
```

---

## Common Sources

- GitHub repos (use the zip archive URL: `https://github.com/&lt;user&gt;/&lt;repo&gt;/archive/&lt;branch&gt;.zip`)
- GitLab, Gitea, etc. (similar zip URLs)
- Local directories from other projects

---

## Notes

- Always validate before installing — don't copy arbitrary files blindly
- Respect existing skills — ask before overwriting
- After installation, the user may need to restart MBOpenClacky to see the new skill
