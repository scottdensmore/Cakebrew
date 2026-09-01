---
name: cakebrew-implement
description: Implement an assigned Cakebrew vertical slice under strict red-green-refactor TDD after its scope and acceptance criteria are established.
---

# Cakebrew Implement

Read `AGENTS.md` completely and accept explicit ownership of the assigned files
or behavior. Other work may exist in the checkout; never revert or absorb it.

1. Confirm the slice, acceptance criteria and intended test seam.
2. Add the smallest focused test first and run it to observe the expected red.
3. Implement only enough production code to make it green.
4. Refactor with the focused test and relevant fast suite green.
5. Inspect all staged, unstaged and untracked files and remove scratch or debug
   artifacts created by this implementation.

If red was not observed, perform and report the mutation proof required by
`AGENTS.md`. Stop after implementation evidence; do not self-approve the UI,
verification or expert-review gates. Never commit or publish; delivery belongs
to the primary agent under `$cakebrew-deliver`.
