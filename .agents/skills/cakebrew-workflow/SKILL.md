---
name: cakebrew-workflow
description: Orchestrate a complete Cakebrew feature, bugfix, or behavior-changing refactor through planning, TDD implementation, UI review when applicable, verification, expert review, and delivery gates.
---

# Cakebrew Workflow

Read `AGENTS.md` completely before acting. It is the sole authority for the
workflow, commands, architecture and delivery rules; this skill only routes the
work through the configured roles.

1. Use `cakebrew-planner` with `$cakebrew-plan` to validate assumptions and
   define the smallest vertical slice. Any spike is disposable.
2. Inspect repository state, synchronize the latest `main`, preserve unrelated
   changes, and create the required branch before production edits.
3. Give `cakebrew-implementer` explicit ownership of the slice and invoke
   `$cakebrew-implement`. Require observed red-green-refactor evidence.
4. If a user-visible surface changed, run `cakebrew-ui-reviewer` with
   `$cakebrew-ui-review` after implementation is stable.
5. Run `cakebrew-verifier` with `$cakebrew-verify`, then
   `cakebrew-code-reviewer` with `$cakebrew-code-review`.
6. Route every actionable finding back to the implementer. After any source
   edit, repeat verification and expert review; repeat UI review too when the
   fix changes the visible surface.
7. Keep delivery with the primary agent. Invoke `$cakebrew-deliver` only when
   the user has authorized the relevant commit, push, PR or merge action.

Do not run a mutating agent concurrently with a verifier or reviewer against
the same worktree. Use isolated worktrees when independent passes truly need to
run in parallel. Return concise role summaries and evidence to the primary
agent instead of raw logs.
