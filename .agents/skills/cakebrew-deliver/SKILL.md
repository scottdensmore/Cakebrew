---
name: cakebrew-deliver
description: Deliver a verified Cakebrew slice when the user authorizes committing, publishing, opening a PR or merging; coordinate any required remediation through the workflow.
---

# Cakebrew Delivery

Read the repository's `AGENTS.md` completely before acting. It is the sole
project authority; this skill is a routing adapter. Follow its **Delivery**
section and the assigned role's evidence contract, not a separate checklist here.

Apply only the authorized delivery stages in AGENTS.md. Check source-matched gate evidence before mutation, and use its CI, assigned-review, stacked-PR and cleanup rules. Route stale evidence or in-scope findings back through $cakebrew-workflow; hold the affected delivery stage. Report genuine authority or environment blockers without silently bypassing gates.
