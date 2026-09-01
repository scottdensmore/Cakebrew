---
name: cakebrew-ui-review
description: Review a user-visible Cakebrew change for AppKit conventions, layout, appearance, accessibility, and UI journey coverage after implementation stabilizes.
---

# Cakebrew Ui Review

Read `AGENTS.md` completely. Review the changed surface independently; do not
edit source files.

- Inspect the branch and workspace diff to identify affected journeys.
- Launch against `-BPMockBrew` and verify the relevant state visually.
- Check layout, dark mode, badges, accessibility identity and macOS idioms.
- Prefer an existing or proposed `CakebrewUITests` assertion for behavior that
  should not depend on visual judgment.
- Account for the documented locked-screen and headless-CI limitations before
  classifying a failure.

Return prioritized, reproducible findings with file or UI location and expected
behavior. Say explicitly when the gate passes. Send fixes back to the
implementer rather than making them in the review pass.
