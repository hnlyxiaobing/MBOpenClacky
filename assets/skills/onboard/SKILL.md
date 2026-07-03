---
name: onboard
description: Onboard to a new project: analyze structure, conventions, and setup
version: "1.0.0"
user_invocable: true
category: utility
allowed_tools: [FileReader, Grep, Glob, Write, MemoryTool]
---

# Project Onboarding

## Purpose
Quickly understand a new project's structure, conventions, tech stack, and development workflow. Persist findings for future reference.

## Instructions
1. Identify project type from config files:
   - moon.mod.json (MoonBit)
   - package.json (Node.js)
   - Cargo.toml (Rust)
   - go.mod (Go)
   - Other build system files
2. Read README and any documentation files
3. Map directory structure and identify key modules
4. Identify coding conventions and patterns:
   - Naming style (camelCase, snake_case, kebab-case)
   - File organization patterns
   - Test conventions
5. Discover build/test/run commands
6. Check for CI/CD configuration
7. Persist key findings to memory for future sessions
8. Present a comprehensive onboarding summary

## Output Format
- Project overview (name, type, purpose)
- Tech stack summary
- Key directories and their roles
- Build / test / run commands
- Important conventions to follow
- Any setup steps required for new contributors
