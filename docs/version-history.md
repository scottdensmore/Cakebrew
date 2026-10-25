# Version history

Select a package and expand **Version History** in the inspector. Expand a release row
to read its recipe date, commit message, description, license, declared dependencies,
and complete formula source at that revision. **Load Older Versions** continues
through earlier history, including Homebrew core's older, unsharded formula paths.
Historical Ruby is displayed as text; browsing details does not evaluate it.

For formulae, **Install & Pin This Version…** opens a review before making changes.
Cakebrew creates a local `cakebrew/versions` tap using `brew tap-new --no-git`,
extracts the selected version starting at the selected Git commit, verifies its
version through Homebrew's JSON metadata, installs it with `--skip-link`, confirms
the installed keg version, and pins
the fully qualified versioned formula. Third-party source taps use separate local `cakebrew/versions-…` taps so that
packages with the same name from different upstream taps cannot be confused.
Existing extracted formulae are reused only
when their stable version matches. Cakebrew does not overwrite existing recipes.

The current installation and command links are preserved by default. Choosing
**Make this the active version** unlinks the original formula only after installation
and pinning succeed, then links the historical formula. Linking may allow a keg-only
formula but never uses `--overwrite`. If activation fails or is cancelled after
unlinking, Cakebrew attempts to restore the original links and verifies the original active version before reporting restoration as successful.
Restoration failures are reported explicitly. The original keg stays installed. Other installed formulae,
including the original package, keep their own upgrade and pin policies.

Extracted formulae are separate packages, such as
`cakebrew/versions/wget@1.21.4`. Find them in the Installed or Pinned list to manage
them. Removing their pin does not update the local recipe to the current upstream
formula. Homebrew-maintained versioned formulae (such as `postgresql@16`) remain
available through ordinary package search and are preferable when they meet your
needs.

## Historical casks

**Install & Pin This Version…** also supports casks. The review explains that
installing an older cask replaces the current app. There is no command-link toggle
for casks. Quit the app first and consider compatibility with data written by newer
releases.

Cakebrew saves the exact historical source, unchanged, in a local
`cakebrew/history-…` tap isolated by upstream package and commit. It preserves the
original cask token so Homebrew manages one app installation. Existing files are
reused only if their contents match exactly. Before changing the app or its pin,
Cakebrew checks the resolved version and checksum and uses `brew fetch --cask` to
verify the archive. It then temporarily unpins a pinned cask, uses native
`brew reinstall --cask --require-sha` (or `install` for an absent app), checks the
actual installed version, runs `brew pin --cask`, and verifies both the pin and
pinned version in Homebrew JSON. It does not use `--force` or `--zap`.

A failed download leaves the installed app and pin unchanged. Once replacement
starts, Homebrew can remove the previous app; a failed replacement may require
manual reinstallation. Cakebrew reports this explicitly and attempts to restore
an existing pin even after cancellation. It does not claim an app rollback.

Cask pins appear in the inspector and Pinned list and can be changed with
**Pin Package** / **Unpin Package**. The app’s own updater can bypass a Homebrew
pin. Disable its automatic updater separately when necessary. Historical recipes
are immutable local copies; unpinning does not change them to the latest release.
Use **Return to Latest Release…** to switch back to the original tap and remove the pin.

## Return to the latest release

Expand the installed older version in **Version History** and choose
**Return to Latest Release…**, then review **Unpin & Switch to Latest**.
This refreshes Homebrew and fetches the current release from the original,
fully qualified tap. It does not merely unpin the immutable historical recipe.

For formulae, Cakebrew installs the latest release with `--skip-link`, verifies
the installed version (including Homebrew revision), changes the command links,
and removes both version pins. The older keg remains installed. Failed switching
attempts restore prior command links and pin policies, with recovery verified
through Homebrew metadata. Unrelated files are not overwritten.

For casks, Cakebrew downloads first, unpins, and reinstalls the original current
cask. It verifies the installed version and absence of a pin. A failed replacement
can require manual app reinstallation; Cakebrew attempts to restore the prior pin
policy and reports recovery failures. It does not use Zap.

New historical installs save their upstream identity in Application Support, so
the return action is also available directly from the copied package’s inspector,
including third-party taps. The return action appears only when that historical version is installed.

You can also select a single formula or cask in **Pinned** and use the
**Return to Latest Release…** button above the list, or right-click its row and
choose the same action. The review resolves the installed package’s exact tap
and uses its saved upstream identity for historical copies. Ordinary pinned
packages are upgraded in place and unpinned. Copied historical formulae retain
their separate keg; casks replace the app.

Older copies without a saved upstream record are detected automatically when
Homebrew can identify a unique original package. Formula detection uses Cakebrew’s
source-tap fingerprint and the available formula catalog, including third-party
taps. Cask detection matches the original token and homepage across available
casks. The resolved, fully qualified **Original Package** appears in the review.

When the original is unavailable or ambiguous (for example, multiple original
versioned formula branches or casks with identical identities in different taps),
the review shows an **Original Package** chooser with the fully qualified possible
matches. Choose a package to enable the switch; nothing is preselected. When no
candidates are available, a text field remains available as a fallback. It never silently
chooses a conflicting tap. No package, tap, or pin changes while detecting the
original; the switch still requires confirmation.

## Availability

History is read on demand from public GitHub Homebrew taps. Release entries are
identified from version-bump commit titles; maintenance-only commits are omitted.
The interface offers pagination, retry, and an explicit GitHub rate-limit message.
Per-version source is fetched only when a release is selected.

Automatic formula extraction supports numeric release versions. Historical casks
support fixed versions, including comma-separated build numbers, when the source
declares a matching literal version and Homebrew resolves a SHA-256 checksum for
this Mac. Recipes using `:latest`, `:no_check`, or unsupported version declarations
remain available to inspect.
Private or non-GitHub tap history is not supported by this browser.

Historical formulae may need to build from source, may use obsolete Homebrew syntax,
or may no longer build on the current system. Extracting can require downloading a
source tap's Git history. Missing local commits or shallow tap history can prevent
extraction; the operation transcript shows Homebrew's diagnostic. Pinning stops
Homebrew upgrades of that package, including security updates. See
[Homebrew's version guidance](https://docs.brew.sh/Versions).

## Validation

Unit tests cover source validation, release parsing, HTTP errors and pagination,
recipe-version verification, install/pin ordering, optional activation, failure
restoration, and cancellation after unlinking. Cask tests cover checksum and
download failures, token and version validation, exact pin verification,
existing-pin recovery, and immutable recipe files. Origin tests cover missing receipts,
third-party tap fingerprints, cask identity matches, conflicting taps, unavailable
metadata, and versioned-branch ambiguity. UI tests exercise automatic origin
detection and ambiguous-match selection for both package types, the no-candidate
manual fallback, per-release details,
the review sheet, and installation with the mock Homebrew interface. Live history
and historical source retrieval can be checked without installing any packages.
