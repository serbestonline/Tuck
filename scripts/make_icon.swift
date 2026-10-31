import AppKit

// Tuck simgesi: ⌘ işaretinin yanında, arkasına katlanan menüleri saklayan tek kapsül.
// Çizim 120 birimlik bir ızgarada tasarlandı; macOS simge kalıbına göre 1024'lük tuvalin ortasındaki 824'lük kareye ölçeklenir.
//   swift scripts/make_icon.swift build/AppIcon-1024.png

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let k: CGFloat = 824 / 120, inset: CGFloat = 100
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: inset + x * k, y: inset + y * k, width: w * k, height: h * k) }
let ink = NSColor(srgbRed: 0x1F / 255, green: 0x24 / 255, blue: 0x30 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF1 / 255, green: 0xEF / 255, blue: 0xE8 / 255, alpha: 1)

let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
    ink.setFill()
    NSBezierPath(roundedRect: r(0, 0, 120, 120), xRadius: 27 * k, yRadius: 27 * k).fill()
    for (x, y, w, h, alpha) in [(80.0, 56.5, 12.0, 7.0, 0.1), (74, 55, 16, 10, 0.2), (66, 53, 20, 14, 0.35), (40, 50, 38, 20, 1)] {
        paper.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: r(x, y, w, h), xRadius: h / 2 * k, yRadius: h / 2 * k).fill()
    }
    let glyph = NSAttributedString(string: "⌘", attributes: [.font: NSFont.systemFont(ofSize: 20 * k, weight: .medium), .foregroundColor: paper])
    let size = glyph.size()
    glyph.draw(at: NSPoint(x: inset + 26 * k - size.width / 2, y: inset + 60 * k - size.height / 2))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
