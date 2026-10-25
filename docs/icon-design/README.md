# Cakebrew app icon

The icon keeps Cakebrew’s cake-and-brew silhouette and gives it a stronger visual
hierarchy: a golden layer-cake mug, chocolate ganache, vanilla filling, and a
bright cherry on a deep teal background. The cream bands and open handle keep
the silhouette readable at small sizes.

The editable source is `Cakebrew/AppIcon.icon`, with ten SVG layers in four
front-to-back groups: cherry glaze, chocolate ganache, layer cake, and copper
handle. The default background runs from `#365862` to `#142630`; dark appearance
uses `#243A46` to `#0C151F`. Foreground colors have dark specializations.
Icon Composer supplies the material, lighting, rounded mask, and derived clear
and tinted appearances, following [Apple’s app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons).

This artwork was edited directly as native SVG and Icon Composer JSON. The PNGs
in this directory are previews rendered by Apple’s `ictool`, including 16-, 32-,
and 64-pixel checks. The tinted preview uses an illustrative green system tint.

Regenerate all ten macOS compatibility asset sizes after changing the source:

```sh
bash Tools/export-appicon-fallbacks.sh
```

The script validates pixel dimensions before replacing the asset catalog images.
Build the app with Xcode to compile the layered icon for current macOS releases.
