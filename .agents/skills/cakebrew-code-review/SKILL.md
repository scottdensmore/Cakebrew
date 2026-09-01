---
name: cakebrew-code-review
description: Perform the independent pre-commit expert review of a Cakebrew branch and all uncommitted files after verification passes.
---

# Cakebrew Code Review

Read `AGENTS.md` completely. Review the full branch diff against its base plus
all staged, unstaged and untracked files. Do not edit source files.

Prioritize correctness, regressions, Objective-C and AppKit idioms, memory and
concurrency safety, performance, architecture, edge cases, mock fidelity and
missing tests. Trace the actual execution path before reporting a problem.
Avoid style-only comments unless they reveal a concrete maintenance or defect
risk.

Return findings ordered by severity with precise file and line references,
impact and a reproducible rationale. If there are no actionable findings, say
the gate is approved. Any fix belongs to the implementer and invalidates the
prior verification result.
