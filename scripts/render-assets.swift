// render-assets.swift
//
// Renders every visual asset of topNV deterministically, using only
// CoreGraphics, ImageIO and CoreText (no AppKit, no WindowServer).
//
// Usage:
//   swiftc -O scripts/render-assets.swift -o "$TMPDIR/render-assets"
//   "$TMPDIR/render-assets" Assets
//   iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
//
// Output (relative to the output directory):
//   AppIcon.iconset/icon_{16,32,128,256,512}x{...}[@2x].png
//   MenuBarIcon.png, MenuBarIcon@2x.png   (template images, alpha only)
//   cover.png                             (1280x640 social preview)

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

enum RenderError: Error, CustomStringConvertible {
  case colorSpace
  case context(Int, Int)
  case image(String)
  case destination(String)
  case write(String)

  var description: String {
    switch self {
    case .colorSpace: return "cannot create the sRGB color space"
    case .context(let w, let h): return "cannot create a \(w)x\(h) bitmap context"
    case .image(let name): return "cannot create the image for \(name)"
    case .destination(let path): return "cannot create an image destination at \(path)"
    case .write(let path): return "cannot write \(path)"
    }
  }
}

// MARK: - Basics

guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else {
  FileHandle.standardError.write(Data("error: \(RenderError.colorSpace)\n".utf8))
  exit(1)
}

/// Builds an sRGB color from a 0xRRGGBB value and an alpha.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  let r = CGFloat((hex >> 16) & 0xFF) / 255
  let g = CGFloat((hex >> 8) & 0xFF) / 255
  let b = CGFloat(hex & 0xFF) / 255
  return CGColor(colorSpace: srgb, components: [r, g, b, alpha]) ?? CGColor(gray: 0, alpha: alpha)
}

/// Creates a transparent premultiplied RGBA bitmap context.
func makeContext(width: Int, height: Int) throws -> CGContext {
  guard
    let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { throw RenderError.context(width, height) }
  ctx.setShouldAntialias(true)
  ctx.setAllowsAntialiasing(true)
  ctx.interpolationQuality = .high
  return ctx
}

/// Flips a context so that the origin is top-left and y grows downward.
func flipToTopLeft(_ ctx: CGContext, height: Int) {
  ctx.translateBy(x: 0, y: CGFloat(height))
  ctx.scaleBy(x: 1, y: -1)
}

/// Writes an image as PNG, tagging the pixel density (72 dpi = 1x, 144 dpi = 2x).
func writePNG(_ image: CGImage, to url: URL, dpi: Int = 72) throws {
  guard
    let dest = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw RenderError.destination(url.path)
  }
  let props: [CFString: Any] = [
    kCGImagePropertyDPIWidth: dpi,
    kCGImagePropertyDPIHeight: dpi,
  ]
  CGImageDestinationAddImage(dest, image, props as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { throw RenderError.write(url.path) }
}

func linearGradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
  CGGradient(
    colorsSpace: srgb,
    colors: stops.map { $0.1 } as CFArray,
    locations: stops.map { $0.0 }
  )
}

