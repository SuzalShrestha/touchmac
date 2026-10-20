// Renders AppIcon.icns: a dark squircle with a top-down MacBook and tap ripples.
// Run from app/: swift tools/make_icon.swift && iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // squircle background (Big Sur grid: 824/1024 body)
    let body = r(0.0977, 0.0977, 0.8047, 0.8047)
    let bg = NSBezierPath(roundedRect: body, xRadius: 0.18 * s, yRadius: 0.18 * s)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1),
                        NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)])!.draw(in: bg, angle: -90)
    bg.addClip()  // keep the ripples inside the squircle

    // ripples on the right, where the finger taps the desk
    let tap = CGPoint(x: 0.73 * s, y: 0.36 * s)
    for (i, radius) in [0.06, 0.12, 0.18].enumerated() {
        ctx.setStrokeColor(NSColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.9 - Double(i) * 0.28).cgColor)
        ctx.setLineWidth(0.018 * s)
        ctx.strokeEllipse(in: CGRect(x: tap.x - radius * s, y: tap.y - radius * s, width: 2 * radius * s, height: 2 * radius * s))
    }
    ctx.setFillColor(NSColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: tap.x - 0.03 * s, y: tap.y - 0.03 * s, width: 0.06 * s, height: 0.06 * s))

    // MacBook from above
    let laptop = r(0.2, 0.42, 0.44, 0.3)
    NSGradient(colors: [NSColor(white: 0.82, alpha: 1), NSColor(white: 0.6, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: laptop, xRadius: 0.03 * s, yRadius: 0.03 * s), angle: -90)
    NSColor(white: 0.12, alpha: 0.75).setFill()
    for row in 0..<4 {
        for col in 0..<9 {
            NSBezierPath(roundedRect: r(0.235 + CGFloat(col) * 0.0415, 0.635 - CGFloat(row) * 0.035, 0.034, 0.026),
                         xRadius: 0.005 * s, yRadius: 0.005 * s).fill()
        }
    }
    NSColor(white: 0.12, alpha: 0.35).setFill()
    NSBezierPath(roundedRect: r(0.36, 0.445, 0.12, 0.06), xRadius: 0.01 * s, yRadius: 0.01 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote \(dir.path)")
