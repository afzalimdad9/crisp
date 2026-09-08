import AppKit

// Renders the WiseEdit app icon (gradient squircle + white waveform bars) at
// each required pixel size into the directory given as argument 1.
func makeIcon(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.12, green: 0.14, blue: 0.22, alpha: 1).cgColor,  // deep charcoal navy
        NSColor(srgbRed: 0.27, green: 0.26, blue: 0.50, alpha: 1).cgColor,  // muted indigo
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY),
                           options: [])
    ctx.restoreGState()

    NSColor.white.setFill()
    let heights: [CGFloat] = [0.26, 0.46, 0.66, 0.42, 0.30]
    let barW = body.width * 0.085
    let gap = body.width * 0.055
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = body.midX - totalW / 2
    for h in heights {
        let bh = body.height * h
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: body.midY - bh / 2, width: barW, height: bh),
                               xRadius: barW / 2, yRadius: barW / 2)
        bar.fill()
        x += barW + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! makeIcon(size: CGFloat(size)).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
}
print("icons written to \(outDir)")