/// Paints a soft radial glow: `hex` at `alpha` in the centre, fully transparent at `radius`.
func glow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, hex: UInt32, alpha: CGFloat) {
  guard
    let g = linearGradient([
      (0, color(hex, alpha)), (0.55, color(hex, alpha * 0.45)), (1, color(hex, 0)),
    ])
  else { return }
  ctx.drawRadialGradient(
    g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// MARK: - Shapes

/// A rounded rectangle with continuous ("squircle") corners.
///
/// Each corner is a superellipse quadrant (exponent 3.2) that starts 1.5 * radius
/// away from the corner, so curvature eases in instead of jumping like a circular arc.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat, exponent: CGFloat = 3.2) -> CGPath {
  let path = CGMutablePath()
  let extent = min(radius * 1.5, rect.width / 2, rect.height / 2)
  guard extent > 0 else {
    path.addRect(rect)
    return path
  }
  let steps = 48
  let p = 2 / exponent
  // Corner centres (where the quadrant is anchored) and the quadrant angles, clockwise
  // in a y-down space starting at the top-left corner.
  let corners: [(CGPoint, CGFloat, CGFloat)] = [
    (CGPoint(x: rect.minX + extent, y: rect.minY + extent), -1, -1),  // top-left
    (CGPoint(x: rect.maxX - extent, y: rect.minY + extent), 1, -1),  // top-right
    (CGPoint(x: rect.maxX - extent, y: rect.maxY - extent), 1, 1),  // bottom-right
    (CGPoint(x: rect.minX + extent, y: rect.maxY - extent), -1, 1),  // bottom-left
  ]
  var first = true
  for (index, corner) in corners.enumerated() {
    let (c, sx, sy) = corner
    for i in 0...steps {
      // t = 0 lies on a vertical edge, t = pi/2 on a horizontal edge. The top-left and
      // bottom-right quadrants run 0 -> pi/2, the other two run backwards, so the
      // whole outline is traced clockwise without crossing itself.
      var t = CGFloat(i) / CGFloat(steps) * (.pi / 2)
      if index % 2 == 1 { t = .pi / 2 - t }
      let dx = pow(cos(t), p)
      let dy = pow(sin(t), p)
      let point = CGPoint(x: c.x + sx * extent * dx, y: c.y + sy * extent * dy)
      if first {
        path.move(to: point)
        first = false
      } else {
        path.addLine(to: point)
      }
    }
  }
  path.closeSubpath()
  return path
}

/// A plain circular-corner rounded rectangle (used where pixel alignment matters).
func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - App icon

/// Level of detail, chosen from the output pixel size so small icons stay legible.
enum Detail {
  case tiny  // 16 and 32 px: bold shapes only
  case small  // 64 px: no menu items, no dashed notch
  case full  // 128 px and up

  init(pixels: Int) {
    if pixels <= 32 { self = .tiny } else if pixels < 128 { self = .small } else { self = .full }
  }
}

/// Draws the aurora wallpaper inside `rect`. The caller sets up the clip.
func drawWallpaper(_ ctx: CGContext, in rect: CGRect, scale: CGFloat, detail: Detail) {
  let w = rect.width
  let h = rect.height
  func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + fx * w, y: rect.minY + fy * h)
  }

  if let base = linearGradient([
    (0.00, color(0x0A1650)),
    (0.40, color(0x2C1B86)),
    (0.70, color(0x7A2B94)),
    (0.88, color(0xD8507E)),
    (1.00, color(0xFF9A5C)),
  ]) {
    ctx.drawLinearGradient(
      base, start: at(0.05, 0), end: at(0.95, 1.1),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }

  glow(ctx, center: at(0.22, 0.30), radius: 0.55 * w, hex: 0x29E3C1, alpha: 0.55)
  glow(ctx, center: at(0.78, 0.50), radius: 0.45 * w, hex: 0xFF4FA3, alpha: 0.42)
  glow(ctx, center: at(0.92, 1.05), radius: 0.50 * w, hex: 0xFFC46B, alpha: 0.65)
  glow(ctx, center: at(0.05, 0.95), radius: 0.40 * w, hex: 0x3D6BFF, alpha: 0.45)

  // Aurora ribbon: a glowing stroke sweeping across the sky.
  if detail != .tiny {
    let ribbon = CGMutablePath()
    ribbon.move(to: at(-0.08, 0.70))
    ribbon.addCurve(to: at(1.08, 0.18), control1: at(0.30, 0.05), control2: at(0.62, 0.85))
    ctx.saveGState()
    ctx.setLineCap(.round)
    // Only the blurred shadow of the stroke is painted: the stroke itself is drawn far
    // outside the clip and the shadow offset brings the blur back in place. This gives a
    // soft band of light with no hard edges. Shadow offsets live in device pixels.
    let shift: CGFloat = 4 * w
    var moveAway = CGAffineTransform(translationX: shift, y: 0)
    guard let farRibbon = ribbon.copy(using: &moveAway) else {
      ctx.restoreGState()
      return
    }
    let passes: [(width: CGFloat, blur: CGFloat, hex: UInt32, alpha: CGFloat)] = [
      (0.16, 90, 0x3DFFC8, 0.55),
      (0.06, 34, 0x9DFFE6, 0.60),
      (0.015, 10, 0xEFFFFA, 0.55),
    ]
    for pass in passes {
      ctx.setShadow(
        offset: CGSize(width: -shift * scale, height: 0), blur: pass.blur * scale,
        color: color(pass.hex, pass.alpha))
      ctx.setStrokeColor(color(0xFFFFFF))
      ctx.setLineWidth(pass.width * h)
      ctx.addPath(farRibbon)
      ctx.strokePath()
    }
    ctx.restoreGState()
  }

  // Soft glass sheen from the top-left.
  if let sheen = linearGradient([(0, color(0xFFFFFF, 0.08)), (0.45, color(0xFFFFFF, 0.0))]) {
    ctx.drawLinearGradient(sheen, start: at(0, 0), end: at(0.55, 0.9), options: [])
  }
}

