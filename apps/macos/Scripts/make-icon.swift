// Draws WallVue's app icon and writes an .iconset folder.
// Usage: swift Scripts/make-icon.swift <output.iconset>
// Then:  iconutil -c icns <output.iconset> -o Resources/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func glow(_ cg: CGContext, _ hex: UInt32, x: CGFloat, y: CGFloat, radius: CGFloat, alpha: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                          endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let s = CGFloat(pixels)

    // Standard macOS icon body: 824pt square on a 1024pt canvas.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = CGPath(roundedRect: body, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.35))
    cg.addPath(shape)
    cg.setFillColor(color(0x0A0F24))
    cg.fillPath()
    cg.restoreGState()

    // Night-sky base with three soft glows, like light moving across a wall.
    cg.saveGState()
    cg.addPath(shape)
    cg.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let base = CGGradient(colorsSpace: space, colors: [color(0x1A2466), color(0x070B1C)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(base, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    glow(cg, 0x2BD9C6, x: s * 0.22, y: s * 0.30, radius: s * 0.55, alpha: 0.85)
    glow(cg, 0x8B3DFF, x: s * 0.80, y: s * 0.74, radius: s * 0.55, alpha: 0.80)
    glow(cg, 0xFF7A3D, x: s * 0.66, y: s * 0.18, radius: s * 0.38, alpha: 0.55)
    cg.restoreGState()

    // A display outline with a play mark: "your screen, playing".
    let screen = CGRect(x: s * 0.24, y: s * 0.36, width: s * 0.52, height: s * 0.34)
    let screenPath = CGPath(roundedRect: screen, cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: s * 0.02, color: color(0x000000, 0.25))
    cg.addPath(screenPath)
    cg.setStrokeColor(color(0xFFFFFF, 0.96))
    cg.setLineWidth(s * 0.034)
    cg.strokePath()

    // Stand
    cg.setLineCap(.round)
    cg.move(to: CGPoint(x: s * 0.41, y: s * 0.285))
    cg.addLine(to: CGPoint(x: s * 0.59, y: s * 0.285))
    cg.setLineWidth(s * 0.034)
    cg.strokePath()

    // Play triangle, nudged right so it looks centred.
    let cx = screen.midX + s * 0.012, cy = screen.midY, r = s * 0.075
    cg.move(to: CGPoint(x: cx - r * 0.75, y: cy + r))
    cg.addLine(to: CGPoint(x: cx + r, y: cy))
    cg.addLine(to: CGPoint(x: cx - r * 0.75, y: cy - r))
    cg.closePath()
    cg.setFillColor(color(0xFFFFFF, 0.96))
    cg.setLineJoin(.round)
    cg.fillPath()
    cg.restoreGState()

    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(points * scale).write(to: output.appendingPathComponent(name))
}
print("Wrote \(output.path)")
