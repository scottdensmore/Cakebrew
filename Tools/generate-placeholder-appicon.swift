import AppKit

// Placeholder Cakebrew app icon generator.
// Draws a Tahoe-style rounded-rect (squircle) with an amber "homebrew" gradient
// and a centered white SF Symbol glyph, then exports PNGs at each native size.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// pixel size -> filename
let targets: [(Int, String)] = [
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

func glyphImage(pointSize: CGFloat) -> NSImage? {
    let candidates = ["mug.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill"]
    // Bake a white palette color in so the symbol renders white (a template
    // symbol drawn via draw(in:) ignores the current fill color).
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    for name in candidates {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Cakebrew")?
            .withSymbolConfiguration(config) {
            return img
        }
    }
    return nil
}

func renderIcon(px: Int) -> NSBitmapImageRep {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect tile with a small margin (squircle-ish).
    let margin = size * 0.08
    let rect = NSRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
    let radius = rect.width * 0.2237
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Amber "homebrew" gradient, top -> bottom.
    let top = NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.30, alpha: 1.0)
    let bottom = NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.10, alpha: 1.0)
    let gradient = NSGradient(starting: top, ending: bottom)!
    tile.addClip()
    gradient.draw(in: rect, angle: -90)

    // Centered white glyph at ~52% of the tile.
    if let glyph = glyphImage(pointSize: rect.width * 0.5) {
        let gw = glyph.size.width, gh = glyph.size.height
        let scale = (rect.width * 0.52) / max(gw, gh)
        let dw = gw * scale, dh = gh * scale
        let gx = rect.midX - dw/2, gy = rect.midY - dh/2
        NSColor.white.set()
        glyph.draw(in: NSRect(x: gx, y: gy, width: dw, height: dh),
                   from: .zero, operation: .sourceOver, fraction: 1.0,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (px, name) in targets {
    let rep = renderIcon(px: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed PNG for \(name)\n".data(using: .utf8)!)
        continue
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! data.write(to: url)
    print("wrote \(name) (\(px)px)")
}
