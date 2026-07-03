---
name: new
description: "Create a new project from scratch"
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [Terminal, Write, FileReader]
argument_hint: "[project-name] [--template moonbit|generic]"
---

# New Project

## Purpose

Interactively scaffold a new project with proper directory structure, configuration files, Git initialization, and a generated README. MoonBit projects are the primary template, with a generic option for other project types.

## Instructions

1. **Determine Project Parameters**: Ask for or parse from arguments:
   - Project name (required; prompt if not provided)
   - Template: `moonbit` (default) or `generic`
   - Optional: description, author name

2. **Create Directory Structure**:
   - For **moonbit** template:
     ```
     <project-name>/
       src/
         lib/
           hello.mbt
          cmd/
           main.mbt
       test/
         hello_wbtest.mbt
       moon.mod
       moon.pkg (for lib and cmd)
       .gitignore
     ```
   - For **generic** template:
     ```
     <project-name>/
       src/
       tests/
       README.md
       .gitignore
     ```

3. **Initialize Configuration Files**:
   - For MoonBit: write `moon.mod` with `name`, `version`, `preferred_target = native`; write `moon.pkg` for each sub-package
   - For generic: write a basic config (e.g., `.env.example` or `config.json`)

4. **Initialize Git Repository**:
   - Run `git init` in the project directory
   - Create an initial commit with the scaffolded files

5. **Generate README**:
   - Write a `README.md` with project name, description placeholder, getting-started instructions, and project structure overview

6. **Report Results**:
   - Print the created directory tree
   - Show the next steps (e.g., `cd <project-name>`, `moon build`)

## Output Format

- Project directory path
- Generated file list with brief descriptions
- Git initialization status
- Suggested next commands
