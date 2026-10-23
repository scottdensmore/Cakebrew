# Cakebrew

A native macOS app for [Homebrew](https://brew.sh).

[![CI](https://github.com/scottdensmore/Cakebrew/actions/workflows/ci.yml/badge.svg)](https://github.com/scottdensmore/Cakebrew/actions/workflows/ci.yml)

Cakebrew gives Homebrew a Mac interface: browse what is installed, see what is
out of date, install and remove packages, and manage the services brew runs in
the background — without remembering a command for each of them.

| Light | Dark |
|---|---|
| ![Cakebrew in light mode](docs/screenshots/main-window-light.png) | ![Cakebrew in dark mode](docs/screenshots/main-window-dark.png) |

## What it does

**Formulae**
* Browse installed, outdated, leaves, pinned and the full catalog
* Install, uninstall and upgrade, individually or everything at once, with live-filtered formula build options
* Pin a formula to hold it at its installed version, with a badge in the list
* Read a formula's description, version, dependencies, conflicts and dependents

**Casks**
* Browse installed, outdated and all available casks
* Install, uninstall and upgrade, optionally running a cask's `zap` stanza to
  remove its preferences and support files too

**Tools**
* Updates — unified view of outdated formulae and casks with live filtering,
  selective upgrades, and exact-snapshot batch upgrades that respect pinned exclusions
* Services — start, stop and restart the background services brew manages, with
  live status filter pills, inline search, and one-click service plist & log path copy
* Doctor — run `brew doctor` with live diagnostic summary badges, line filtering, and one-click output copy
* Update — run `brew update` with live log filtering and output copy
* Cleanup — preview and reclaim disk space (`brew cleanup`)
* Remove Unused Dependencies — preview and remove unused dependency formulae (`brew autoremove`) with candidate count badges and log filtering
* Import and export a Brewfile with interactive entry status filters, search, summary copy, and live import log filtering

**Around the edges**
* Built with Swift 6 and SwiftUI for macOS Tahoe
* Quick Command Palette (`⌘K`) to jump to any sidebar section, run Homebrew tools,
  or select any installed formula or cask from the keyboard
* Interactive Package Inspector with one-click install path copy, Reveal in Finder,
  More Information popover, homepage launch, and clickable dependency/dependent chips
* Live SwiftUI Tahoe status bar with activity indicator, package count pills, and
  one-click outdated updates badge
* Optional Menu Bar Extra in Settings for instant access to outdated package counts,
  Update Homebrew, Upgrade All Outdated, and Command Palette
* Optional background checking, with a Dock badge and a notification when
  something new goes out of date
* In-app update discovery (`Cakebrew ▸ Check for Updates…`) with SHA-256 and
  Ed25519 feed verification
* Search across formulae and casks
* Six localizations: English, German, French, Italian, Portuguese and
  Simplified Chinese

## Requirements

macOS 15 or later. Homebrew must already be installed — Cakebrew drives the
`brew` you have, it does not bundle its own.

Works with both Homebrew prefixes (`/usr/local` on Intel, `/opt/homebrew` on
Apple silicon).

## Installing & Building

Cakebrew is built from source with Xcode (until a tagged binary release is
published on [Releases](https://github.com/scottdensmore/Cakebrew/releases)):

```sh
git clone https://github.com/scottdensmore/Cakebrew.git
cd Cakebrew
open Cakebrew.xcworkspace
```

In Xcode, select the **Cakebrew** scheme and choose **Product ▸ Run** (`⌘R`), or
build from the command line and copy `Cakebrew.app` to `/Applications`:

```sh
# Build a Release or Debug app bundle without requiring a signing certificate
xcodebuild build -workspace Cakebrew.xcworkspace -scheme Cakebrew \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Unit tests — fast and hermetic
xcodebuild test -project Cakebrew.xcodeproj -scheme Cakebrew \
  -destination 'platform=macOS' -only-testing:CakebrewTests CODE_SIGNING_ALLOWED=NO

# UI tests — journeys against a mock brew, no real Homebrew involved
xcodebuild test -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Launching with `-BPMockBrew` swaps in a fixture-backed interface, so you can
drive the whole UI without touching a real Homebrew installation. That build is
Debug-only.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on contributing to Cakebrew.

## Security

Cakebrew ships a privileged helper. Please report vulnerabilities privately
rather than in a public issue — see [SECURITY.md](SECURITY.md).

## Credits

Cakebrew was created by [Bruno Philipe](https://github.com/brunophilipe), based
on a project by [vincentsaluzzo](https://github.com/vincentsaluzzo/Homebrew-GUI)
whose commits are still in the working tree. This repository is a fork
maintained by [Scott Densmore](https://github.com/scottdensmore).

Distributed under the GNU General Public License version 3. See
[LICENSE](LICENSE).
