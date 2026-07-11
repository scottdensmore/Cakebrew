# Agent Guide — Cakebrew

Cakebrew is a native macOS GUI for Homebrew (Objective-C / AppKit). This file
is the working agreement for **any** coding agent (and human contributor)
touching this repo. Follow it exactly; it encodes decisions the maintainer has
already made.

## The required workflow (9 steps, no exceptions)

1. **Branch off latest `main`.** Prefixes: `feat/`, `fix/`, `refactor/`,
   `docs/`, `chore/`. Never commit to `main` directly.
2. **TDD, red → green → refactor.** Write the smallest failing test first and
   confirm it fails for the right reason (a compile error on a new API counts).
   Then the minimum code to pass. The test and the code that satisfies it land
   in the **same commit**, and the commit message names what the test covers.
   Every behavior change ships with a test written first — bugs, features,
   behavior-changing refactors. Only pure formatting/docs are exempt.
3. **UI review.** If the change touches UI, verify it visually: launch the mock
   build (`-BPMockBrew`), look at it (screenshot if headless), confirm layout,
   dark mode, and badges render correctly.
4. **Verify.** Build with **zero warnings** and run the full unit suite
   (see commands below). Treat a new warning as a failure.
5. **Pre-PR code review** over the full diff. Fix what you find, then re-verify.
6. **Open a PR with the `gh` CLI** (never the web UI). Describe what changed,
   why, and how it was tested.
7. **Green CI is the merge gate.** Both jobs (Build & Test, UI Tests) must
   pass. Never merge on pending or failing checks. If a UI test fails on CI,
   read the failure and the `CAKEBREW_UI_TREE_*` dump in the job log before
   assuming a flake — re-run once only when the evidence says infrastructure.
8. **Address feedback as it lands.** Push fixes to the same branch; let CI
   re-run.
9. **Merge & clean up:** `gh pr merge <n> --squash --delete-branch` (squash is
   the maintainer's explicit choice), then `git checkout main`,
   `git pull --ff-only`, delete the local branch.

**One PR per logical unit of work.** Unrelated changes go on separate branches.

## Build & test commands

```sh
# App build (must be warning-free)
xcodebuild build -workspace Cakebrew.xcworkspace -scheme Cakebrew \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Unit tests (fast, hermetic — run these locally every time)
xcodebuild test -workspace Cakebrew.xcworkspace -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# UI tests (own scheme; needs ad-hoc signing; on CI this is authoritative)
xcodebuild test -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

CI (`.github/workflows/ci.yml`) runs both jobs on `macos-26` (latest SDK) and
uploads crash logs from `~/Library/Logs/DiagnosticReports` on failure.

## Testing architecture

- **Mock brew:** launching the app with `-BPMockBrew` swaps
  `BPHomebrewInterface` for `BPMockHomebrewInterface` (resolved in
  `+sharedInterface`). The mock serves deterministic fixtures (`mockwget`,
  `mockgit` [pinned], `mockchrome`/`mockvscode` [casks], …) and stubs every
  operation as a no-op. **Any new interface method must get a mock override**
  so UI tests never shell out to real brew.
- **Unit tests** (`CakebrewTests/`) cover parsers, model logic, and manager
  state. The `BPHomebrewInterfaceListCall*` parsers are the standard TDD seam:
  pure input → `BPFormula` output. Private classes are re-declared in the test
  file to reach them.
- **UI tests** (`CakebrewUITests/`) are journey tests against the mock. The
  shared launch helper waits for the initial load to settle (mockwget rendered)
  before navigating — do not remove that; it closes a reselect race in
  `homebrewManagerFinishedUpdating:`. Sidebar item names repeat across groups
  (two "Installed", two "Outdated") — disambiguate with
  `matchingIdentifier:` + `elementBoundByIndex:`, and match table cells with
  `value BEGINSWITH` (pinned rows carry a pin glyph after the name).
- **CI environment limits:** the headless runner's window is never key, so
  typing/keyboard focus is untestable; system file panels (NSSave/NSOpenPanel)
  are out-of-process and undrivable. Pattern: unit-test the logic, UI-test
  presence/navigation.

## Architecture crib sheet

- `BPHomebrewInterface` — all brew execution funnels through
  `performBrewCommandWithArguments:dataReturnBlock:` (async, streams) or
  `performSyncBrewCommandWithArguments:`. Output blocks may be nil — always
  guard (`invokeOutputBlock:withString:`), passing nil is legitimate.
- **List pattern:** a `BPListMode` enum case → a `BPHomebrewInterfaceListCall`
  subclass (arguments + line parser) → a `BPHomebrewManager` property fetched
  in `reloadFromInterfaceRebuildingCache:` → a sidebar item + badge → a mock
  fixture. Follow this groove for any new list.
- **Casks** are `BPFormula` instances with `cask == YES` (set by the cask list
  parsers; survives copy/coding). Operations dispatch on that flag in
  `BPInstallationWindowController` (`--cask` variants). `statusForFormula:` is
  namespace-aware — casks read only the cask lists.
- **Slow catalogs** (`brew formulae`, `brew casks`) share a 24h disk cache
  (`allFormulae.cache.bin`, two keys). `brew casks` can take 80+ s cold.
- **Sidebar:** `FormulaeSideBarItem` enum values are **outline row indices**
  (groups included). Inserting a row renumbers everything after it — update
  the enum, the View-menu item tags in `MainMenu.xib`, and check every
  `switch`/comparison on the enum (`grep -rn FormulaeSideBarItem`).

## UI conventions

- **Sheets, not app-modal:** every alert/confirmation uses
  `beginSheetModalForWindow:_appDelegate.window …` — never `runModal` (blocks
  the app and is invisible to XCUITest). Attach to `_appDelegate.window`, NOT
  `self.view.window` (nil under the split-view reparenting; caused a crash).
- **Xibs are edited as XML by hand.** After editing: `xmllint --noout` the
  file, keep new `id`s unique (prefix `cbk-…`), and grow an `NSStackView`'s
  `visibilityPriorities`/`customSpacing` arrays when adding arranged subviews.
  Menu items enable via Cocoa **bindings** on `currentFormula` /
  `currentFormulaPinned` (see existing items), not `validateMenuItem:`.
- **Localization:** UI strings go in all six `Cakebrew/*.lproj/
  Localizable.strings` files (lint with `plutil -lint`). New strings use the
  English text in every locale until translated. Homebrew terms ("Casks") stay
  untranslated. Xib menu titles are Base-internationalized literals — no
  `.strings` churn for new menu items.
- Icons are SF Symbols (`imageWithSystemSymbolName:`); no bundled image assets
  for UI chrome.

## OS support policy

Minimum deployment target = **latest macOS minus one** (currently 15.0);
build and CI against the **latest SDK** (`SDKROOT = macosx`, never pinned;
CI runner tracks the newest image, currently `macos-26`). When a new major
macOS ships: bump the deployment target one, bump the CI runner, never pin
`SDKROOT`. `LSMinimumSystemVersion` derives from the build setting.

## Known environment quirks (primary dev machine)

- **`git push` hangs** on the Entire pre-push hook (session-log sync). Push
  with `git push --no-verify` — it skips only that hook, nothing code-related.
- **Local XCUITest runs** often die at init with "Timed out while enabling
  automation mode" (machine-level permission issue). Don't block on it: local
  verification = build + unit suite + visual check; **CI is the authoritative
  UI-test gate.**
- Commit signing is temporarily disabled (`git -c commit.gpgsign=false`) while
  the 1Password SSH agent is broken. Re-enable when fixed.
