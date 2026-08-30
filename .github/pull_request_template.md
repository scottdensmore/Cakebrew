## What changed

<!-- What this does, and why. Link the issue it closes. -->

## How it was tested

<!-- What you ran, and anything you verified by hand. -->

## Checklist

Mirrors the workflow in [AGENTS.md](../AGENTS.md):

- [ ] Branched off latest `main` with a `feat/` `fix/` `refactor/` `docs/` `chore/` prefix
- [ ] Test written first, failing for the right reason, in the **same commit** as the code
- [ ] UI changes verified visually, and a journey added where behaviour changed
- [ ] Builds with **zero warnings**; unit suite passes
- [ ] Reviewed my own full diff before opening this
- [ ] New user-facing strings added to all six `.lproj` files
- [ ] Any new brew interface method has a mock override
- [ ] One logical unit of work — unrelated changes are on their own branch
