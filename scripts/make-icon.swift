#!/usr/bin/env swift
// Renders the EyeRest app icon into an .iconset folder.
//
//   swift scripts/make-icon.swift build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
//
// Every PNG is drawn into an explicit NSBitmapImageRep of its exact pixel size, so the output never
// depends on the backing scale factor of the Mac running the script (NSImage + lockFocus doubles
// the pixels on Retina displays).

import AppKit

// MARK: - Output

/// The ten images `iconutil` expects in a macOS iconset, with their pixel sizes.
let iconImages: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

// MARK: - Geometry

/// A rounded rectangle with continuous ("squircle") corners, like the system app-icon shape.
///
/// Each corner eases from the straight edge into a circular arc of `radius` over 1.528 × `radius`,
/// using the widely used reverse-engineered control points of Apple's continuous corner.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let extent: CGFloat = 1.528_664_83
    let r = min(radius, min(rect.width, rect.height) / 2 / extent)
    // Clockwise from the top-right corner; `back` points along the edge we arrive on, `ahead` along
    // the edge we leave on (both away from the corner, y axis pointing up).
    let corners: [(corner: CGPoint, back: CGVector, ahead: CGVector)] = [
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]
    let path = CGMutablePath()
    for (index, c) in corners.enumerated() {
        /// A point `x` radii back along the incoming edge and `y` radii ahead along the outgoing edge.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: c.corner.x + (c.back.dx * x + c.ahead.dx * y) * r,
                    y: c.corner.y + (c.back.dy * x + c.ahead.dy * y) * r)
        }
        if index == 0 { path.move(to: p(extent, 0)) } else { path.addLine(to: p(extent, 0)) }
        path.addCurve(to: p(0.669_934_27, 0.065_496_00), control1: p(1.088_493_23, 0), control2: p(0.868_406_89, 0))
        path.addLine(to: p(0.631_493_99, 0.074_911_00))
        path.addCurve(to: p(0.074_911_00, 0.631_493_99),
                      control1: p(0.372_823_92, 0.169_058_99), control2: p(0.169_058_99, 0.372_823_92))
        path.addLine(to: p(0.065_496_00, 0.669_934_27))
        path.addCurve(to: p(0, extent), control1: p(0, 0.868_406_89), control2: p(0, 1.088_493_23))
    }
    path.closeSubpath()
    return path
}

// MARK: - Artwork

// A glossy almond eye resting on a sunlit Frutiger Aero meadow under a clear sky, in the reminder card's palette
// (sky #1D84E6 → #BDEBFF, lime hills, an aqua bubble iris).
//
// CoreGraphics only, y axis up, authored on Apple's 1024 × 1024 macOS icon grid (824 × 824 tile, continuous corners at
// 22.5 % of its width). Colours are raw components in the context's colour space (`renderPNG` tags its bitmaps as
// sRGB). Needs macOS 13+ (`CGPath.union`). At 32 px and below it switches to a flat, pixel-aligned drawing: at 16 px a
// 10 × 6 px eye with a 4 px iris and 2 px pupil; at 32 px the same doubled plus a 1 px catch-light.

/// Draws the icon into `ctx`, filling a `pixelSize` × `pixelSize` square from the context's origin.
func drawAppIcon(in ctx: CGContext, pixelSize: CGFloat) {
    AeroIcon(ctx: ctx, pixels: pixelSize).draw()
}

private struct AeroIcon {
    let ctx: CGContext
    let pixels: CGFloat
    private let space: CGColorSpace

