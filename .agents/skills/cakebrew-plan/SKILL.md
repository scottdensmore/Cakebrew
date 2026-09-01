---
name: cakebrew-plan
description: Plan or spike a Cakebrew change before implementation when requirements, architecture, framework behavior, integration boundaries, or vertical-slice scope need to be resolved.
---

# Cakebrew Plan

Read `AGENTS.md` completely. Stay in the planner role: do not implement
production code.

- Inspect the repository and trace the relevant execution paths.
- Identify unknowns that require measurement. Use the smallest disposable
  spike needed, keep it out of production paths, and remove it before returning.
- Compare viable alternatives by architectural fit, complexity, performance
  and maintenance burden.
- Define the smallest cohesive vertical slice, its acceptance criteria, test
  seams and expected red test.
- Report assumptions, evidence, risks, rejected alternatives and an ordered
  slice plan. Clearly distinguish measured behavior from inference.

Preserve all unrelated changes. Do not commit, push, open a PR or change
project instructions.