/// Draws the whole icon in a 1024x1024 y-down design space, scaled by `scale`.
func drawIcon(_ ctx: CGContext, scale s: CGFloat, detail: Detail) {
  ctx.saveGState()
  ctx.scaleBy(x: s, y: s)

  // Body: macOS grid, 824x824 centred on the 1024 canvas.
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  let bodyPath = continuousRoundedRect(body, radius: 185)

  ctx.saveGState()
  let shadowBlur: CGFloat = detail == .tiny ? 14 : 28
  let shadowY: CGFloat = detail == .tiny ? 6 : 12
  ctx.setShadow(
    offset: CGSize(width: 0, height: -shadowY * s), blur: shadowBlur * s,
    color: color(0x000000, 0.38))
  ctx.setFillColor(color(0xE4E8F1))
  ctx.addPath(bodyPath)
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(bodyPath)
  ctx.clip()
  if let g = linearGradient([(0, color(0xFBFCFF)), (1, color(0xC9D0DF))]) {
    ctx.drawLinearGradient(
      g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
  }
  ctx.restoreGState()

  // Geometry of the laptop. Small sizes get a larger display and thicker parts.
  let tiny = detail == .tiny
  let display =
    tiny
    ? CGRect(x: 150, y: 228, width: 724, height: 520)
    : CGRect(x: 168, y: 254, width: 688, height: 476)
  let rim: CGFloat = tiny ? 0 : 5
  let bezel: CGFloat = tiny ? 26 : 20
  let displayRadius: CGFloat = tiny ? 44 : 34
  let baseHeight: CGFloat = tiny ? 44 : 30
  let baseOverhang: CGFloat = tiny ? 34 : 38

  // Lower deck of the laptop, drawn first so the display sits on top of its hinge.
  let base = CGRect(
    x: display.minX - baseOverhang, y: display.maxY - 4,
    width: display.width + 2 * baseOverhang, height: baseHeight + 4)
  let basePath = CGMutablePath()
  let br = baseHeight * 0.55
  basePath.move(to: CGPoint(x: base.minX, y: base.minY))
  basePath.addLine(to: CGPoint(x: base.maxX, y: base.minY))
  basePath.addLine(to: CGPoint(x: base.maxX, y: base.maxY - br))
  basePath.addQuadCurve(
    to: CGPoint(x: base.maxX - br * 2.2, y: base.maxY),
    control: CGPoint(x: base.maxX - br * 0.15, y: base.maxY))
  basePath.addLine(to: CGPoint(x: base.minX + br * 2.2, y: base.maxY))
  basePath.addQuadCurve(
    to: CGPoint(x: base.minX, y: base.maxY - br),
    control: CGPoint(x: base.minX + br * 0.15, y: base.maxY))
  basePath.closeSubpath()

  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -6 * s), blur: 16 * s, color: color(0x1B2240, 0.30))
  ctx.setFillColor(color(0xA9AFBC))
  ctx.addPath(basePath)
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(basePath)
  ctx.clip()
  if let g = linearGradient([(0, color(0xF1F3F7)), (0.35, color(0xC7CCD6)), (1, color(0x868C9A))]) {
    ctx.drawLinearGradient(
      g, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
  }
  if !tiny {
    // Thumb notch on the front edge of the deck.
    let notch = CGRect(x: 512 - 62, y: base.minY + 4, width: 124, height: 10)
    ctx.setFillColor(color(0x7D8392, 0.85))
    ctx.addPath(roundedRect(notch, radius: 5))
    ctx.fillPath()
  }
  ctx.restoreGState()

  // Display: thin aluminium rim, black bezel, black glass.
  let displayPath = continuousRoundedRect(display, radius: displayRadius)
  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -8 * s), blur: 22 * s, color: color(0x141A33, 0.35))
  ctx.setFillColor(color(0xB3B8C3))
  ctx.addPath(displayPath)
  ctx.fillPath()
  ctx.restoreGState()

  let bezelRect = display.insetBy(dx: rim, dy: rim)
  ctx.setFillColor(color(0x17181C))
  ctx.addPath(continuousRoundedRect(bezelRect, radius: displayRadius - rim))
  ctx.fillPath()

  let glass = display.insetBy(dx: rim + bezel, dy: rim + bezel)
  ctx.setFillColor(color(0x000000))
  ctx.addPath(roundedRect(glass, radius: tiny ? 10 : 12))
  ctx.fillPath()

  // Black menu bar band and rounded desktop below it.
  let bandHeight = (glass.height * (tiny ? 0.24 : 0.205)).rounded()
  let desktop = CGRect(
    x: glass.minX, y: glass.minY + bandHeight, width: glass.width, height: glass.height - bandHeight
  )
  let desktopPath = continuousRoundedRect(desktop, radius: tiny ? 52 : 44)

  ctx.saveGState()
  ctx.addPath(desktopPath)
  ctx.clip()
  drawWallpaper(ctx, in: desktop, scale: s, detail: detail)
  ctx.restoreGState()

  if detail == .full {
    // Hint of the hidden notch: a faint dashed outline inside the band.
    let notchWidth: CGFloat = 112
    let notchHeight = bandHeight * 0.74
    let nx = glass.midX - notchWidth / 2
    let ny = glass.minY
    let nr: CGFloat = 16
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx, y: ny + 2))
    notch.addLine(to: CGPoint(x: nx, y: ny + notchHeight - nr))
    notch.addQuadCurve(
      to: CGPoint(x: nx + nr, y: ny + notchHeight), control: CGPoint(x: nx, y: ny + notchHeight))
    notch.addLine(to: CGPoint(x: nx + notchWidth - nr, y: ny + notchHeight))
    notch.addQuadCurve(
      to: CGPoint(x: nx + notchWidth, y: ny + notchHeight - nr),
      control: CGPoint(x: nx + notchWidth, y: ny + notchHeight))
    notch.addLine(to: CGPoint(x: nx + notchWidth, y: ny + 2))
    ctx.saveGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.38))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [9, 8])
    ctx.addPath(notch)
    ctx.strokePath()
    ctx.restoreGState()

    // Menu bar items: short light bars left and right of the hidden notch.
    let itemHeight = (bandHeight * 0.20).rounded()
    let itemY = glass.minY + (bandHeight - itemHeight) / 2
    var x = glass.minX + 30
    for (i, width) in [CGFloat(22), 50, 38, 44].enumerated() {
      ctx.setFillColor(color(0xFFFFFF, i == 1 ? 0.78 : 0.52))
      ctx.addPath(
        roundedRect(
          CGRect(x: x, y: itemY, width: width, height: itemHeight), radius: itemHeight / 2))
      ctx.fillPath()
      x += width + 16
    }
    x = glass.maxX - 30
    for width in [CGFloat(58), 22, 22, 32] {
      x -= width
      ctx.setFillColor(color(0xFFFFFF, 0.52))
      ctx.addPath(
        roundedRect(
          CGRect(x: x, y: itemY, width: width, height: itemHeight), radius: itemHeight / 2))
      ctx.fillPath()
      x -= 16
    }
  }

  ctx.restoreGState()
}

