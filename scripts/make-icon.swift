// Draws the app icon (a usage gauge with a four-point star) and writes Resources/AppIcon.icns.
//
//   swiftc -O -sdk "$(xcrun --show-sdk-path)" scripts/make-icon.swift -o /tmp/make-icon
//   /tmp/make-icon Resources docs/images/icon.png
//
// The artwork is generated from shapes only; no third-party or brand artwork is used.

import AppKit
import CoreGraphics

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let previewPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func bitmap(_ pixels: Int, _ draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(context.cgContext, CGFloat(pixels) / 1024)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

/// The Big Sur icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    ctx.scaleBy(x: s, y: s)
    let space = CGColorSpaceCreateDeviceRGB()
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Soft drop shadow under the plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.32))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0.1, 0.1, 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    // Plate gradient, dark indigo to warm graphite.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0.08, 0.09, 0.17), color(0.27, 0.15, 0.20)] as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // A faint highlight along the top edge.
    let sheen = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 0.14), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // Gauge: a track and a progress arc that starts at twelve o'clock and runs clockwise.
    let centre = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 262
    let lineWidth: CGFloat = 70
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(color(1, 1, 1, 0.16))
    ctx.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    let progress: CGFloat = 0.68
    let start = CGFloat.pi / 2
    ctx.saveGState()
    ctx.addArc(center: centre, radius: radius, startAngle: start, endAngle: start - progress * .pi * 2, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arc = CGGradient(colorsSpace: space, colors: [color(0.96, 0.62, 0.43), color(0.99, 0.80, 0.45)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(arc, start: CGPoint(x: 250, y: 780), end: CGPoint(x: 780, y: 250), options: [])
    ctx.restoreGState()

    // Four-point star in the middle.
    let reach: CGFloat = 150
    let pinch: CGFloat = 30
    let star = CGMutablePath()
    star.move(to: CGPoint(x: centre.x, y: centre.y + reach))
    star.addQuadCurve(to: CGPoint(x: centre.x + reach, y: centre.y), control: CGPoint(x: centre.x + pinch, y: centre.y + pinch))
    star.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - reach), control: CGPoint(x: centre.x + pinch, y: centre.y - pinch))
    star.addQuadCurve(to: CGPoint(x: centre.x - reach, y: centre.y), control: CGPoint(x: centre.x - pinch, y: centre.y - pinch))
    star.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + reach), control: CGPoint(x: centre.x - pinch, y: centre.y + pinch))
    star.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0, 0, 0, 0.28))
    ctx.addPath(star)
    ctx.setFillColor(color(1, 1, 1, 0.97))
    ctx.fillPath()
    ctx.restoreGState()
}

let master = bitmap(1024, drawIcon)

func resized(_ pixels: Int) -> NSBitmapImageRep {
    bitmap(pixels) { ctx, _ in
        ctx.interpolationQuality = .high
        ctx.draw(master.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    }
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = pixels == 1024 ? master : resized(pixels)
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.icns").path]
try! process.run()
process.waitUntilExit()
precondition(process.terminationStatus == 0, "iconutil failed")
try? fileManager.removeItem(at: iconset)
print("wrote \(outputDirectory)/AppIcon.icns")

if let previewPath {
    try! resized(512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: previewPath))
    print("wrote \(previewPath)")
}
