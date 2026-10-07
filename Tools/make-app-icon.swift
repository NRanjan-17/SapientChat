// Renders SapientChat's app icon (1024×1024 PNGs) for the three iOS
// appearances: default, dark and tinted. Plain Core Graphics shapes, no
// SF Symbols (their licence doesn't allow them in app icons).
//
//   swift Tools/make-app-icon.swift <output-directory>
//
// Concept: a speech bubble holding three stacked layers — chatting with a
// model that runs on the device. Colours follow the app's accent violet.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0

func color(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: alpha
    )
}

struct Palette {
    let background: (CGColor, CGColor)   // top-left → bottom-right
    let bubble: (CGColor, CGColor)       // top → bottom
    let glyph: (CGColor, CGColor)        // top → bottom
    let glyphGlow: CGColor?
}

let palettes: [(name: String, palette: Palette)] = [
    ("AppIcon", Palette(
        background: (color(0x8F72FF), color(0x4527C9)),
        bubble: (color(0xFFFFFF), color(0xEEE9FF)),
        glyph: (color(0x7A5CF0), color(0x4A2CCB)),
        glyphGlow: nil)),
    ("AppIcon-Dark", Palette(
        background: (color(0x1E1736), color(0x0C0916)),
        bubble: (color(0x9B82FF), color(0x5B3DDB)),
        glyph: (color(0xFFFFFF), color(0xE9E3FF)),
        glyphGlow: color(0xFFFFFF, 0.35))),
    ("AppIcon-Tinted", Palette(
        background: (color(0x000000), color(0x000000)),
        bubble: (color(0xFFFFFF), color(0xD6D6D6)),
        glyph: (color(0x000000), color(0x000000)),
        glyphGlow: nil)),
]

/// The speech bubble: a rounded rectangle merged with a curved tail at the
/// bottom left (one shape, so fills and shadows have no seams).
func bubblePath() -> CGPath {
    let body = CGPath(roundedRect: CGRect(x: 196, y: 220, width: 632, height: 500),
                      cornerWidth: 160, cornerHeight: 160, transform: nil)
    // Tail: starts inside the body, sweeps down-left to a soft point.
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 290, y: 620))
    tail.addLine(to: CGPoint(x: 300, y: 690))
    tail.addCurve(to: CGPoint(x: 250, y: 830),
                  control1: CGPoint(x: 306, y: 760), control2: CGPoint(x: 290, y: 800))
    tail.addCurve(to: CGPoint(x: 470, y: 700),
                  control1: CGPoint(x: 350, y: 820), control2: CGPoint(x: 430, y: 770))
    tail.addLine(to: CGPoint(x: 470, y: 620))
    tail.closeSubpath()
    return body.union(tail)
}

/// Three stacked layers: a filled top diamond and two chevrons below it,
/// painted into a transparency layer and then filled with one gradient.
func drawLayers(_ ctx: CGContext, palette: Palette) {
    let cx = 512.0, top = 396.0, halfW = 160.0, halfH = 80.0, step = 72.0, stroke = 34.0

    let diamond = CGMutablePath()
    diamond.move(to: CGPoint(x: cx, y: top - halfH))
    diamond.addLine(to: CGPoint(x: cx + halfW, y: top))
    diamond.addLine(to: CGPoint(x: cx, y: top + halfH))
    diamond.addLine(to: CGPoint(x: cx - halfW, y: top))
    diamond.closeSubpath()

    let chevrons = CGMutablePath()
    for i in 1...2 {
        let y = top + step * Double(i)
        chevrons.move(to: CGPoint(x: cx - halfW, y: y))
        chevrons.addLine(to: CGPoint(x: cx, y: y + halfH))
        chevrons.addLine(to: CGPoint(x: cx + halfW, y: y))
    }

    ctx.saveGState()
    if let glow = palette.glyphGlow {
        ctx.setShadow(offset: .zero, blur: 40, color: glow)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.setStrokeColor(gray: 0, alpha: 1)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(diamond)
    ctx.drawPath(using: .fillStroke)
    ctx.addPath(chevrons)
    ctx.strokePath()
    // Keep only what was just painted, recoloured with the gradient.
    ctx.setBlendMode(.sourceIn)
    let gradient = CGGradient(colorsSpace: nil, colors: [palette.glyph.0, palette.glyph.1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: cx, y: top - halfH), end: CGPoint(x: cx, y: top + 2 * step + halfH),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func render(_ palette: Palette, to url: URL) throws {
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Top-down coordinates.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let background = CGGradient(colorsSpace: nil, colors: [palette.background.0, palette.background.1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: size, y: size), options: [])

    // Bubble with a soft drop shadow, then its own vertical gradient.
    let bubble = bubblePath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 48, color: color(0x000000, 0.28))
    ctx.addPath(bubble)
    ctx.setFillColor(palette.bubble.0)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bubble)
    ctx.clip()
    let bubbleGradient = CGGradient(colorsSpace: nil, colors: [palette.bubble.0, palette.bubble.1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bubbleGradient, start: CGPoint(x: 512, y: 220), end: CGPoint(x: 512, y: 836), options: [])
    ctx.restoreGState()

    drawLayers(ctx, palette: palette)

    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, palette) in palettes {
    let url = output.appendingPathComponent("\(name).png")
    try render(palette, to: url)
    print("wrote \(url.path)")
}
