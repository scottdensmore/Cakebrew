<p align="center">
  <img src="docs/icon-design/cakebrew-default.png" width="128" height="128" alt="Cakebrew’s cake-shaped brew mug, topped with chocolate and a cherry">
</p>

<h1 align="center">Cakebrew</h1>

<p align="center"><strong>A friendly Mac home for Homebrew.</strong></p>

Find your next favorite tool, keep your packages current, and see what’s installed
on your Mac. Cakebrew brings [Homebrew](https://brew.sh) into a native SwiftUI
interface, with searchable package lists, a detailed inspector, and familiar
Mac controls.

It works with the Homebrew installation you already have, so your packages stay
part of your usual Homebrew setup.

| Light | Dark |
| --- | --- |
| ![Cakebrew’s package list and inspector in light appearance](docs/screenshots/main-window-light.png) | ![Cakebrew’s package list and inspector in dark appearance](docs/screenshots/main-window-dark.png) |

*Screenshots use demo packages from Cakebrew’s mock Homebrew interface.*

## Meet your packages

- **Browse and discover.** Search formulae and casks, explore the catalog, or focus
  on installed, outdated, pinned, and leaf formulae. Manage your taps from Repositories.
- **Install and update.** Install, remove, and upgrade packages, with formula build
  options when available. Review outdated formulae and casks together in Updates,
  then upgrade selected packages or all eligible packages. Pinned packages are excluded.
- **See the details.** Select a package to read its description, versions,
  dependencies, dependents, license, and Homebrew output in the inspector. Follow
  its homepage, copy an install path, or reveal it in Finder.
- **Choose your version.** Browse release history, expand a version to inspect its
  recipe and metadata, and install and pin an older formula or cask.
- **Keep services in view.** Check the status of Homebrew services, start, stop, or
  restart them, and copy their service and log paths.
- **Take care of your setup.** Update Homebrew, run Doctor, preview cleanup, or
  review unused dependencies before removing them. Follow live operation output.
- **Bring your setup along.** Import or export a Brewfile to describe the packages
  you want on another Mac.

### Older versions, with a way back

Need a previous release? Open **Version History** in the package inspector and
expand a release to see its details before choosing **Install & Pin This Version…**.
Historical formulae can remain alongside the current version; installing an older
cask replaces the app.

When you’re ready to move forward, select the package in **Pinned** and choose
**Return to Latest Release…** from the button above the list or the row’s context
menu. Cakebrew detects the original tap and package when it can. If there are
several possible matches, choose one from the **Original Package** dropdown.
Manual entry is available when no candidates can be found.

History is available for supported public GitHub taps. Older recipes and downloads
may no longer work on your Mac, and a cask’s own updater can bypass its Homebrew
pin. See the [version-history guide](docs/version-history.md) for supported
versions, installation behavior, and recovery details.

## Make yourself at home

Optional background checks surface package updates with a Dock badge and
notifications. Turn them on in **Settings**, or enable a menu bar item for quick
access to updates and Homebrew tools. Cakebrew follows light and dark appearance
and is localized in English, German, French, Italian, Portuguese, and Simplified Chinese.

| Shortcut | Action |
| --- | --- |
| `⌘F` | Search packages |
| `⌘K` | Open the Command Palette |
| `⌘R` | Refresh package information |
| `⌘U` | Update Homebrew |
| `⌘,` | Open Settings |

The Command Palette can take you to a sidebar section, select an installed
package, or open a Homebrew tool. **Cakebrew ▸ Check for Updates…** checks for
updates to Cakebrew itself.

## Get started

You’ll need **macOS 15 or later** and [Homebrew](https://brew.sh) installed.
Cakebrew supports the standard Homebrew locations on Apple silicon
(`/opt/homebrew`) and Intel (`/usr/local`).

To build the current source, use **Xcode 26 or later**, including its command-line
tools. The app uses Swift 6 with complete concurrency checking and a layered
Icon Composer app icon.

```sh
git clone https://github.com/scottdensmore/Cakebrew.git
cd Cakebrew
open Cakebrew.xcworkspace
```

Select the **Cakebrew** scheme, choose **My Mac**, and run with `⌘R`.
Published builds, when available, are listed on
[Releases](https://github.com/scottdensmore/Cakebrew/releases).

For a local command-line build without a development team:

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme Cakebrew \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" build

open build/Build/Products/Debug/Cakebrew.app
```

Once Cakebrew opens, start with **Installed** to explore your setup, or press `⌘F`
to find a package. Select a row to open its details in the inspector.

## For contributors

Bug reports, translations, accessibility improvements, and thoughtful feature
ideas are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), or explore:

- [SwiftUI architecture and migration notes](docs/swiftui-migration.md)
- [Version history and returning to the latest release](docs/version-history.md)
- [The layered app icon and appearance previews](docs/icon-design/README.md)

The interface uses SwiftUI scenes, navigation, tables, an inspector, Settings, and
commands. There are no XIB, NIB, or storyboard resources. macOS integrations such
as Finder, the clipboard, and notifications use the platform APIs.

### Try the demo interface

Debug builds include a mock Homebrew interface for exploring the UI without
changing your Homebrew installation:

```sh
open -n build/Build/Products/Debug/Cakebrew.app --args -BPMockBrew
```

### Run the checks

Run the unit suite with the dedicated **CakebrewTests** scheme:

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

UI tests use mock Homebrew data and require a logged-in macOS session with
UI-testing permission. The test runner needs a signature; ad-hoc signing works
for local runs:

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewUITests \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" test
```

Live Homebrew compatibility checks are opt-in and skipped by default. They read
real Homebrew output without installing or removing packages. The fixtures expect
`wget` to be installed and `cowsay` to be absent:

```sh
CAKEBREW_BREW_COMPAT=1 TEST_RUNNER_CAKEBREW_BREW_COMPAT=1 \
HOMEBREW_NO_AUTO_UPDATE=1 TEST_RUNNER_HOMEBREW_NO_AUTO_UPDATE=1 \
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewTests \
  -destination 'platform=macOS' \
  -only-testing:CakebrewTests/BPBrewCompatibilityTests \
  CODE_SIGNING_ALLOWED=NO test
```

Please report security vulnerabilities privately through
[SECURITY.md](SECURITY.md).

## Thanks and license

Cakebrew was created by [Bruno Philipe](https://github.com/brunophilipe), based on
[vincentsaluzzo’s Homebrew-GUI](https://github.com/vincentsaluzzo/Homebrew-GUI),
whose commits remain in the repository history. This fork is maintained by
[Scott Densmore](https://github.com/scottdensmore).

Distributed under the **GNU General Public License version 3**. See [LICENSE](LICENSE).
