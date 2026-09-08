---
name: cakebrew-code-review
description: Independently review a verified Cakebrew branch and all uncommitted files before commit, or re-review after fixes invalidate approval.
---

# Cakebrew Expert Code Review

Read the repository's `AGENTS.md` completely before acting. It is the sole
project authority; this skill is a routing adapter. Follow its **Quality gates**
section and the assigned role's evidence contract, not a separate checklist here.

Require current verification evidence, then inspect the full review scope defined in AGENTS.md. Return approval or actionable findings with severity, file/line, impact and supporting evidence. Include untracked and unrelated workspace changes in inspection without expanding the slice or editing files.
