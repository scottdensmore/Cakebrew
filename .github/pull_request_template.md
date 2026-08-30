## What changed

<!-- What this does, and why. Link the issue it closes. -->

## How it was tested

<!-- What you ran. Say explicitly what you could NOT verify, and why. -->

## Checklist

The workflow lives in [AGENTS.md](../AGENTS.md); this is the short form.

- [ ] Branched off latest `main` with a `feat/` `fix/` `refactor/` `docs/` `chore/` `test/` `perf/` prefix
- [ ] One thin vertical slice — unrelated changes are on their own branch
- [ ] Test written **first** and seen to fail for the right reason; if test and code were written together, the test was proven to bite by mutation
- [ ] Test and the code satisfying it are in the **same commit**
- [ ] Builds **Debug and Release** with zero warnings; unit suite green
- [ ] UI test target compiles (`build-for-testing`); journeys run if behaviour changed
- [ ] User-facing change reviewed visually — layout, dark mode, accessibility
- [ ] Reviewed my own full diff, including untracked files; no scratch files or leftover instrumentation
- [ ] New user-facing strings added to all six `.lproj` files
- [ ] Any new brew interface method has a mock override
- [ ] Commit follows Conventional Commits: `<type>(<scope>): <imperative summary>`
