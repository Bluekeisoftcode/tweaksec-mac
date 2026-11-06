// Renders the app icon into the AppIcon asset catalog.
// Usage: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let background = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                        NSColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1)])!
        .draw(in: background, angle: -90)

    // Three slider tracks with knobs: a simple "tweak" motif.
    let knobs: [CGFloat] = [0.30, 0.68, 0.45]
    let accent = NSColor(red: 0.36, green: 0.78, blue: 0.98, alpha: 1)
    for (index, position) in knobs.enumerated() {
        let y = inset.minY + inset.height * (0.72 - CGFloat(index) * 0.22)
        let track = NSBezierPath(roundedRect: NSRect(x: inset.minX + 130, y: y - 14, width: inset.width - 260, height: 28),
                                 xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(0.25).setFill()
        track.fill()
        let x = inset.minX + 130 + (inset.width - 260) * position
        let knob = NSBezierPath(ovalIn: NSRect(x: x - 52, y: y - 52, width: 104, height: 104))
        accent.setFill()
        knob.fill()
    }
    return true
}

let output = URL(fileURLWithPath: "Tweaksec/Resources/Assets.xcassets/AppIcon.appiconset")
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons")
