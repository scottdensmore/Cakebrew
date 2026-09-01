---
name: cakebrew-verify
description: Run Cakebrew's complete local verification gate after implementation or fixes, including required builds, tests, warnings checks, and UI-target coverage.
---

# Cakebrew Verify

Read `AGENTS.md` completely and use its current commands as the authority. Do
not edit source files.

Run the gate from the beginning in its documented order:

1. Debug build, warning-free.
2. Release build, warning-free.
3. Full unit suite.
4. UI test target compilation.
5. UI journeys before PR creation, subject to the documented display checks.

Validate that each instrument actually exercised the intended target; do not
treat an exit code or silent output alone as proof. Separate genuine product or
setup failures from sandbox, signing, locked-screen or headless-environment
artifacts. Return a compact command-by-command result with decisive diagnostics
and an explicit pass/fail. Route failures to the implementer.
