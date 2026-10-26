# Cakebrew

**Native Homebrew package management for macOS.**

![An architectural illustration of modular packages connected by metal paths on a dark teal background](docs/images/cakebrew-banner.png)

Cakebrew provides a native SwiftUI interface for managing command-line tools and
Mac applications through [Homebrew](https://brew.sh). Browse packages, review
updates, inspect dependencies, and manage services using your existing Homebrew
installation.

[Releases](https://github.com/scottdensmore/Cakebrew/releases) ·
[Report an issue](https://github.com/scottdensmore/Cakebrew/issues) ·
[Contributing](CONTRIBUTING.md) · [License](LICENSE)

## Features

| Area | Capabilities |
| --- | --- |
| Package browser | Search formulae and casks; filter installed, outdated, pinned, and leaf packages; manage taps from Repositories. |
| Installation and updates | Install, uninstall, and upgrade packages, with formula build options and a combined view of available formula and cask updates. |
| Package inspector | Review descriptions, versions, dependencies, dependents, licenses, source links, and Homebrew output in a resizable panel. |
| Version management | Inspect release history, install and pin supported historical versions, and return to the latest release directly from Pinned. |
| Services | View status, start, stop, and restart Homebrew services; copy service and log paths. |
| Maintenance | Update Homebrew, run Doctor, preview cleanup, and review unused dependencies before removing them. |
| Brewfiles | Import and export package definitions to reproduce a setup on another Mac. |

Package rows include cached descriptions, aligned versions, and update and pin
indicators. Choose **View → Compact Package Rows** for a denser layout. The sidebar
and inspector can be resized and collapsed independently.

Optional background update checks, notifications, a Dock badge, and a menu bar
item are available in **Settings**. The interface supports light and dark
appearance and is localized in English, German, French, Italian, Portuguese, and
Simplified Chinese.

## Requirements

- **macOS 15 or later.**
- **Homebrew**, installed separately. Standard Apple silicon (`/opt/homebrew`) and
  Intel (`/usr/local`) installations are supported.
- **Xcode 26 or later** with command-line tools to build from source.

This README describes the current `main` branch. Published releases may differ;
see [Releases](https://github.com/scottdensmore/Cakebrew/releases) for available builds.

## Build and run

```sh
git clone https://github.com/scottdensmore/Cakebrew.git
cd Cakebrew
open Cakebrew.xcworkspace
```

Select the **Cakebrew** scheme and **My Mac** destination, configure your signing
team if needed, and choose **Product → Run** (`⌘R`).

<details>
<summary>Command-line build with local ad-hoc signing</summary>

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme Cakebrew \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" build

open build/Build/Products/Debug/Cakebrew.app
```

</details>

## Using Cakebrew

Start with **Installed** to review your setup, or search for a formula or cask with
`⌘F`. Select a package to view its details in the inspector. Use **Outdated** for a
single package type or **Updates** to review formula and cask updates together.
Pinned packages are excluded from bulk upgrades.

The Command Palette (`⌘K`) provides access to sidebar sections, installed
packages, and Homebrew tools. **Cakebrew → Check for Updates…** checks for updates
to Cakebrew itself.

| Shortcut | Action |
| --- | --- |
| `⌘F` | Search packages |
| `⌘K` | Open the Command Palette |
| `⌘R` | Refresh package information |
| `⌘U` | Update Homebrew |
| `⌘,` | Open Settings |

### Historical versions

Expand **Version History** in the inspector to review a release before choosing
**Install & Pin This Version…**. Historical formulae can coexist with the current
version; installing an older cask replaces the current application.

To switch back, select the package in **Pinned** and choose **Return to Latest
Release…**. Cakebrew detects the original package when possible and provides a
chooser when several candidates match.

History browsing supports public GitHub taps. Installation depends on recipe,
version, checksum, and download availability; older releases may no longer work
on the current system. A cask's own updater can bypass its Homebrew pin. See the
[version-history guide](docs/version-history.md) for supported cases and recovery
behavior.

## Development

The application uses **Swift 6** with complete concurrency checking. SwiftUI owns
the scenes, navigation, tables, inspector, Settings, and commands. There are no
XIB, NIB, or storyboard resources. Platform integrations use native macOS APIs.
See the [architecture notes](docs/swiftui-migration.md) for implementation details.

Debug builds include a mock Homebrew interface for exploring the UI without
changing your Homebrew installation:

```sh
open -n build/Build/Products/Debug/Cakebrew.app --args -BPMockBrew
```

The path above assumes the command-line build shown earlier.

### Tests

Run unit tests with the dedicated **CakebrewTests** scheme:

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

UI tests use mock Homebrew data and require an unlocked macOS session with
UI-testing permission. The runner must be signed; local ad-hoc signing is supported:

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewUITests \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" test
```

<details>
<summary>Live Homebrew compatibility checks</summary>

These opt-in tests read real Homebrew output without installing or removing
packages. They are skipped by default. The fixtures expect `wget` to be installed
and `cowsay` to be absent.

```sh
CAKEBREW_BREW_COMPAT=1 TEST_RUNNER_CAKEBREW_BREW_COMPAT=1 \
HOMEBREW_NO_AUTO_UPDATE=1 TEST_RUNNER_HOMEBREW_NO_AUTO_UPDATE=1 \
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewTests \
  -destination 'platform=macOS' \
  -only-testing:CakebrewTests/BPBrewCompatibilityTests \
  CODE_SIGNING_ALLOWED=NO test
```

</details>

## Contributing

Bug reports, accessibility improvements, translations, and focused feature
proposals are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a
change. Report security vulnerabilities privately using [SECURITY.md](SECURITY.md).

## Credits and license

Created by [Bruno Philipe](https://github.com/brunophilipe), based on
[vincentsaluzzo's Homebrew-GUI](https://github.com/vincentsaluzzo/Homebrew-GUI).
This fork is maintained by [Scott Densmore](https://github.com/scottdensmore).
Original project commits remain in the repository history.

Licensed under the **GNU General Public License version 3**. See [LICENSE](LICENSE).