    init(ctx: CGContext, pixels: CGFloat) {
        self.ctx = ctx
        self.pixels = pixels
        space = ctx.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Gradient stops: (0xRRGGBB, alpha, location).
    private typealias Stops = [(UInt32, CGFloat, CGFloat)]

    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private var small: Bool { pixels <= 32 }      // flat, pixel-aligned glyph
    private var detail: Bool { pixels >= 128 }    // shadows, clouds, glints
    private var scale: CGFloat { pixels / 1024 }

    // Eye geometry on the 1024 grid (at ≤ 32 px it snaps to whole pixels of the 16 px grid, 64 units each).
    private var eyeCenter: CGPoint { CGPoint(x: 512, y: small ? 512 : 560) }
    private var eyeSize: CGSize { small ? CGSize(width: 640, height: 384) : CGSize(width: 600, height: 360) }
    private var irisRadius: CGFloat { small ? 128 : 142 }
    private var pupilRadius: CGFloat { small ? 64 : 56 }

    func draw() {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.scaleBy(x: scale, y: scale)
        let tile = continuousRoundedRect(Self.tile, radius: Self.tile.width * 0.225)

        if detail {   // soft drop shadow under the tile
            ctx.saveGState()
            shadow(dropping: 10, blur: 22, color(0x0A2A50, 0.35))
            fill(tile, color(0x2A96EA))
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        drawSky()
        drawMeadow()
        drawEye()
        if pixels >= 256 {
            for (x, y, r) in [(806.0, 468.0, 28.0), (850, 604, 17), (206, 770, 21), (256, 856, 12)] {
                drawBubble(p(x, y), r)
            }
        }
        if detail {   // glass sheen over the upper half and a bright inner rim
            vertical([(0xFFFFFF, 0.22, 0), (0xFFFFFF, 0, 1)], from: 924, to: 600)
            stroke(tile, color(0xFFFFFF, 0.35), width: 10)
        }
        ctx.restoreGState()
    }

    // MARK: Scene

    private func drawSky() {
        if small {   // deeper at the horizon than the large art, so the white eye stands out
            vertical([(0x1D84E6, 1, 0), (0x4DB2F3, 1, 1)], from: 924, to: 330)
            return
        }
        vertical([(0x1D84E6, 1, 0), (0x55BCF6, 1, 0.45), (0xBDEBFF, 1, 1)], from: 924, to: 330)
        radial(center: p(240, 880), radius: 480, [(0xFFFFFF, 0.6, 0), (0xFFFFFF, 0, 1)])   // the sun, top left
        radial(center: p(240, 880), radius: 180, [(0xFFFFFF, 0.55, 0), (0xFFFFFF, 0, 1)])
        if detail {
            drawCloud(center: p(752, 808), width: 290)
            drawCloud(center: p(214, 618), width: 210)
        }
    }

    /// A hazy far hill and a sunlit lime meadow in front, domed under the eye.
    private func drawMeadow() {
        let crest = CGMutablePath()
        if small {
            crest.move(to: p(100, 272))
            crest.addCurve(to: p(924, 272), control1: p(380, 332), control2: p(644, 332))
            fillBelow(crest, [(0xB6EE6A, 1, 0), (0x5DBE3C, 1, 0.45), (0x2F8F2E, 1, 1)], top: 330)
            return
        }
        let far = CGMutablePath()
        far.move(to: p(100, 430))
        far.addCurve(to: p(600, 364), control1: p(260, 530), control2: p(440, 384))
        far.addCurve(to: p(924, 480), control1: p(740, 348), control2: p(850, 480))
        fillBelow(far, [(0xBDEB94, 1, 0), (0x74C463, 1, 1)], top: 500)
        stroke(far, color(0xFFFFFF, 0.5), width: 5)

        crest.move(to: p(100, 300))
        crest.addCurve(to: p(924, 330), control1: p(360, 440), control2: p(660, 430))
        fillBelow(crest, [(0xD4F77C, 1, 0), (0x8ED645, 1, 0.3), (0x3F9F34, 1, 0.75), (0x2A7F2A, 1, 1)], top: 420)
        if detail {   // sunlight pooling on the crest
            ctx.saveGState()
            ctx.addPath(closedBelow(crest))
            ctx.clip()
            radial(center: p(600, 330), radius: 360, [(0xFFFFFF, 0.3, 0), (0xFFFFFF, 0, 1)], squash: 0.3)
            ctx.restoreGState()
        }
        stroke(crest, color(0xF1FFC8, 0.9), width: 7)
    }

    /// A soft cumulus: overlapping puffs drawn only as a blurred shadow, so its edges melt into the sky, with a cool
    /// blue-grey underside.
    private func drawCloud(center c: CGPoint, width s: CGFloat) {
        let puffs = [(-0.3, -0.06, 0.15), (-0.1, 0.05, 0.22), (0.14, 0.02, 0.19), (0.32, -0.06, 0.12), (0, -0.1, 0.18)]
        let cloud = puffs.map { dx, dy, r in
            CGPath(ellipseIn: circle(p(c.x + dx * s, c.y + dy * s), r * s), transform: nil)
        }.reduce(CGMutablePath() as CGPath) { $0.union($1) }
        soft(cloud, color(0xFFFFFF, 0.95), blur: s * 0.06)
        ctx.saveGState()
        ctx.addPath(cloud)
        ctx.clip()
        vertical([(0xFFFFFF, 0, 0.45), (0xC4DCF2, 0.55, 1)], from: c.y + 0.27 * s, to: c.y - 0.28 * s)
        ctx.restoreGState()
    }

    private func drawBubble(_ c: CGPoint, _ r: CGFloat) {
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, r))
        ctx.clip()
        radial(center: c, radius: r, [(0xFFFFFF, 0.06, 0), (0xFFFFFF, 0.16, 0.62), (0xFFFFFF, 0.7, 1)])
        radial(center: p(c.x + r * 0.35, c.y - r * 0.4), radius: r * 0.5, [(0xB9FFF2, 0.7, 0), (0xB9FFF2, 0, 1)])
        ctx.restoreGState()
        stroke(CGPath(ellipseIn: circle(c, r - 1.2), transform: nil), color(0xFFFFFF, 0.55), width: 2.4)
        dot(p(c.x - r * 0.38, c.y + r * 0.4), r * 0.28, color(0xFFFFFF, 0.95))
    }

