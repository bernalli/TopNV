// render-assets.swift
//
// Renders every visual asset of TopNV from AppIconMaster.png in the output
// directory, using CoreGraphics, ImageIO and CoreText (no AppKit, no WindowServer).
// AppIcon.icon is the editable design source; the master is its full-canvas render.
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
  case master(String)
  case destination(String)
  case write(String)

  var description: String {
    switch self {
    case .colorSpace: return "cannot create the sRGB color space"
    case .context(let w, let h): return "cannot create a \(w)x\(h) bitmap context"
    case .image(let name): return "cannot create the image for \(name)"
    case .master(let path): return "cannot load app icon master at \(path); provide AppIconMaster.png in the output directory"
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

// MARK: - App icon

/// Loads the full-canvas Icon Composer render before writing any output.
func loadMaster(from url: URL) throws -> CGImage {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw RenderError.master(url.path) }
  return image
}

/// Geometry of the app icon in the 1024x1024 y-down design space.
enum IconGrid {
  /// Body: macOS grid, 824x824 centred on the 1024 canvas.
  static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
}

/// Scales the master into the macOS body, preserving its outline and drop shadow.
func drawIcon(_ ctx: CGContext, scale s: CGFloat, master: CGImage) {
  ctx.saveGState()
  ctx.scaleBy(x: s, y: s)
  ctx.setShadow(
    offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.38))
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)

  // The context is y-down; draw the image in a y-up frame to keep it upright.
  ctx.translateBy(x: 0, y: 1024)
  ctx.scaleBy(x: 1, y: -1)
  ctx.draw(master, in: IconGrid.body)

  ctx.endTransparencyLayer()
  ctx.restoreGState()
}

func renderIcon(pixels: Int, master: CGImage) throws -> CGImage {
  let ctx = try makeContext(width: pixels, height: pixels)
  flipToTopLeft(ctx, height: pixels)
  drawIcon(ctx, scale: CGFloat(pixels) / 1024, master: master)
  guard let image = ctx.makeImage() else { throw RenderError.image("icon \(pixels)px") }
  return image
}

// MARK: - Menu bar icon

/// Black template with transparency on an 18x18 point canvas, opening bottom-right.
func renderMenuBarIcon(scale: Int) throws -> CGImage {
  let px = 18 * scale
  let ctx = try makeContext(width: px, height: px)
  flipToTopLeft(ctx, height: px)
  ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

  // At 1x, 3 pt puts the straight stroke edges and cap extrema on whole pixels.
  // At 2x, 3.5 pt is exactly 7 pixels. Both retain the same 10.5 pt outer radius.
  let stroke: CGFloat = scale == 1 ? 3 : 3.5
  ctx.setStrokeColor(color(0x000000))
  ctx.setLineWidth(stroke)
  ctx.setLineCap(.round)
  ctx.addArc(
    center: CGPoint(x: 13.5, y: 13.5), radius: 10.5 - stroke / 2,
    startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
  ctx.strokePath()

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

  if let bg = linearGradient([(0, color(0x101010)), (0.55, color(0x161616)), (1, color(0x1B1B1B))])
  {
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
  }
  let iconSide: CGFloat = 440  // body of the icon is ~354 px
  let iconRect = CGRect(x: 78, y: (H - iconSide) / 2 - 6, width: iconSide, height: iconSide)
  glow(
    ctx, center: CGPoint(x: iconRect.midX, y: iconRect.midY), radius: 360, hex: 0xFFFFFF,
    alpha: 0.10)

  ctx.interpolationQuality = .high
  ctx.draw(icon, in: iconRect)

  // Text block on the right.
  let textX: CGFloat = 590
  let maxWidth = W - textX - 96
  let (title, _) = fittedLine(
    "TopNV", size: 132, maxWidth: maxWidth, color: color(0xFFFFFF), kern: -2.5, font: titleFont)
  let (tag1, tagSize) = fittedLine(
    "Hide the notch.", size: 44, maxWidth: maxWidth, color: color(0xEEEEEE, 0.95), font: bodyFont)
  let (tag2, _) = fittedLine(
    "Keep your wallpaper.", size: tagSize, maxWidth: maxWidth, color: color(0xEEEEEE, 0.95),
    font: bodyFont)
  let (small, _) = fittedLine(
    "Black menu bar \u{00B7} rounded corners \u{00B7} animated wallpapers",
    size: 24, maxWidth: maxWidth, color: color(0xA7A7A7), font: bodyFont)

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
  let master = try loadMaster(from: out.appendingPathComponent("AppIconMaster.png"))
  let iconset = out.appendingPathComponent("AppIcon.iconset", isDirectory: true)
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

  var cache: [Int: CGImage] = [:]
  func icon(_ px: Int) throws -> CGImage {
    if let hit = cache[px] { return hit }
    let image = try renderIcon(pixels: px, master: master)
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