func renderIcon(pixels: Int) throws -> CGImage {
  let ctx = try makeContext(width: pixels, height: pixels)
  flipToTopLeft(ctx, height: pixels)
  drawIcon(ctx, scale: CGFloat(pixels) / 1024, detail: Detail(pixels: pixels))
  guard let image = ctx.makeImage() else { throw RenderError.image("icon \(pixels)px") }
  return image
}

// MARK: - Menu bar icon

/// Template image: pure black with alpha. Geometry in points on an 18x18 canvas,
/// every edge on a whole point except the 1.5 pt inner stroke edge.
func renderMenuBarIcon(scale: Int) throws -> CGImage {
  let px = 18 * scale
  let ctx = try makeContext(width: px, height: px)
  flipToTopLeft(ctx, height: px)
  ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

  let screen = CGRect(x: 1, y: 3, width: 16, height: 12)
  // 1.5 pt at 2x is exactly 3 px. At 1x a 1.5 px edge would land mid-pixel and blur,
  // so the stroke snaps to 1 px there to stay crisp.
  let stroke: CGFloat = scale == 1 ? 1 : 1.5
  let bandBottom: CGFloat = 7  // band covers the top 4 pt (one third of the screen)
  let desktop = CGRect(
    x: screen.minX + stroke, y: bandBottom,
    width: screen.width - 2 * stroke, height: screen.maxY - stroke - bandBottom)

  let shape = CGMutablePath()
  shape.addPath(roundedRect(screen, radius: 3))
  shape.addPath(roundedRect(desktop, radius: 3 - stroke))
  ctx.setFillColor(color(0x000000))
  ctx.addPath(shape)
  ctx.fillPath(using: .evenOdd)

  guard let image = ctx.makeImage() else { throw RenderError.image("menu bar icon @\(scale)x") }
  return image
}