    // MARK: Eye

    /// The eye is a clear water drop: white at the top, aqua towards the bottom, the sky gathered along its edge.
    private func drawEye() {
        let c = eyeCenter
        let eye = almond(center: c, size: eyeSize)

        if detail {   // its shadow on the grass
            ctx.saveGState()
            shadow(dropping: 22, blur: 44, color(0x0C3D2A, 0.38))
            fill(eye, color(0xDDF4FF))
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(eye)
        ctx.clip()
        if small {
            fill(eye, color(0xFFFFFF))
        } else {
            vertical([(0xFFFFFF, 1, 0), (0xF4FCFF, 1, 0.5), (0xC6ECFC, 1, 1)],
                     from: c.y + eyeSize.height / 2, to: c.y - eyeSize.height / 2)
            innerGlow(eye, color(0x3AA8E8, 0.85), blur: detail ? 52 : 26)
        }
        drawIris(at: c)
        if !small {   // one broad soft reflection over the upper half
            radial(center: p(c.x - eyeSize.width * 0.05, c.y + eyeSize.height * 0.33), radius: eyeSize.width * 0.38,
                   [(0xFFFFFF, 0.7, 0), (0xFFFFFF, 0.25, 0.55), (0xFFFFFF, 0, 1)], squash: 0.3)
        }
        if pixels > 32 {   // catch-light up and to the left, where the sun is
            dot(p(c.x - pupilRadius * 1.05, c.y + pupilRadius * 1.05), 28, color(0xFFFFFF))
        } else if pixels == 32 {   // exactly one pixel, on the pupil's upper-left corner
            fill(CGPath(rect: CGRect(x: 448, y: 544, width: 32, height: 32), transform: nil), color(0xFFFFFF))
        }
        if detail { dot(p(c.x + irisRadius * 0.5, c.y - irisRadius * 0.5), 11, color(0xFFFFFF, 0.75)) }
        ctx.restoreGState()
        if !small { stroke(eye, color(0x1C6FC0, 0.42), width: detail ? 5 : 10) }
    }

    /// The iris is a water bubble: aqua at the heart, deep blue at its rim, the meadow reflected upside down in its top
    /// and light gathered into a bright crescent at the bottom.
    private func drawIris(at c: CGPoint) {
        guard !small else {
            dot(c, irisRadius, color(0x1683CC))
            dot(c, pupilRadius, color(0x062448))
            return
        }
        let iris = circle(c, irisRadius)
        ctx.saveGState()
        ctx.addEllipse(in: iris)
        ctx.clip()
        radial(center: c, radius: irisRadius, [(0x8AF0E8, 1, 0.3), (0x22AED6, 1, 0.64), (0x0A56A6, 1, 1)])
        vertical([(0x9BE05A, 0.8, 0), (0x9BE05A, 0, 0.45)], from: c.y + irisRadius, to: c.y - irisRadius)
        ctx.addEllipse(in: iris)
        ctx.addEllipse(in: circle(p(c.x, c.y + irisRadius * 0.16), irisRadius))
        ctx.clip(using: .evenOdd)   // a crescent along the bottom
        vertical([(0xC8FFFF, 0, 0), (0xC8FFFF, 0.85, 1)], from: c.y - irisRadius * 0.55, to: c.y - irisRadius)
        ctx.restoreGState()
        stroke(CGPath(ellipseIn: iris.insetBy(dx: 3, dy: 3), transform: nil), color(0x0A4A8E, 0.9), width: 6)

        ctx.saveGState()
        ctx.addEllipse(in: circle(c, pupilRadius))
        ctx.clip()
        radial(center: p(c.x, c.y - pupilRadius * 0.3), radius: pupilRadius * 1.3, [(0x0E3A6A, 1, 0), (0x041A36, 1, 1)])
        ctx.restoreGState()
    }

    /// An almond eye outline whose pointed corners are slightly softened at large sizes.
    private func almond(center c: CGPoint, size: CGSize) -> CGPath {
        let lift = size.height * 2 / 3   // a cubic with both control points at h peaks at 0.75 h
        let pull = size.width * 0.22
        let left = p(c.x - size.width / 2, c.y), right = p(c.x + size.width / 2, c.y)
        let path = CGMutablePath()
        path.move(to: left)
        path.addCurve(to: right, control1: p(c.x - pull, c.y + lift), control2: p(c.x + pull, c.y + lift))
        path.addCurve(to: left, control1: p(c.x + pull, c.y - lift), control2: p(c.x - pull, c.y - lift))
        path.closeSubpath()
        guard detail else { return path }
        return path.union(path.copy(strokingWithWidth: 26, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    // MARK: Primitives (1024-grid units)

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        let c = [CGFloat((hex >> 16) & 0xFF), CGFloat((hex >> 8) & 0xFF), CGFloat(hex & 0xFF)].map { $0 / 255 }
        return CGColor(colorSpace: space, components: c + [alpha])!
    }

    private func gradient(_ stops: Stops) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map(\.2))!
    }

    /// A vertical linear gradient across the whole clip, from `top` to `bottom` (y up).
    private func vertical(_ stops: Stops, from top: CGFloat, to bottom: CGFloat) {
        ctx.drawLinearGradient(gradient(stops), start: p(0, top), end: p(0, bottom),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A radial gradient, optionally squashed vertically into an ellipse.
    private func radial(center: CGPoint, radius: CGFloat, _ stops: Stops, squash: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1, y: squash)
        ctx.drawRadialGradient(gradient(stops), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius,
                               options: [])
        ctx.restoreGState()
    }

    private func closedBelow(_ crest: CGPath) -> CGPath {
        let path = crest.mutableCopy()!
        path.addLine(to: p(924, 0))
        path.addLine(to: p(100, 0))
        path.closeSubpath()
        return path
    }

    /// Fills the region under an open crest line with a vertical gradient from `top` down to the tile's bottom.
    private func fillBelow(_ crest: CGPath, _ stops: Stops, top: CGFloat) {
        ctx.saveGState()
        ctx.addPath(closedBelow(crest))
        ctx.clip()
        vertical(stops, from: top, to: 100)
        ctx.restoreGState()
    }

    /// Soft light along the inside of `path`: the shadow of everything outside it, cast inwards.
    private func innerGlow(_ path: CGPath, _ glow: CGColor, blur: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur * scale, color: glow)
        let ring = CGMutablePath()
        ring.addRect(path.boundingBox.insetBy(dx: -200, dy: -200))
        ring.addPath(path)
        ctx.addPath(ring)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    /// Fills `path` blurred: the shape is drawn far off to the side and only its shadow lands in place.
    private func soft(_ path: CGPath, _ c: CGColor, blur: CGFloat) {
        let away: CGFloat = 4096
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: away * scale, height: 0), blur: blur * scale, color: c)
        ctx.translateBy(x: -away, y: 0)
        fill(path, color(0xFFFFFF))
        ctx.restoreGState()
    }

