#!/usr/bin/env swift
// Regenerates Resources/AppIcon.icns: swift scripts/icon.swift
import AppKit

func render(_ side: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!.retagging(with: .sRGB)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(side)
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // A notification card with an unread dot, drawn rather than taken from SF Symbols.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.18, y: s * 0.36, width: s * 0.64, height: s * 0.28), xRadius: s * 0.09, yRadius: s * 0.09).fill()
    NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.25, y: s * 0.435, width: s * 0.13, height: s * 0.13)).fill()
    NSColor(white: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.43, y: s * 0.515, width: s * 0.31, height: s * 0.045), xRadius: s * 0.0225, yRadius: s * 0.0225).fill()
    NSColor(white: 0.72, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.43, y: s * 0.44, width: s * 0.2, height: s * 0.04), xRadius: s * 0.02, yRadius: s * 0.02).fill()
    return bitmap.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manotify-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for side in [16, 32, 128, 256, 512] {
    try render(side).write(to: set.appendingPathComponent("icon_\(side)x\(side).png"))
    try render(side * 2).write(to: set.appendingPathComponent("icon_\(side)x\(side)@2x.png"))
}
try render(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-preview.png"))
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", "-o", "Resources/AppIcon.icns", set.path]
try tool.run()
tool.waitUntilExit()
exit(tool.terminationStatus)
