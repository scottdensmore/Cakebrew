---
name: cakebrew-deliver
description: Commit, publish, review, merge, and clean up a fully verified Cakebrew slice when the user explicitly requests the applicable delivery actions.
---

# Cakebrew Deliver

Read `AGENTS.md` completely. Delivery does not grant authority: perform only the
commit, push, PR or merge actions the user requested.

- Confirm UI review when applicable, complete verification, and expert approval
  all correspond to the current source state.
- Reinspect the entire workspace and stage only the intended slice. Preserve
  unrelated modifications and untracked files.
- Create the atomic Conventional Commit required by `AGENTS.md`, including why
  the change exists and what the test covers.
- Open a ready PR with `gh` only when requested, reporting all verification and
  any genuine gaps.
- Wait for both CI jobs and every assigned human or automated review. Never
  bypass pending, failing or requested-change gates.
- Squash merge and clean up only with explicit merge authorization, including
  the stacked-PR precaution in `AGENTS.md`.

Stop and report any stale gate evidence, changed head, failed CI, unresolved
review, authentication issue or authorization boundary.
