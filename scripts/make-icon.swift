// Draws Caliper's app icon and writes it as an .icns, so the icon is rebuilt from source
// like the rest of the app and needs no asset catalog, which needs Xcode.
//
//   swift scripts/make-icon.swift Resources/AppIcon.icns          # the shipped colour
//   swift scripts/make-icon.swift out.icns "#10B981" preview.png  # another colour, plus a PNG
//
// One emerald field with a white dimension line: a tick at each end and an arrow into
// each, the way a measurement is drawn.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: make-icon.swift OUTPUT.icns [#RRGGBB] [PREVIEW.png]")
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let hex = arguments.count > 2 ? arguments[2] : "#10B981"

func color(_ hex: String, lighter: CGFloat = 0) -> NSColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x10B981
    func channel(_ shift: UInt32) -> CGFloat {
        let base = CGFloat((value >> shift) & 0xFF) / 255
        return base + (1 - base) * lighter
    }
    return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
}

/// The whole icon on Apple's 1024 point grid: an 824 point rounded square with room
/// around it for the shadow.
func drawIcon(side: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        let unit = side / 1024
        let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
        shadow.shadowBlurRadius = 24 * unit
        shadow.set()
        color(hex).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // One hue, a touch lighter at the top, for depth without a second colour.
        NSGradient(starting: color(hex, lighter: 0.14), ending: color(hex))?.draw(in: shape, angle: -90)

        NSColor.white.setStroke()
        let line = NSBezierPath()
        func segment(_ points: [(CGFloat, CGFloat)]) {
            line.move(to: NSPoint(x: points[0].0 * unit, y: points[0].1 * unit))
            for point in points.dropFirst() { line.line(to: NSPoint(x: point.0 * unit, y: point.1 * unit)) }
        }
        segment([(300, 400), (300, 624)])
        segment([(724, 400), (724, 624)])
        segment([(300, 512), (724, 512)])
        segment([(400, 582), (310, 512), (400, 442)])
        segment([(624, 582), (714, 512), (624, 442)])
        line.lineWidth = 60 * unit
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.stroke()
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Caliper-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let pixels = points * factor
        try png(drawIcon(side: CGFloat(pixels)), pixels: pixels)?.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(1) }

if arguments.count > 3 {
    try png(drawIcon(side: 512), pixels: 512)?.write(to: URL(fileURLWithPath: arguments[3]))
}
print("Wrote \(output.path)")
