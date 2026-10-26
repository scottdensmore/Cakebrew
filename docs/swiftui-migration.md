# SwiftUI migration

Cakebrew now starts with `CakebrewApp`, a SwiftUI `App`. A `WindowGroup` scene
handles Brewfile URLs and owns `NavigationSplitView`, a native selectable
sidebar, package `Table`, and trailing system inspector. A `Settings` scene owns persisted preferences;
`Commands` supplies keyboard shortcuts and the application menus. A native
`MenuBarExtra` scene provides optional status-menu access. All targets,
including the helper and both test bundles, use Swift 6 with complete concurrency
checking.

All eleven XIB resources are removed. Their localized `.strings` tables remain
ordinary resources, so existing translated copy is preserved. The application
has no main-nib declaration, compiled NIBs, storyboards, `NSViewRepresentable`, or
`NSViewControllerRepresentable`. Package context menus and primary actions use
SwiftUI APIs rather than discovering or modifying SwiftUI's private AppKit table
implementation. Services use a SwiftUI `Table`; logs use selectable SwiftUI text
with bounded backing storage and a Latest Output control after scrolling back.

The established Homebrew operation layer is retained. AppKit remains at macOS
integration boundaries: file panels, confirmation alerts, operation-sheet window
hosting, notifications, clipboard, Finder, and Dock.
Legacy controller APIs remain covered by the regression suite, but do not compose
the main scene. Existing streaming text objects currently serve as output buffers;
they are never embedded in the SwiftUI interface.

## Design

- Native sidebar selection, resize behavior, collapsed navigation, system toolbar
  controls, and an independently resizable inspector follow macOS conventions.
  Toolbar structure stays independent of package selection; individual action
  views observe enablement changes. Search uses an explicitly sized SwiftUI
  toolbar item. The inspector toggle has one permanent workspace toolbar owner
  across sidebar and inspector transitions. No toolbar items
  are removed or reinserted to repair their position after layout. The selection
  regression test samples search geometry during animations as well as at rest.
  Command-F focuses the SwiftUI toolbar field through the macOS responder chain;
  clearing search and Escape preserve the expected search behavior.
- Sidebar and package-table selection bindings defer their controller handoffs
  until after SwiftUI reconciliation. Requests are coalesced, and programmatic
  navigation or list changes invalidate stale pending selections.
- The package browser uses a continuous table background, subtle separators only
  between actual rows, package symbols, cached descriptions, and aligned versions.
  `View > Compact Package Rows` offers a persistent denser layout. Ordinary
  installed status stays quiet; update and pin indicators remain easy to scan.
  Cached descriptions update without issuing Homebrew info commands for every row.
  The inspector uses a flat layout with a primary heading instead of a nested card.
- Semantic colors and materials adapt to light and dark appearance, accent color,
  contrast, and transparency settings. Transitions do not require motion.
- System typography, selectable metadata and output, spoken icon-button labels,
  stable accessibility identifiers, and textual service statuses support assistive
  technologies without depending on color alone.
- Context-specific empty states distinguish search results, pinned packages, and
  up-to-date installations. Refresh has progress and cancellation controls.
- Package-changing operations retain their review, confirmation, cancellation,
  pinned-package exclusions, and output/error reporting.
- Standard shortcuts include search (Command-F), refresh (Command-R), Settings
  (Command-comma), and Command Palette (Command-K).

These choices follow Apple's [macOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/),
[sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
Design-award quality remains a product goal that requires visual review,
accessibility testing, and real-user validation; a code migration alone cannot
establish it.

## Verification

`CakebrewTests` covers the established package, service, transport, security,
streaming, cache, update, and Brewfile behavior. Architecture checks prevent
Interface Builder resources and embedded AppKit surfaces from returning.
`CakebrewSwiftUIJourneyTests` exercises native navigation, inspector, package
search restoration, and Settings, and attaches screenshots for visual review.

```sh
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Cakebrew.xcodeproj -scheme CakebrewUITests \
  -destination 'platform=macOS' \
  -only-testing:CakebrewUITests/CakebrewSwiftUIJourneyTests test
```

UI tests require a signed test runner and a macOS session with UI-testing access.
Unsigned command-line builds still support the unit suite.

## Validation record — October 23, 2026

- Debug and Release builds succeed with Swift 6 and complete concurrency checking.
- Full unit suite: 564 tests, zero failures, eight existing skips.
- Sixteen targeted UI journeys cover launch and reopening, inspector and services,
  light/dark appearance, Settings, search restoration, package confirmations,
  Doctor streaming, Brewfile review, notification routing, command-palette
  operation previews, empty states, German localization, and Homebrew recovery/retry.
- New scene, command, and accessibility copy is localized in all six languages.
- The production app bundle contains no XIB, NIB, or compiled storyboard resources.
- Light and dark previews in the README were captured from the running SwiftUI
  app using mock Homebrew data and visually reviewed.

## Validation record — October 24, 2026

- Final Debug unit run: 638 tests executed, 637 passed, zero failures. The only
  skip is the release-workflow check because `.github/workflows/release.yml` is
  absent from this checkout. All seven opt-in live Homebrew compatibility checks
  ran and passed without installing or removing packages.
- The final Release app builds with Swift 6 and complete concurrency checking
  and passes the repository’s zero-warning check. The app bundle contains no
  Interface Builder resources.
- Targeted UI journeys verify formula and cask history, install/pin/return flows,
  automatic upstream detection, ambiguous-origin selection, the manual fallback,
  stable toolbar search, action enablement, narrow-window inspector boundaries,
  and keyboard search restoration.
- Fresh light/dark README screenshots were captured and visually reviewed from
  the current app. Its layered icon was checked in default, dark, tinted, clear,
  and small-size appearances; all ten compatibility icon sizes were regenerated
  and validated.
