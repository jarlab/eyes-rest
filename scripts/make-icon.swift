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

/// All artwork is authored on Apple's 1024 × 1024 macOS icon grid and scaled to each output size.
let canvas: CGFloat = 1024

/// The Big Sur tile: an 824 × 824 rounded square centred on the canvas, corner radius 22.5 % of its width.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileCornerRadius = tileRect.width * 0.225

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

/// An almond-shaped eye outline with softly pointed corners.
func eyeOutline(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    // A cubic whose control points both sit at height h peaks at 0.75 h, hence the 2/3 factor.
    let lift = height * 2 / 3
    let pull = width * 0.22
    let left = CGPoint(x: center.x - width / 2, y: center.y)
    let right = CGPoint(x: center.x + width / 2, y: center.y)
    let path = CGMutablePath()
    path.move(to: left)
    path.addCurve(to: right, control1: CGPoint(x: center.x - pull, y: center.y + lift),
                  control2: CGPoint(x: center.x + pull, y: center.y + lift))
    path.addCurve(to: left, control1: CGPoint(x: center.x + pull, y: center.y - lift),
                  control2: CGPoint(x: center.x - pull, y: center.y - lift))
    path.closeSubpath()
    return path
}

// MARK: - Palette

/// An sRGB colour as 0–1 components.
struct RGB {
    let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat

    init(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) {
        self.red = CGFloat(red) / 255
        self.green = CGFloat(green) / 255
        self.blue = CGFloat(blue) / 255
        self.alpha = alpha
    }

    var components: [CGFloat] { [red, green, blue, alpha] }
}

enum Palette {
    static let tileTop = RGB(72, 206, 190)        // calm teal
    static let tileBottom = RGB(46, 104, 214)     // soft blue
    static let tileShadow = RGB(0, 0, 0, alpha: 0.28)
    static let gloss = RGB(255, 255, 255, alpha: 0.12)
    static let eyeWhite = RGB(255, 255, 255)
    static let eyeWhiteShade = RGB(226, 238, 250)
    static let eyeShadow = RGB(12, 40, 96, alpha: 0.30)
    static let irisInner = RGB(64, 176, 214)
    static let irisOuter = RGB(24, 86, 176)
    static let irisRim = RGB(20, 70, 150)
    static let pupil = RGB(10, 24, 52)
    static let glint = RGB(255, 255, 255, alpha: 0.95)
}

// MARK: - Drawing

/// Proportions of the eye glyph on the 1024 grid. At 16 and 32 pixels the glyph is larger, flat
/// and aligned to whole pixels (iris 4 px and pupil 2 px wide at 16 px) so it still reads as an eye.
struct EyeStyle {
    let width: CGFloat
    let height: CGFloat
    let irisRadius: CGFloat
    let pupilRadius: CGFloat
    let showsDetail: Bool   // shading, iris rim, glint and shadows

    init(pixels: Int) {
        if pixels <= 32 {
            self.init(width: 640, height: 384, irisRadius: 128, pupilRadius: 64, showsDetail: false)
        } else {
            self.init(width: 600, height: 348, irisRadius: 136, pupilRadius: 58, showsDetail: pixels >= 128)
        }
    }

    private init(width: CGFloat, height: CGFloat, irisRadius: CGFloat, pupilRadius: CGFloat, showsDetail: Bool) {
        self.width = width
        self.height = height
        self.irisRadius = irisRadius
        self.pupilRadius = pupilRadius
        self.showsDetail = showsDetail
    }
}

/// A square that circumscribes the circle at `center` with `radius`.
func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

func drawIcon(in context: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / canvas
    let style = EyeStyle(pixels: pixels)
    let space = context.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    func color(_ c: RGB) -> CGColor { CGColor(colorSpace: space, components: c.components)! }
    func gradient(_ from: RGB, _ to: RGB) -> CGGradient {
        CGGradient(colorSpace: space, colorComponents: from.components + to.components, locations: [0, 1], count: 2)!
    }
    /// Shadow metrics are in device space, unaffected by the CTM, so they are scaled by hand.
    func setShadow(dropping offset: CGFloat, blur: CGFloat, _ c: RGB) {
        context.setShadow(offset: CGSize(width: 0, height: -offset * scale), blur: blur * scale, color: color(c))
    }
    let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: scale, y: scale)

    // Tile: diagonal teal-to-blue gradient over a soft drop shadow, with a faint gloss at the top.
    let tile = continuousRoundedRect(tileRect, radius: tileCornerRadius)
    context.saveGState()
    if style.showsDetail { setShadow(dropping: 10, blur: 20, Palette.tileShadow) }
    context.addPath(tile)
    context.setFillColor(color(Palette.tileBottom))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(gradient(Palette.tileTop, Palette.tileBottom),
                               start: CGPoint(x: tileRect.minX + 120, y: tileRect.maxY),
                               end: CGPoint(x: tileRect.maxX - 120, y: tileRect.minY), options: extend)
    if style.showsDetail {
        context.drawLinearGradient(gradient(Palette.gloss, RGB(255, 255, 255, alpha: 0)),
                                   start: CGPoint(x: 0, y: tileRect.maxY), end: CGPoint(x: 0, y: tileRect.midY),
                                   options: [])
    }
    context.restoreGState()

    // Eye white. At large sizes its pointed corners are softened by merging in a round-joined outline.
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let outline = eyeOutline(center: center, width: style.width, height: style.height)
    let eye = style.showsDetail
        ? outline.union(outline.copy(strokingWithWidth: 24, lineCap: .round, lineJoin: .round, miterLimit: 10))
        : outline
    context.saveGState()
    if style.showsDetail { setShadow(dropping: 12, blur: 36, Palette.eyeShadow) }
    context.addPath(eye)
    context.setFillColor(color(Palette.eyeWhite))
    context.fillPath()
    context.restoreGState()

    // Everything inside the eye is clipped to its outline, so a large iris tucks under the lids.
    context.saveGState()
    context.addPath(eye)
    context.clip()
    if style.showsDetail {
        context.drawLinearGradient(gradient(Palette.eyeWhite, Palette.eyeWhiteShade),
                                   start: CGPoint(x: center.x, y: center.y + style.height * 0.1),
                                   end: CGPoint(x: center.x, y: center.y - style.height / 2), options: extend)
    }

    let iris = circle(center, style.irisRadius)
    context.saveGState()
    context.addEllipse(in: iris)
    context.clip()
    context.drawRadialGradient(gradient(Palette.irisInner, Palette.irisOuter),
                               startCenter: center, startRadius: style.pupilRadius,
                               endCenter: center, endRadius: style.irisRadius, options: extend)
    context.restoreGState()
    if style.showsDetail {
        let rimWidth: CGFloat = 8
        context.addEllipse(in: iris.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
        context.setStrokeColor(color(Palette.irisRim))
        context.setLineWidth(rimWidth)
        context.strokePath()
    }

    context.addEllipse(in: circle(center, style.pupilRadius))
    context.setFillColor(color(Palette.pupil))
    context.fillPath()

    // A catch-light up and to the left, where the tile gradient is lightest.
    if pixels >= 64 {
        let offset = style.pupilRadius * 0.6
        context.addEllipse(in: circle(CGPoint(x: center.x - offset, y: center.y + offset), style.pupilRadius * 0.4))
        context.setFillColor(color(Palette.glint))
        context.fillPath()
    }
    context.restoreGState()
}

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
    drawIcon(in: graphics.cgContext, pixels: pixels)
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
