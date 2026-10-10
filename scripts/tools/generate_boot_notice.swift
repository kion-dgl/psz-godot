// macOS: swift scripts/tools/generate_boot_notice.swift
// Reproducible typography-only engine splash. Keep /journey/splash in sync.
import AppKit
let width = 1920, height = 1080
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
    pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func line(_ text: String, _ size: CGFloat, _ baseline: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Arial", size: size)!, .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    str.draw(at: NSPoint(x: (CGFloat(width) - str.size().width) / 2, y: baseline))
}
line("Phantasy Star Zero fan remake", 54, 635)
line("Unofficial. Not affiliated with or endorsed by SEGA.", 36, 535)
line("Phantasy Star Zero and its original content © SEGA.", 36, 485)
line("Follow @wagieweeb on X for updates.", 36, 370)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "splash_screen.png"))
