---
name: mbopenclacky-commit-push
description: Use this skill when the user wants to finalize the current MBOpenClacky task by reviewing git changes, running the relevant validation, drafting a clear commit message that reflects the actual work, creating the commit, and pushing the current branch to the remote repository.
---

# MBOpenClacky Commit Push

Use this skill when the user wants the repository changes from the current task
to be committed and pushed.

## Workflow

1. Inspect the worktree with `git status --short`, `git diff --stat`, and
   `git diff --name-status`.
2. Determine the validation set from the changed files.
3. Run the relevant verification before committing.
4. Draft a commit message that reflects the actual changes.
5. Write the message to a temporary file and call
   `scripts/commit_and_push.ps1`.
6. Report the commit SHA, branch, push target, and verification that ran.

If the worktree is clean, stop and tell the user there is nothing to commit.

If there are unrelated changes that make the commit scope ambiguous, stop and
ask the user before proceeding.

## Validation Rules

- If any MoonBit source or package metadata changed, run:
  - `moon info`
  - `moon fmt`
  - `moon build`
  - `moon test`
- If only docs, CI, scripts, or skill files changed, run the most relevant
  lightweight checks available. Good defaults are:
  - `git diff --check`
  - `python -m py_compile <changed .py files>` (if any .py files exist)
  - dry-run a helper script when it supports a non-destructive mode
- Never claim validation ran if it did not complete successfully. Report failures
  clearly and stop before committing unless the user explicitly asks to continue.

## Commit Message Rules

- Subject line:
  - imperative mood
  - specific to the change
  - ideally 72 characters or fewer
- Body:
  - one blank line after the subject
  - 2 to 4 bullets beginning with `- `
  - group changes by capability or subsystem, not by raw file dump
  - mention important verification if it materially explains the change
- Avoid generic wording such as `update files`, `misc`, `cleanup`, or
  `fix stuff`.

## Helper Script

Use the bundled helper:

- [scripts/commit_and_push.ps1](scripts/commit_and_push.ps1)

Call pattern:

```powershell
$messageFile = Join-Path $env:TEMP "mbopenclacky-commit-message.txt"
@'
<subject>

- <bullet 1>
- <bullet 2>
'@ | Set-Content -Path $messageFile -Encoding UTF8

.qoder/skills/mbopenclacky-commit-push/scripts/commit_and_push.ps1 `
  -MessageFile $messageFile
```

Use `-DryRun` when validating the flow without creating a commit.
Use `-NoPush` when the user only wants to commit without pushing.

## Output Checklist

In the final user response, include:

- the commit SHA
- the branch and remote that were pushed
- the validation that ran
- any follow-up risk if validation was narrower than usual