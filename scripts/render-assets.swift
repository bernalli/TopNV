// render-assets.swift
//
// Renders every visual asset of topNV deterministically, using only
// CoreGraphics, ImageIO and CoreText (no AppKit, no WindowServer).
//
// Usage:
//   swiftc -O scripts/render-assets.swift -o "$TMPDIR/render-assets"
//   "$TMPDIR/render-assets" Assets
//
// Output (relative to the output directory):
//   AppIcon.iconset/icon_{16,32,128,256,512}x{...}[@2x].png
//   AppIcon.icns                          (the iconset images, written with ImageIO)
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

/// Geometry of the app icon in the 1024x1024 y-down design space.
enum IconGrid {
  /// Body: macOS grid, 824x824 centred on the 1024 canvas.
  static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  static let cornerRadius: CGFloat = 185
  /// Bottom edge of the black band (29% of the body height).
  static let bandBottom = body.minY + (body.height * 0.29).rounded()
  /// Radius of the rounded screen corners tucked under the band.
  static let filletRadius = (body.width * 0.095).rounded()
  /// How far black shapes reach past the body, so only the squircle mask defines the outline.
  static let bleed: CGFloat = 24
}

/// Draws the wallpaper with its gradient laid out on `rect`: deep indigo at the
/// bottom-left flowing to magenta and warm orange at the top-right.
func drawWallpaper(_ ctx: CGContext, in rect: CGRect) {
  let w = rect.width
  let h = rect.height
  func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + fx * w, y: rect.minY + fy * h)
  }

  if let base = linearGradient([
    (0.00, color(0x140F52)),
    (0.30, color(0x3A2397)),
    (0.56, color(0x8E2FA6)),
    (0.78, color(0xE04E86)),
    (1.00, color(0xFFA25A)),
  ]) {
    ctx.drawLinearGradient(
      base, start: at(0, 1), end: at(1, 0),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }

  // Soft light pooling in the warm corner and a cool haze in the deep one.
  glow(ctx, center: at(0.95, 0.02), radius: 0.62 * w, hex: 0xFFC27A, alpha: 0.38)
  glow(ctx, center: at(0.08, 0.98), radius: 0.55 * w, hex: 0x4C3BFF, alpha: 0.30)
}

/// Renders the screen face (wallpaper, black band, rounded corners) with no outline.
///
/// The face is drawn unclipped and masked by the squircle in a single step afterwards:
/// two anti-aliased fills on the same clip edge would leave a tinted fringe on the rim.
func renderScreen(pixels: Int) throws -> CGImage {
  let ctx = try makeContext(width: pixels, height: pixels)
  flipToTopLeft(ctx, height: pixels)
  ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

  let body = IconGrid.body
  let bandBottom = IconGrid.bandBottom
  let radius = IconGrid.filletRadius
  let bleed = IconGrid.bleed

  drawWallpaper(
    ctx, in: CGRect(x: body.minX, y: bandBottom, width: body.width, height: body.maxY - bandBottom))

  ctx.setFillColor(color(0x000000))
  ctx.fill(
    CGRect(
      x: body.minX - bleed, y: body.minY - bleed,
      width: body.width + 2 * bleed, height: bandBottom - body.minY + bleed))

  // Each fillet is a black square with a quarter disc cut out, tangent to the band and to
  // the body edge. It overlaps the band slightly so the two never show a seam.
  for side in [CGFloat(-1), 1] {
    let edgeX = side < 0 ? body.minX : body.maxX
    let inner = edgeX - side * radius
    let fillet = CGMutablePath()
    fillet.move(to: CGPoint(x: edgeX + side * bleed, y: bandBottom - 2))
    fillet.addLine(to: CGPoint(x: inner, y: bandBottom - 2))
    fillet.addLine(to: CGPoint(x: inner, y: bandBottom))
    fillet.addArc(
      tangent1End: CGPoint(x: edgeX, y: bandBottom),
      tangent2End: CGPoint(x: edgeX, y: bandBottom + radius), radius: radius)
    fillet.addLine(to: CGPoint(x: edgeX + side * bleed, y: bandBottom + radius))
    fillet.closeSubpath()
    ctx.addPath(fillet)
    ctx.fillPath()
  }

  guard let image = ctx.makeImage() else { throw RenderError.image("icon face \(pixels)px") }
  return image
}

/// Draws the whole icon in a 1024x1024 y-down design space, scaled by `scale`.
///
/// The squircle is the screen: a black band across the top (the hidden notch area) and,
/// just below it, two concave black fillets that round the visible corners of the screen.
func drawIcon(_ ctx: CGContext, scale s: CGFloat, screen: CGImage) {
  ctx.saveGState()
  ctx.scaleBy(x: s, y: s)

  let body = IconGrid.body
  let bodyPath = continuousRoundedRect(body, radius: IconGrid.cornerRadius)

  // One transparency layer, so the drop shadow is cast by the finished icon.
  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.38))
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)

  ctx.saveGState()
  ctx.addPath(bodyPath)
  ctx.clip()

  // The context is y-down; the image must be drawn in a y-up frame to stay upright.
  ctx.saveGState()
  ctx.translateBy(x: 0, y: 1024)
  ctx.scaleBy(x: 1, y: -1)
  ctx.draw(screen, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
  ctx.restoreGState()

  // Faint highlight on the top rim, fading out well before the band ends.
  ctx.addPath(bodyPath)
  ctx.setLineWidth(6)
  ctx.replacePathWithStrokedPath()
  ctx.clip()
  if let rim = linearGradient([(0, color(0xFFFFFF, 0.20)), (1, color(0xFFFFFF, 0))]) {
    ctx.drawLinearGradient(
      rim, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.minY + 200), options: [])
  }
  ctx.restoreGState()

  ctx.endTransparencyLayer()
  ctx.restoreGState()

  ctx.restoreGState()
}

func renderIcon(pixels: Int) throws -> CGImage {
  let screen = try renderScreen(pixels: pixels)
  let ctx = try makeContext(width: pixels, height: pixels)
  flipToTopLeft(ctx, height: pixels)
  drawIcon(ctx, scale: CGFloat(pixels) / 1024, screen: screen)
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

  let iconSizes = [16, 32, 128, 256, 512].flatMap { points in [1, 2].map { (points, $0) } }
  for (points, scale) in iconSizes {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try writePNG(
      try icon(points * scale), to: iconset.appendingPathComponent(name), dpi: 72 * scale)
    print("wrote AppIcon.iconset/\(name) (\(points * scale)px)")
  }

  // iconutil is not always usable, so the .icns is written directly with ImageIO.
  let icnsURL = out.appendingPathComponent("AppIcon.icns")
  guard
    let icns = CGImageDestinationCreateWithURL(
      icnsURL as CFURL, "com.apple.icns" as CFString, iconSizes.count, nil)
  else {
    throw RenderError.destination(icnsURL.path)
  }
  for (points, scale) in iconSizes {
    let dpi = 72 * scale
    let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(icns, try icon(points * scale), props as CFDictionary)
  }
  guard CGImageDestinationFinalize(icns) else { throw RenderError.write(icnsURL.path) }
  print("wrote AppIcon.icns (\(iconSizes.count) images)")

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
