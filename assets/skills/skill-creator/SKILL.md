
---
name: skill-creator
description: |
  Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch,
  edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description
  for better triggering accuracy.
always-show: true
user_invocable: true
category: development
allowed_tools:
  - FileReader
  - Write
  - Edit
  - Terminal
  - Glob
  - Grep
---

# Skill Creator

A skill for creating new skills and iteratively improving them.

---

## Usage Modes

This skill supports two main modes:

### 1. Interactive Mode (default)

The full workflow with user interviews, test cases, and iteration cycles. Use when creating or refining skills manually.

At a high level, the process of creating a skill goes like this:
- Decide what you want the skill to do and roughly how it should do it
- Write a draft of the skill
- Create a few test prompts and simulate running them
- Help the user evaluate the results both qualitatively and quantitatively
- Rewrite the skill based on the user's feedback
- Repeat until satisfied

Your job is to figure out where the user is in this process and jump in to help them progress through these stages. Maybe they say "I want to make a skill for X" — help narrow down the intent, write a draft, write test cases, evaluate, and repeat. Or maybe they already have a draft — go straight to evaluation and iteration.

Always be flexible. If the user says "skip the evals, just vibe with me", do that instead.

### 2. Quick Mode (for agent self-evolution)

Trigger when invoked with `mode: "quick"` in the task arguments. Fast, opinionated skill creation without user interaction.

Behavior in quick mode:
- Skip user interviews and detailed requirements gathering
- Extract workflow pattern from provided context
- Write a minimal but functional SKILL.md
- Save to the appropriate location
- Focus on the happy path; edge cases can be added later

---

## Platform Context: MBOpenClacky

This skill runs inside **MBOpenClacky**. Key platform specifics:

- **Skills** live in these locations (create in user-level by default):
  - **User-level** → `~/.mbopenclacky/skills/<skill-name>/` (always available)
  - **Project-level** → `./.mbopenclacky/skills/<skill-name>/` (only in this project)
  - **Built-in** → `assets/skills/` (shipped with MBOpenClacky)
- To locate an existing skill, check these paths in order
- Skills are simple directories with a `SKILL.md` file (no build step needed)
- MoonBit is the language of MBOpenClacky, but skills themselves are just Markdown with YAML frontmatter

---

## Communicating with the user

Pay attention to context cues to understand how technical the user is. In general:
- "Evaluation" and "benchmark" are fine
- For "YAML" and "frontmatter" — explain briefly if you're unsure the user knows these terms

It's always OK to briefly explain a term if you're in doubt.

---

## Creating a skill

### Capture Intent

Start by understanding what the user wants. If the current conversation already shows a workflow they want to capture (tools used, sequence of steps, corrections made, input/output formats), extract answers from history first — the user may just need to fill gaps and confirm.

