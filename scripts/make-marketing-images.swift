// Composes the README hero images, the GitHub social preview and an animated size tour
// from the demo renders in docs/images (see `ClaudeUsageWidget --snapshot ... --demo`).
//
//   swiftc -O -sdk "$(xcrun --show-sdk-path)" scripts/make-marketing-images.swift -o /tmp/make-images
//   /tmp/make-images docs/images
//
// The background is a generated gradient; no third-party artwork is used.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"

func load(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: "\(directory)/\(name)") else { fatalError("missing \(name)") }
    return image
}

/// Draws into a bitmap of exactly `size` pixels (scale 1), so that the output size is not tied to the display.
func render(_ size: NSSize, _ draw: (NSSize) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(size)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func gradient(_ size: NSSize, dark: Bool) {
    let colors: [NSColor] = dark
        ? [NSColor(red: 0.09, green: 0.10, blue: 0.16, alpha: 1), NSColor(red: 0.30, green: 0.17, blue: 0.22, alpha: 1)]
        : [NSColor(red: 0.93, green: 0.90, blue: 0.97, alpha: 1), NSColor(red: 0.99, green: 0.88, blue: 0.82, alpha: 1)]
    NSGradient(colors: colors)!.draw(in: NSRect(origin: .zero, size: size), angle: 35)
}

/// Draws a widget render with a soft shadow, scaled so that one render point is `scale` output pixels.
func place(_ image: NSImage, at origin: NSPoint, scale: CGFloat) {
    let size = NSSize(width: image.size.width / 2 * scale, height: image.size.height / 2 * scale)
    let rect = NSRect(origin: origin, size: size)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, maxWidth: CGFloat = 1000) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
    NSAttributedString(string: string, attributes: attributes)
        .draw(in: NSRect(x: point.x, y: point.y, width: maxWidth, height: size * 4))
}

func writePNG(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/\(name)"))
    print("wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

// MARK: Social preview (1280 x 640)

func social(lang: String, title: String, subtitle: String) -> NSBitmapImageRep {
    render(NSSize(width: 1280, height: 640)) { size in
        gradient(size, dark: true)
        let light = NSColor.white
        text(title, at: NSPoint(x: 72, y: 360), size: 64, weight: .bold, color: light, maxWidth: 560)
        text(subtitle, at: NSPoint(x: 72, y: 240), size: 26, weight: .regular, color: light.withAlphaComponent(0.78), maxWidth: 520)
        text("macOS 14+  ·  Universal  ·  MIT", at: NSPoint(x: 72, y: 72), size: 20, weight: .medium,
             color: light.withAlphaComponent(0.6), maxWidth: 520)
        place(load("large-\(lang)-dark.png"), at: NSPoint(x: 690, y: 60), scale: 1.5)
        place(load("small-\(lang)-light.png"), at: NSPoint(x: 560, y: 44), scale: 1.0)
    }
}

writePNG(social(lang: "en", title: "Claude Usage\nWidget",
                subtitle: "5-hour and weekly limits, a GitHub-style activity heatmap and Claude Code token usage on your macOS desktop."),
         "social-preview.png")

// MARK: README hero images

func hero(lang: String, dark: Bool) -> NSBitmapImageRep {
    let ink = dark ? NSColor.white : NSColor(white: 0.16, alpha: 1)
    let tagline = lang == "zh"
        ? "原生尺寸 · 真实额度 · 使用热力图"
        : "Native sizes · Real plan limits · Activity heatmap"
    return render(NSSize(width: 1400, height: 520)) { size in
        gradient(size, dark: dark)
        place(load("small-\(lang)-light.png"), at: NSPoint(x: 70, y: 150), scale: 1.25)
        place(load("large-\(lang)-\(dark ? "dark" : "light").png"), at: NSPoint(x: 340, y: 50), scale: 1.2)
        place(load("medium-\(lang)-light.png"), at: NSPoint(x: 830, y: 290), scale: 1.1)
        text(tagline, at: NSPoint(x: 830, y: 170), size: 22, weight: .semibold, color: ink.withAlphaComponent(0.85), maxWidth: 520)
    }
}

writePNG(hero(lang: "en", dark: false), "hero-en.png")
writePNG(hero(lang: "zh", dark: false), "hero-zh.png")

// MARK: Animated size tour (GIF)

func tourFrame(lang: String, size name: String, caption: String) -> CGImage {
    let canvas = NSSize(width: 760, height: 460)
    let rep = render(canvas) { size in
        gradient(size, dark: false)
        let image = load("\(name)-\(lang)-light.png")
        let scale: CGFloat = name == "extraLarge" ? 1.0 : 1.0
        let w = image.size.width / 2 * scale, h = image.size.height / 2 * scale
        place(image, at: NSPoint(x: (size.width - w) / 2, y: (size.height - h) / 2 + 14), scale: scale)
        text(caption, at: NSPoint(x: 24, y: 20), size: 20, weight: .semibold, color: NSColor(white: 0.18, alpha: 1), maxWidth: 700)
    }
    return rep.cgImage!
}

func writeGIF(lang: String, captions: [(String, String)], to name: String) {
    let url = URL(fileURLWithPath: "\(directory)/\(name)") as CFURL
    let destination = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, captions.count, nil)!
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
    for (size, caption) in captions {
        let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.6]] as CFDictionary
        CGImageDestinationAddImage(destination, tourFrame(lang: lang, size: size, caption: caption), frameProps)
    }
    precondition(CGImageDestinationFinalize(destination))
    print("wrote \(name)")
}

writeGIF(lang: "en", captions: [("small", "Small  164 × 164"), ("medium", "Medium  344 × 164"),
                                ("large", "Large  344 × 344"), ("extraLarge", "Extra Large  704 × 344")],
         to: "sizes-en.gif")
writeGIF(lang: "zh", captions: [("small", "小  164 × 164"), ("medium", "中  344 × 164"),
                                ("large", "大  344 × 344"), ("extraLarge", "特大  704 × 344")],
         to: "sizes-zh.gif")