// MARK: - Cover

/// Returns the bold system font, falling back to SF Pro Display and then Helvetica Neue.
func titleFont(size: CGFloat) -> CTFont {
  if let ui = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) {
    return ui
  }
  let sf = CTFontCreateWithName("SFProDisplay-Bold" as CFString, size, nil)
  if (CTFontCopyPostScriptName(sf) as String) == "SFProDisplay-Bold" { return sf }
  return CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
}

/// Returns the regular system font, falling back to Helvetica Neue.
func bodyFont(size: CGFloat) -> CTFont {
  CTFontCreateUIFontForLanguage(.system, size, nil)
    ?? CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
}

func makeLine(_ text: String, font: CTFont, color fg: CGColor, kern: CGFloat = 0) -> CTLine {
  let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: fg,
    kCTKernAttributeName: kern,
  ]
  let string = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
  return CTLineCreateWithAttributedString(string)
}

func lineWidth(_ line: CTLine) -> CGFloat {
  CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Builds a line at `size`, shrinking the font until the line fits in `maxWidth`.
func fittedLine(
  _ text: String, size: CGFloat, maxWidth: CGFloat, color fg: CGColor, kern: CGFloat = 0,
  font: (CGFloat) -> CTFont
) -> (CTLine, CGFloat) {
  var current = size
  var line = makeLine(text, font: font(current), color: fg, kern: kern)
  while lineWidth(line) > maxWidth && current > 8 {
    current -= 1
    line = makeLine(text, font: font(current), color: fg, kern: kern * current / size)
  }
  return (line, current)
}

func renderCover(icon: CGImage) throws -> CGImage {
  let width = 1280
  let height = 640
  let ctx = try makeContext(width: width, height: height)
  let W = CGFloat(width)
  let H = CGFloat(height)
  // y-up space here: CoreText draws upright without extra flips.

  if let bg = linearGradient([(0, color(0x0B0C14)), (0.55, color(0x141229)), (1, color(0x24143A))])
  {
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
  }
  let iconSide: CGFloat = 440  // body of the icon is ~354 px
  let iconRect = CGRect(x: 78, y: (H - iconSide) / 2 - 6, width: iconSide, height: iconSide)
  glow(
    ctx, center: CGPoint(x: iconRect.midX, y: iconRect.midY), radius: 360, hex: 0x5B3BFF,
    alpha: 0.30)
  glow(ctx, center: CGPoint(x: W * 0.98, y: 0), radius: 520, hex: 0xFF7E5F, alpha: 0.13)
  glow(ctx, center: CGPoint(x: W * 0.70, y: H * 1.05), radius: 420, hex: 0x29E3C1, alpha: 0.08)

  ctx.interpolationQuality = .high
  ctx.draw(icon, in: iconRect)

  // Text block on the right.
  let textX: CGFloat = 590
  let maxWidth = W - textX - 96
  let (title, _) = fittedLine(
    "topNV", size: 132, maxWidth: maxWidth, color: color(0xFFFFFF), kern: -2.5, font: titleFont)
  let (tag1, tagSize) = fittedLine(
    "Hide the notch.", size: 44, maxWidth: maxWidth, color: color(0xEEEAFB, 0.95), font: bodyFont)
  let (tag2, _) = fittedLine(
    "Keep your wallpaper.", size: tagSize, maxWidth: maxWidth, color: color(0xEEEAFB, 0.95),
    font: bodyFont)
  let (small, _) = fittedLine(
    "Black menu bar \u{00B7} rounded corners \u{00B7} animated wallpapers",
    size: 24, maxWidth: maxWidth, color: color(0xA7A3C2), font: bodyFont)

  func metrics(_ line: CTLine) -> (ascent: CGFloat, descent: CGFloat) {
    var a: CGFloat = 0
    var d: CGFloat = 0
    var l: CGFloat = 0
    _ = CTLineGetTypographicBounds(line, &a, &d, &l)
    return (a, d)
  }
  let mt = metrics(title)
  let m1 = metrics(tag1)
  let ms = metrics(small)
  let gapTitle: CGFloat = 26
  let tagLeading: CGFloat = tagSize * 1.25
  let gapSmall: CGFloat = 34
  let blockHeight =
    mt.ascent + mt.descent + gapTitle + m1.ascent + tagLeading + m1.descent + gapSmall + ms.ascent
    + ms.descent
  var y = (H + blockHeight) / 2 - mt.ascent  // baseline of the title
  let centerY = iconRect.midY
  y += centerY - H / 2

  ctx.textPosition = CGPoint(x: textX - 4, y: y)
  CTLineDraw(title, ctx)
  y -= mt.descent + gapTitle + m1.ascent
  ctx.textPosition = CGPoint(x: textX, y: y)
  CTLineDraw(tag1, ctx)
  y -= tagLeading
  ctx.textPosition = CGPoint(x: textX, y: y)
  CTLineDraw(tag2, ctx)
  y -= m1.descent + gapSmall + ms.ascent
  ctx.textPosition = CGPoint(x: textX, y: y)
  CTLineDraw(small, ctx)

  guard let image = ctx.makeImage() else { throw RenderError.image("cover") }
  return image
}

// MARK: - Main

func run() throws {
  let args = CommandLine.arguments
  guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-assets <output-dir>\n".utf8))
    exit(2)
  }
  let out = URL(fileURLWithPath: args[1], isDirectory: true)
  let iconset = out.appendingPathComponent("AppIcon.iconset", isDirectory: true)
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

  var cache: [Int: CGImage] = [:]
  func icon(_ px: Int) throws -> CGImage {
    if let hit = cache[px] { return hit }
    let image = try renderIcon(pixels: px)
    cache[px] = image
    return image
  }

  for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
      let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
      try writePNG(
        try icon(points * scale), to: iconset.appendingPathComponent(name), dpi: 72 * scale)
      print("wrote AppIcon.iconset/\(name) (\(points * scale)px)")
    }
  }

  try writePNG(
    try renderMenuBarIcon(scale: 1), to: out.appendingPathComponent("MenuBarIcon.png"), dpi: 72)
  try writePNG(
    try renderMenuBarIcon(scale: 2), to: out.appendingPathComponent("MenuBarIcon@2x.png"), dpi: 144)
  print("wrote MenuBarIcon.png (18px), MenuBarIcon@2x.png (36px)")

  try writePNG(try renderCover(icon: try icon(1024)), to: out.appendingPathComponent("cover.png"))
  print("wrote cover.png (1280x640)")
}

do {
  try run()
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
