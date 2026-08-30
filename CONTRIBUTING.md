# Contributing

[AGENTS.md](AGENTS.md) is the authoritative working agreement — it is written
for both human contributors and coding agents. This file is the short version.

## The workflow

1. **Branch off latest `main`.** Prefixes: `feat/`, `fix/`, `refactor/`,
   `docs/`, `chore/`. Never commit to `main` directly.
2. **Write the failing test first.** The test and the code that satisfies it
   land in the **same commit**, and the message names what the test covers.
   Every behaviour change ships with a test written first — bugs, features,
   behaviour-changing refactors alike. Only pure formatting and docs are exempt.
3. **Verify.** Build with **zero warnings** and run the unit suite. A new
   warning is a failure, and CI enforces it with
   `GCC_TREAT_WARNINGS_AS_ERRORS`.
4. **Open a PR** describing what changed, why, and how it was tested.
5. **Green CI is the merge gate** — both jobs, no exceptions.

One PR per logical unit of work. Unrelated changes go on separate branches.

## Commands

```sh
# Build — must be warning-free
xcodebuild build -workspace Cakebrew.xcworkspace -scheme Cakebrew \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Unit tests — run these every time; they take seconds
xcodebuild test -workspace Cakebrew.xcworkspace -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# UI tests — a pre-PR step, not an inner-loop one (~6 minutes)
xcodebuild test -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

If you touch `CakebrewUITests.m`, compile that target — neither command above
does, so a syntax error there passes locally and fails on CI:

```sh
xcodebuild build-for-testing -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

## Things that will surprise you

AGENTS.md documents these in full; they are the ones that most often cost a
round trip:

* **Never `runModal`.** Every alert is a sheet on `_appDelegate.window` — not
  `self.view.window`, which is nil under the split-view reparenting.
* **Any new brew interface method needs a mock override**, or UI tests will
  shell out to real brew. A test enforces this.
* **Xibs are hand-edited XML.** Run `xmllint --noout` afterwards and keep new
  ids unique with a `cbk-` prefix.
* **New strings go in all six `.lproj` files**, English text until translated.
  A test fails if any locale is missing a key.
* **`FormulaeSideBarItem` values are outline row indices.** Inserting a row
  renumbers everything after it.

## Reporting bugs

Please use the issue templates. The environment questions are not boilerplate:
the macOS version, the Homebrew version and prefix, and whether the problem
reproduces under `-BPMockBrew` are what separate a parser bug from an
environment one.