Ask these questions (but only if you don't already know the answers):

1. What should this skill enable MBOpenClacky to do?
2. When should this skill trigger? (what phrases/contexts from the user?)
3. What's the expected output format?
4. Should we set up test cases? (Skills with objectively verifiable outputs benefit from test cases. Skills with subjective outputs often don't need them.)

### Interview and Research

Ask about edge cases, input/output formats, example files, success criteria, and dependencies before writing test prompts. Come prepared with context to reduce burden on the user.

### Write the SKILL.md

Components to fill in:

#### YAML Frontmatter (required!)

```markdown
---
name: my-skill
description: What this skill does AND when to use it. Be a little pushy in the description — err toward over-triggering rather than under-triggering.
user_invocable: true  # ALWAYS include this! Makes it appear in WebUI / slash commands
category: development  # or utility, memory, management
allowed_tools: [Write, FileReader, Edit]  # list only what's needed
---
```

**Important frontmatter notes:**
- **Every skill MUST include `user_invocable: true`** — without it, users cannot manually invoke the skill from the MBOpenClacky WebUI `/` command list
- **Wrap description in single quotes if it contains `:` followed by space** — YAML will parse it wrong otherwise
- **Keep the description a little pushy** — instead of "Helps with dashboard creation", write "Helps with dashboard creation. Use this skill whenever the user mentions dashboards, data visualization, or wants to display any kind of data, even if they don't explicitly say 'dashboard'."

#### Skill Body

The body goes after the frontmatter. Structure it clearly:

```markdown
# My Skill

## Purpose

Explain what this skill does in 1-2 paragraphs.

## Workflow

Follow this order strictly:

1. First step
2. Second step
3. Third step

## Guidelines

- Rule 1
- Rule 2

## Output Format

Tell exactly what to output.
```

#### Progressive Disclosure Pattern

If the skill is long, use this pattern:
1. Keep SKILL.md under ~500 lines
2. If approaching the limit, extract content into `references/` files and add clear pointers
3. Reference files from SKILL.md with guidance on when to read them
4. For large reference files (>300 lines), include a table of contents

#### Bundled Scripts (optional)

When a skill needs to execute code (API calls, file processing, data transforms), bundle a script instead of writing inline shell commands. This is cleaner, reusable, and more maintainable.

Store scripts in `scripts/` subdirectory:
- MoonBit scripts (`.mbt`) — preferred for MBOpenClacky
- Shell scripts (`.sh`)
- Python scripts (`.py`)
- Other languages as needed

Invoke from SKILL.md by referencing the script via its path. Never hardcode full paths like `~/.mbopenclacky/skills/my-skill/scripts/...` — use relative paths or assume the skill directory is the working directory.

#### Principle of Least Surprise

Skills must not contain malware, exploit code, or anything that could compromise security. A skill's contents should not surprise the user if described. Don't create misleading skills or skills designed for unauthorized access or data exfiltration.

#### Writing Patterns

Use the imperative form in instructions.

**Defining output formats:**
```markdown
## Report structure

Use this exact template:

# Title

## Executive summary

## Key findings

## Recommendations
```

**Examples pattern:**
```markdown
## Commit message format

Example 1:
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

#### Writing Style

Explain *why* things are important rather than just issuing commands. Use theory of mind — make the skill general, not over-fitted to specific examples. Write a draft, then look at it with fresh eyes and improve it. If you find yourself writing ALWAYS or NEVER in all caps, that's a yellow flag — try to reframe as an explanation of why, so the agent understands the reasoning rather than just following a rule.

### Validate the frontmatter

After writing SKILL.md, always validate it:
- Check that YAML is valid
- Verify required fields are present (`name`, `description`, `user_invocable`)
- Fix any issues

---

## Improving the Skill (Iteration)

This is the heart of the loop. You've run tests, the user reviewed results — now make the skill better.

### How to think about improvements

**Generalize from feedback.** You're iterating on a few examples, but the skill will be used across thousands of different prompts. Avoid overfitting to specific examples. If there's a stubborn issue, try different metaphors or different approaches rather than adding more rigid rules.

**Keep it lean.** Remove things that aren't pulling their weight. Read the execution trace, not just the final output — if the skill is making the agent waste time on unproductive steps, cut those parts.

**Explain the why.** Try hard to explain *why* each instruction matters. Agents are smart — they perform better when they understand the reasoning rather than following rules blindly. If you find yourself writing ALWAYS or NEVER in all caps, reframe as an explanation.

**Look for repeated work.** If every test case resulted in writing similar helper logic (e.g., an API call setup, a file parser), that's a signal to bundle a reusable script into `scripts/` and tell the skill to use it.

### The iteration loop

1. Apply improvements to the skill
2. Re-test with the same test cases
3. Get user feedback
4. Repeat until:
   - The user says they're happy
   - Feedback is all empty/positive
   - You're not making meaningful progress

---

## Packaging

New skills are created directly in the skills directory — no packaging step needed. The skill is immediately available (may need a restart to show up in the UI).

---

## The core loop (summary)

1. Understand what the skill should do
2. Draft or edit the SKILL.md
3. Get user feedback, improve the skill
4. Repeat until satisfied

Add these steps to your todo list if needed.