    /// Shadow metrics are in device space, unaffected by the CTM, so they are scaled by hand.
    private func shadow(dropping offset: CGFloat, blur: CGFloat, _ c: CGColor) {
        ctx.setShadow(offset: CGSize(width: 0, height: -offset * scale), blur: blur * scale, color: c)
    }

    private func fill(_ path: CGPath, _ c: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(c)
        ctx.fillPath()
    }

    private func dot(_ center: CGPoint, _ radius: CGFloat, _ c: CGColor) {
        fill(CGPath(ellipseIn: circle(center, radius), transform: nil), c)
    }

    private func stroke(_ path: CGPath, _ c: CGColor, width: CGFloat) {
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(c)
        ctx.strokePath()
    }
}

// MARK: - Rendering

/// Draws the icon at `pixels` × `pixels` and returns it PNG-encoded.
func renderPNG(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    drawAppIcon(in: graphics.cgContext, pixelSize: CGFloat(pixels))
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    // Colours were written as raw components, so tag the pixels as sRGB (no conversion) before encoding.
    return rep.retagging(with: .sRGB)?.representation(using: .png, properties: [:])
}

// MARK: - Main

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(code)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, let outputPath = arguments.first, outputPath.hasSuffix(".iconset") else {
    fail("usage: swift scripts/make-icon.swift <output>.iconset", code: 64)
}

let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(outputURL.path): \(error.localizedDescription)")
}

for image in iconImages {
    guard let png = renderPNG(pixels: image.pixels) else { fail("could not render \(image.name)") }
    let fileURL = outputURL.appendingPathComponent("\(image.name).png")
    do {
        try png.write(to: fileURL, options: .atomic)
    } catch {
        fail("cannot write \(fileURL.path): \(error.localizedDescription)")
    }
}
print("make-icon: wrote \(iconImages.count) images to \(outputURL.path)")
