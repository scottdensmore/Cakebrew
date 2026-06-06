import AppKit
import Foundation

// Placeholder Cakebrew app icon generator.
// Draws a Tahoe-style rounded-rect (squircle) with an amber "homebrew" gradient
// and a centered white SF Symbol glyph, then exports PNGs at each native size.
//
// Usage: swift generate-placeholder-appicon.swift [outputDir]
//   outputDir defaults to the current directory; it is created if missing.

// MARK: - Tunable parameters

let kTileMarginRatio: CGFloat   = 0.08    // transparent margin around the tile
let kCornerRadiusRatio: CGFloat = 0.2237  // corner radius as a fraction of the tile width
let kGlyphScaleRatio: CGFloat   = 0.52    // glyph size as a fraction of the tile width

let kGradientTop    = NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.30, alpha: 1.0)
let kGradientBottom = NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.10, alpha: 1.0)

// Tried in order; the first available symbol is used for every size.
let kGlyphCandidates = ["mug.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill"]

// pixel size -> filename (matches AppIcon.appiconset/Contents.json)
let kTargets: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

// MARK: - Helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

// Resolve an available glyph up front so we fail before writing any files rather
// than silently producing a glyph-less icon set.
func resolveGlyphName() -> String {
    let probe = NSImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
    for name in kGlyphCandidates {
        if NSImage(systemSymbolName: name, accessibilityDescription: "Cakebrew")?
            .withSymbolConfiguration(probe) != nil {
            return name
        }
    }
    fail("none of the candidate SF Symbols \(kGlyphCandidates) are available; cannot render the icon glyph")
}

func glyphImage(named name: String, pointSize: CGFloat) -> NSImage {
    // Bake a white palette color in so the symbol renders white (a template
    // symbol drawn via draw(in:) ignores the current fill color).
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: "Cakebrew")?
        .withSymbolConfiguration(config) else {
        fail("failed to render glyph \(name) at \(pointSize)pt")
    }
    return img
}

func renderIcon(px: Int, glyphName: String) -> NSBitmapImageRep {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        fail("could not allocate bitmap for \(px)px")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect tile with a small margin (squircle-ish).
    let margin = size * kTileMarginRatio
    let rect = NSRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
    let radius = rect.width * kCornerRadiusRatio
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Amber "homebrew" gradient, top -> bottom.
    let gradient = NSGradient(starting: kGradientTop, ending: kGradientBottom)!
    tile.addClip()
    gradient.draw(in: rect, angle: -90)

    // Centered white glyph.
    let glyph = glyphImage(named: glyphName, pointSize: rect.width * 0.5)
    let gw = glyph.size.width, gh = glyph.size.height
    let scale = (rect.width * kGlyphScaleRatio) / max(gw, gh)
    let dw = gw * scale, dh = gh * scale
    let gx = rect.midX - dw/2, gy = rect.midY - dh/2
    glyph.draw(in: NSRect(x: gx, y: gy, width: dw, height: dh),
               from: .zero, operation: .sourceOver, fraction: 1.0,
               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Main

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

do {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
} catch {
    fail("could not create output directory \(outDir): \(error.localizedDescription)")
}

let glyphName = resolveGlyphName()

for (px, name) in kTargets {
    let rep = renderIcon(px: px, glyphName: glyphName)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("failed to encode PNG for \(name)")
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    do {
        try data.write(to: url)
    } catch {
        fail("failed to write \(url.path): \(error.localizedDescription)")
    }
    print("wrote \(name) (\(px)px)")
}
