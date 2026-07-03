---
name: code-explorer
description: Explore and analyze codebase structure, find patterns, understand architecture
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [FileReader, Grep, Glob]
---

# Code Explorer

## Purpose
Analyze and explore codebase structure to understand architecture, find patterns, and map dependencies.

## Instructions
1. Start by identifying the project type (check for moon.mod.json, package.json, Cargo.toml, etc.)
2. Map the top-level directory structure
3. Identify core modules and their responsibilities
4. Trace key data flows and dependencies
5. Look for patterns: naming conventions, file organization, recurring structures
6. Summarize findings in a structured report

## Output Format
Provide a structured report with:
- Project type and technology stack
- Module map with responsibilities
- Key entry points
- Dependency graph (simplified)
- Notable patterns or conventions
- Potential areas of concern or complexity
