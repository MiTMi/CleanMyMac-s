#!/usr/bin/env swift
// Renders Spruce's original app icon (Prism design system) into an .iconset folder.
//
//   swift scripts/make-icon.swift build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o Spruce.icns
//
// Artwork: a superellipse "squircle" on an indigo night sky with drifting aurora
// blooms (violet, cyan, mint), a glass lens lit from the top-left, and a stylised
// spruce sprig with a sparkle. Everything is drawn procedurally with CoreGraphics —
// no bitmaps, no third-party artwork.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Colour helpers

var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Gradient from (colour, alpha, location) stops.
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient? {
    let colors = stops.map { rgb($0.0, $0.1) } as CFArray
    let locations: [CGFloat] = stops.map { $0.2 }
    return CGGradient(colorsSpace: sRGB, colors: colors, locations: locations)
}

// MARK: - Shapes

/// Superellipse |x|^n + |y|^n = 1 fitted to `rect` (n = 5 approximates the macOS squircle).
func squircle(in rect: CGRect, exponent n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = Double(rect.width) / 2
    let b = Double(rect.height) / 2
    let cx = Double(rect.midX)
    let cy = Double(rect.midY)
    let steps = 720
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * Double.pi
        let c = cos(t)
        let s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        let point = CGPoint(x: x, y: y)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func circle(center: CGPoint, radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
}

/// Four-point sparkle star.
func sparkle(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let pinch: CGFloat = 0.2
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * pinch, y: c.y + r * pinch))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * pinch, y: c.y - r * pinch))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * pinch, y: c.y - r * pinch))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * pinch, y: c.y + r * pinch))
    path.closeSubpath()
    return path
}

/// Stylised spruce sprig: a stem with stacked chevron branches (y up).
func spruceMark(center c: CGPoint, unit u: CGFloat, simplified: Bool) -> CGPath {
    let path = CGMutablePath()
    let tiers: [(apex: CGFloat, armX: CGFloat, armY: CGFloat)] = simplified
        ? [(0.42, 0.34, 0.06), (0.10, 0.50, -0.28)]
        : [(0.50, 0.24, 0.25), (0.26, 0.36, -0.03), (0.01, 0.48, -0.31)]
    path.move(to: CGPoint(x: c.x, y: c.y + u * (simplified ? 0.42 : 0.50)))
    path.addLine(to: CGPoint(x: c.x, y: c.y - u * 0.50))
    for tier in tiers {
        path.move(to: CGPoint(x: c.x - u * tier.armX, y: c.y + u * tier.armY))
        path.addLine(to: CGPoint(x: c.x, y: c.y + u * tier.apex))
        path.addLine(to: CGPoint(x: c.x + u * tier.armX, y: c.y + u * tier.armY))
    }
    return path
}

// MARK: - Drawing

func fillRadial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: UInt32, alpha: CGFloat) {
    guard let g = gradient([(color, alpha, 0), (color, alpha * 0.45, 0.45), (color, 0, 1)]) else { return }
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Draws the icon in a 1024 × 1024 design space (y up), scaled to `size` pixels.
func drawIcon(_ ctx: CGContext, size: CGFloat) {
    let k = size / 1024
    let detailed = size >= 64
    let simplified = size <= 32
    ctx.scaleBy(x: k, y: k)

    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = squircle(in: bodyRect)

    // Drop shadow (shadow metrics are in device space, so scale them by hand).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * k), blur: 28 * k, color: rgb(0x000000, 0.38))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0x120E33))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // Night-sky base: deep indigo, brighter toward the bottom.
    if let base = gradient([(0x0C0A22, 1, 0), (0x1B1450, 1, 0.55), (0x2C2070, 1, 1)]) {
        ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    // Aurora blooms.
    fillRadial(ctx, center: CGPoint(x: 250, y: 250), radius: 620, color: 0x6F5CFF, alpha: 0.80)
    fillRadial(ctx, center: CGPoint(x: 790, y: 800), radius: 540, color: 0x45D9F5, alpha: 0.55)
    fillRadial(ctx, center: CGPoint(x: 870, y: 190), radius: 400, color: 0x3BE8A9, alpha: 0.28)
    if detailed {
        fillRadial(ctx, center: CGPoint(x: 160, y: 860), radius: 300, color: 0xB98CFF, alpha: 0.22)
    }

    // Glass lens.
    let c = CGPoint(x: 512, y: 500)
    let r: CGFloat = 292
    fillRadial(ctx, center: c, radius: r * 1.32, color: 0x45D9F5, alpha: 0.30)

    let lens = circle(center: c, radius: r)
    ctx.saveGState()
    ctx.addPath(lens)
    ctx.clip()
    if let bodyGradient = gradient([(0x45D9F5, 0.95, 0), (0x8C7BFF, 1, 0.55), (0x241A5C, 0.98, 1)]) {
        ctx.drawRadialGradient(bodyGradient,
                               startCenter: CGPoint(x: c.x - r * 0.30, y: c.y + r * 0.35), startRadius: 0,
                               endCenter: c, endRadius: r * 1.06, options: [.drawsAfterEndLocation])
    }
    // Light pooling from below.
    fillRadial(ctx, center: CGPoint(x: c.x, y: c.y - r * 0.95), radius: r * 0.95, color: 0x45D9F5, alpha: 0.45)
    // Frosted core.
    ctx.addPath(circle(center: c, radius: r * 0.72))
    ctx.setFillColor(rgb(0xFFFFFF, 0.10))
    ctx.fillPath()
    ctx.addPath(circle(center: c, radius: r * 0.72))
    ctx.setLineWidth(3)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
    ctx.strokePath()
    ctx.restoreGState()

    // Spruce sprig with a cyan glow, then a white → ice gradient fill.
    let mark = spruceMark(center: CGPoint(x: c.x, y: c.y - r * 0.02), unit: r, simplified: simplified)
    let markWidth: CGFloat = r * (simplified ? 0.15 : 0.085)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34 * k, color: rgb(0x45D9F5, 0.95))
    ctx.addPath(mark)
    ctx.setLineWidth(markWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.strokePath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(mark)
    ctx.setLineWidth(markWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let ice = gradient([(0xFFFFFF, 1, 0), (0xD8F7FF, 1, 0.6), (0xB4ECFF, 1, 1)]) {
        ctx.drawLinearGradient(ice, start: CGPoint(x: c.x, y: c.y + r * 0.55), end: CGPoint(x: c.x, y: c.y - r * 0.55), options: [])
    }
    ctx.restoreGState()

    // Sparkles.
    let sparkles: [(CGPoint, CGFloat)] = detailed
        ? [(CGPoint(x: c.x + r * 0.52, y: c.y + r * 0.50), r * 0.16), (CGPoint(x: c.x - r * 0.56, y: c.y + r * 0.30), r * 0.075)]
        : [(CGPoint(x: c.x + r * 0.52, y: c.y + r * 0.50), r * 0.2)]
    for (center, radius) in sparkles {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 22 * k, color: rgb(0x7FE6FF, 0.9))
        ctx.addPath(sparkle(center: center, radius: radius))
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()
    }

    if detailed {
        // Specular highlight, top-left of the lens.
        ctx.saveGState()
        ctx.addPath(lens)
        ctx.clip()
        ctx.translateBy(x: c.x - r * 0.26, y: c.y + r * 0.60)
        ctx.rotate(by: 20 * .pi / 180)
        let highlight = CGRect(x: -r * 0.52, y: -r * 0.15, width: r * 1.04, height: r * 0.30)
        ctx.addEllipse(in: highlight)
        ctx.clip()
        if let shine = gradient([(0xFFFFFF, 0.55, 0), (0xFFFFFF, 0, 1)]) {
            ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: highlight.maxY), end: CGPoint(x: 0, y: highlight.minY), options: [])
        }
        ctx.restoreGState()
    }

    // Lens rim: bright top-left, clear middle, cyan bottom-right.
    ctx.saveGState()
    ctx.addPath(lens)
    ctx.setLineWidth(detailed ? 5 : 9)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let rim = gradient([(0xFFFFFF, 0.9, 0), (0xFFFFFF, 0.12, 0.5), (0x7FE6FF, 0.8, 1)]) {
        ctx.drawLinearGradient(rim, start: CGPoint(x: c.x - r, y: c.y + r), end: CGPoint(x: c.x + r, y: c.y - r), options: [])
    }
    ctx.restoreGState()

    // Inner top highlight along the squircle edge.
    ctx.addPath(body)
    ctx.setLineWidth(detailed ? 6 : 10)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let edge = gradient([(0xFFFFFF, 0.40, 0), (0xFFFFFF, 0.0, 0.45), (0xFFFFFF, 0.0, 1)]) {
        ctx.drawLinearGradient(edge, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    ctx.restoreGState()
}

func renderIcon(pixels: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    drawIcon(ctx, size: CGFloat(pixels))
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <out.iconset>\n".utf8))
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("make-icon: cannot create \(outputDirectory.path): \(error)\n".utf8))
    exit(73)
}

let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

var rendered: [Int: CGImage] = [:]
var failures = 0
for variant in variants {
    let image: CGImage?
    if let cached = rendered[variant.pixels] {
        image = cached
    } else {
        image = renderIcon(pixels: variant.pixels)
        rendered[variant.pixels] = image
    }
    let url = outputDirectory.appendingPathComponent(variant.name)
    if let image, writePNG(image, to: url) {
        print("wrote \(url.path)")
    } else {
        failures += 1
        FileHandle.standardError.write(Data("make-icon: failed to write \(variant.name)\n".utf8))
    }
}
exit(failures == 0 ? 0 : 1)
